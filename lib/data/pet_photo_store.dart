import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/data/pet_photo_codec.dart';

/// Pet photos on disk, under the app documents directory:
///
/// - `pet_photos/<petId>.jpg` — a photo picked on this phone (works offline,
///   solo phones keep only this).
/// - `pet_photo_cache/<photoKey>.jpg` — a photo another member set,
///   downloaded once and reused until the household's key changes.
class PetPhotoStore {
  PetPhotoStore({Future<Directory> Function()? baseDir})
    : _baseDir = baseDir ?? getApplicationDocumentsDirectory;

  static const ownFolder = 'pet_photos';
  static const cacheFolder = 'pet_photo_cache';

  final Future<Directory> Function() _baseDir;
  String? _root;
  final Set<String> _cached = {};

  /// Resolves the folders and lists the cache once. Safe to call repeatedly.
  Future<void> init() async {
    if (_root != null) return;
    final base = await _baseDir();
    _root = base.path;
    final cache = Directory(_join(cacheFolder));
    if (await cache.exists()) {
      await for (final entry in cache.list()) {
        if (entry is File) _cached.add(entry.uri.pathSegments.last);
      }
    }
  }

  bool get isReady => _root != null;

  String _join(String folder, [String? name]) =>
      name == null ? '$_root/$folder' : '$_root/$folder/$name';

  /// Keys are `households/<id>/pets/<id>/<hex>.jpg`; flattened to one name.
  static String cacheName(String photoKey) =>
      '${photoKey.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')}'
      '${photoKey.endsWith('.jpg') ? '' : '.jpg'}';

  static String _ownName(String petId) =>
      '${petId.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')}.jpg';

  String? ownPath(String petId) =>
      _root == null ? null : _join(ownFolder, _ownName(petId));

  String? cachePath(String photoKey) =>
      _root == null ? null : _join(cacheFolder, cacheName(photoKey));

  bool isCached(String photoKey) => _cached.contains(cacheName(photoKey));

  Future<void> writeOwn(String petId, Uint8List bytes) async {
    await init();
    final file = File(ownPath(petId)!);
    await file.parent.create(recursive: true);
    // Write then rename so a crash never leaves half a photo behind.
    final temp = File('${file.path}.tmp');
    await temp.writeAsBytes(bytes, flush: true);
    await temp.rename(file.path);
  }

  Future<Uint8List?> readOwn(String petId) async {
    await init();
    final file = File(ownPath(petId)!);
    return await file.exists() ? file.readAsBytes() : null;
  }

  Future<void> deleteOwn(String petId) async {
    await init();
    final file = File(ownPath(petId)!);
    if (await file.exists()) await file.delete();
  }

  Future<void> writeCache(String photoKey, Uint8List bytes) async {
    await init();
    final file = File(cachePath(photoKey)!);
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.tmp');
    await temp.writeAsBytes(bytes, flush: true);
    await temp.rename(file.path);
    _cached.add(cacheName(photoKey));
  }

  /// Copies a cached household photo into this phone's own slot (used when
  /// the household goes away but the pet stays on the phone).
  Future<bool> adoptCached(String photoKey, String petId) async {
    await init();
    final source = File(cachePath(photoKey)!);
    if (!await source.exists()) return false;
    final bytes = await source.readAsBytes();
    await writeOwn(petId, bytes);
    return true;
  }

  /// Deletes own photos of pets that are gone and cache files whose key no
  /// pet uses any more. Returns how many files were removed.
  Future<int> prune({
    required Set<String> keepPetIds,
    required Set<String> keepKeys,
  }) async {
    await init();
    final keepOwn = {for (final id in keepPetIds) _ownName(id)};
    final keepCache = {for (final key in keepKeys) cacheName(key)};
    var removed = 0;
    Future<void> sweep(String folder, Set<String> keep) async {
      final dir = Directory(_join(folder));
      if (!await dir.exists()) return;
      await for (final entry in dir.list()) {
        final name = entry.uri.pathSegments.last;
        if (entry is File && !keep.contains(name)) {
          await entry.delete();
          _cached.remove(name);
          removed++;
        }
      }
    }

    await sweep(ownFolder, keepOwn);
    await sweep(cacheFolder, keepCache);
    return removed;
  }

  /// Removes every photo this app saved (account deletion / reset).
  Future<void> clearAll() async {
    await init();
    for (final folder in [ownFolder, cacheFolder]) {
      final dir = Directory(_join(folder));
      if (await dir.exists()) await dir.delete(recursive: true);
    }
    _cached.clear();
  }
}

class PhotoTransferException implements Exception {
  const PhotoTransferException(this.kind, [this.status]);

  /// `offline`, `rejected` (bucket said no / expired URL) or `invalid`.
  final String kind;
  final int? status;

  @override
  String toString() => 'PhotoTransferException($kind, $status)';
}

/// Moves photo bytes straight to and from the bucket with presigned URLs.
/// Its own plain Dio: no auth interceptor, so the household token is never
/// sent to the bucket, and no request logging of signed URLs.
class PetPhotoTransfer {
  PetPhotoTransfer({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              sendTimeout: const Duration(seconds: 20),
              receiveTimeout: const Duration(seconds: 20),
            ),
          );

  final Dio _dio;

  Future<void> put(String url, Map<String, String> headers, Uint8List bytes) {
    return _guard(() async {
      await _dio.put<void>(
        url,
        data: Stream.fromIterable([bytes]),
        options: Options(headers: headers, responseType: ResponseType.plain),
      );
    });
  }

  Future<Uint8List> get(String url) {
    return _guard(() async {
      final response = await _dio.get<List<int>>(
        url,
        options: Options(responseType: ResponseType.bytes),
      );
      final data = response.data;
      if (data == null ||
          data.isEmpty ||
          data.length > PetPhotoCodec.maxBytes) {
        throw const PhotoTransferException('invalid');
      }
      return Uint8List.fromList(data);
    });
  }

  Future<T> _guard<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on DioException catch (error) {
      final status = error.response?.statusCode;
      throw PhotoTransferException(
        status == null ? 'offline' : 'rejected',
        status,
      );
    } on PhotoTransferException {
      rethrow;
    } catch (error, stack) {
      AppLog.error('pet.photo_transfer_error', error, stack);
      throw const PhotoTransferException('invalid');
    }
  }
}
