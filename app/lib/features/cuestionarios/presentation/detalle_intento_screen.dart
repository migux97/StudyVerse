import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/forms/validar.dart';
import '../../../core/widgets/avisos.dart';
import '../../entregas/domain/trabajo.dart' show formatearNota, leerNota;
import '../../groups/presentation/group_shell.dart' show Aviso;
import '../domain/cuestionario.dart';
import 'cuestionarios_providers.dart';

/// Un intento con sus respuestas. El docente ve todo (con las salidas paso a
/// paso) y pone el puntaje de las preguntas de desarrollo; el alumno ve su nota
/// y las correctas cuando el cuestionario lo permite.
class DetalleIntentoScreen extends ConsumerWidget {
  const DetalleIntentoScreen({super.key, required this.intentoId, required this.docente, required this.volver});
  final String intentoId;
  final bool docente;

  /// A dónde vuelve si se abrió desde un link.
  final String volver;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detalle = ref.watch(detalleIntentoProvider(intentoId));
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.canPop() ? context.pop() : context.go(volver)),
        title: Text(switch (detalle.value) {
          final d? when docente => d.alumno ?? 'Intento',
          final d? => d.cuestionario.titulo,
          _ => 'Resultado',
        }),
      ),
      body: switch (detalle) {
        AsyncValue(:final error?) => Aviso(
            icono: Icons.cloud_off_outlined,
            texto: error is CuestionariosFailure ? error.mensaje : 'Algo salió mal. Probá de nuevo',
            accion: FilledButton(
                onPressed: () => ref.invalidate(detalleIntentoProvider(intentoId)), child: const Text('Reintentar')),
          ),
        AsyncValue(value: final DetalleIntento d) => RefreshIndicator(
            onRefresh: () => ref.refresh(detalleIntentoProvider(intentoId).future),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 800),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      _Resumen(d: d, docente: docente),
                      if (docente && d.eventos.any((e) => e.tipo != 'empezo' && e.tipo != 'entrego'))
                        _Salidas(eventos: d.eventos),
                      for (final (n, p) in d.preguntas.indexed)
                        _Respuesta(n: n + 1, p: p, d: d, docente: docente),
                    ]),
                  ),
                ),
              ],
            ),
          ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _Resumen extends StatelessWidget {
  const _Resumen({required this.d, required this.docente});
  final DetalleIntento d;
  final bool docente;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final i = d.intento;
    final c = d.cuestionario;
    final porCorregir = d.detalleVisible ? d.preguntas.where((p) => p.porCorregir).length : 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (docente)
            Text([c.titulo, if (d.grupo != null) d.grupo!, 'Intento ${i.numero}'].join(' · '),
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 4),
          if (i.visible)
            Text(i.pendiente ? 'Falta corregir' : textoNota(i, c), style: theme.textTheme.headlineSmall)
          else
            Text(
              c.resultadosAlCerrar
                  ? 'La nota y las respuestas correctas se ven cuando cierre (${_fecha(c.cierraAt)})'
                  : 'Entregado',
              style: theme.textTheme.titleMedium,
            ),
          if (i.visible && i.puntajeMax != null)
            Text(
              '${formatearNota(i.puntaje ?? 0)} de ${formatearNota(i.puntajeMax!)} puntos'
              '${porCorregir > 0 ? ' · ${porCorregir == 1 ? '1 respuesta' : '$porCorregir respuestas'} por corregir' : ''}',
              style: theme.textTheme.bodyMedium,
            ),
          if (i.visible && !d.detalleVisible)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Las respuestas correctas se ven cuando cierre o cuando ya no te queden intentos.',
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 4, children: [
            Chip(
              visualDensity: VisualDensity.compact,
              avatar: Icon(i.entregado ? Icons.check_circle_outline : Icons.edit_note, size: 18),
              label: Text(estadoIntento(i)),
            ),
            Chip(
              visualDensity: VisualDensity.compact,
              avatar: const Icon(Icons.visibility_off_outlined, size: 18),
              label: Text(i.salidas == 0
                  ? 'No salió de la pantalla'
                  : '${textoSalidas(i.salidas)} · ${formatearSegundos(i.segundosAfuera)} afuera'),
            ),
            if (i.entregadoAt case final e?)
              Chip(
                visualDensity: VisualDensity.compact,
                avatar: const Icon(Icons.schedule, size: 18),
                label: Text('Tardó ${formatearSegundos(e.difference(i.empezadoAt).inSeconds)}'),
              ),
          ]),
        ]),
      ),
    );
  }
}

String _fecha(DateTime d) {
  final l = d.toLocal();
  String dos(int n) => n.toString().padLeft(2, '0');
  return '${dos(l.day)}/${dos(l.month)} ${dos(l.hour)}:${dos(l.minute)}';
}

String _hora(DateTime d) {
  final l = d.toLocal();
  String dos(int n) => n.toString().padLeft(2, '0');
  return '${dos(l.hour)}:${dos(l.minute)}:${dos(l.second)}';
}

/// Qué pasó mientras rendía (para el docente).
class _Salidas extends StatelessWidget {
  const _Salidas({required this.eventos});
  final List<EventoIntento> eventos;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: ExpansionTile(
        leading: const Icon(Icons.history),
        title: const Text('Registro'),
        subtitle: const Text('Cuándo salió y volvió a la pantalla'),
        shape: const Border(),
        children: [
          for (final e in eventos)
            ListTile(
              dense: true,
              leading: Icon(
                switch (e.tipo) {
                  'salio' || 'reabrio' => Icons.logout,
                  'volvio' => Icons.login,
                  'entrego' => Icons.send_outlined,
                  _ => Icons.play_arrow_outlined,
                },
                size: 20,
                color: e.esSalida ? theme.colorScheme.tertiary : theme.colorScheme.onSurfaceVariant,
              ),
              title: Text(e.texto),
              trailing: Text(_hora(e.at), style: theme.textTheme.bodySmall),
            ),
        ],
      ),
    );
  }
}

