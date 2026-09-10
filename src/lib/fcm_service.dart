import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';

// Handler untuk notif saat app background/terminated
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  // JANGAN showLocalNotification di background — FCM sudah tampil otomatis
  // Ini hanya untuk data-only messages
  if (message.notification == null) {
    await FCMService.showLocalNotification(message);
  }
}

class FCMService {
  static final FlutterLocalNotificationsPlugin _localNotif =
      FlutterLocalNotificationsPlugin();

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'lunex_broadcast',
    'LuNEX Broadcast',
    description: 'Channel untuk broadcast resmi LuNEX Project',
    importance: Importance.max,
    playSound: true,
  );

  static bool _initialized = false; // Guard agar init tidak dipanggil 2x

  static Future<void> init() async {
    if (_initialized) return; // Cegah double init = double notif
    _initialized = true;

    // Setup local notifications
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initSettings =
        InitializationSettings(android: androidSettings);
    await _localNotif.initialize(initSettings);

    // Buat channel notifikasi
    await _localNotif
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);

    // Request permission (Android 13+)
    FirebaseMessaging messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // Subscribe ke topic 'broadcast'
    await messaging.subscribeToTopic('broadcast');

    // Handler notif saat app FOREGROUND — tampilkan sebagai local notif
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      // Hanya tampilkan jika ada notification payload
      if (message.notification != null) {
        showLocalNotification(message);
      }
    });

    // Handler background — hanya untuk data-only messages
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    debugPrint('[FCM] Initialized & subscribed to broadcast topic');
  }

  // Tampilkan notif lokal dengan ID tetap per broadcast (cegah spam)
  static Future<void> showLocalNotification(RemoteMessage message) async {
    final title = message.notification?.title ?? '📢 PENGUMUMAN RESMI';
    final body = message.notification?.body ?? '';

    // Pakai ID tetap (0) agar notif yang sama tidak muncul 2x
    await _localNotif.show(
      0,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.max,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
          playSound: true,
          // Pastikan tidak duplicate dengan FCM system notif
          tag: 'lunex_broadcast',
        ),
      ),
    );
  }
}
