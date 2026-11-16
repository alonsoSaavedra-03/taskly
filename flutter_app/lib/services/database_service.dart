import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/task_model.dart';
import 'cache_service.dart';

/// Servicio de Base de Datos y Sincronización Selectiva con Supabase Free (PostgreSQL + RLS).
/// Optimizaciones aplicadas:
/// - Consultas SELECT con columnas explícitas (nunca SELECT *).
/// - Paginación y filtros ejecutados en PostgreSQL.
/// - Realtime selectivo con pausa en segundo plano para ahorrar batería y datos.
/// - Caché local inteligente acotada (< 20 MB, máx. 150 tareas) y cola offline.
class DatabaseService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final CacheService _cache = CacheService();

  RealtimeChannel? _tasksChannel;
  bool _realtimePaused = false;

  static const String _taskColumns =
      'id, user_id, title, description, category_id, priority, status, due_date, due_time, reminder_label, recurrence, assigned_to, completed_at, updated_at';
  static const String _categoryColumns = 'id, user_id, name, color, icon, created_at';
  static const String _subtaskColumns = 'id, task_id, title, is_completed, position';
  static const String _reminderColumns = 'id, task_id, title, message, remind_at, is_read, created_at';

  User? get currentUser => _supabase.auth.currentUser;
  bool get isAuthenticated => _supabase.auth.currentSession != null;
  String? get currentUserId => _supabase.auth.currentUser?.id;

  Stream<AuthState> get authStateChanges => _supabase.auth.onAuthStateChange;

  /// 1. Autenticación Real en Supabase Auth (registro directo sin verificación por correo)
  Future<AuthResponse> signUp({
    required String email,
    required String password,
    required String fullName,
  }) async {
    return await _supabase.auth.signUp(
      email: email.trim().toLowerCase(),
      password: password,
      data: {'full_name': fullName.trim()},
    );
  }

  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    return await _supabase.auth.signInWithPassword(
      email: email.trim().toLowerCase(),
      password: password,
    );
  }

  Future<void> signOut() async {
    await unsubscribeRealtime();
    await _supabase.auth.signOut();
  }

  /// Eliminar permanentemente la cuenta y datos personales del usuario autenticado mediante RPC RLS
  Future<void> deleteOwnAccount() async {
    final uid = currentUserId;
    await unsubscribeRealtime();
    await _supabase.rpc('delete_own_account');
    if (uid != null) {
      await _cache.clearUserDataCache(uid);
    }
    await _supabase.auth.signOut();
  }

  /// 2. Perfil y Preferencias (`public.profiles`, `public.user_preferences`)
  Future<Map<String, dynamic>?> fetchProfile() async {
    final uid = currentUserId;
    if (uid == null) return null;
    return await _supabase
        .from('profiles')
        .select('id, full_name, email, role_title, updated_at')
        .eq('id', uid)
        .maybeSingle();
  }

  Future<void> updateProfile({
    required String fullName,
    required String email,
    required String roleTitle,
  }) async {
    final uid = currentUserId;
    if (uid == null) return;
    await _supabase.from('profiles').upsert({
      'id': uid,
      'full_name': fullName,
      'email': email,
      'role_title': roleTitle,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<Map<String, dynamic>?> fetchUserPreferences() async {
    final uid = currentUserId;
    if (uid == null) return null;
    return await _supabase
        .from('user_preferences')
        .select('user_id, tutorial_status, theme_mode, accent_color, border_radius, card_density, font_scale, floating_nav, notifications_enabled, sound_enabled')
        .eq('user_id', uid)
        .maybeSingle();
  }

  Future<void> saveUserPreferences(Map<String, dynamic> prefs) async {
    final uid = currentUserId;
    if (uid == null) return;
    await _supabase.from('user_preferences').upsert({
      'user_id': uid,
      ...prefs,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  /// 3. Categorías (`public.categories`)
  Future<List<Map<String, dynamic>>> fetchCategories() async {
    final uid = currentUserId;
    if (uid == null) return [];
    try {
      final rows = await _supabase
          .from('categories')
          .select(_categoryColumns)
          .order('created_at', ascending: true)
          .limit(50);
      final list = List<Map<String, dynamic>>.from(rows);
      await _cache.saveCategories(uid, list);
      return list;
    } catch (_) {
      return await _cache.loadCategories(uid);
    }
  }

  Future<void> createCategory({
    required String name,
    required String color,
    required String icon,
  }) async {
    final uid = currentUserId;
    if (uid == null) return;
    await _supabase.from('categories').insert({
      'user_id': uid,
      'name': name,
      'color': color,
      'icon': icon,
    });
  }

  Future<void> deleteCategory(String categoryId) async {
    if (!isAuthenticated) return;
    await _supabase.from('categories').delete().eq('id', categoryId);
  }

  /// 4. Tareas paginadas y filtradas en PostgreSQL (`public.tasks`)
  Future<List<TaskModel>> fetchTasksPage({
    int limit = 50,
    int offset = 0,
    String? status,
    String? categoryId,
    DateTime? dueDate,
  }) async {
    final uid = currentUserId;
    if (uid == null) return [];

    try {
      var query = _supabase
          .from('tasks')
          .select(_taskColumns)
          .eq('user_id', uid);

      if (status != null && status != 'todas') {
        query = query.eq('status', status);
      }
      if (categoryId != null && categoryId.isNotEmpty) {
        query = query.eq('category_id', categoryId);
      }
      if (dueDate != null) {
        final dateIso = dueDate.toIso8601String().split('T').first;
        query = query.eq('due_date', dateIso);
      }

      final rows = await query
          .order('due_date', ascending: true)
          .order('due_time', ascending: true)
          .range(offset, offset + limit - 1);

      final tasks = List<Map<String, dynamic>>.from(rows)
          .map(TaskModel.fromSupabase)
          .toList();

      if (offset == 0 && status == null && categoryId == null && dueDate == null) {
        await _cache.saveRecentTasks(uid, tasks);
      }
      return tasks;
    } catch (_) {
      if (offset == 0) {
        return await _cache.loadRecentTasks(uid);
      }
      return [];
    }
  }

  /// Suscripción Realtime selectiva (solo cambios en filas del usuario actual)
  void subscribeTasksRealtime(void Function() onChanged) {
    final uid = currentUserId;
    if (uid == null) return;
    _realtimePaused = false;
    if (_tasksChannel != null) {
      _supabase.removeChannel(_tasksChannel!);
      _tasksChannel = null;
    }
    _tasksChannel = _supabase
        .channel('taskly-tasks-$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'tasks',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: uid,
          ),
          callback: (_) {
            if (!_realtimePaused) {
              onChanged();
            }
          },
        )
        .subscribe();
  }

  Future<void> pauseRealtime() async {
    _realtimePaused = true;
    await unsubscribeRealtime();
  }

  Future<void> unsubscribeRealtime() async {
    if (_tasksChannel != null) {
      try {
        await _supabase.removeChannel(_tasksChannel!);
      } catch (_) {}
      _tasksChannel = null;
    }
  }

  Future<void> createTask(TaskModel task) async {
    final uid = currentUserId;
    if (uid == null) return;
    final payload = task.toSupabaseMap(uid);
    try {
      await _supabase.from('tasks').insert(payload);
    } catch (_) {
      await _cache.enqueuePendingOp(uid, {'op': 'insert', 'payload': payload});
      rethrow;
    }
  }

  Future<void> updateTask(TaskModel task) async {
    final uid = currentUserId;
    if (uid == null) return;
    final payload = task.toSupabaseMap(uid);
    try {
      await _supabase
          .from('tasks')
          .update(payload)
          .eq('id', task.id)
          .eq('user_id', uid);
    } catch (_) {
      await _cache.enqueuePendingOp(uid, {
        'op': 'update',
        'id': task.id,
        'payload': payload,
      });
      rethrow;
    }
  }

  Future<void> toggleTaskStatus(String taskId, bool isCompleted) async {
    final uid = currentUserId;
    if (uid == null) return;
    final patch = {
      'status': isCompleted ? 'completada' : 'pendiente',
      'completed_at':
          isCompleted ? DateTime.now().toUtc().toIso8601String() : null,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    try {
      await _supabase
          .from('tasks')
          .update(patch)
          .eq('id', taskId)
          .eq('user_id', uid);
    } catch (_) {
      await _cache.enqueuePendingOp(uid, {
        'op': 'toggle',
        'id': taskId,
        'payload': patch,
      });
      rethrow;
    }
  }

  Future<void> deleteTask(String taskId) async {
    final uid = currentUserId;
    if (uid == null) return;
    try {
      await _supabase
          .from('tasks')
          .delete()
          .eq('id', taskId)
          .eq('user_id', uid);
    } catch (_) {
      await _cache.enqueuePendingOp(uid, {'op': 'delete', 'id': taskId});
      rethrow;
    }
  }

  /// Sincroniza operaciones pendientes acumuladas sin conexión al recuperar conectividad.
  Future<int> syncPendingOperations() async {
    final uid = currentUserId;
    if (uid == null) return 0;
    final ops = await _cache.loadPendingOps(uid);
    if (ops.isEmpty) return 0;

    final remaining = <Map<String, dynamic>>[];
    int synced = 0;

    for (final item in ops) {
      try {
        final op = item['op'] as String?;
        if (op == 'insert') {
          await _supabase.from('tasks').insert(item['payload']);
          synced++;
        } else if (op == 'update' || op == 'toggle') {
          await _supabase
              .from('tasks')
              .update(item['payload'])
              .eq('id', item['id'])
              .eq('user_id', uid);
          synced++;
        } else if (op == 'delete') {
          await _supabase
              .from('tasks')
              .delete()
              .eq('id', item['id'])
              .eq('user_id', uid);
          synced++;
        }
      } catch (_) {
        remaining.add(item);
      }
    }

    await _cache.setPendingOps(uid, remaining);
    return synced;
  }

  /// 5. Subtareas (`public.subtasks`)
  Future<List<SubtaskItem>> fetchSubtasks(String taskId) async {
    final rows = await _supabase
        .from('subtasks')
        .select(_subtaskColumns)
        .eq('task_id', taskId)
        .order('position', ascending: true);
    return List<Map<String, dynamic>>.from(rows)
        .map(SubtaskItem.fromSupabase)
        .toList();
  }

  Future<void> addSubtask(String taskId, String title) async {
    await _supabase.from('subtasks').insert({
      'task_id': taskId,
      'title': title,
      'is_completed': false,
    });
  }

  Future<void> toggleSubtask(String subtaskId, bool isCompleted) async {
    await _supabase
        .from('subtasks')
        .update({'is_completed': isCompleted})
        .eq('id', subtaskId);
  }

  Future<void> deleteSubtask(String subtaskId) async {
    await _supabase.from('subtasks').delete().eq('id', subtaskId);
  }

  /// 6. Recordatorios y Notificaciones (`public.reminders`, máx. 50 recientes)
  Future<List<Map<String, dynamic>>> fetchReminders({int limit = 50}) async {
    final uid = currentUserId;
    if (uid == null) return [];
    final rows = await _supabase
        .from('reminders')
        .select(_reminderColumns)
        .eq('user_id', uid)
        .order('created_at', ascending: false)
        .limit(limit);
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<void> createReminder({
    String? taskId,
    required String title,
    required String message,
  }) async {
    final uid = currentUserId;
    if (uid == null) return;
    await _supabase.from('reminders').insert({
      'user_id': uid,
      'task_id': taskId,
      'title': title,
      'message': message,
      'remind_at': DateTime.now().toUtc().toIso8601String(),
      'is_read': false,
    });
  }

  Future<void> markAllRemindersRead() async {
    final uid = currentUserId;
    if (uid == null) return;
    await _supabase
        .from('reminders')
        .update({'is_read': true})
        .eq('user_id', uid)
        .eq('is_read', false);
  }
}
