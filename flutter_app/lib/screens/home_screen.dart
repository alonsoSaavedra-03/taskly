import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../models/task_model.dart';
import '../providers/theme_provider.dart';
import '../services/cache_service.dart';
import '../services/database_service.dart';
import '../services/notification_service.dart';
import '../widgets/task_form_sheet.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final DatabaseService _dbService = DatabaseService();
  final CacheService _cacheService = CacheService();
  final NotificationService _notificationService = NotificationService();

  static const int _pageSize = 50;

  int _currentTabIndex = 0;
  String _statusFilter = 'todas'; // 'todas' | 'pendiente' | 'completada'
  String _categoryFilter = 'Todas';
  String _searchQuery = '';
  DateTime _selectedDate = DateTime.now();
  int _weekOffset = 0;

  List<TaskModel> _tasks = [];
  List<Map<String, dynamic>> _categories = [];
  List<Map<String, dynamic>> _reminders = [];
  bool _isLoadingTasks = true;
  bool _hasMoreTasks = false;
  int _cacheBytes = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initHomeData();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _dbService.unsubscribeRealtime();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      // Ahorro de batería y datos: suspender Realtime en segundo plano
      _dbService.pauseRealtime();
    } else if (state == AppLifecycleState.resumed) {
      // Sincronizar cola offline y reanudar Realtime al volver a primer plano
      _dbService.syncPendingOperations().then((_) {
        _refreshTasks(reset: true);
        _dbService.subscribeTasksRealtime(() => _refreshTasks(reset: true));
      });
    }
  }

  Future<void> _initHomeData() async {
    await _dbService.syncPendingOperations();
    await _refreshTasks(reset: true);
    await _refreshCategoriesAndReminders();
    await _updateCacheSize();
    _dbService.subscribeTasksRealtime(() => _refreshTasks(reset: true));
    await _checkFirstTimeTutorial();
  }

  Future<void> _checkFirstTimeTutorial() async {
    final uid = _dbService.currentUserId;
    if (uid == null) return;
    final prefs = await _dbService.fetchUserPreferences();
    final remoteStatus = prefs?['tutorial_status'] as String?;
    final localStatus = await _cacheService.getTutorialStatus(uid);
    final effective = remoteStatus ?? localStatus;
    if (effective == 'not_started' && mounted) {
      await _cacheService.setTutorialStatus(uid, 'completed');
      await _dbService.saveUserPreferences({'tutorial_status': 'completed'});
      if (mounted) _openInteractiveTutorialDialog();
    }
  }

  Future<void> _refreshTasks({bool reset = false}) async {
    if (!mounted) return;
    if (reset) {
      setState(() => _isLoadingTasks = true);
    }
    final offset = reset ? 0 : _tasks.length;
    final fetched = await _dbService.fetchTasksPage(
      limit: _pageSize,
      offset: offset,
    );
    if (!mounted) return;
    setState(() {
      if (reset) {
        _tasks = fetched;
      } else {
        _tasks = [..._tasks, ...fetched];
      }
      _hasMoreTasks = fetched.length == _pageSize;
      _isLoadingTasks = false;
    });
    await _updateCacheSize();
  }

  Future<void> _refreshCategoriesAndReminders() async {
    final cats = await _dbService.fetchCategories();
    final rems = await _dbService.fetchReminders(limit: 50);
    if (!mounted) return;
    setState(() {
      _categories = cats;
      _reminders = rems;
    });
  }

  Future<void> _updateCacheSize() async {
    final uid = _dbService.currentUserId;
    if (uid == null) return;
    final bytes = await _cacheService.estimateCacheBytes(uid);
    if (mounted) setState(() => _cacheBytes = bytes);
  }

  static const List<Color> _accentSwatches = [
    Color(0xFFA5B4FC), // Índigo Suave
    Color(0xFF6366F1), // Índigo Vibrante
    Color(0xFF38BDF8), // Cielo
    Color(0xFF34D399), // Esmeralda
    Color(0xFFF472B6), // Rosa
    Color(0xFFFBBF24), // Ámbar
    Color(0xFFC084FC), // Violeta
    Color(0xFFFB7185), // Coral
  ];

  void _openTaskForm([TaskModel? task]) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(
            Provider.of<ThemeProvider>(context, listen: false).cardRadius + 8,
          ),
        ),
      ),
      builder: (_) => TaskFormSheet(
        existingTask: task,
        onSave: (savedTask) async {
          if (task == null) {
            await _dbService.createTask(savedTask);
          } else {
            await _dbService.updateTask(savedTask);
          }
          if (savedTask.hasReminder) {
            await _notificationService.scheduleTaskReminder(savedTask);
          } else {
            await _notificationService.cancelReminder(savedTask.id);
          }
          await _refreshTasks(reset: true);
        },
      ),
    );
  }

  void _openTaskDetailSheet(TaskModel task) {
    final subtaskCtrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return FutureBuilder<List<SubtaskItem>>(
              future: _dbService.fetchSubtasks(task.id),
              builder: (context, snapshot) {
                final subtasks = snapshot.data ?? task.subtasks;
                return Padding(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    18,
                    20,
                    MediaQuery.of(context).viewInsets.bottom + 24,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Chip(label: Text(task.category)),
                          Row(
                            children: [
                              IconButton(
                                icon: const Icon(LucideIcons.pencil, size: 18),
                                tooltip: 'Editar tarea',
                                onPressed: () {
                                  Navigator.pop(ctx);
                                  _openTaskForm(task);
                                },
                              ),
                              IconButton(
                                icon: const Icon(
                                  LucideIcons.trash2,
                                  size: 18,
                                  color: Colors.redAccent,
                                ),
                                tooltip: 'Eliminar tarea',
                                onPressed: () async {
                                  await _dbService.deleteTask(task.id);
                                  if (ctx.mounted) Navigator.pop(ctx);
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        task.title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (task.description.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          task.description,
                          style: const TextStyle(color: Colors.grey),
                        ),
                      ],
                      const SizedBox(height: 16),
                      Text(
                        'Subtareas (${subtasks.where((s) => s.isCompleted).length}/${subtasks.length})',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      ...subtasks.map(
                        (s) => CheckboxListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          value: s.isCompleted,
                          title: Text(
                            s.title,
                            style: TextStyle(
                              decoration: s.isCompleted
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          ),
                          secondary: IconButton(
                            icon: const Icon(LucideIcons.x, size: 16),
                            onPressed: () async {
                              await _dbService.deleteSubtask(s.id);
                              setModalState(() {});
                            },
                          ),
                          onChanged: (val) async {
                            await _dbService.toggleSubtask(s.id, val ?? false);
                            setModalState(() {});
                          },
                        ),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: subtaskCtrl,
                              decoration: const InputDecoration(
                                hintText: 'Añadir subtarea...',
                                isDense: true,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(LucideIcons.plus),
                            onPressed: () async {
                              final txt = subtaskCtrl.text.trim();
                              if (txt.isEmpty) return;
                              subtaskCtrl.clear();
                              await _dbService.addSubtask(task.id, txt);
                              setModalState(() {});
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  void _openNotificationsSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Notificaciones',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                    TextButton(
                      onPressed: () async {
                        await _dbService.markAllRemindersRead();
                        await _refreshCategoriesAndReminders();
                        if (ctx.mounted) Navigator.pop(ctx);
                      },
                      child: const Text('Marcar leídas'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (_reminders.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      'Sin notificaciones recientes.',
                      textAlign: TextAlign.center,
                    ),
                  )
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 320),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _reminders.length,
                      itemBuilder: (_, idx) {
                        final r = _reminders[idx];
                        return ListTile(
                          leading: Icon(
                            r['is_read'] == true
                                ? LucideIcons.bell
                                : LucideIcons.bellRing,
                            size: 18,
                          ),
                          title: Text((r['title'] as String?) ?? 'Recordatorio'),
                          subtitle: Text((r['message'] as String?) ?? ''),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _openCategoriesSheet() {
    final nameCtrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                20,
                20,
                MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Categorías',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: nameCtrl,
                          decoration: const InputDecoration(
                            hintText: 'Nueva categoría...',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () async {
                          final n = nameCtrl.text.trim();
                          if (n.isEmpty) return;
                          await _dbService.createCategory(
                            name: n,
                            color: '#A5B4FC',
                            icon: 'folder',
                          );
                          nameCtrl.clear();
                          await _refreshCategoriesAndReminders();
                          setModalState(() {});
                        },
                        child: const Text('Crear'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_categories.isEmpty)
                    const Text('Aún no has creado categorías personalizadas.')
                  else
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 240),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: _categories.length,
                        itemBuilder: (_, idx) {
                          final c = _categories[idx];
                          return ListTile(
                            leading: const Icon(LucideIcons.folder, size: 18),
                            title: Text((c['name'] as String?) ?? ''),
                            trailing: IconButton(
                              icon: const Icon(LucideIcons.trash2, size: 18),
                              onPressed: () async {
                                await _dbService.deleteCategory(c['id'] as String);
                                await _refreshCategoriesAndReminders();
                                setModalState(() {});
                              },
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _openInteractiveTutorialDialog() {
    final steps = [
      const (
        'Paso 1 de 4 • Organiza tu día',
        'Selecciona una fecha en el calendario semanal para consultar tus actividades.'
      ),
      const (
        'Paso 2 de 4 • Sigue tu progreso',
        'Observa la barra de avance diario conforme completas tus prioridades.'
      ),
      const (
        'Paso 3 de 4 • Gestiona tus actividades',
        'Marca tus tareas como completadas o tócalas para gestionar sus subtareas.'
      ),
      const (
        'Paso 4 de 4 • Crea tu primera tarea',
        'Pulsa el botón + para programar una nueva actividad con recordatorio.'
      ),
    ];
    int stepIdx = 0;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          final current = steps[stepIdx];
          return AlertDialog(
            title: Text(
              current.$1,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            content: Text(current.$2),
            actions: [
              TextButton(
                onPressed: () {
                  _dbService.saveUserPreferences({'tutorial_status': 'skipped'});
                  Navigator.pop(ctx);
                },
                child: const Text('Omitir'),
              ),
              FilledButton(
                onPressed: () {
                  if (stepIdx < steps.length - 1) {
                    setModalState(() => stepIdx++);
                  } else {
                    _dbService
                        .saveUserPreferences({'tutorial_status': 'completed'});
                    Navigator.pop(ctx);
                    _openTaskForm();
                  }
                },
                child: Text(
                    stepIdx < steps.length - 1 ? 'Siguiente' : 'Crear tarea'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _triggerDemoPushNotification() async {
    await _notificationService.sendTestNotification(
      'Recordatorio: Revisar prototipos finales',
      'Categoría: Trabajo • Toca para completar o posponer +10m',
    );
    await _dbService.createReminder(
      title: 'Recordatorio • Ahora',
      message: 'Alerta interactiva disparada desde Taskly.',
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Notificación de recordatorio disparada con éxito'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(themeProvider.fontScale),
      ),
      child: Scaffold(
        body: SafeArea(
          child: IndexedStack(
            index: _currentTabIndex,
            children: [
              _buildDashboardTab(themeProvider),
              _buildTasksTab(themeProvider),
              _buildCalendarTab(themeProvider),
              _buildStatsTab(themeProvider),
              _buildProfileAndDesignTab(themeProvider),
            ],
          ),
        ),
        floatingActionButton: _currentTabIndex < 4
            ? FloatingActionButton(
                backgroundColor: themeProvider.accentColor,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(themeProvider.cardRadius),
                ),
                onPressed: () => _openTaskForm(),
                child: const Icon(LucideIcons.plus),
              )
            : null,
        bottomNavigationBar: Padding(
          padding: themeProvider.floatingNav
              ? const EdgeInsets.fromLTRB(16, 0, 16, 12)
              : EdgeInsets.zero,
          child: ClipRRect(
            borderRadius: themeProvider.floatingNav
                ? BorderRadius.circular(22)
                : BorderRadius.zero,
            child: NavigationBar(
              selectedIndex: _currentTabIndex,
              onDestinationSelected: (idx) =>
                  setState(() => _currentTabIndex = idx),
              destinations: const [
                NavigationDestination(
                    icon: Icon(LucideIcons.home), label: 'Inicio'),
                NavigationDestination(
                    icon: Icon(LucideIcons.checkSquare), label: 'Tareas'),
                NavigationDestination(
                    icon: Icon(LucideIcons.calendar), label: 'Calendario'),
                NavigationDestination(
                    icon: Icon(LucideIcons.barChart2), label: 'Estadísticas'),
                NavigationDestination(
                    icon: Icon(LucideIcons.user), label: 'Perfil'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDashboardTab(ThemeProvider themeProvider) {
    final userEmail = _dbService.currentUser?.email ?? '';
    final userName = (_dbService.currentUser?.userMetadata?['full_name']
            as String?) ??
        (userEmail.contains('@') ? userEmail.split('@').first : 'Usuario');

    final dayLabels = ['Dom', 'Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb'];
    final stripDays = List.generate(7, (i) {
      return DateTime.now()
          .add(Duration(days: (_weekOffset * 7) + (i - 2)));
    });

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    userEmail,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    userName,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              Row(
                children: [
                  IconButton(
                    tooltip: 'Recorrido interactivo',
                    icon: const Icon(LucideIcons.sparkles, size: 20),
                    onPressed: _openInteractiveTutorialDialog,
                  ),
                  IconButton(
                    tooltip: 'Personalizar diseño',
                    icon: const Icon(LucideIcons.palette, size: 20),
                    onPressed: () => setState(() => _currentTabIndex = 4),
                  ),
                  IconButton(
                    tooltip: 'Probar notificación',
                    icon: const Icon(LucideIcons.bellRing, size: 20),
                    onPressed: _triggerDemoPushNotification,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Tira semanal de 7 días sincronizada con el Inicio Web
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        DateFormat('MMMM yyyy').format(_selectedDate),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Row(
                        children: [
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(LucideIcons.chevronLeft, size: 16),
                            onPressed: () => setState(() => _weekOffset--),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            icon:
                                const Icon(LucideIcons.chevronRight, size: 16),
                            onPressed: () => setState(() => _weekOffset++),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: stripDays.map((d) {
                      final isSelected = d.year == _selectedDate.year &&
                          d.month == _selectedDate.month &&
                          d.day == _selectedDate.day;
                      return GestureDetector(
                        onTap: () => setState(() => _selectedDate = d),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 6),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? themeProvider.accentColor
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Column(
                            children: [
                              Text(
                                dayLabels[d.weekday % 7],
                                style: TextStyle(
                                  fontSize: 11,
                                  color:
                                      isSelected ? Colors.black : Colors.grey,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${d.day}',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: isSelected ? Colors.black : null,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(child: _buildTaskStreamList(themeProvider)),
        ],
      ),
    );
  }

  Widget _buildTasksTab(ThemeProvider themeProvider) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Mis tareas',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              ),
              IconButton(
                icon: const Icon(LucideIcons.bell),
                tooltip: 'Probar recordatorio',
                onPressed: _triggerDemoPushNotification,
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            decoration: InputDecoration(
              hintText: 'Buscar tareas...',
              prefixIcon: const Icon(LucideIcons.search, size: 18),
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(themeProvider.cardRadius),
              ),
            ),
            onChanged: (val) => setState(() => _searchQuery = val),
          ),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'todas', label: Text('Todas')),
              ButtonSegment(value: 'pendiente', label: Text('Pendientes')),
              ButtonSegment(value: 'completada', label: Text('Completadas')),
            ],
            selected: {_statusFilter},
            onSelectionChanged: (s) => setState(() => _statusFilter = s.first),
          ),
          const SizedBox(height: 16),
          Expanded(child: _buildTaskStreamList(themeProvider)),
        ],
      ),
    );
  }

  Widget _buildTaskStreamList(ThemeProvider themeProvider) {
    if (_isLoadingTasks && _tasks.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    final tasks = _tasks.where((t) {
      final matchCat = _categoryFilter == 'Todas' || t.category == _categoryFilter;
      final matchStatus = _statusFilter == 'todas' ||
          (_statusFilter == 'completada' ? t.isCompleted : !t.isCompleted);
      final q = _searchQuery.toLowerCase();
      final matchQ = q.isEmpty ||
          t.title.toLowerCase().contains(q) ||
          t.description.toLowerCase().contains(q);
      return matchCat && matchStatus && matchQ;
    }).toList();

    if (tasks.isEmpty) {
      return const Center(
        child: Text('No hay tareas registradas en esta vista'),
      );
    }

    final itemCount = tasks.length + (_hasMoreTasks ? 1 : 0);

    return RefreshIndicator(
      onRefresh: () => _refreshTasks(reset: true),
      child: ListView.builder(
        itemCount: itemCount,
        itemBuilder: (context, index) {
          if (index >= tasks.length) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: OutlinedButton(
                onPressed: () => _refreshTasks(reset: false),
                child: const Text('Cargar más tareas'),
              ),
            );
          }

          final task = tasks[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Card(
              child: Padding(
                padding: themeProvider.taskRowPadding,
                child: Row(
                  children: [
                    Checkbox(
                      value: task.isCompleted,
                      onChanged: (val) async {
                        final completed = val ?? false;
                        await _dbService.toggleTaskStatus(task.id, completed);
                        if (completed) {
                          await _notificationService.cancelReminder(task.id);
                        }
                        await _refreshTasks(reset: true);
                      },
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => _openTaskDetailSheet(task),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              task.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                decoration: task.isCompleted
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                            ),
                            if (themeProvider.cardDensity != 'compact') ...[
                              const SizedBox(height: 4),
                              Text(
                                '${task.category} • ${DateFormat('dd MMM').format(task.dueDate)} ${task.dueTime}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(LucideIcons.clock, size: 18),
                      tooltip: 'Posponer +10m',
                      onPressed: () async {
                        await _notificationService.snoozeTaskReminder(
                          task,
                          minutes: 10,
                        );
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Recordatorio pospuesto +10 min'),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCalendarTab(ThemeProvider themeProvider) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Calendario',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Card(
            child: CalendarDatePicker(
              initialDate: _selectedDate,
              firstDate: DateTime(2024),
              lastDate: DateTime(2030),
              onDateChanged: (d) => setState(() => _selectedDate = d),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(child: _buildTaskStreamList(themeProvider)),
        ],
      ),
    );
  }

  Widget _buildStatsTab(ThemeProvider themeProvider) {
    final all = _tasks;
    final done = all.where((t) => t.isCompleted).length;
    final pending = all.length - done;
    final pct = all.isEmpty ? 0 : ((done / all.length) * 100).round();

    final todayStr = DateTime.now().toIso8601String().split('T').first;
    final todayTasks = all
        .where((t) => t.dueDate.toIso8601String().split('T').first == todayStr)
        .toList();
    final todayDone = todayTasks.where((t) => t.isCompleted).length;
    final todayPct =
        todayTasks.isEmpty ? 0 : ((todayDone / todayTasks.length) * 100).round();

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Estadísticas',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            Text(
              'Hoy: $todayPct%',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: themeProvider.accentColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Completadas',
                              style: TextStyle(fontSize: 12)),
                          const SizedBox(height: 6),
                          Text('$done',
                              style: const TextStyle(
                                  fontSize: 22, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Cumplimiento',
                              style: TextStyle(fontSize: 12)),
                          const SizedBox(height: 6),
                          Text('$pct%',
                              style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: themeProvider.accentColor)),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Pendientes',
                              style: TextStyle(fontSize: 12)),
                          const SizedBox(height: 6),
                          Text('$pending',
                              style: const TextStyle(
                                  fontSize: 22, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
  }

  Widget _buildProfileAndDesignTab(ThemeProvider themeProvider) {
    final isLogged = _dbService.isAuthenticated;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Perfil y Diseño',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            TextButton(
              onPressed: () => themeProvider.resetToDefault(),
              child: const Text('Restablecer'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: const CircleAvatar(child: Icon(LucideIcons.user)),
            title: Text(
              _dbService.currentUser?.email ?? 'Cuenta sin sesión activa',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              isLogged
                  ? 'Conectado a Supabase Auth + PostgreSQL RLS'
                  : 'Inicia sesión con Supabase Auth para sincronizar',
            ),
            trailing: FilledButton.tonal(
              onPressed: isLogged
                  ? () async {
                      await _dbService.signOut();
                    }
                  : null,
              child: const Text('Salir'),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Tema de Superficie',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'dark', label: Text('Oscuro')),
                    ButtonSegment(value: 'amoled', label: Text('AMOLED')),
                    ButtonSegment(value: 'light', label: Text('Claro')),
                    ButtonSegment(value: 'auto', label: Text('Auto')),
                  ],
                  selected: {themeProvider.surfaceMode},
                  onSelectionChanged: (s) {
                    themeProvider.setSurfaceMode(s.first);
                    _dbService.saveUserPreferences({'theme': s.first});
                  },
                ),
                const SizedBox(height: 16),
                const Text(
                  'Color de Acento Principal',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: _accentSwatches.map((color) {
                    final isSelected =
                        themeProvider.accentColor.toARGB32() ==
                            color.toARGB32();
                    return GestureDetector(
                      onTap: () {
                        themeProvider.setAccentColor(color);
                        final hex =
                            '#${color.toARGB32().toRadixString(16).substring(2).toUpperCase()}';
                        _dbService.saveUserPreferences({'accent_color': hex});
                      },
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSelected
                                ? Theme.of(context).colorScheme.onSurface
                                : Colors.transparent,
                            width: 2.5,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Bordes y Esquinas',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'sharp', label: Text('Recto (8px)')),
                    ButtonSegment(
                        value: 'standard', label: Text('Estándar (16px)')),
                    ButtonSegment(value: 'rounded', label: Text('Curvo (24px)')),
                  ],
                  selected: {themeProvider.borderRadiusMode},
                  onSelectionChanged: (s) {
                    themeProvider.setBorderRadiusMode(s.first);
                    _dbService
                        .saveUserPreferences({'border_radius': s.first});
                  },
                ),
                const SizedBox(height: 16),
                const Text(
                  'Densidad de Tarjetas',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'compact', label: Text('Compacta')),
                    ButtonSegment(value: 'comfortable', label: Text('Cómoda')),
                    ButtonSegment(value: 'spacious', label: Text('Detallada')),
                  ],
                  selected: {themeProvider.cardDensity},
                  onSelectionChanged: (s) {
                    themeProvider.setCardDensity(s.first);
                    _dbService.saveUserPreferences({'card_density': s.first});
                  },
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Barra inferior estilo Cápsula Flotante'),
                  value: themeProvider.floatingNav,
                  onChanged: (v) {
                    themeProvider.setFloatingNav(v);
                    _dbService.saveUserPreferences(
                        {'nav_style': v ? 'floating' : 'classic'});
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Column(
            children: [
              SwitchListTile(
                title: const Text('Notificaciones Push Activas'),
                subtitle: const Text('Recordatorios interactivos en Android'),
                value: themeProvider.notificationsEnabled,
                onChanged: (v) {
                  themeProvider.setNotificationsEnabled(v);
                  _dbService
                      .saveUserPreferences({'notifications_enabled': v});
                },
              ),
              ListTile(
                leading: const Icon(LucideIcons.folder),
                title: const Text('Gestionar categorías'),
                trailing: const Icon(LucideIcons.chevronRight),
                onTap: _openCategoriesSheet,
              ),
              ListTile(
                leading: const Icon(LucideIcons.bell),
                title: const Text('Centro de notificaciones'),
                trailing: const Icon(LucideIcons.chevronRight),
                onTap: _openNotificationsSheet,
              ),
              ListTile(
                leading: const Icon(LucideIcons.hardDrive),
                title: const Text('Limpiar caché local'),
                subtitle: Text(
                  'Uso actual: ${(_cacheBytes / 1024).toStringAsFixed(1)} KB (no borra tus tareas en Supabase)',
                ),
                trailing: const Icon(LucideIcons.trash2, size: 18),
                onTap: () async {
                  final uid = _dbService.currentUserId;
                  if (uid != null) {
                    await _cacheService.clearUserDataCache(uid);
                    await _updateCacheSize();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Caché local limpiada')),
                      );
                    }
                  }
                },
              ),
              ListTile(
                leading: const Icon(LucideIcons.bellRing),
                title: const Text('Probar alerta de recordatorio ahora'),
                trailing: const Icon(LucideIcons.chevronRight),
                onTap: _triggerDemoPushNotification,
              ),
              ListTile(
                leading: const Icon(LucideIcons.sparkles),
                title: const Text('Ver recorrido interactivo (4 pasos)'),
                trailing: const Icon(LucideIcons.chevronRight),
                onTap: _openInteractiveTutorialDialog,
              ),
              if (isLogged)
                ListTile(
                  leading: const Icon(LucideIcons.userX, color: Colors.redAccent),
                  title: const Text(
                    'Eliminar cuenta y datos personales',
                    style: TextStyle(color: Colors.redAccent),
                  ),
                  onTap: () async {
                    await _dbService.deleteOwnAccount();
                    if (mounted) setState(() {});
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }
}
