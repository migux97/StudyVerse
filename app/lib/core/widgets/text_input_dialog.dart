import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../forms/validar.dart';

/// Pide un texto (nombre de carpeta, renombrar…). Devuelve `null` si se cancela.
Future<String?> pedirTexto(
  BuildContext context, {
  required String titulo,
  required String etiqueta,
  required String accion,
  String? inicial,
  String? Function(String?)? validator,
  bool seleccionarSinExtension = false,
  String? ejemplo,
  String? ayuda,
  int? maximo,
  TextInputType? teclado,
  List<TextInputFormatter>? formatos,
}) =>
    showDialog<String>(
      context: context,
      builder: (_) => _TextoDialog(
        titulo: titulo,
        etiqueta: etiqueta,
        accion: accion,
        inicial: inicial,
        validator: validator,
        seleccionarSinExtension: seleccionarSinExtension,
        ejemplo: ejemplo,
        ayuda: ayuda,
        maximo: maximo,
        teclado: teclado,
        formatos: formatos,
      ),
    );

class _TextoDialog extends StatefulWidget {
  const _TextoDialog({
    required this.titulo,
    required this.etiqueta,
    required this.accion,
    this.inicial,
    this.validator,
    required this.seleccionarSinExtension,
    this.ejemplo,
    this.ayuda,
    this.maximo,
    this.teclado,
    this.formatos,
  });

  final String titulo;
  final String etiqueta;
  final String accion;
  final String? inicial;
  final String? Function(String?)? validator;
  final bool seleccionarSinExtension;

  /// Ejemplo que se ve con el campo vacío ("Ej.: TP 2").
  final String? ejemplo;

  /// Texto de ayuda debajo del campo.
  final String? ayuda;

  /// Largo máximo: no deja escribir más y muestra el contador cuando falta poco.
  final int? maximo;
  final TextInputType? teclado;
  final List<TextInputFormatter>? formatos;

  @override
  State<_TextoDialog> createState() => _TextoDialogState();
}

class _TextoDialogState extends State<_TextoDialog> {
  late final _controller = TextEditingController(text: widget.inicial);
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    // Al renombrar "Informe.docx" queda seleccionado "Informe", como en Drive.
    final texto = widget.inicial ?? '';
    final punto = texto.lastIndexOf('.');
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: widget.seleccionarSinExtension && punto > 0 ? punto : texto.length,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// El contador aparece recién cuando quedan pocos caracteres, para no
  /// llenar el diálogo de números.
  Widget? _contador(BuildContext context,
      {required int currentLength, required bool isFocused, required int? maxLength}) {
    final max = widget.maximo;
    if (max == null || currentLength < max * 0.8) return null;
    return Text('$currentLength / $max');
  }

  void _ok() {
    if (_formKey.currentState!.validate()) Navigator.pop(context, _controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.titulo),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: TextFormField(
            controller: _controller,
            autofocus: true,
            keyboardType: widget.teclado,
            textCapitalization: widget.teclado == null ? TextCapitalization.sentences : TextCapitalization.none,
            inputFormatters: [
              ...?widget.formatos,
              if (widget.maximo != null) LengthLimitingTextInputFormatter(widget.maximo),
            ],
            decoration: InputDecoration(
              labelText: widget.etiqueta,
              hintText: widget.ejemplo,
              helperText: widget.ayuda,
              helperMaxLines: 2,
            ),
            buildCounter: _contador,
            autovalidateMode: validarAlCorregir,
            onFieldSubmitted: (_) => _ok(),
            validator: widget.validator ?? (v) => (v?.trim().isEmpty ?? true) ? 'Completá este campo' : null,
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(88, 40)),
          onPressed: _ok,
          child: Text(widget.accion),
        ),
      ],
    );
  }
}
