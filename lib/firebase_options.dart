// Generated from the Firebase CLI config for project gave-it-app
// (`firebase apps:sdkconfig`), in the shape `flutterfire configure` writes.
// Firebase client keys identify the project; they are not secrets.
// ignore_for_file: type=lint
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError('Gave It has no web Firebase app.');
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError(
          'Firebase is configured for iOS and Android only.',
        );
    }
  }

  /// Web OAuth client: Android Google sign-in asks for a token for it so
  /// Firebase can verify the result.
  static const androidServerClientId =
      '937452218604-1gj9jf4htlc0slonf39drang45ndoiq4.apps.googleusercontent.com';

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCFomWnUEh0AmFweUtrjWutdJ4-KjCu4YY',
    appId: '1:937452218604:android:ddc8bda7fbdacd94d21dc9',
    messagingSenderId: '937452218604',
    projectId: 'gave-it-app',
    storageBucket: 'gave-it-app.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyDYXYXzJuSr80wZlQGoLcMvL8QccK7dimU',
    appId: '1:937452218604:ios:80f7136419a387f3d21dc9',
    messagingSenderId: '937452218604',
    projectId: 'gave-it-app',
    storageBucket: 'gave-it-app.firebasestorage.app',
    iosClientId: '937452218604-967jcva0mibg0onr8bcf9v7qssevnc19.apps.googleusercontent.com',
    iosBundleId: 'com.pawsitivesync.app',
  );
}
