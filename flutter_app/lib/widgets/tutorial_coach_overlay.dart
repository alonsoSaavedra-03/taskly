import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum TutorialStatus { notStarted, inProgress, completed, skipped }

class TutorialStepData {
  final String title;
  final String description;
  final GlobalKey targetKey;
  final double targetBorderRadius;

  const TutorialStepData({
    required this.title,
    required this.description,
    required this.targetKey,
    this.targetBorderRadius = 14.0,
  });
}

/// Overlay de Tutorial Interactivo (Coach Marks / Feature Discovery Tour) para Flutter
class TutorialCoachOverlay extends StatefulWidget {
  final List<TutorialStepData> steps;
  final VoidCallback onComplete;
  final VoidCallback onSkip;

  const TutorialCoachOverlay({
    super.key,
    required this.steps,
    required this.onComplete,
    required this.onSkip,
  });

  static Future<TutorialStatus> getSavedStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final str = prefs.getString('taskly_tutorial_status') ?? 'notStarted';
    return TutorialStatus.values.firstWhere(
      (e) => e.name == str,
      orElse: () => TutorialStatus.notStarted,
    );
  }

  static Future<void> saveStatus(TutorialStatus status) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('taskly_tutorial_status', status.name);
  }

  @override
  State<TutorialCoachOverlay> createState() => _TutorialCoachOverlayState();
}

class _TutorialCoachOverlayState extends State<TutorialCoachOverlay> {
  int _currentIndex = 0;

  void _ensureVisibleAndAdvance(int newIndex) {
    setState(() => _currentIndex = newIndex);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = widget.steps[_currentIndex].targetKey.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          alignment: 0.25,
        );
      }
    });
  }

  void _next() {
    if (_currentIndex < widget.steps.length - 1) {
      _ensureVisibleAndAdvance(_currentIndex + 1);
    } else {
      TutorialCoachOverlay.saveStatus(TutorialStatus.completed);
      widget.onComplete();
    }
  }

  void _prev() {
    if (_currentIndex > 0) {
      _ensureVisibleAndAdvance(_currentIndex - 1);
    }
  }

  void _skip() {
    TutorialCoachOverlay.saveStatus(TutorialStatus.skipped);
    widget.onSkip();
  }

  @override
  Widget build(BuildContext context) {
    final step = widget.steps[_currentIndex];
    final renderBox =
        step.targetKey.currentContext?.findRenderObject() as RenderBox?;
    final Offset targetOffset =
        renderBox != null ? renderBox.localToGlobal(Offset.zero) : Offset.zero;
    final Size targetSize = renderBox?.size ?? Size.zero;

    const double outerPad = 7.0; // Padding exterior uniforme de 6–8 px
    const double tooltipGap = 14.0; // Separación de 12–16 px

    final media = MediaQuery.of(context);
    final screenHeight = media.size.height;
    final safeTop = media.padding.top + 12.0;
    final safeBottom = screenHeight - media.padding.bottom - 76.0;

    final double spotTop = targetOffset.dy - outerPad;
    final double spotLeft = targetOffset.dx - outerPad;
    final double spotWidth = targetSize.width + outerPad * 2;
    final double spotHeight = targetSize.height + outerPad * 2;

    const double estimatedTooltipHeight = 164.0;
    final double belowTop = spotTop + spotHeight + tooltipGap;
    final double aboveTop = spotTop - estimatedTooltipHeight - tooltipGap;
    final bool placeBelow = (belowTop + estimatedTooltipHeight) <= safeBottom;

    final double tooltipTop = placeBelow
        ? belowTop
        : aboveTop.clamp(safeTop, safeBottom - estimatedTooltipHeight);

    return Material(
      color: Colors.black.withValues(alpha: 0.76),
      child: Stack(
        children: [
          if (renderBox != null)
            AnimatedPositioned(
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              top: spotTop,
              left: spotLeft,
              width: spotWidth,
              height: spotHeight,
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius:
                        BorderRadius.circular(step.targetBorderRadius + 4.0),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.primary,
                      width: 1.75,
                    ),
                  ),
                ),
              ),
            ),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            left: 20, // Márgenes laterales uniformes de 20–24 px
            right: 20,
            top: tooltipTop,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 18, // Padding interno uniforme de 18–20 px
              ),
              decoration: BoxDecoration(
                color: const Color(0xFF252830),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFF30333B)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 1. Encabezado: "Paso 1 de 4" a la izquierda y "Omitir" a la derecha
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Paso ${_currentIndex + 1} de ${widget.steps.length}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      GestureDetector(
                        onTap: _skip,
                        child: const Text(
                          'Omitir',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF9498A3),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // 2. Contenido: título y descripción con espaciado vertical consistente
                  Text(
                    step.title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFF5F5F7),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    step.description,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      color: Color(0xFF9498A3),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // 3. Pie: indicador de progreso a la izquierda y botón "Siguiente" a la derecha
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: List.generate(
                          widget.steps.length,
                          (i) => AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.only(right: 6),
                            width: i == _currentIndex ? 18 : 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: i == _currentIndex
                                  ? Theme.of(context).colorScheme.primary
                                  : const Color(0xFF30333B),
                              borderRadius: BorderRadius.circular(99),
                            ),
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          if (_currentIndex > 0)
                            TextButton(
                              onPressed: _prev,
                              child: const Text('Anterior'),
                            ),
                          FilledButton(
                            onPressed: _next,
                            child: Text(
                              _currentIndex == widget.steps.length - 1
                                  ? 'Crear tarea'
                                  : 'Siguiente',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
