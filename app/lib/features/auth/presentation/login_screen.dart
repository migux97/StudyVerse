import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/widgets/auth_layout.dart';
import '../domain/auth_repository.dart';
import 'auth_providers.dart';
import 'campos.dart';
import 'google_button.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _cargando = false;

  /// Error de credenciales: va debajo de la contraseña, como en Google.
  String? _errorPassword;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _limpiarError() {
    if (_errorPassword != null) setState(() => _errorPassword = null);
  }

  String? get _from => GoRouterState.of(context).uri.queryParameters['from'];

  Future<void> _entrar() async {
    setState(() => _errorPassword = null);
    if (!_formKey.currentState!.validate()) return;
    setState(() => _cargando = true);
    try {
      await ref
          .read(authRepositoryProvider)
          .signInWithEmail(email: _email.text, password: _password.text);
    } on AuthFailure catch (e) {
      if (!mounted) return;
      if (e.codigo == 'invalid_credentials') {
        setState(() => _errorPassword = e.mensaje);
      } else if (e.codigo == 'email_not_confirmed') {
        // Cuenta sin confirmar: se manda un código nuevo y se sigue desde ahí.
        await ref.read(authRepositoryProvider).enviarCodigo(_email.text, MotivoCodigo.registro).catchError((_) {});
        if (mounted) context.go(Routes.codigo(MotivoCodigo.registro, from: _from), extra: _email.text.trim());
      } else {
        mostrarMensaje(context, e.mensaje, error: true);
      }
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthLayout(
      titulo: 'Entrá a StudyVerse',
      subtitulo: 'Los archivos y tareas de tus grupos, en un solo lugar',
      child: AutofillGroup(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CampoEmail(
                controller: _email,
                autofillHints: const [AutofillHints.email, AutofillHints.username],
                onChanged: (_) => _limpiarError(),
              ),
              const SizedBox(height: 16),
              CampoContrasena(
                controller: _password,
                errorText: _errorPassword,
                onSubmitted: (_) => _entrar(),
                onChanged: (_) => _limpiarError(),
                validator: (v) => (v ?? '').isEmpty ? 'Ingresá tu contraseña' : null,
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => context.push(Routes.codigo(MotivoCodigo.recuperar), extra: _email.text.trim()),
                  child: const Text('¿Olvidaste tu contraseña?'),
                ),
              ),
              const SizedBox(height: 8),
              BotonPrincipal(texto: 'Entrar', cargando: _cargando, onPressed: _entrar),
              const SizedBox(height: 24),
              const SeparadorO(),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                icon: const Icon(Icons.mail_outline_rounded),
                label: const Text('Entrar con un código por mail'),
                onPressed: () =>
                    context.push(Routes.codigo(MotivoCodigo.entrar, from: _from), extra: _email.text.trim()),
              ),
              const SizedBox(height: 12),
              const GoogleButton(),
              const SizedBox(height: 24),
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text('¿No tenés cuenta?'),
                  TextButton(
                    onPressed: () => context.go(Routes.conDestino(Routes.registro, _from)),
                    child: const Text('Creá una'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
