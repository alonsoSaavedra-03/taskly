import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/task_model.dart';

/// Servicio de Caché Local Inteligente (< 20 MB).
/// - Guarda únicamente preferencias, estado de onboarding/tutorial, últimas 150 tareas y cola offline.
/// - Nunca guarda contraseñas ni tokens sensibles (la sesión la gestiona supabase_flutter).
/// - Permite limpiar la caché local sin borrar las tareas almacenadas en Supabase.
class CacheService {
  static final CacheService _instance = CacheService._internal();
  factory CacheService() => _instance;
  CacheService._internal();

  static const int maxCachedTasks = 150;
  static const int maxCachedCategories = 50;
  static const int maxPendingOps = 100;

  static const String _keyOnboardingSeen = 'taskly_onboarding_seen';
  static String _keyTutorialStatus(String userId) =>
      'taskly_tutorial_status_$userId';
  static String _keyTasksCache(String userId) => 'taskly_tasks_cache_$userId';
  static String _keyCategoriesCache(String userId) =>
      'taskly_categories_cache_$userId';
  static String _keyPendingOps(String userId) => 'taskly_pending_ops_$userId';

  Future<bool> isOnboardingSeen() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyOnboardingSeen) ?? false;
  }

  Future<void> setOnboardingSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyOnboardingSeen, true);
  }

  Future<String> getTutorialStatus(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyTutorialStatus(userId)) ?? 'not_started';
  }

  Future<void> setTutorialStatus(String userId, String status) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyTutorialStatus(userId), status);
  }

  /// Guarda como máximo las 150 tareas más recientes para evitar crecimiento ilimitado.
  Future<void> saveRecentTasks(String userId, List<TaskModel> tasks) async {
    final prefs = await SharedPreferences.getInstance();
    final sorted = List<TaskModel>.from(tasks)
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final capped = sorted.take(maxCachedTasks).map((t) => t.toCacheJson()).toList();
    await prefs.setString(_keyTasksCache(userId), jsonEncode(capped));
  }

  Future<List<TaskModel>> loadRecentTasks(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyTasksCache(userId));
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(TaskModel.fromSupabase)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveCategories(
    String userId,
    List<Map<String, dynamic>> categories,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final capped = categories.take(maxCachedCategories).toList();
    await prefs.setString(_keyCategoriesCache(userId), jsonEncode(capped));
  }

  Future<List<Map<String, dynamic>>> loadCategories(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyCategoriesCache(userId));
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded.whereType<Map<String, dynamic>>().toList();
    } catch (_) {
      return [];
    }
  }

  /// Encola operaciones offline pendientes de sincronización (create | update | toggle | delete).
  Future<void> enqueuePendingOp(
    String userId,
    Map<String, dynamic> op,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await loadPendingOps(userId);
    list.add({
      ...op,
      'queued_at': DateTime.now().toUtc().toIso8601String(),
    });
    final capped = list.length > maxPendingOps
        ? list.sublist(list.length - maxPendingOps)
        : list;
    await prefs.setString(_keyPendingOps(userId), jsonEncode(capped));
  }

  Future<List<Map<String, dynamic>>> loadPendingOps(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyPendingOps(userId));
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded.whereType<Map<String, dynamic>>().toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> setPendingOps(
    String userId,
    List<Map<String, dynamic>> ops,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    if (ops.isEmpty) {
      await prefs.remove(_keyPendingOps(userId));
    } else {
      await prefs.setString(_keyPendingOps(userId), jsonEncode(ops));
    }
  }

  /// Limpia la caché local de tareas, categorías y cola sin borrar datos en Supabase.
  Future<void> clearUserDataCache(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyTasksCache(userId));
    await prefs.remove(_keyCategoriesCache(userId));
    await prefs.remove(_keyPendingOps(userId));
  }

  /// Estima el tamaño total en bytes usado por las claves de caché de Taskly.
  Future<int> estimateCacheBytes(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    int total = 0;
    for (final key in [
      _keyTasksCache(userId),
      _keyCategoriesCache(userId),
      _keyPendingOps(userId),
      _keyTutorialStatus(userId),
    ]) {
      final val = prefs.getString(key);
      if (val != null) {
        total += utf8.encode(val).length;
      }
    }
    return total;
  }
}
