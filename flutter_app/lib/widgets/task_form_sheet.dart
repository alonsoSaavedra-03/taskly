import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:uuid/uuid.dart';
import '../models/task_model.dart';

class TaskFormSheet extends StatefulWidget {
  final TaskModel? existingTask;
  final Function(TaskModel) onSave;

  const TaskFormSheet({
    super.key,
    this.existingTask,
    required this.onSave,
  });

  @override
  State<TaskFormSheet> createState() => _TaskFormSheetState();
}

class _TaskFormSheetState extends State<TaskFormSheet> {
  late TextEditingController _titleController;
  late TextEditingController _descController;
  late TextEditingController _assignedController;

  String _selectedCategory = 'Trabajo';
  TaskPriority _selectedPriority = TaskPriority.media;
  DateTime _selectedDate = DateTime.now().add(const Duration(hours: 2));
  bool _hasReminder = true;
  bool _showMoreOptions = false;
  String? _titleError;

  final List<String> _categories = [
    'Trabajo',
    'Personal',
    'Estudios',
    'Salud',
    'Proyectos'
  ];

  @override
  void initState() {
    super.initState();
    final task = widget.existingTask;
    _titleController = TextEditingController(text: task?.title ?? '');
    _descController = TextEditingController(text: task?.description ?? '');
    _assignedController =
        TextEditingController(text: task?.assignedTo ?? 'Valeria Mendoza');
    if (task != null) {
      _selectedCategory = task.category;
      _selectedPriority = task.priority;
      _selectedDate = task.dueDate;
      _hasReminder = task.hasReminder;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    _assignedController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_titleController.text.trim().isEmpty) {
      setState(() => _titleError = 'Escribe un título para continuar.');
      return;
    }

    final task = TaskModel(
      id: widget.existingTask?.id ?? const Uuid().v4(),
      title: _titleController.text.trim(),
      description: _descController.text.trim(),
      category: _selectedCategory,
      priority: _selectedPriority,
      dueDate: _selectedDate,
      isCompleted: widget.existingTask?.isCompleted ?? false,
      hasReminder: _hasReminder,
      assignedTo: _assignedController.text.trim(),
    );

    widget.onSave(task);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.outline,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          widget.existingTask == null
                              ? 'Nueva tarea'
                              : 'Editar tarea',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(LucideIcons.x, size: 18),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _titleController,
                      autofocus: widget.existingTask == null,
                      onChanged: (_) {
                        if (_titleError != null) {
                          setState(() => _titleError = null);
                        }
                      },
                      decoration: InputDecoration(
                        labelText: 'Título',
                        errorText: _titleError,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _descController,
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: 'Descripción (opcional)',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<TaskPriority>(
                            initialValue: _selectedPriority,
                            decoration: InputDecoration(
                              labelText: 'Prioridad',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            items: TaskPriority.values
                                .map((p) => DropdownMenuItem(
                                      value: p,
                                      child: Text(p.name),
                                    ))
                                .toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setState(() => _selectedPriority = val);
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: _selectedCategory,
                            decoration: InputDecoration(
                              labelText: 'Categoría',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            items: _categories
                                .map((c) => DropdownMenuItem(
                                      value: c,
                                      child: Text(c),
                                    ))
                                .toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setState(() => _selectedCategory = val);
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: () =>
                          setState(() => _showMoreOptions = !_showMoreOptions),
                      icon: Icon(_showMoreOptions
                          ? LucideIcons.chevronUp
                          : LucideIcons.chevronDown),
                      label: const Text('Más opciones'),
                    ),
                    if (_showMoreOptions) ...[
                      const SizedBox(height: 8),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Recordatorio automático'),
                        value: _hasReminder,
                        onChanged: (val) =>
                            setState(() => _hasReminder = val),
                      ),
                      TextField(
                        controller: _assignedController,
                        decoration: InputDecoration(
                          labelText: 'Responsables',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              width: double.infinity,
              child: FilledButton(
                onPressed: _submit,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text(widget.existingTask == null
                    ? 'Crear tarea'
                    : 'Guardar cambios'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
