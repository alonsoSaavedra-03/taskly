import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import '../models/task_model.dart';

/// Servicio de Notificaciones Push Locales e Interactivas (Android / iOS)
/// Incluye acciones rápidas ("Completar" y "Posponer +10 min"), zonas horarias y deduplicación por ID.
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  Future<void> initialize({
    void Function(String? payload, String? actionId)? onNotificationAction,
  }) async {
    tz.initializeTimeZones();

    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notificationsPlugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        if (onNotificationAction != null) {
          onNotificationAction(response.payload, response.actionId);
        }
      },
    );

    final androidImplementation =
        _notificationsPlugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidImplementation?.requestNotificationsPermission();
    await androidImplementation?.requestExactAlarmsPermission();
  }

  /// Programa un recordatorio interactivo evitando duplicados mediante el hashCode determinista del ID
  Future<void> scheduleTaskReminder(TaskModel task) async {
    if (!task.hasReminder || task.dueDate.isBefore(DateTime.now())) return;

    await cancelReminder(task.id);

    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      'taskly_reminders_channel',
      'Recordatorios de Tareas Taskly',
      channelDescription:
          'Alertas y recordatorios interactivos para tus actividades en Taskly',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      actions: <AndroidNotificationAction>[
        AndroidNotificationAction(
          'ACTION_COMPLETE',
          'Completar',
          showsUserInterface: true,
        ),
        AndroidNotificationAction(
          'ACTION_SNOOZE_10',
          'Posponer +10m',
          showsUserInterface: true,
        ),
      ],
    );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const NotificationDetails platformDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notificationsPlugin.zonedSchedule(
      task.id.hashCode,
      'Recordatorio: ${task.title}',
      'Categoría: ${task.category} • Prioridad: ${task.priority.name.toUpperCase()}',
      tz.TZDateTime.from(task.dueDate, tz.local),
      platformDetails,
      payload: task.id,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  /// Pospone el recordatorio de una tarea por N minutos (Snooze)
  Future<void> snoozeTaskReminder(TaskModel task, {int minutes = 10}) async {
    await cancelReminder(task.id);
    final snoozedDate = DateTime.now().add(Duration(minutes: minutes));
    final snoozedTask = task.copyWith(dueDate: snoozedDate, hasReminder: true);
    await scheduleTaskReminder(snoozedTask);
  }

  /// Envía una notificación local instantánea sin emojis Unicode
  Future<void> sendTestNotification(
    String title,
    String body, {
    String? taskId,
  }) async {
    const NotificationDetails details = NotificationDetails(
      android: AndroidNotificationDetails(
        'taskly_reminders_channel',
        'Recordatorios de Tareas Taskly',
        channelDescription:
            'Alertas y recordatorios interactivos para tus actividades en Taskly',
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
        actions: <AndroidNotificationAction>[
          AndroidNotificationAction(
            'ACTION_COMPLETE',
            'Completar',
            showsUserInterface: true,
          ),
          AndroidNotificationAction(
            'ACTION_SNOOZE_10',
            'Posponer +10m',
            showsUserInterface: true,
          ),
        ],
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );

    await _notificationsPlugin.show(
      (taskId ?? 'test_notif').hashCode,
      title,
      body,
      details,
      payload: taskId,
    );
  }

  /// Cancela el recordatorio cuando una tarea se completa o elimina
  Future<void> cancelReminder(String taskId) async {
    await _notificationsPlugin.cancel(taskId.hashCode);
  }
}
