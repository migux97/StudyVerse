import 'package:flutter/material.dart';

/// Pide un texto (nombre de carpeta, renombrar…). Devuelve `null` si se cancela.
Future<String?> pedirTexto(
  BuildContext context, {
  required String titulo,
  required String etiqueta,
  required String accion,
  String? inicial,
  String? Function(String?)? validator,
  bool seleccionarSinExtension = false,
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
  });

  final String titulo;
  final String etiqueta;
  final String accion;
  final String? inicial;
  final String? Function(String?)? validator;
  final bool seleccionarSinExtension;

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
            decoration: InputDecoration(labelText: widget.etiqueta),
            onFieldSubmitted: (_) => _ok(),
            validator: widget.validator ??
                (v) => (v?.trim().isEmpty ?? true) ? 'No puede quedar vacío' : null,
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
