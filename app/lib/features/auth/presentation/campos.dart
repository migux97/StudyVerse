import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/forms/validar.dart';
import '../domain/auth_repository.dart';
import '../domain/validators.dart';
import 'auth_providers.dart';

/// Campo de contraseña con el ojito para verla.
class CampoContrasena extends StatefulWidget {
  const CampoContrasena({
    super.key,
    required this.controller,
    this.etiqueta = 'Contraseña',
    this.nueva = false,
    this.validator,
    this.errorText,
    this.onSubmitted,
    this.onChanged,
    this.textInputAction,
  });

  final TextEditingController controller;
  final String etiqueta;

  /// Contraseña nueva: el gestor de contraseñas la sugiere en vez de completarla.
  final bool nueva;
  final String? Function(String?)? validator;
  final String? errorText;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final TextInputAction? textInputAction;

  @override
  State<CampoContrasena> createState() => _CampoContrasenaState();
}

class _CampoContrasenaState extends State<CampoContrasena> {
  bool _ver = false;
  bool _mayusculas = false;
  final _foco = FocusNode();

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_teclas);
    _foco.addListener(_revisarMayusculas);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_teclas);
    _foco.dispose();
    super.dispose();
  }

  bool _teclas(KeyEvent _) {
    _revisarMayusculas();
    return false;
  }

  /// Aviso de Bloq Mayús, como en la pantalla de entrada de Google.
  void _revisarMayusculas() {
    final activo =
        _foco.hasFocus && HardwareKeyboard.instance.lockModesEnabled.contains(KeyboardLockMode.capsLock);
    if (activo != _mayusculas && mounted) setState(() => _mayusculas = activo);
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      focusNode: _foco,
      obscureText: !_ver,
      autocorrect: false,
      enableSuggestions: false,
      autofillHints: [widget.nueva ? AutofillHints.newPassword : AutofillHints.password],
      textInputAction: widget.textInputAction,
      onFieldSubmitted: widget.onSubmitted,
      onChanged: widget.onChanged,
      validator: widget.validator,
      autovalidateMode: validarAlCorregir,
      decoration: InputDecoration(
        labelText: widget.etiqueta,
        errorText: widget.errorText,
        helperText: _mayusculas ? 'Bloq Mayús está activado' : null,
        suffixIcon: IconButton(
          tooltip: _ver ? 'Ocultar contraseña' : 'Mostrar contraseña',
          icon: Icon(_ver ? Icons.visibility_off_outlined : Icons.visibility_outlined),
          onPressed: () => setState(() => _ver = !_ver),
        ),
      ),
    );
  }
}

/// Lo que le falta a la contraseña, en vivo mientras se escribe.
class RequisitosContrasena extends StatelessWidget {
  const RequisitosContrasena({super.key, required this.controller});
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final estilo = Theme.of(context).textTheme.bodySmall;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
        child: Wrap(
          spacing: 16,
          runSpacing: 6,
          children: [
            for (final r in RequisitoContrasena.values)
              Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(
                  r.cumple(controller.text) ? Icons.check_circle_rounded : Icons.circle_outlined,
                  size: 16,
                  color: r.cumple(controller.text) ? scheme.primary : scheme.outline,
                ),
                const SizedBox(width: 6),
                Text(r.texto,
                    style: estilo?.copyWith(
                        color: r.cumple(controller.text) ? scheme.onSurface : scheme.onSurfaceVariant)),
              ]),
          ],
        ),
      ),
    );
  }
}

/// Botón principal que muestra un indicador mientras trabaja.
class BotonPrincipal extends StatelessWidget {
  const BotonPrincipal({super.key, required this.texto, required this.cargando, required this.onPressed});
  final String texto;
  final bool cargando;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: cargando ? null : onPressed,
      child: cargando
          ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
          : Text(texto),
    );
  }
}

/// Separador "o" entre el formulario y los otros métodos.
class SeparadorO extends StatelessWidget {
  const SeparadorO({super.key});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(children: [
      const Expanded(child: Divider()),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Text('o', style: TextStyle(color: color)),
      ),
      const Expanded(child: Divider()),
    ]);
  }
}

/// Nombre de usuario con "@" adelante. Mientras escribís se fija si está
/// libre, sin esperar a enviar el formulario.
class CampoUsuario extends ConsumerStatefulWidget {
  const CampoUsuario({super.key, required this.controller, this.actual});
  final TextEditingController controller;

  /// El usuario que ya tenés (al editarlo desde el perfil): no cuenta como ocupado.
  final String? actual;

