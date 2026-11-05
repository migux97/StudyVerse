import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/forms/validar.dart';
import '../../../core/router/app_router.dart';
import '../../../core/widgets/auth_layout.dart';
import '../domain/auth_repository.dart';
import '../domain/validators.dart';
import 'auth_providers.dart';
import 'campos.dart';

/// Código de 6 dígitos por correo: confirmar la cuenta, entrar sin contraseña
/// o elegir una nueva. Si el código es correcto queda la sesión iniciada y el
/// router lleva a la app.
class CodigoScreen extends ConsumerStatefulWidget {
  const CodigoScreen({super.key, required this.motivo, this.email});
  final MotivoCodigo motivo;

  /// Si viene, el código ya se mandó (registro) o se ofrece mandarlo a ese email.
  final String? email;

  @override
  ConsumerState<CodigoScreen> createState() => _CodigoScreenState();
}

class _CodigoScreenState extends ConsumerState<CodigoScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _email = TextEditingController(text: widget.email);
  final _codigo = TextEditingController();
  final _password = TextEditingController();

  /// En el registro el código ya salió con el alta.
  late bool _enviado = widget.motivo == MotivoCodigo.registro && (widget.email?.isNotEmpty ?? false);
  bool _cargando = false;
  String? _errorCodigo;
  String? _errorEmail;
  int _esperar = 0;
  Timer? _reloj;

  @override
  void initState() {
    super.initState();
    if (_enviado) _arrancarEspera();
  }

  @override
  void dispose() {
    _reloj?.cancel();
    _email.dispose();
    _codigo.dispose();
    _password.dispose();
    super.dispose();
  }

  void _arrancarEspera() {
    _reloj?.cancel();
    setState(() => _esperar = 30);
    _reloj = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _esperar--);
      if (_esperar <= 0) t.cancel();
    });
  }

  Future<void> _enviar() async {
    if (_cargando) return;
    setState(() => _errorEmail = null);
    if (!_enviado && !_formKey.currentState!.validate()) return;
    setState(() => _cargando = true);
    try {
      await ref.read(authRepositoryProvider).enviarCodigo(_email.text, widget.motivo);
      if (!mounted) return;
      setState(() => _enviado = true);
      _arrancarEspera();
    } on AuthFailure catch (e) {
      if (!mounted) return;
      if (e.codigo == 'otp_disabled' || e.codigo == 'user_not_found') {
        // No se dice si la cuenta existe: se sigue igual que si se hubiera mandado.
        setState(() => _enviado = true);
        _arrancarEspera();
      } else {
        mostrarMensaje(context, e.mensaje, error: true);
      }
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _verificar() async {
    if (_cargando) return;
    setState(() => _errorCodigo = null);
    if (!_formKey.currentState!.validate()) return;
    setState(() => _cargando = true);
    try {
      await ref.read(authRepositoryProvider).verificarCodigo(
            _email.text,
            _codigo.text,
            widget.motivo,
            nuevaPassword: widget.motivo == MotivoCodigo.recuperar ? _password.text : null,
          );
      // Con la sesión iniciada, el router lleva a la app.
    } on AuthFailure catch (e) {
      if (e.codigo == 'recuperacion_incompleta') {
        // Ya entró y el router cambió de pantalla.
        return avisarEnLaApp(e.mensaje, duracion: const Duration(seconds: 10));
      }
      if (!mounted) return;
      if (e.codigo == 'otp_expired' || e.codigo == 'invalid_otp') {
        setState(() => _errorCodigo = 'El código no es correcto o ya venció');
      } else {
        mostrarMensaje(context, e.mensaje, error: true);
      }
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  ({String titulo, String accion}) get _textos => switch (widget.motivo) {
        MotivoCodigo.registro => (titulo: 'Confirmá tu email', accion: 'Confirmar'),
        MotivoCodigo.entrar => (titulo: 'Entrá con un código', accion: 'Entrar'),
        MotivoCodigo.recuperar => (titulo: 'Elegí una contraseña nueva', accion: 'Cambiar contraseña'),
      };

  void _volver() => context.canPop() ? context.pop() : context.go(Routes.login);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AuthLayout(
      titulo: _textos.titulo,
      subtitulo: _enviado
          ? (widget.motivo == MotivoCodigo.registro
              ? 'Te mandamos un código de 6 números a ${_email.text.trim()}'
              : 'Si hay una cuenta con ${_email.text.trim()}, te llega un código de 6 números')
          : 'Te mandamos un código de 6 números a tu email',
      alVolver: _volver,
      child: AutofillGroup(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!_enviado) ...[
                CampoEmail(
                  controller: _email,
                  autofocus: _email.text.isEmpty,
                  errorText: _errorEmail,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _enviar(),
                  onChanged: (_) {
                    if (_errorEmail != null) setState(() => _errorEmail = null);
                  },
                ),
                const SizedBox(height: 24),
                BotonPrincipal(texto: 'Mandame el código', cargando: _cargando, onPressed: _enviar),
              ] else ...[
                TextFormField(
                  controller: _codigo,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  autofillHints: const [AutofillHints.oneTimeCode],
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(6),
                  ],
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(letterSpacing: 10),
                  decoration: InputDecoration(
                    labelText: 'Código de 6 números',
                    hintText: '••••••',
                    errorText: _errorCodigo,
                    helperText: '¿No te llegó? Revisá la carpeta de spam',
                  ),
                  autovalidateMode: validarAlCorregir,
                  onChanged: (v) {
                    if (_errorCodigo != null) setState(() => _errorCodigo = null);
                    // Con el sexto número se verifica solo, como en Google.
                    if (v.length == 6 && widget.motivo != MotivoCodigo.recuperar && !_cargando) _verificar();
                  },
                  textInputAction:
                      widget.motivo == MotivoCodigo.recuperar ? TextInputAction.next : TextInputAction.done,
                  onFieldSubmitted: (_) => widget.motivo == MotivoCodigo.recuperar ? null : _verificar(),
                  validator: Validators.codigo,
                ),
                if (widget.motivo == MotivoCodigo.recuperar) ...[
                  const SizedBox(height: 16),
                  CampoContrasena(
                    controller: _password,
                    etiqueta: 'Contraseña nueva',
                    nueva: true,
                    onSubmitted: (_) => _verificar(),
                    validator: Validators.password,
                    textInputAction: TextInputAction.done,
                  ),
                  RequisitosContrasena(controller: _password),
                ],
                const SizedBox(height: 24),
                BotonPrincipal(texto: _textos.accion, cargando: _cargando, onPressed: _verificar),
                const SizedBox(height: 12),
                Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    TextButton(
                      onPressed: _esperar > 0 || _cargando ? null : _enviar,
                      child: Text(_esperar > 0 ? 'Reenviar en $_esperar s' : 'Reenviar código'),
                    ),
                    if (widget.motivo != MotivoCodigo.registro)
                      TextButton(
                        onPressed: () => setState(() {
                          _enviado = false;
                          _codigo.clear();
                          _errorCodigo = null;
                        }),
                        child: const Text('Usar otro email'),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                if (widget.motivo == MotivoCodigo.registro)
                  TextButton(
                    onPressed: () => context.go(Routes.login),
                    child: const Text('¿Ya tenías cuenta con este email? Entrá'),
                  ),
                Text(
                  '¿No te llegó? Fijate en spam o promociones.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
