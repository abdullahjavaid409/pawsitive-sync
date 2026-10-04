import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:image/image.dart' as img;
import 'package:pawsitive_sync/data/care_repository.dart';
import 'package:pawsitive_sync/data/household_api.dart';
import 'package:pawsitive_sync/data/household_store.dart';
import 'package:pawsitive_sync/data/pet_photo_store.dart';

import 'fake_household_api.dart';

/// What a route does on one call: answer, or fail like a bad network.
sealed class RouteResult {
  const RouteResult();
}

class Answer extends RouteResult {
  const Answer(this.status, this.body);
  final int status;
  final Object body;
}

/// No connection at all (never reached the server).
class Offline extends RouteResult {
  const Offline();
}

/// Sent, but no answer in time (slow link): the server may have acted.
class TimedOut extends RouteResult {
  const TimedOut();
}

/// Household API fake keyed by "METHOD /path". A route can return a queue
/// of results (one per call, last one repeats) to script retries.
class RouteAdapter implements HttpClientAdapter {
  RouteAdapter(this.routes);

  final Map<String, List<RouteResult>> routes;
  final calls = <String>[];
  final bodies = <String, List<Object?>>{};

  int count(String key) => calls.where((c) => c == key).length;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final key = '${options.method} ${options.path}';
    calls.add(key);
    (bodies[key] ??= []).add(options.data);
    final queue = routes[key];
    final result = queue == null || queue.isEmpty
        ? const Answer(404, {'error': 'Not found'})
        : (queue.length > 1 ? queue.removeAt(0) : queue.first);
    switch (result) {
      case Offline():
        throw DioException.connectionError(
          requestOptions: options,
          reason: 'offline (test)',
        );
      case TimedOut():
        throw DioException.receiveTimeout(
          timeout: const Duration(seconds: 12),
          requestOptions: options,
        );
      case Answer(:final status, :final body):
        return ResponseBody.fromString(
          jsonEncode(body),
          status,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
    }
  }

  @override
  void close({bool force = false}) {}
}

/// Stands in for the bucket. `putFailures` / `getFailures` are consumed one
/// per call before succeeding.
class FakeTransfer extends PetPhotoTransfer {
  FakeTransfer();

  final puts = <(String url, Map<String, String> headers, int bytes)>[];
  final gets = <String>[];
  final putFailures = <PhotoTransferException>[];
  final getFailures = <PhotoTransferException>[];
  final progress = <double>[];
  Uint8List downloadBytes = Uint8List.fromList(List.filled(2048, 7));
  bool cancelled = false;

  @override
  Future<void> put(
    String url,
    Map<String, String> headers,
    Uint8List bytes, {
    void Function(double sent)? onProgress,
  }) async {
    puts.add((url, headers, bytes.length));
    if (putFailures.isNotEmpty) throw putFailures.removeAt(0);
    for (final step in [0.25, 0.5, 1.0]) {
      progress.add(step);
      onProgress?.call(step);
    }
  }

  @override
  Future<Uint8List> get(String url) async {
    gets.add(url);
    if (getFailures.isNotEmpty) throw getFailures.removeAt(0);
    return downloadBytes;
  }

  @override
  void cancelDownloads() => cancelled = true;
}

/// [HouseholdApi] over [adapter], already linked (token set).
HouseholdApi routeApi(RouteAdapter adapter, {String? token = 'house-token'}) {
  final api = HouseholdApi(
    Uri.parse('https://example.test'),
    dio: Dio()..httpClientAdapter = adapter,
  );
  api.token = token;
  return api;
}

/// GET /v1/household answer with one pet whose photo fields are set.
Map<String, Object?> snapshotWithPhoto({
  String? photoKey,
  String? photoUrl,
  String memberId = 'you',
  String role = 'owner',
}) {
  final body = connectHouseholdBody(memberId: memberId);
  final pet = <String, Object?>{
    ...((body['pets']! as List).first as Map<String, Object?>),
    'photoKey': photoKey,
    'photoUrl': photoUrl,
  };
  body['pets'] = [pet];
  if (role != 'owner') {
    body['members'] = [
      {'id': 'owner-1', 'name': 'Owner', 'role': 'owner'},
      {'id': memberId, 'name': 'Sam', 'role': role, 'isYou': true},
    ];
  }
  return body;
}

/// Upload routes for pet `miso` that always succeed, issuing [key].
Map<String, List<RouteResult>> uploadRoutes(String key) => {
  'POST /v1/pets/miso/photo/upload': [
    Answer(200, {
      'photoKey': key,
      'upload': {
        'url': 'https://bucket.test/$key?sig=1',
        'headers': {'content-type': 'image/jpeg', 'content-length': '1000'},
        'expiresInSeconds': 300,
      },
    }),
  ],
  'PUT /v1/pets/miso/photo': [
    Answer(200, {'photoKey': key, 'photoUrl': 'https://bucket.test/$key?get'}),
  ],
  'DELETE /v1/pets/miso/photo': [
    const Answer(200, {'removed': true}),
  ],
};

/// A connected repository (token set) with photos on in [dir], synced once
/// from [snapshot].
Future<(CareRepository, RouteAdapter, FakeTransfer)> connectedCare(
  Directory dir, {
  Map<String, Object?>? snapshot,
  Map<String, List<RouteResult>> routes = const {},
}) async {
  final adapter = RouteAdapter({
    'GET /v1/household': [Answer(200, snapshot ?? snapshotWithPhoto())],
    ...routes,
  });
  final transfer = FakeTransfer();
  final care = CareRepository(
    api: routeApi(adapter),
    store: HouseholdStore(),
    photoStore: PetPhotoStore(baseDir: () async => dir),
    photoTransfer: transfer,
  );
  await care.restore();
  await care.sync(force: true);
  return (care, adapter, transfer);
}

/// A real JPEG the codec can read, [w]×[h], smooth or noisy.
Uint8List sampleJpeg(int w, int h, {bool noisy = false, int seed = 1}) {
  final image = img.Image(width: w, height: h);
  var x = seed;
  for (final p in image) {
    if (noisy) {
      x = (x * 1103515245 + 12345) & 0x7fffffff;
      p.setRgb(x & 255, (x >> 8) & 255, (x >> 16) & 255);
    } else {
      p.setRgb(p.x * 255 ~/ w, p.y * 255 ~/ h, 128);
    }
  }
  return img.encodeJpg(image, quality: 95);
}
