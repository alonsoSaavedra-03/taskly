import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Estudio de Diseño Personalizable de Taskly (Sincronizado para Android Studio)
/// Soporta:
/// - Temas: Oscuro (#101114), AMOLED Puro (#000000), Claro (#F8F9FB) y Automático
/// - Paleta de colores de acento personalizable
/// - Radio de bordes: Recto (8px), Estándar (16px), Curvo (24px)
/// - Densidad de tarjetas: Compacta, Cómoda, Detallada
/// - Escala de texto y estilo de barra inferior (Clásica vs Cápsula Flotante)
class ThemeProvider extends ChangeNotifier {
  String _surfaceMode = 'dark'; // 'dark' | 'amoled' | 'light' | 'auto'
  Color _accentColor = const Color(0xFFA5B4FC);
  String _borderRadiusMode = 'standard'; // 'sharp' | 'standard' | 'rounded'
  String _cardDensity = 'comfortable'; // 'compact' | 'comfortable' | 'spacious'
  double _fontScale = 1.0; // 0.93 | 1.0 | 1.07
  bool _floatingNav = false;
  bool _notificationsEnabled = true;
  bool _soundEnabled = true;

  String get surfaceMode => _surfaceMode;
  Color get accentColor => _accentColor;
  String get borderRadiusMode => _borderRadiusMode;
  String get cardDensity => _cardDensity;
  double get fontScale => _fontScale;
  bool get floatingNav => _floatingNav;
  bool get notificationsEnabled => _notificationsEnabled;
  bool get soundEnabled => _soundEnabled;

  ThemeMode get themeMode {
    if (_surfaceMode == 'light') return ThemeMode.light;
    if (_surfaceMode == 'auto') return ThemeMode.system;
    return ThemeMode.dark;
  }

  bool get isDarkMode => _surfaceMode != 'light';

  double get cardRadius {
    switch (_borderRadiusMode) {
      case 'sharp':
        return 8.0;
      case 'rounded':
        return 24.0;
      default:
        return 16.0;
    }
  }

  EdgeInsets get taskRowPadding {
    switch (_cardDensity) {
      case 'compact':
        return const EdgeInsets.symmetric(horizontal: 11, vertical: 7);
      case 'spacious':
        return const EdgeInsets.symmetric(horizontal: 16, vertical: 14);
      default:
        return const EdgeInsets.symmetric(horizontal: 14, vertical: 11);
    }
  }

  ThemeProvider() {
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    _surfaceMode = prefs.getString('surfaceMode') ?? 'dark';
    final savedAccent = prefs.getInt('accentColor');
    if (savedAccent != null) {
      _accentColor = Color(savedAccent);
    }
    _borderRadiusMode = prefs.getString('borderRadiusMode') ?? 'standard';
    _cardDensity = prefs.getString('cardDensity') ?? 'comfortable';
    _fontScale = prefs.getDouble('fontScale') ?? 1.0;
    _floatingNav = prefs.getBool('floatingNav') ?? false;
    _notificationsEnabled = prefs.getBool('notificationsEnabled') ?? true;
    _soundEnabled = prefs.getBool('soundEnabled') ?? true;
    notifyListeners();
  }

  Future<void> setSurfaceMode(String mode) async {
    _surfaceMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('surfaceMode', mode);
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    await setSurfaceMode(mode == ThemeMode.light
        ? 'light'
        : mode == ThemeMode.system
            ? 'auto'
            : 'dark');
  }

  Future<void> setAccentColor(Color color) async {
    _accentColor = color;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('accentColor', color.toARGB32());
    notifyListeners();
  }

  Future<void> setBorderRadiusMode(String mode) async {
    _borderRadiusMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('borderRadiusMode', mode);
    notifyListeners();
  }

  Future<void> setCardDensity(String density) async {
    _cardDensity = density;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('cardDensity', density);
    notifyListeners();
  }

  Future<void> setFontScale(double scale) async {
    _fontScale = scale;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('fontScale', scale);
    notifyListeners();
  }

  Future<void> setFloatingNav(bool value) async {
    _floatingNav = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('floatingNav', value);
    notifyListeners();
  }

  Future<void> setNotificationsEnabled(bool value) async {
    _notificationsEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notificationsEnabled', value);
    notifyListeners();
  }

  Future<void> setSoundEnabled(bool value) async {
    _soundEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('soundEnabled', value);
    notifyListeners();
  }

  Future<void> resetToDefault() async {
    _surfaceMode = 'dark';
    _accentColor = const Color(0xFFA5B4FC);
    _borderRadiusMode = 'standard';
    _cardDensity = 'comfortable';
    _fontScale = 1.0;
    _floatingNav = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    notifyListeners();
  }

  /// Tema Oscuro Principal o AMOLED Puro
  ThemeData get darkTheme {
    final isAmoled = _surfaceMode == 'amoled';
    final bgMain = isAmoled ? const Color(0xFF000000) : const Color(0xFF101114);
    final bgSurface = isAmoled ? const Color(0xFF0C0D10) : const Color(0xFF1B1D22);
    final borderCol = isAmoled ? const Color(0xFF22252D) : const Color(0xFF30333B);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bgMain,
      colorScheme: ColorScheme.dark(
        primary: _accentColor,
        surface: bgSurface,
        onSurface: const Color(0xFFF5F5F7),
        secondary: const Color(0xFF9498A3),
        outline: borderCol,
      ),
      cardTheme: CardThemeData(
        color: bgSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
          side: BorderSide(color: borderCol, width: 1),
        ),
      ),
    );
  }

  /// Tema Claro (#F8F9FB, #FFFFFF, #17191F, #777D89, #E9EAF0)
  ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: const Color(0xFFF8F9FB),
      colorScheme: ColorScheme.light(
        primary: _accentColor == const Color(0xFFA5B4FC)
            ? const Color(0xFF6366F1)
            : _accentColor,
        surface: const Color(0xFFFFFFFF),
        onSurface: const Color(0xFF17191F),
        secondary: const Color(0xFF777D89),
        outline: const Color(0xFFE9EAF0),
      ),
      cardTheme: CardThemeData(
        color: const Color(0xFFFFFFFF),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
          side: const BorderSide(color: Color(0xFFE9EAF0), width: 1),
        ),
      ),
    );
  }
}
