enum TaskPriority { baja, media, alta }

class SubtaskItem {
  final String id;
  final String taskId;
  final String title;
  final bool isCompleted;

  const SubtaskItem({
    required this.id,
    required this.taskId,
    required this.title,
    this.isCompleted = false,
  });

  factory SubtaskItem.fromSupabase(Map<String, dynamic> row) {
    return SubtaskItem(
      id: (row['id'] as String?) ?? '',
      taskId: (row['task_id'] as String?) ?? '',
      title: (row['title'] as String?) ?? '',
      isCompleted: (row['is_completed'] as bool?) ?? false,
    );
  }
}

class TaskModel {
  final String id;
  final String userId;
  final String title;
  final String description;
  final String category;
  final String? categoryId;
  final TaskPriority priority;
  final DateTime dueDate;
  final String dueTime;
  final String status; // 'pendiente' | 'en_progreso' | 'completada'
  final bool isCompleted;
  final bool hasReminder;
  final String reminderOffset; // mapeado a reminder_label en PostgreSQL
  final String repeatRule; // mapeado a recurrence en PostgreSQL ('Nunca' | 'Diario' | 'Semanal' | 'Mensual')
  final String assignedTo; // mapeado a assigned_to (text[]) en PostgreSQL
  final List<SubtaskItem> subtasks;
  final DateTime updatedAt;

  TaskModel({
    required this.id,
    this.userId = '',
    required this.title,
    required this.description,
    required this.category,
    this.categoryId,
    required this.priority,
    required this.dueDate,
    this.dueTime = '11:30',
    this.status = 'pendiente',
    this.isCompleted = false,
    this.hasReminder = true,
    this.reminderOffset = '30 min antes',
    this.repeatRule = 'Nunca',
    this.assignedTo = '',
    this.subtasks = const [],
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  TaskModel copyWith({
    String? id,
    String? userId,
    String? title,
    String? description,
    String? category,
    String? categoryId,
    TaskPriority? priority,
    DateTime? dueDate,
    String? dueTime,
    String? status,
    bool? isCompleted,
    bool? hasReminder,
    String? reminderOffset,
    String? repeatRule,
    String? assignedTo,
    List<SubtaskItem>? subtasks,
    DateTime? updatedAt,
  }) {
    final nextCompleted = isCompleted ?? this.isCompleted;
    return TaskModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      title: title ?? this.title,
      description: description ?? this.description,
      category: category ?? this.category,
      categoryId: categoryId ?? this.categoryId,
      priority: priority ?? this.priority,
      dueDate: dueDate ?? this.dueDate,
      dueTime: dueTime ?? this.dueTime,
      status: status ?? (nextCompleted ? 'completada' : 'pendiente'),
      isCompleted: nextCompleted,
      hasReminder: hasReminder ?? this.hasReminder,
      reminderOffset: reminderOffset ?? this.reminderOffset,
      repeatRule: repeatRule ?? this.repeatRule,
      assignedTo: assignedTo ?? this.assignedTo,
      subtasks: subtasks ?? this.subtasks,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  /// Convierte el modelo exactamente al esquema PostgreSQL (`public.tasks`) de `20261114000000_taskly_schema_and_rls.sql`
  Map<String, dynamic> toSupabaseMap(String currentUserId) {
    final dateIso = dueDate.toIso8601String().split('T').first;
    final assignedList = assignedTo
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    return {
      'id': id,
      'user_id': userId.isNotEmpty ? userId : currentUserId,
      'title': title,
      'description': description,
      'category_id': categoryId,
      'priority': priority.name,
      'status': isCompleted ? 'completada' : status,
      'due_date': dateIso,
      'due_time': dueTime,
      'reminder_label': hasReminder ? reminderOffset : '30 min antes',
      'recurrence': repeatRule,
      'assigned_to': assignedList,
      'completed_at':
          isCompleted ? DateTime.now().toUtc().toIso8601String() : null,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
  }

  /// Construye un TaskModel desde una fila de PostgreSQL en Supabase (`public.tasks`)
  factory TaskModel.fromSupabase(Map<String, dynamic> row) {
    final rawStatus = (row['status'] as String?) ?? 'pendiente';
    final completed = rawStatus == 'completada';
    final rawDate = (row['due_date'] as String?) ??
        DateTime.now().toIso8601String().split('T').first;
    final rawTime =
        ((row['due_time'] as String?) ?? '11:30').split(':').take(2).join(':');
    final parsedDate =
        DateTime.tryParse('${rawDate}T$rawTime:00') ?? DateTime.now();

    final rawAssigned = row['assigned_to'];
    final assignedStr = rawAssigned is List
        ? rawAssigned.map((e) => e.toString()).join(', ')
        : (rawAssigned?.toString() ?? '');

    final rawSubs = row['subtasks'];
    final parsedSubs = rawSubs is List
        ? rawSubs
            .whereType<Map<String, dynamic>>()
            .map(SubtaskItem.fromSupabase)
            .toList()
        : <SubtaskItem>[];

    return TaskModel(
      id: (row['id'] as String?) ?? '',
      userId: (row['user_id'] as String?) ?? '',
      title: (row['title'] as String?) ?? '',
      description: (row['description'] as String?) ?? '',
      category: (row['category_name'] as String?) ?? 'Trabajo',
      categoryId: row['category_id'] as String?,
      priority: TaskPriority.values.firstWhere(
        (e) => e.name == (row['priority'] ?? 'media'),
        orElse: () => TaskPriority.media,
      ),
      dueDate: parsedDate,
      dueTime: rawTime,
      status: rawStatus,
      isCompleted: completed,
      hasReminder: row['reminder_label'] != null,
      reminderOffset: (row['reminder_label'] as String?) ?? '30 min antes',
      repeatRule: (row['recurrence'] as String?) ?? 'Nunca',
      assignedTo: assignedStr,
      subtasks: parsedSubs,
      updatedAt: DateTime.tryParse((row['updated_at'] as String?) ?? '') ??
          DateTime.now(),
    );
  }

  /// Serialización compacta para caché local inteligente (< 20 MB, máx. 150 tareas)
  Map<String, dynamic> toCacheJson() {
    return {
      'id': id,
      'user_id': userId,
      'title': title,
      'description': description,
      'category_name': category,
      'category_id': categoryId,
      'priority': priority.name,
      'status': isCompleted ? 'completada' : status,
      'due_date': dueDate.toIso8601String().split('T').first,
      'due_time': dueTime,
      'reminder_label': hasReminder ? reminderOffset : null,
      'recurrence': repeatRule,
      'assigned_to': assignedTo
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
    };
  }
}