class _Respuesta extends ConsumerWidget {
  const _Respuesta({required this.n, required this.p, required this.d, required this.docente});
  final int n;
  final PreguntaRespondida p;
  final DetalleIntento d;
  final bool docente;

  Future<void> _corregir(BuildContext context, WidgetRef ref) async {
    final r = await showDialog<({num puntaje, String? comentario})>(
      context: context,
      builder: (_) => _CorregirDialog(p: p),
    );
    if (r == null || !context.mounted) return;
    try {
      await ref.read(cuestionariosRepositoryProvider)
          .corregir(d.intento.id, p.pregunta.id!, puntaje: r.puntaje, comentario: r.comentario);
      if (!context.mounted) return;
      ref.invalidate(detalleIntentoProvider(d.intento.id));
      ref.invalidate(resultadosProvider(d.cuestionario.id));
    } on CuestionariosFailure catch (e) {
      if (context.mounted) mostrarMensaje(context, e.mensaje, error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final q = p.pregunta;
    final visible = d.detalleVisible;
    final elegidas = switch (p.valor) { final List<int> l => l, _ => const <int>[] };
    final bien = visible && p.puntaje != null && p.puntaje == q.puntos;
    final mal = visible && p.puntaje != null && p.puntaje == 0;

    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: Text('Pregunta $n · ${q.tipo.texto}',
                  style: theme.textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant)),
            ),
            if (visible)
              Text(
                p.porCorregir
                    ? 'Por corregir · ${formatearNota(q.puntos)} pts'
                    : '${formatearNota(p.puntaje ?? 0)} / ${formatearNota(q.puntos)} pts',
                style: theme.textTheme.labelLarge?.copyWith(
                    color: bien ? scheme.primary : mal ? scheme.error : scheme.onSurfaceVariant),
              ),
          ]),
          const SizedBox(height: 6),
          Text(q.enunciado, style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          if (q.tipo.conOpciones)
            for (final (i, o) in q.opciones.indexed)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(children: [
                  Icon(
                    elegidas.contains(i)
                        ? (q.tipo == TipoPregunta.opcion ? Icons.radio_button_checked : Icons.check_box)
                        : (q.tipo == TipoPregunta.opcion ? Icons.radio_button_unchecked : Icons.check_box_outline_blank),
                    size: 20,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(o)),
                  if (visible && q.correctas.contains(i))
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Text('Correcta', style: theme.textTheme.labelMedium?.copyWith(color: scheme.primary)),
                    ),
                ]),
              )
          else
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                p.respondida ? p.valor as String : 'Sin responder',
                style: p.respondida ? null : TextStyle(color: scheme.onSurfaceVariant, fontStyle: FontStyle.italic),
              ),
            ),
          if (visible && q.tipo == TipoPregunta.corta && q.aceptadas.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Respuesta correcta: ${q.aceptadas.join(' / ')}',
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.primary)),
          ],
          if (q.tipo.conOpciones && elegidas.isEmpty)
            Text('Sin responder', style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          if (visible && p.comentario != null) ...[
            const SizedBox(height: 8),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.comment_outlined, size: 18, color: scheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(child: Text(p.comentario!, style: theme.textTheme.bodyMedium)),
            ]),
          ],
          if (docente && d.intento.entregado)
            Align(
              alignment: Alignment.centerRight,
              child: p.porCorregir
                  ? FilledButton.tonalIcon(
                      icon: const Icon(Icons.rate_review_outlined, size: 18),
                      label: const Text('Corregir'),
                      onPressed: () => _corregir(context, ref),
                    )
                  : TextButton(onPressed: () => _corregir(context, ref), child: const Text('Cambiar puntaje')),
            ),
        ]),
      ),
    );
  }
}

class _CorregirDialog extends StatefulWidget {
  const _CorregirDialog({required this.p});
  final PreguntaRespondida p;

  @override
  State<_CorregirDialog> createState() => _CorregirDialogState();
}

class _CorregirDialogState extends State<_CorregirDialog> {
  final _form = GlobalKey<FormState>();
  late final _puntaje = TextEditingController(text: widget.p.puntaje == null ? '' : formatearNota(widget.p.puntaje!));
  late final _comentario = TextEditingController(text: widget.p.comentario);

  @override
  void dispose() {
    _puntaje.dispose();
    _comentario.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final max = widget.p.pregunta.puntos;
    return AlertDialog(
      title: const Text('Corregir respuesta'),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _form,
          autovalidateMode: validarAlCorregir,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(
              controller: _puntaje,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: 'Puntaje (de 0 a ${formatearNota(max)})', hintText: 'Ej.: 1,5'),
              validator: (v) {
                final n = leerNota(v ?? '');
                if (n == null) return 'Ingresá el puntaje';
                if (n < 0 || n > max) return 'Va de 0 a ${formatearNota(max)}';
                return null;
              },
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _comentario,
              minLines: 2,
              maxLines: 5,
              maxLength: 2000,
              decoration: const InputDecoration(
                labelText: 'Comentario (opcional)',
                hintText: 'Ej.: Faltó justificar por qué no depende de la masa',
              ),
            ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () {
            if (!_form.currentState!.validate()) return;
            final c = _comentario.text.trim();
            Navigator.pop(context, (puntaje: leerNota(_puntaje.text)!, comentario: c.isEmpty ? null : c));
          },
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