  @override
  ConsumerState<CampoUsuario> createState() => CampoUsuarioState();
}

enum _Disponibilidad { nada, buscando, libre, ocupado }

class CampoUsuarioState extends ConsumerState<CampoUsuario> {
  Timer? _espera;
  var _estado = _Disponibilidad.nada;

  void marcarOcupado() => setState(() => _estado = _Disponibilidad.ocupado);

  @override
  void dispose() {
    _espera?.cancel();
    super.dispose();
  }

  void _alCambiar(String texto) {
    _espera?.cancel();
    final v = texto.trim().toLowerCase();
    if (Validators.username(v) != null || v == widget.actual) {
      setState(() => _estado = _Disponibilidad.nada);
      return;
    }
    setState(() => _estado = _Disponibilidad.buscando);
    _espera = Timer(const Duration(milliseconds: 450), () async {
      try {
        final libre = await ref.read(authRepositoryProvider).usernameDisponible(v);
        if (mounted && widget.controller.text.trim().toLowerCase() == v) {
          setState(() => _estado = libre ? _Disponibilidad.libre : _Disponibilidad.ocupado);
        }
      } on AuthFailure {
        if (mounted) setState(() => _estado = _Disponibilidad.nada);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TextFormField(
      controller: widget.controller,
      autocorrect: false,
      enableSuggestions: false,
      autofillHints: const [AutofillHints.newUsername],
      textInputAction: TextInputAction.next,
      inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'\s')), _Minusculas()],
      onChanged: _alCambiar,
      autovalidateMode: validarAlCorregir,
      validator: (v) =>
          Validators.username(v) ?? (_estado == _Disponibilidad.ocupado ? 'Ese usuario ya está en uso' : null),
      decoration: InputDecoration(
        labelText: 'Nombre de usuario',
        hintText: 'ana.garcia',
        prefixText: '@',
        helperText: switch (_estado) {
          _Disponibilidad.libre => 'Está disponible',
          _ => 'Con este nombre te encuentran tus compañeros',
        },
        errorText: _estado == _Disponibilidad.ocupado ? 'Ese usuario ya está en uso' : null,
        suffixIcon: switch (_estado) {
          _Disponibilidad.buscando => const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          _Disponibilidad.libre => Icon(Icons.check_circle_rounded, color: scheme.primary),
          _ => null,
        },
      ),
    );
  }
}

class _Minusculas extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) =>
      newValue.copyWith(text: newValue.text.toLowerCase());
}

/// Campo de email: ejemplo de formato, sin espacios ni autocorrector, y si el
/// dominio parece mal escrito ("gmial.com") ofrece corregirlo con un toque.
class CampoEmail extends StatelessWidget {
  const CampoEmail({
    super.key,
    required this.controller,
    this.errorText,
    this.autofillHints = const [AutofillHints.email],
    this.textInputAction = TextInputAction.next,
    this.onSubmitted,
    this.onChanged,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final String? errorText;
  final List<String> autofillHints;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final sugerencia = Validators.sugerenciaEmail(controller.text);
        return TextFormField(
          controller: controller,
          autofocus: autofocus,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          enableSuggestions: false,
          autofillHints: autofillHints,
          textInputAction: textInputAction,
          inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'\s'))],
          onFieldSubmitted: onSubmitted,
          onChanged: onChanged,
          validator: Validators.email,
          autovalidateMode: validarAlCorregir,
          decoration: InputDecoration(
            labelText: 'Email',
            hintText: Validators.emailEjemplo,
            errorText: errorText,
            helper: sugerencia == null
                ? null
                : _Sugerencia(
                    texto: sugerencia,
                    onTap: () {
                      controller.value = TextEditingValue(
                        text: sugerencia,
                        selection: TextSelection.collapsed(offset: sugerencia.length),
                      );
                      onChanged?.call(sugerencia);
                    },
                  ),
          ),
        );
      },
    );
  }
}

class _Sugerencia extends StatelessWidget {
  const _Sugerencia({required this.texto, required this.onTap});
  final String texto;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final estilo = Theme.of(context).textTheme.bodySmall;
    return Semantics(
      button: true,
      label: '¿Quisiste decir $texto?',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text.rich(TextSpan(style: estilo, children: [
          const TextSpan(text: '¿Quisiste decir '),
          TextSpan(
            text: texto,
            style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w600,
                decoration: TextDecoration.underline),
          ),
          const TextSpan(text: '?'),
        ])),
        ),
      ),
    );
  }
}
