import 'package:flutter/material.dart';

/// Grupos de símbolos que se pueden insertar al escribir una respuesta.
const gruposDeSimbolos = <(String, List<String>)>[
  ('Matemática', ['²', '³', '√', 'π', '±', '×', '÷', '≈', '≠', '≤', '≥', '∞', '½', '°', '%', '∑', '∫']),
  ('Flechas', ['→', '←', '↔', '⇒', '⇔', '↑', '↓']),
  ('Griegas', ['α', 'β', 'γ', 'Δ', 'δ', 'ε', 'θ', 'λ', 'μ', 'ρ', 'σ', 'Σ', 'φ', 'ω', 'Ω']),
  ('Índices', ['⁰', '¹', '⁴', '⁵', '⁶', '⁷', '⁸', '⁹', '⁻', '₀', '₁', '₂', '₃', '₄', 'ₙ', 'ₓ']),
];

/// Inserta [texto] donde está el cursor (o en lugar de lo seleccionado).
TextEditingValue insertarEn(TextEditingValue v, String texto) {
  final sel = v.selection;
  final inicio = sel.isValid ? sel.start : v.text.length;
  final fin = sel.isValid ? sel.end : v.text.length;
  final nuevo = v.text.replaceRange(inicio, fin, texto);
  return TextEditingValue(
    text: nuevo,
    selection: TextSelection.collapsed(offset: inicio + texto.length),
  );
}

/// Empieza una viñeta: si el cursor está en una línea con texto, pasa a una
/// línea nueva; si la línea ya es una viñeta, no hace nada.
TextEditingValue insertarVineta(TextEditingValue v) {
  final sel = v.selection;
  final pos = sel.isValid ? sel.start : v.text.length;
  final inicioLinea = pos == 0 ? 0 : v.text.lastIndexOf('\n', pos - 1) + 1;
  final finLinea = v.text.indexOf('\n', pos);
  final linea = v.text.substring(inicioLinea, finLinea == -1 ? v.text.length : finLinea);
  if (RegExp(r'^\s*•\s*$').hasMatch(linea)) return v;
  if (v.text.substring(inicioLinea, pos).trim().isEmpty) return insertarEn(v, '• ');
  return insertarEn(v, '\n• ');
}

final _conLetra = RegExp(r'[\p{L}\p{N}]', unicode: true);

/// Palabras de un texto (para el contador). No cuenta viñetas ni signos sueltos.
int contarPalabras(String t) =>
    RegExp(r'\S+').allMatches(t).where((m) => _conLetra.hasMatch(m[0]!)).length;

/// Barra chica arriba de un campo de respuesta: símbolos, viñetas, deshacer y
/// rehacer. Como cambia el texto desde afuera, avisa con [alCambiar].
class HerramientasEscritura extends StatefulWidget {
  const HerramientasEscritura({
    super.key,
    required this.controller,
    required this.deshacer,
    required this.alCambiar,
    this.focusNode,
    this.maxLength,
    this.conVinetas = true,
    this.habilitado = true,
  });

  final TextEditingController controller;
  final UndoHistoryController deshacer;
  final ValueChanged<String> alCambiar;
  final FocusNode? focusNode;

  /// El mismo tope que el campo: lo que inserta la barra no lo puede pasar.
  final int? maxLength;
  final bool conVinetas;
  final bool habilitado;

  @override
  State<HerramientasEscritura> createState() => _HerramientasEscrituraState();
}

class _HerramientasEscrituraState extends State<HerramientasEscritura> {
  int _grupo = 0;
  bool _simbolos = false;

  void _aplicar(TextEditingValue nuevo) {
    if (widget.maxLength case final max? when nuevo.text.characters.length > max) {
      widget.focusNode?.requestFocus();
      return;
    }
    widget.controller.value = nuevo;
    widget.alCambiar(nuevo.text);
    widget.focusNode?.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final on = widget.habilitado;
    // Tocar la barra no le saca el foco al campo: el cursor queda donde estaba.
    return TextFieldTapRegion(child: _barra(theme, scheme, on));
  }

  Widget _barra(ThemeData theme, ColorScheme scheme, bool on) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ValueListenableBuilder<UndoHistoryValue>(
        valueListenable: widget.deshacer,
        builder: (context, h, _) => Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
          IconButton(
            tooltip: 'Deshacer',
            icon: const Icon(Icons.undo),
            onPressed: on && h.canUndo
                ? () {
                    widget.deshacer.undo();
                    widget.alCambiar(widget.controller.text);
                  }
                : null,
          ),
          IconButton(
            tooltip: 'Rehacer',
            icon: const Icon(Icons.redo),
            onPressed: on && h.canRedo
                ? () {
                    widget.deshacer.redo();
                    widget.alCambiar(widget.controller.text);
                  }
                : null,
          ),
          if (widget.conVinetas)
            IconButton(
              tooltip: 'Viñeta',
              icon: const Icon(Icons.format_list_bulleted),
              onPressed: on ? () => _aplicar(insertarVineta(widget.controller.value)) : null,
            ),
          IconButton(
            tooltip: _simbolos ? 'Ocultar símbolos' : 'Símbolos',
            visualDensity: VisualDensity.compact,
            isSelected: _simbolos,
            icon: const Icon(Icons.functions),
            onPressed: on ? () => setState(() => _simbolos = !_simbolos) : null,
          ),
        ]),
      ),
      if (_simbolos && on)
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Wrap(spacing: 6, runSpacing: 4, children: [
              for (final (i, (nombre, _)) in gruposDeSimbolos.indexed)
                ChoiceChip(
                  label: Text(nombre),
                  selected: _grupo == i,
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) => setState(() => _grupo = i),
                ),
            ]),
            const SizedBox(height: 6),
            Wrap(spacing: 2, runSpacing: 2, children: [
              for (final s in gruposDeSimbolos[_grupo].$2)
                SizedBox.square(
                  dimension: 48,
                  child: TextButton(
                    style: TextButton.styleFrom(padding: EdgeInsets.zero),
                    onPressed: () => _aplicar(insertarEn(widget.controller.value, s)),
                    child: Text(s, style: theme.textTheme.titleMedium),
                  ),
                ),
            ]),
          ]),
        ),
    ]);
  }
}
