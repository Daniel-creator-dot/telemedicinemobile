import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import '../models/appointment.dart';
import 'api_client.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();

  String? _fcmToken;
  String? get fcmToken => _fcmToken;

  ApiClient? _apiClient;

  // Register token with backend server
  Future<void> registerTokenWithBackend(ApiClient api) async {
    _apiClient = api;
    final token = _fcmToken ?? await _messaging.getToken();
    if (token == null || token.isEmpty) return;
    _fcmToken = token;
    
    try {
      await api.dio.post('/api/push/fcm-token', data: {
        'token': token,
        'platform': defaultTargetPlatform.name,
      });
      if (kDebugMode) {
        print('FCM Token registered with backend successfully: $token');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error registering FCM token with backend: $e');
      }
    }
  }

  // Initialize notification service
  Future<void> initialize() async {
    // Initialize timezone database
    tz_data.initializeTimeZones();
    
    // Request permission for iOS (only on non-web platforms)
    if (!kIsWeb) {
      await _requestIOSPermission();
      await _requestAndroidPermission();
    }

    // Initialize local notifications (for foreground notifications) - only on mobile
    if (!kIsWeb) {
      await _initializeLocalNotifications();
    }

    // Get FCM token
    await _getFCMToken();

    // Configure message handlers
    _configureMessageHandlers();
  }

  // Request iOS notification permission
  Future<void> _requestIOSPermission() async {
    try {
      final settings = await _messaging.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );

      if (kDebugMode) {
        print('iOS permission status: ${settings.authorizationStatus}');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error requesting iOS permission: $e');
      }
    }
  }

  // Request Android notification permission (Android 13+)
  Future<void> _requestAndroidPermission() async {
    try {
      final settings = await _messaging.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );

      if (kDebugMode) {
        print('Android permission status: ${settings.authorizationStatus}');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error requesting Android permission: $e');
      }
    }
  }

  // Initialize local notifications for foreground messages
  Future<void> _initializeLocalNotifications() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(settings);
  }

  // Get FCM token
  Future<void> _getFCMToken() async {
    try {
      // Get the current FCM token
      final token = await _messaging.getToken();
      _fcmToken = token;
      
      if (kDebugMode) {
        print('FCM Token: $token');
      }

      // Listen to token refresh
      _messaging.onTokenRefresh.listen((newToken) {
        _fcmToken = newToken;
        if (kDebugMode) {
          print('FCM Token refreshed: $newToken');
        }
        if (_apiClient != null) {
          registerTokenWithBackend(_apiClient!);
        }
      });
    } catch (e) {
      if (kDebugMode) {
        print('Error getting FCM token: $e');
      }
    }
  }

  // Configure message handlers
  void _configureMessageHandlers() {
    // Handle messages when app is in foreground
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // Handle messages when app is in background but opened
    FirebaseMessaging.onMessageOpenedApp.listen(_handleBackgroundMessage);

    // Handle messages when app is completely terminated
    _handleTerminatedState();
  }

  // Handle foreground messages
  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    if (kDebugMode) {
      print('Received foreground message: ${message.messageId}');
      print('Title: ${message.notification?.title}');
      print('Body: ${message.notification?.body}');
      print('Data: ${message.data}');
    }

    // Show local notification for foreground message
    _showLocalNotification(message);
  }

  // Handle background messages
  Future<void> _handleBackgroundMessage(RemoteMessage message) async {
    if (kDebugMode) {
      print('Received background message: ${message.messageId}');
      print('Title: ${message.notification?.title}');
      print('Body: ${message.notification?.body}');
    }

    // Navigate to specific screen based on message data
    _handleNotificationNavigation(message.data);
  }

  // Handle terminated state
  Future<void> _handleTerminatedState() async {
    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      if (kDebugMode) {
        print('App opened from terminated state via notification');
      }
      _handleNotificationNavigation(initialMessage.data);
    }
  }

  // Show local notification for foreground messages
  Future<void> _showLocalNotification(RemoteMessage message) async {
    final notification = message.notification;
    final android = message.notification?.android;

    if (notification != null && android != null) {
      final androidDetails = AndroidNotificationDetails(
        'telemedicine_channel',
        'Telemedicine Notifications',
        channelDescription: 'Notifications from Telemedicine app',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      );

      const iosDetails = DarwinNotificationDetails();

      final details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _localNotifications.show(
        message.hashCode,
        notification.title,
        notification.body,
        details,
        payload: message.data.toString(),
      );
    }
  }

  // Handle navigation based on notification data
  void _handleNotificationNavigation(Map<String, dynamic> data) {
    // TODO: Implement navigation logic based on notification data
    // Example: Navigate to appointment details, consultation screen, etc.
    if (kDebugMode) {
      print('Navigate based on data: $data');
    }
  }

  // Subscribe to a topic
  Future<void> subscribeToTopic(String topic) async {
    try {
      await _messaging.subscribeToTopic(topic);
      if (kDebugMode) {
        print('Subscribed to topic: $topic');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error subscribing to topic: $e');
      }
    }
  }

  // Unsubscribe from a topic
  Future<void> unsubscribeFromTopic(String topic) async {
    try {
      await _messaging.unsubscribeFromTopic(topic);
      if (kDebugMode) {
        print('Unsubscribed from topic: $topic');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error unsubscribing from topic: $e');
      }
    }
  }

  // Schedule a local notification at a specific time
  Future<void> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledTime,
    String? payload,
  }) async {
    if (kIsWeb) return; // Local notifications not supported on web

    try {
      final androidDetails = AndroidNotificationDetails(
        'telemedicine_channel',
        'Telemedicine Notifications',
        channelDescription: 'Notifications from Telemedicine app',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      );

      const iosDetails = DarwinNotificationDetails();

      final details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _localNotifications.zonedSchedule(
        id,
        title,
        body,
        tz.TZDateTime.from(scheduledTime, tz.local),
        details,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
        payload: payload,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );

      if (kDebugMode) {
        print('Scheduled notification $id for $scheduledTime');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error scheduling notification: $e');
      }
    }
  }

  // Cancel a scheduled notification
  Future<void> cancelNotification(int id) async {
    if (kIsWeb) return;

    try {
      await _localNotifications.cancel(id);
      if (kDebugMode) {
        print('Cancelled notification $id');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error cancelling notification: $e');
      }
    }
  }

  // Cancel all scheduled notifications
  Future<void> cancelAllNotifications() async {
    if (kIsWeb) return;

    try {
      await _localNotifications.cancelAll();
      if (kDebugMode) {
        print('Cancelled all notifications');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error cancelling all notifications: $e');
      }
    }
  }

  // Schedule a reminder for an appointment 30 minutes before it starts
  Future<void> scheduleAppointmentReminder(Appointment appointment) async {
    if (kIsWeb) return;

    // Only schedule for telemedicine appointments with a meeting link
    if (!appointment.isTelemedicine || appointment.meetingLink == null) {
      return;
    }

    try {
      // Parse the appointment date and time
      final appointmentDateTime = _parseAppointmentDateTime(
        appointment.preferredDate,
        appointment.preferredTime,
      );

      if (appointmentDateTime == null) {
        if (kDebugMode) {
          print('Failed to parse appointment datetime');
        }
        return;
      }

      // Calculate reminder time (30 minutes before appointment)
      final reminderTime = appointmentDateTime.subtract(const Duration(minutes: 30));

      // Only schedule if the reminder time is in the future
      if (reminderTime.isAfter(DateTime.now())) {
        // Use appointment ID as notification ID for uniqueness
        final notificationId = appointment.id.hashCode;

        await scheduleNotification(
          id: notificationId,
          title: 'Upcoming Telemedicine Appointment',
          body: 'Your appointment with ${appointment.doctorName ?? "your doctor"} starts in 30 minutes.',
          scheduledTime: reminderTime,
          payload: appointment.meetingLink,
        );

        if (kDebugMode) {
          print('Scheduled appointment reminder for $reminderTime');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error scheduling appointment reminder: $e');
      }
    }
  }

  // Schedule a notification when the meeting is due (at the exact meeting time)
  Future<void> scheduleMeetingStartNotification(Appointment appointment) async {
    if (kIsWeb) return;

    // Only schedule for telemedicine appointments with a meeting link
    if (!appointment.isTelemedicine || appointment.meetingLink == null) {
      return;
    }

    try {
      // Parse the appointment date and time
      final appointmentDateTime = _parseAppointmentDateTime(
        appointment.preferredDate,
        appointment.preferredTime,
      );

      if (appointmentDateTime == null) {
        if (kDebugMode) {
          print('Failed to parse appointment datetime');
        }
        return;
      }

      // Only schedule if the appointment time is in the future
      if (appointmentDateTime.isAfter(DateTime.now())) {
        // Use appointment ID + 1 as notification ID to avoid conflict with reminder
        final notificationId = appointment.id.hashCode + 1;

        await scheduleNotification(
          id: notificationId,
          title: 'Your Telemedicine Appointment is Due',
          body: 'Your appointment with ${appointment.doctorName ?? "your doctor"} is starting now. Tap to join the meeting.',
          scheduledTime: appointmentDateTime,
          payload: appointment.meetingLink,
        );

        if (kDebugMode) {
          print('Scheduled meeting start notification for $appointmentDateTime');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error scheduling meeting start notification: $e');
      }
    }
  }

  // Parse appointment date and time strings into DateTime
  DateTime? _parseAppointmentDateTime(String dateStr, String timeStr) {
    try {
      // Expected format: dateStr could be "2024-01-15" or similar
      // timeStr could be "14:30" or "2:30 PM" or similar
      
      // Try to parse the date
      final dateParts = dateStr.split('-');
      if (dateParts.length != 3) {
        return null;
      }

      final year = int.parse(dateParts[0]);
      final month = int.parse(dateParts[1]);
      final day = int.parse(dateParts[2]);

      // Try to parse the time
      int hour, minute;
      
      // Check if it's in 24-hour format (e.g., "14:30")
      if (timeStr.contains(':') && !timeStr.toLowerCase().contains('am') && !timeStr.toLowerCase().contains('pm')) {
        final timeParts = timeStr.split(':');
        hour = int.parse(timeParts[0]);
        minute = int.parse(timeParts[1]);
      } else {
        // Parse 12-hour format
        final isPM = timeStr.toLowerCase().contains('pm');
        final cleanTimeStr = timeStr.toLowerCase().replaceAll('am', '').replaceAll('pm', '').trim();
        final timeParts = cleanTimeStr.split(':');
        
        hour = int.parse(timeParts[0]);
        minute = timeParts.length > 1 ? int.parse(timeParts[1]) : 0;
        
        if (isPM && hour != 12) {
          hour += 12;
        } else if (!isPM && hour == 12) {
          hour = 0;
        }
      }

      return DateTime(year, month, day, hour, minute);
    } catch (e) {
      if (kDebugMode) {
        print('Error parsing appointment datetime: $e');
      }
      return null;
    }
  }

  // Schedule reminders for multiple appointments
  Future<void> scheduleAppointmentReminders(List<Appointment> appointments) async {
    if (kIsWeb) return;

    for (final appointment in appointments) {
      await scheduleAppointmentReminder(appointment);
      await scheduleMeetingStartNotification(appointment);
    }
  }
}