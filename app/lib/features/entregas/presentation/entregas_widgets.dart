import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/forms/validar.dart';
import '../domain/trabajo.dart';

/// "Aprobado · 8" con el color del estado.
class ChipEstado extends StatelessWidget {
  const ChipEstado({super.key, required this.estado, this.nota, this.tarde = false});
  final EstadoEntrega estado;
  final num? nota;
  final bool tarde;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (fondo, texto, icono) = switch (estado) {
      EstadoEntrega.pendiente => (scheme.surfaceContainerHighest, scheme.onSurfaceVariant, Icons.schedule),
      EstadoEntrega.entregada => (scheme.secondaryContainer, scheme.onSecondaryContainer, Icons.outbox_outlined),
      EstadoEntrega.aprobada => (scheme.primaryContainer, scheme.onPrimaryContainer, Icons.check_circle_outline),
      EstadoEntrega.aRehacer => (scheme.tertiaryContainer, scheme.onTertiaryContainer, Icons.replay),
      EstadoEntrega.desaprobada => (scheme.errorContainer, scheme.onErrorContainer, Icons.cancel_outlined),
    };
    final etiqueta = [
      estado.texto,
      if (nota != null) formatearNota(nota!),
      if (tarde) 'tarde',
    ].join(' · ');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: fondo, borderRadius: BorderRadius.circular(16)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icono, size: 16, color: texto),
        const SizedBox(width: 4),
        Text(etiqueta, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: texto)),
      ]),
    );
  }
}

/// Lo que se carga al crear o editar un trabajo.
typedef DatosTrabajo = ({String titulo, String? consigna, DateTime venceAt, num notaMaxima});

/// Formulario de un trabajo (nuevo o para editar [inicial]).
Future<DatosTrabajo?> pedirTrabajo(BuildContext context, {Trabajo? inicial}) =>
    showDialog<DatosTrabajo>(context: context, builder: (_) => _TrabajoDialog(inicial: inicial));

class _TrabajoDialog extends StatefulWidget {
  const _TrabajoDialog({this.inicial});
  final Trabajo? inicial;

  @override
  State<_TrabajoDialog> createState() => _TrabajoDialogState();
}

class _TrabajoDialogState extends State<_TrabajoDialog> {
  final _form = GlobalKey<FormState>();
  late final _titulo = TextEditingController(text: widget.inicial?.titulo);
  late final _consigna = TextEditingController(text: widget.inicial?.consigna);
  late final _nota = TextEditingController(text: formatearNota(widget.inicial?.notaMaxima ?? 10));
  late DateTime? _dia = widget.inicial?.venceAt.toLocal();
  late TimeOfDay _hora = widget.inicial == null
      ? const TimeOfDay(hour: 23, minute: 59)
      : TimeOfDay.fromDateTime(widget.inicial!.venceAt.toLocal());
  bool _sinDia = false;

  @override
  void dispose() {
    _titulo.dispose();
    _consigna.dispose();
    _nota.dispose();
    super.dispose();
  }

  Future<void> _elegirDia() async {
    final hoy = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _dia ?? hoy.add(const Duration(days: 7)),
      firstDate: DateTime(hoy.year - 1),
      lastDate: DateTime(hoy.year + 2),
    );
    if (d != null) setState(() => (_dia = d, _sinDia = false));
  }

  Future<void> _elegirHora() async {
    final h = await showTimePicker(context: context, initialTime: _hora);
    if (h != null) setState(() => _hora = h);
  }

  void _guardar() {
    final ok = _form.currentState!.validate();
    if (_dia == null) setState(() => _sinDia = true);
    if (!ok || _dia == null) return;
    final d = _dia!;
    Navigator.pop<DatosTrabajo>(context, (
      titulo: _titulo.text.trim(),
      consigna: _consigna.text.trim().isEmpty ? null : _consigna.text.trim(),
      venceAt: DateTime(d.year, d.month, d.day, _hora.hour, _hora.minute),
      notaMaxima: leerNota(_nota.text)!,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final loc = MaterialLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.inicial == null ? 'Nuevo trabajo' : 'Editar trabajo'),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _form,
          autovalidateMode: validarAlCorregir,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextFormField(
                controller: _titulo,
                autofocus: widget.inicial == null,
                maxLength: 120,
                decoration: const InputDecoration(labelText: 'Nombre', hintText: 'Ej.: TP 2 · Péndulo simple'),
                validator: Validar.texto(vacio: 'Ingresá el nombre del trabajo', max: 120),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _consigna,
                minLines: 3,
                maxLines: 8,
                maxLength: 4000,
                decoration: const InputDecoration(
                  labelText: 'Consigna (opcional)',
                  hintText: 'Ej.: Informe de hasta 10 páginas con las mediciones y las conclusiones',
                  alignLabelWithHint: true,
                ),
                validator: Validar.opcional(4000),
              ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: 'Vence el',
                      errorText: _sinDia ? 'Elegí el día' : null,
                    ),
                    child: InkWell(
                      onTap: _elegirDia,
                      child: Text(_dia == null ? 'Elegir día' : loc.formatMediumDate(_dia!)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 110,
                  child: InputDecorator(
                    decoration: const InputDecoration(labelText: 'Hora'),
                    child: InkWell(onTap: _elegirHora, child: Text(_hora.format(context))),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nota,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                decoration: const InputDecoration(labelText: 'Nota máxima', hintText: 'Ej.: 10'),
                validator: (v) {
                  final n = leerNota(v ?? '');
                  if (n == null) return 'Ingresá un número';
                  if (n <= 0 || n > 100) return 'Usá un número entre 1 y 100';
                  return null;
                },
              ),
            ]),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _guardar, child: Text(widget.inicial == null ? 'Crear' : 'Guardar')),
      ],
    );
  }
}

