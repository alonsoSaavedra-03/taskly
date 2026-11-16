import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/cache_service.dart';
import '../services/database_service.dart';

/// Pantalla nativa de Acceso y Registro en Supabase Auth.
/// - Registro directo con correo y contraseña sin confirmación por correo ni OTP.
/// - Inicio de sesión para usuarios existentes.
/// - Recuperación por correo desactivada visualmente con mensaje claro.
class AuthScreen extends StatefulWidget {
  final VoidCallback onAuthenticated;

  const AuthScreen({super.key, required this.onAuthenticated});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final DatabaseService _db = DatabaseService();
  final CacheService _cache = CacheService();

  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  String _mode = 'welcome'; // 'welcome' | 'login' | 'register'
  bool _isSubmitting = false;
  String? _feedback;
  bool _isError = true;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  String _mapAuthError(Object err) {
    final raw = err.toString().toLowerCase();
    if (raw.contains('rate limit') ||
        raw.contains('rate_limit') ||
        raw.contains('too many') ||
        raw.contains('429')) {
      return 'Realizaste varios intentos seguidos. Espera un minuto antes de intentarlo nuevamente.';
    }
    if (raw.contains('invalid login credentials')) {
      return 'El correo o la contraseña no coinciden. Verifica tus datos.';
    }
    if (raw.contains('email not confirmed')) {
      return 'Esta cuenta requiere confirmación en Supabase Auth. Desactiva "Confirm email" en Authentication → Sign In / Providers.';
    }
    if (raw.contains('already registered') || raw.contains('already been')) {
      return 'Ya existe una cuenta registrada con este correo. Inicia sesión para continuar.';
    }
    if (raw.contains('socketexception') || raw.contains('network')) {
      return 'Sin conexión a internet. Verifica tu red e inténtalo de nuevo.';
    }
    return 'No pudimos completar la solicitud en este momento. Inténtalo nuevamente.';
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;

    final email = _emailCtrl.text.trim().toLowerCase();
    final pass = _passCtrl.text;
    final name = _nameCtrl.text.trim();

    if (email.isEmpty || !email.contains('@')) {
      setState(() {
        _feedback = 'Ingresa un correo electrónico válido.';
        _isError = true;
      });
      return;
    }
    if (pass.length < 6) {
      setState(() {
        _feedback = 'La contraseña debe tener al menos 6 caracteres.';
        _isError = true;
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _feedback = null;
    });

    try {
      if (_mode == 'register') {
        final fullName = name.isNotEmpty ? name : email.split('@').first;
        final res = await _db.signUp(
          email: email,
          password: pass,
          fullName: fullName,
        );
        Session? session = res.session;
        User? user = res.user;

        if (session == null) {
          final signInRes = await _db.signIn(email: email, password: pass);
          session = signInRes.session;
          user = signInRes.user;
        }

        if (session == null || user == null) {
          setState(() {
            _feedback =
                'Tu cuenta fue creada, pero Supabase Auth aún exige confirmación por correo.';
            _isError = true;
          });
          return;
        }

        await _cache.setTutorialStatus(user.id, 'not_started');
        widget.onAuthenticated();
      } else {
        final res = await _db.signIn(email: email, password: pass);
        if (res.session != null) {
          widget.onAuthenticated();
        }
      }
    } catch (err) {
      setState(() {
        _feedback = _mapAuthError(err);
        _isError = true;
      });
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final isWelcome = _mode == 'welcome';
    final isReg = _mode == 'register';

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(LucideIcons.layers, color: accent, size: 22),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                isWelcome
                    ? 'Bienvenido a Taskly'
                    : isReg
                        ? 'Crea tu cuenta'
                        : 'Inicia sesión',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                isWelcome
                    ? 'Tu espacio de trabajo sincronizado en la nube.'
                    : isReg
                        ? 'Comienza con una cuenta limpia y entra al instante.'
                        : 'Accede a tu espacio de trabajo sincronizado en la nube.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.secondary,
                ),
              ),
              const SizedBox(height: 20),
              if (_feedback != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: (_isError ? theme.colorScheme.error : accent)
                        .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _isError ? theme.colorScheme.error : accent,
                    ),
                  ),
                  child: Text(
                    _feedback!,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: _isError ? theme.colorScheme.error : accent,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              if (isWelcome) ...[
                SizedBox(
                  height: 50,
                  child: FilledButton.icon(
                    onPressed: () => setState(() {
                      _mode = 'register';
                      _feedback = null;
                    }),
                    icon: const Icon(LucideIcons.arrowRight, size: 18),
                    label: const Text('Crear cuenta'),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 50,
                  child: OutlinedButton(
                    onPressed: () => setState(() {
                      _mode = 'login';
                      _feedback = null;
                    }),
                    child: const Text('Iniciar sesión'),
                  ),
                ),
              ] else ...[
                if (isReg) ...[
                  TextField(
                    controller: _nameCtrl,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Nombre completo',
                      prefixIcon: Icon(LucideIcons.user, size: 18),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Correo electrónico',
                    prefixIcon: Icon(LucideIcons.mail, size: 18),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passCtrl,
                  obscureText: true,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submit(),
                  decoration: const InputDecoration(
                    labelText: 'Contraseña (mín. 6 caracteres)',
                    prefixIcon: Icon(LucideIcons.lock, size: 18),
                  ),
                ),
                if (!isReg) ...[
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        '¿Olvidaste tu contraseña? (Desactivado)',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: theme.colorScheme.secondary
                              .withValues(alpha: 0.55),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'La recuperación por correo está desactivada temporalmente porque no hay servicio de correo configurado.',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: theme.colorScheme.secondary,
                      height: 1.35,
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  height: 50,
                  child: FilledButton(
                    onPressed: _isSubmitting ? null : _submit,
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(isReg ? 'Crear cuenta' : 'Iniciar sesión'),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _isSubmitting
                      ? null
                      : () => setState(() {
                            _mode = isReg ? 'login' : 'register';
                            _feedback = null;
                          }),
                  child: Text(
                    isReg
                        ? '¿Ya tienes una cuenta? Iniciar sesión'
                        : '¿No tienes una cuenta? Crear cuenta',
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
