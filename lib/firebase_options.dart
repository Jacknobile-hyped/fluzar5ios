import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'No Web configuration provided',
      );
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        throw UnsupportedError(
          'MacOS is not supported',
        );
      case TargetPlatform.windows:
        throw UnsupportedError(
          'Windows is not supported',
        );
      case TargetPlatform.linux:
        throw UnsupportedError(
          'Linux is not supported',
        );
      default:
        throw UnsupportedError(
          'Unknown platform ${defaultTargetPlatform}',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDcqQOKXVB2Y-2R73ytvlT9Hww92mD6MEg',
    appId: '1:1095391771291:android:977f23de07c86ac8a1e43e',
    messagingSenderId: '1095391771291',
    projectId: 'share-magica',
    storageBucket: 'share-magica.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyC3LPWsfcl4bRa4TsXV91z3DP07PNffZfI',
    appId: '1:1095391771291:ios:92c17dfcae6aa7d8a1e43e',
    messagingSenderId: '1095391771291',
    projectId: 'share-magica',
    storageBucket: 'share-magica.firebasestorage.app',
    iosClientId: '1095391771291-ner3467g5fqv14j0l5886qe5u7sho8a2.apps.googleusercontent.com',
  );
} 