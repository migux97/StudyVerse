import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/forms/validar.dart';
import '../../../core/theme/colores_materia.dart';

/// Pide nombre y color de una materia. Con [soloColor], solo el color.
/// Devuelve `null` si se cancela.
Future<({String nombre, int color})?> pedirMateria(
  BuildContext context, {
  String titulo = 'Nueva materia',
  String accion = 'Crear',
  String? nombre,
  int color = 0,
  bool soloColor = false,
}) =>
    showDialog(
      context: context,
      builder: (_) => _MateriaDialog(titulo: titulo, accion: accion, nombre: nombre, color: color, soloColor: soloColor),
    );

class _MateriaDialog extends StatefulWidget {
  const _MateriaDialog({
    required this.titulo,
    required this.accion,
    required this.nombre,
    required this.color,
    required this.soloColor,
  });
  final String titulo;
  final String accion;
  final String? nombre;
  final int color;
  final bool soloColor;

  @override
  State<_MateriaDialog> createState() => _MateriaDialogState();
}

class _MateriaDialogState extends State<_MateriaDialog> {
  late final _nombre = TextEditingController(text: widget.nombre);
  late var _color = widget.color;
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _nombre.dispose();
    super.dispose();
  }

  void _ok() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(context, (nombre: _nombre.text.trim(), color: _color));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(widget.titulo),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (!widget.soloColor) ...[
              TextFormField(
                controller: _nombre,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Nombre de la materia', hintText: 'Ej.: Análisis Matemático II'),
                textCapitalization: TextCapitalization.sentences,
                inputFormatters: [LengthLimitingTextInputFormatter(120)],
                autovalidateMode: validarAlCorregir,
                validator: Validar.nombreArchivo(vacio: 'Ingresá el nombre de la materia'),
                onFieldSubmitted: (_) => _ok(),
              ),
              const SizedBox(height: 20),
            ],
            Text('Color', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(children: [
              for (final (i, c) in coloresMateria.indexed)
                // 48 px para tocar cómodo; el círculo se ve de 36.
                Semantics(
                  selected: i == _color,
                  child: InkResponse(
                    onTap: () => setState(() => _color = i),
                    radius: 24,
                    child: Tooltip(
                      message: c.nombre,
                      child: SizedBox.square(
                        dimension: 48,
                        child: Center(
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: colorMateria(context, i),
                              shape: BoxShape.circle,
                              border: i == _color ? Border.all(color: scheme.onSurface, width: 3) : null,
                            ),
                            child: i == _color ? Icon(Icons.check, size: 20, color: scheme.surface) : null,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ]),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _ok, child: Text(widget.accion)),
      ],
    );
  }
}
