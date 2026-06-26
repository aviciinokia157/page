import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        return ios;
      default:
        return web;
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'SUBSTITUA_PELO_API_KEY',
    appId: 'SUBSTITUA_PELO_APP_ID_WEB',
    messagingSenderId: 'SUBSTITUA_PELO_SENDER_ID',
    projectId: 'SUBSTITUA_PELO_PROJECT_ID',
    authDomain: 'SUBSTITUA.firebaseapp.com',
    storageBucket: 'SUBSTITUA.appspot.com',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'SUBSTITUA_PELO_API_KEY',
    appId: 'SUBSTITUA_PELO_APP_ID_ANDROID',
    messagingSenderId: 'SUBSTITUA_PELO_SENDER_ID',
    projectId: 'SUBSTITUA_PELO_PROJECT_ID',
    storageBucket: 'SUBSTITUA.appspot.com',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'SUBSTITUA_PELO_API_KEY',
    appId: 'SUBSTITUA_PELO_APP_ID_IOS',
    messagingSenderId: 'SUBSTITUA_PELO_SENDER_ID',
    projectId: 'SUBSTITUA_PELO_PROJECT_ID',
    iosBundleId: 'com.example.reservaDeConvidados',
    storageBucket: 'SUBSTITUA.appspot.com',
  );
}
