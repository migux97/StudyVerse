import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/widgets/auth_layout.dart';
import '../domain/auth_repository.dart';
import '../domain/validators.dart';
import 'auth_providers.dart';

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  bool _cargando = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _cargando = true);
    try {
      await ref.read(authRepositoryProvider).sendPasswordReset(_email.text);
      if (!mounted) return;
      mostrarMensaje(context, 'Si el email existe, te llegará un link para cambiar la contraseña');
      context.go(Routes.login);
    } on AuthFailure catch (e) {
      if (mounted) mostrarMensaje(context, e.mensaje, error: true);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthLayout(
      titulo: 'Recuperar contraseña',
      subtitulo: 'Te enviamos un link a tu email',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _email,
              decoration: const InputDecoration(labelText: 'Email'),
              keyboardType: TextInputType.emailAddress,
              onFieldSubmitted: (_) => _enviar(),
              validator: Validators.email,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _cargando ? null : _enviar,
              child: const Text('Enviar link'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => context.go(Routes.login),
              child: const Text('Volver'),
            ),
          ],
        ),
      ),
    );
  }
}
