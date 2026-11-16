import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taskly/models/task_model.dart';
import 'package:taskly/services/cache_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TaskModel', () {
    test('serializa y deserializa correctamente entre Supabase y caché', () {
      final task = TaskModel(
        id: 't-1',
        userId: 'u-1',
        title: 'Revisar entrega Android',
        description: 'Verificar APK release',
        category: 'Trabajo',
        priority: TaskPriority.alta,
        dueDate: DateTime(2026, 11, 20, 10, 30),
        dueTime: '10:30',
        status: 'pendiente',
        isCompleted: false,
      );

      final supaMap = task.toSupabaseMap('u-1');
      expect(supaMap['title'], 'Revisar entrega Android');
      expect(supaMap['priority'], 'alta');
      expect(supaMap['status'], 'pendiente');

      final cached = task.toCacheJson();
      final restored = TaskModel.fromSupabase(cached);
      expect(restored.id, 't-1');
      expect(restored.title, 'Revisar entrega Android');
      expect(restored.priority, TaskPriority.alta);
    });
  });

  group('CacheService', () {
    test('limita la caché a 150 tareas y permite limpiar sin perder onboarding', () async {
      SharedPreferences.setMockInitialValues({});
      final cache = CacheService();
      await cache.setOnboardingSeen();

      final largeList = List.generate(
        220,
        (i) => TaskModel(
          id: 'task-$i',
          userId: 'user-a',
          title: 'Tarea #$i',
          description: '',
          category: 'General',
          priority: TaskPriority.media,
          dueDate: DateTime(2026, 11, 20),
        ),
      );

      await cache.saveRecentTasks('user-a', largeList);
      final loaded = await cache.loadRecentTasks('user-a');
      expect(loaded.length, CacheService.maxCachedTasks);

      final bytes = await cache.estimateCacheBytes('user-a');
      expect(bytes, greaterThan(0));
      expect(bytes, lessThan(20 * 1024 * 1024));

      await cache.clearUserDataCache('user-a');
      final afterClear = await cache.loadRecentTasks('user-a');
      expect(afterClear, isEmpty);
      expect(await cache.isOnboardingSeen(), isTrue);
    });
  });

  group('Rendimiento de listas virtualizadas (0, 10, 100 y 1000 tareas)', () {
    for (final count in [0, 10, 100, 1000]) {
      testWidgets('Renderiza ListView.builder con $count tareas sin bloqueo',
          (tester) async {
        final items = List.generate(
          count,
          (i) => TaskModel(
            id: 'perf-$i',
            title: 'Tarea de rendimiento #$i',
            description: '',
            category: 'Trabajo',
            priority: TaskPriority.media,
            dueDate: DateTime(2026, 11, 20),
          ),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: items.isEmpty
                  ? const Center(child: Text('Sin tareas'))
                  : ListView.builder(
                      itemCount: items.length,
                      itemBuilder: (_, idx) => ListTile(
                        title: Text(items[idx].title),
                      ),
                    ),
            ),
          ),
        );

        if (count == 0) {
          expect(find.text('Sin tareas'), findsOneWidget);
        } else {
          expect(find.byType(ListTile), findsWidgets);
        }
      });
    }
  });
}