/// Lo que carga el docente al corregir.
typedef Correccion = ({EstadoEntrega estado, num? nota, String? devolucion});

Future<Correccion?> pedirCorreccion(BuildContext context, {required Trabajo trabajo, required Entrega entrega, required String grupo}) =>
    showDialog<Correccion>(
      context: context,
      builder: (_) => _CorregirDialog(trabajo: trabajo, entrega: entrega, grupo: grupo),
    );

class _CorregirDialog extends StatefulWidget {
  const _CorregirDialog({required this.trabajo, required this.entrega, required this.grupo});
  final Trabajo trabajo;
  final Entrega entrega;
  final String grupo;

  @override
  State<_CorregirDialog> createState() => _CorregirDialogState();
}

class _CorregirDialogState extends State<_CorregirDialog> {
  final _form = GlobalKey<FormState>();
  late EstadoEntrega? _estado = widget.entrega.estado.corregida ? widget.entrega.estado : null;
  late final _nota = TextEditingController(text: widget.entrega.nota == null ? '' : formatearNota(widget.entrega.nota!));
  late final _devolucion = TextEditingController(text: widget.entrega.devolucion);
  bool _sinEstado = false;

  @override
  void dispose() {
    _nota.dispose();
    _devolucion.dispose();
    super.dispose();
  }

  void _guardar() {
    final ok = _form.currentState!.validate();
    if (_estado == null) setState(() => _sinEstado = true);
    if (!ok || _estado == null) return;
    Navigator.pop<Correccion>(context, (
      estado: _estado!,
      nota: _nota.text.trim().isEmpty ? null : leerNota(_nota.text),
      devolucion: _devolucion.text.trim().isEmpty ? null : _devolucion.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final max = widget.trabajo.notaMaxima;
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text('Corregir · ${widget.grupo}'),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _form,
          autovalidateMode: validarAlCorregir,
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(widget.trabajo.titulo, style: theme.textTheme.titleSmall),
              const SizedBox(height: 12),
              SegmentedButton<EstadoEntrega>(
                emptySelectionAllowed: true,
                showSelectedIcon: false,
                segments: [
                  for (final e in EstadoEntrega.correcciones) ButtonSegment(value: e, label: Text(e.texto)),
                ],
                selected: {?_estado},
                onSelectionChanged: (s) => setState(() {
                  _estado = s.firstOrNull;
                  _sinEstado = false;
                }),
              ),
              if (_sinEstado)
                Padding(
                  padding: const EdgeInsets.only(top: 6, left: 12),
                  child: Text('Elegí cómo quedó la entrega',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
                ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nota,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                decoration: InputDecoration(
                  labelText: 'Nota (opcional)',
                  hintText: 'Ej.: 8',
                  suffixText: 'de ${formatearNota(max)}',
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return null;
                  final n = leerNota(v);
                  if (n == null) return 'Ingresá un número';
                  if (n < 0 || n > max) return 'La nota va de 0 a ${formatearNota(max)}';
                  return null;
                },
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _devolucion,
                minLines: 3,
                maxLines: 8,
                maxLength: 4000,
                decoration: const InputDecoration(
                  labelText: 'Devolución (opcional)',
                  hintText: 'Ej.: Muy bien el análisis. Faltó citar la bibliografía',
                  alignLabelWithHint: true,
                ),
              ),
            ]),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _guardar, child: const Text('Guardar corrección')),
      ],
    );
  }
}
