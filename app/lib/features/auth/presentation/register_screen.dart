import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/widgets/auth_layout.dart';
import '../domain/auth_repository.dart';
import '../../../core/forms/validar.dart';
import '../domain/validators.dart';
import 'auth_providers.dart';
import 'campos.dart';
import 'google_button.dart';
import '../domain/profile.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nombre = TextEditingController();
  final _usuario = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmar = TextEditingController();
  bool _cargando = false;
  String? _errorEmail;
  var _tipo = TipoCuenta.estudiante;

  @override
  void dispose() {
    _nombre.dispose();
    _usuario.dispose();
    _email.dispose();
    _password.dispose();
    _confirmar.dispose();
    super.dispose();
  }

  String? get _from => GoRouterState.of(context).uri.queryParameters['from'];

  Future<void> _registrar() async {
    setState(() => _errorEmail = null);
    if (!_formKey.currentState!.validate()) return;
    setState(() => _cargando = true);
    final repo = ref.read(authRepositoryProvider);
    try {
      if (!await repo.usernameDisponible(_usuario.text.trim().toLowerCase())) {
        _campoUsuario.currentState?.marcarOcupado();
        return;
      }
      await repo.signUpWithEmail(
        nombre: _nombre.text,
        username: _usuario.text,
        email: _email.text,
        password: _password.text,
        tipo: _tipo,
      );
      if (mounted) context.go(Routes.codigo(MotivoCodigo.registro, from: _from), extra: _email.text.trim());
    } on AuthFailure catch (e) {
      if (!mounted) return;
      if (e.codigo == 'user_already_exists' || e.codigo == 'email_exists') {
        setState(() => _errorEmail = e.mensaje);
      } else {
        mostrarMensaje(context, e.mensaje, error: true);
      }
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  final _campoUsuario = GlobalKey<CampoUsuarioState>();

  @override
  Widget build(BuildContext context) {
    return AuthLayout(
      titulo: 'Creá tu cuenta',
      subtitulo: 'Es gratis y te lleva un minuto',
      child: AutofillGroup(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Como en la mayoría de las apps: primero, quién sos.
              Text('¿Cómo vas a usar StudyVerse?', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              SegmentedButton<TipoCuenta>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: TipoCuenta.estudiante, label: Text('Soy estudiante'), icon: Icon(Icons.backpack_outlined)),
                  ButtonSegment(value: TipoCuenta.docente, label: Text('Soy docente'), icon: Icon(Icons.school_outlined)),
                ],
                selected: {_tipo},
                onSelectionChanged: (s) => setState(() => _tipo = s.single),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 6, 4, 16),
                child: Text(
                  _tipo == TipoCuenta.docente
                      ? 'Creás cursos y ves los grupos de tu clase: archivos, tareas y aportes.'
                      : 'Armás grupos con tus compañeros para los TPs.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),
              TextFormField(
                controller: _nombre,
                decoration: const InputDecoration(labelText: 'Nombre y apellido', hintText: 'Ana García'),
                textCapitalization: TextCapitalization.words,
                autofillHints: const [AutofillHints.name],
                textInputAction: TextInputAction.next,
                autovalidateMode: validarAlCorregir,
                validator: Validators.nombre,
              ),
              const SizedBox(height: 16),
              CampoUsuario(key: _campoUsuario, controller: _usuario),
              const SizedBox(height: 16),
              CampoEmail(
                controller: _email,
                errorText: _errorEmail,
                onChanged: (_) {
                  if (_errorEmail != null) setState(() => _errorEmail = null);
                },
              ),
              const SizedBox(height: 16),
              CampoContrasena(
                controller: _password,
                nueva: true,
                textInputAction: TextInputAction.next,
                validator: Validators.password,
              ),
              RequisitosContrasena(controller: _password),
              const SizedBox(height: 16),
              CampoContrasena(
                controller: _confirmar,
                etiqueta: 'Repetí la contraseña',
                nueva: true,
                onSubmitted: (_) => _registrar(),
                validator: Validators.confirmarPassword(() => _password.text),
              ),
              const SizedBox(height: 16),
              Text(
                'Tus compañeros de grupo van a ver tu nombre, tu usuario y tu foto.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              BotonPrincipal(texto: 'Crear cuenta', cargando: _cargando, onPressed: _registrar),
              const GoogleButton(espacioArriba: 16),
              const SizedBox(height: 24),
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text('¿Ya tenés cuenta?'),
                  TextButton(
                    onPressed: () => context.go(Routes.conDestino(Routes.login, _from)),
                    child: const Text('Entrá'),
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
