import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/forms/validar.dart';
import '../../../core/router/app_router.dart';
import '../../../core/web/guardar_archivo.dart';
import '../../../core/widgets/avisos.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../cursos/domain/curso.dart';
import '../../entregas/domain/trabajo.dart' show formatearNota, leerNota;
import '../../groups/presentation/group_shell.dart' show Aviso;
import '../domain/cuestionario.dart';
import '../domain/exportar_resultados.dart';
import 'cuestionarios_grupo_screen.dart' show formatearCierre, ventana;
import 'cuestionarios_providers.dart';

/// Pestaña "Cuestionarios" del curso.
class CuestionariosDelCurso extends ConsumerWidget {
  const CuestionariosDelCurso({super.key, required this.curso});
  final Curso curso;

  Future<void> _nuevo(BuildContext context, WidgetRef ref) async {
    final d = await pedirCuestionario(context);
    if (d == null || !context.mounted) return;
    try {
      final c = await ref.read(cuestionariosRepositoryProvider).guardar(cursoId: curso.id, datos: d);
      if (!context.mounted) return;
      ref.invalidate(cuestionariosProvider(curso.id));
      context.push(Routes.cuestionarioDocente(curso.id, c.id));
    } on CuestionariosFailure catch (e) {
      if (context.mounted) mostrarMensaje(context, e.mensaje, error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lista = ref.watch(cuestionariosProvider(curso.id));
    final ahora = DateTime.now();
    final boton = FilledButton.icon(
      icon: const Icon(Icons.add),
      label: const Text('Nuevo cuestionario'),
      onPressed: () => _nuevo(context, ref),
    );
    return switch (lista) {
      AsyncValue(:final error?) => Aviso(
          icono: Icons.cloud_off_outlined,
          texto: error is CuestionariosFailure ? error.mensaje : 'Algo salió mal. Probá de nuevo',
          accion: FilledButton(onPressed: () => ref.invalidate(cuestionariosProvider(curso.id)), child: const Text('Reintentar')),
        ),
      AsyncValue(value: final List<Cuestionario> cs) when cs.isEmpty => Aviso(
          icono: Icons.quiz_outlined,
          texto: 'Todavía no hay cuestionarios',
          detalle: 'Armá cuestionarios de práctica o evaluaciones con tiempo límite. Las preguntas de opción y de '
              'respuesta corta se corrigen solas, y ves si alguien salió de la pantalla mientras rendía.',
          accion: boton,
        ),
      AsyncValue(value: final List<Cuestionario> cs) => RefreshIndicator(
          onRefresh: () => ref.refresh(cuestionariosProvider(curso.id).future),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            children: [
              Align(alignment: Alignment.centerRight, child: boton),
              const SizedBox(height: 8),
              for (final c in cs)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: const Icon(Icons.quiz_outlined),
                    title: Text(c.titulo),
                    subtitle: Text(c.publicado ? ventana(c, ahora) : 'Sin publicar: los alumnos todavía no lo ven'),
                    trailing: Chip(visualDensity: VisualDensity.compact, label: Text(c.estado(ahora).texto)),
                    onTap: () => context.push(Routes.cuestionarioDocente(curso.id, c.id)),
                  ),
                ),
            ],
          ),
        ),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }
}

// Ajustes del cuestionario ------------------------------------------------------------

Future<DatosCuestionario?> pedirCuestionario(BuildContext context, {Cuestionario? inicial}) =>
    showDialog<DatosCuestionario>(context: context, builder: (_) => _CuestionarioDialog(inicial: inicial));

class _CuestionarioDialog extends StatefulWidget {
  const _CuestionarioDialog({this.inicial});
  final Cuestionario? inicial;

  @override
  State<_CuestionarioDialog> createState() => _CuestionarioDialogState();
}

class _CuestionarioDialogState extends State<_CuestionarioDialog> {
  final _form = GlobalKey<FormState>();
  late final Cuestionario? _c = widget.inicial;
  late final _titulo = TextEditingController(text: _c?.titulo);
  late final _descripcion = TextEditingController(text: _c?.descripcion);
  late final _duracion = TextEditingController(text: '${_c?.duracionMin ?? 40}');
  late final _intentos = TextEditingController(text: '${_c?.intentos ?? 1}');
  late final _tope = TextEditingController(text: '${_c?.topeSalidas ?? 3}');
  late final _nota = TextEditingController(text: formatearNota(_c?.notaMaxima ?? 10));
  late DateTime _abre = _c?.abreAt.toLocal() ?? DateTime.now();
  late DateTime _cierra = _c?.cierraAt.toLocal() ?? _finDelDia(DateTime.now().add(const Duration(days: 7)));
  late bool _conTiempo = _c == null || _c.duracionMin != null;
  late bool _conTope = _c?.topeSalidas != null;
  late bool _alCerrar = _c?.resultadosAlCerrar ?? false;
  late bool _mezclar = _c?.mezclar ?? false;
  String? _errorFechas;

  static DateTime _finDelDia(DateTime d) => DateTime(d.year, d.month, d.day, 23, 59);

  @override
  void dispose() {
    for (final c in [_titulo, _descripcion, _duracion, _intentos, _tope, _nota]) {
      c.dispose();
    }
    super.dispose();
  }

  void _guardar() {
    final ok = _form.currentState!.validate();
    setState(() => _errorFechas = _cierra.isAfter(_abre) ? null : 'El cierre tiene que ser después de la apertura');
    if (!ok || _errorFechas != null) return;
    final desc = _descripcion.text.trim();
    Navigator.pop<DatosCuestionario>(context, (
      titulo: _titulo.text.trim(),
      descripcion: desc.isEmpty ? null : desc,
      abreAt: _abre,
      cierraAt: _cierra,
      duracionMin: _conTiempo ? int.parse(_duracion.text.trim()) : null,
      intentos: int.parse(_intentos.text.trim()),
      resultadosAlCerrar: _alCerrar,
      mezclar: _mezclar,
      topeSalidas: _conTope ? int.parse(_tope.text.trim()) : null,
      notaMaxima: leerNota(_nota.text)!,
    ));
  }

  String? Function(String?) _entero(int min, int max, String vacio) => (v) {
        final n = int.tryParse(v?.trim() ?? '');
        if (n == null) return vacio;
        if (n < min || n > max) return 'Va de $min a $max';
        return null;
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final digitos = [FilteringTextInputFormatter.digitsOnly];
    return AlertDialog(
      title: Text(_c == null ? 'Nuevo cuestionario' : 'Ajustes del cuestionario'),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _form,
          autovalidateMode: validarAlCorregir,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TextFormField(
                controller: _titulo,
                autofocus: _c == null,
                maxLength: 120,
                decoration: const InputDecoration(labelText: 'Nombre', hintText: 'Ej.: Parcialito 1 · Cinemática'),
                validator: Validar.texto(vacio: 'Ingresá el nombre', max: 120),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _descripcion,
                minLines: 2,
                maxLines: 5,
                maxLength: 4000,
                decoration: const InputDecoration(
                  labelText: 'Instrucciones (opcional)',
                  hintText: 'Ej.: Usen g = 9,8 m/s². Pueden usar calculadora.',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 8),
              _FechaHora(etiqueta: 'Abre', valor: _abre, onChanged: (d) => setState(() => _abre = d)),
              const SizedBox(height: 8),
              _FechaHora(etiqueta: 'Cierra', valor: _cierra, onChanged: (d) => setState(() => _cierra = d)),
              if (_errorFechas != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4, left: 12),
                  child: Text(_errorFechas!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
                ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Tiempo límite'),
                subtitle: const Text('Desde que cada alumno empieza'),
                value: _conTiempo,
                onChanged: (v) => setState(() => _conTiempo = v),
              ),
              if (_conTiempo)
                TextFormField(
                  controller: _duracion,
                  keyboardType: TextInputType.number,
                  inputFormatters: digitos,
                  decoration: const InputDecoration(labelText: 'Minutos', hintText: 'Ej.: 40'),
                  validator: _entero(1, 600, 'Ingresá los minutos'),
                ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: TextFormField(
                    controller: _intentos,
                    keyboardType: TextInputType.number,
                    inputFormatters: digitos,
                    decoration: const InputDecoration(labelText: 'Intentos', hintText: 'Ej.: 1'),
                    validator: _entero(1, 20, 'Ingresá los intentos'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _nota,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Nota máxima', hintText: 'Ej.: 10'),
                    validator: (v) {
                      final n = leerNota(v ?? '');
                      if (n == null) return 'Ingresá la nota máxima';
                      if (n <= 0 || n > 100) return 'Va de 1 a 100';
                      return null;
                    },
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Entregar solo al pasar un máximo de salidas'),
                subtitle: const Text('Las salidas de la pantalla siempre quedan registradas'),
                value: _conTope,
                onChanged: (v) => setState(() => _conTope = v),
              ),
              if (_conTope)
                TextFormField(
                  controller: _tope,
                  keyboardType: TextInputType.number,
                  inputFormatters: digitos,
                  decoration: const InputDecoration(
                    labelText: 'Salidas permitidas',
                    hintText: 'Ej.: 3 (con 0, la primera salida lo entrega)',
                  ),
                  validator: _entero(0, 50, 'Ingresá las salidas permitidas'),
                ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Mezclar preguntas y opciones'),
                subtitle: const Text('Cada alumno las ve en otro orden'),
                value: _mezclar,
                onChanged: (v) => setState(() => _mezclar = v),
              ),
              const SizedBox(height: 4),
              Text('¿Cuándo ven la nota y las respuestas correctas?', style: theme.textTheme.bodyMedium),
              const SizedBox(height: 8),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Al entregar')),
                  ButtonSegment(value: true, label: Text('Cuando cierra')),
                ],
                selected: {_alCerrar},
                onSelectionChanged: (s) => setState(() => _alCerrar = s.first),
              ),
            ]),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _guardar, child: Text(_c == null ? 'Crear' : 'Guardar')),
      ],
    );
  }
}

class _FechaHora extends StatelessWidget {
  const _FechaHora({required this.etiqueta, required this.valor, required this.onChanged});
  final String etiqueta;
  final DateTime valor;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    final loc = MaterialLocalizations.of(context);
    return Row(children: [
      SizedBox(width: 56, child: Text(etiqueta)),
      Expanded(
        child: OutlinedButton.icon(
          icon: const Icon(Icons.event, size: 18),
          label: Text(loc.formatMediumDate(valor)),
          onPressed: () async {
            final hoy = DateTime.now();
            final d = await showDatePicker(
              context: context,
              initialDate: valor,
              firstDate: DateTime(hoy.year - 1).isBefore(valor) ? DateTime(hoy.year - 1) : valor,
              lastDate: DateTime(hoy.year + 2).isAfter(valor) ? DateTime(hoy.year + 2) : valor,
            );
            if (d != null) onChanged(DateTime(d.year, d.month, d.day, valor.hour, valor.minute));
          },
        ),
      ),
      const SizedBox(width: 8),
      OutlinedButton.icon(
        icon: const Icon(Icons.schedule, size: 18),
        label: Text(loc.formatTimeOfDay(TimeOfDay.fromDateTime(valor), alwaysUse24HourFormat: true)),
        onPressed: () async {
          final h = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(valor));
          if (h != null) onChanged(DateTime(valor.year, valor.month, valor.day, h.hour, h.minute));
        },
      ),
    ]);
  }
}

// Pantalla del cuestionario (docente) ---------------------------------------------------

class CuestionarioDocenteScreen extends ConsumerWidget {
  const CuestionarioDocenteScreen({super.key, required this.cursoId, required this.cuestionarioId});
  final String cursoId;
  final String cuestionarioId;

  Future<void> _intentar(BuildContext context, Future<void> Function() accion) async {
    try {
      await accion();
    } on CuestionariosFailure catch (e) {
      if (context.mounted) mostrarMensaje(context, e.mensaje, error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cuestionario = ref.watch(cuestionarioProvider(cuestionarioId));
    final c = cuestionario.value;
    final repo = ref.read(cuestionariosRepositoryProvider);

    void refrescar() {
      ref.invalidate(cuestionarioProvider(cuestionarioId));
      ref.invalidate(cuestionariosProvider(cursoId));
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          leading: BackButton(onPressed: () => context.canPop() ? context.pop() : context.go(Routes.curso(cursoId))),
          title: Text(c?.titulo ?? 'Cuestionario'),
          bottom: const TabBar(tabs: [Tab(text: 'Preguntas'), Tab(text: 'Resultados')]),
          actions: [
            if (c != null && !c.publicado)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: FilledButton(
                  onPressed: () async {
                    final ok = await confirmar(
                      context,
                      titulo: '¿Publicar «${c.titulo}»?',
                      mensaje: 'Les llega un aviso a todos los alumnos del curso. '
                          'Las preguntas se pueden cambiar hasta que alguien empiece.',
                      accion: 'Publicar',
                    );
                    if (!ok || !context.mounted) return;
                    await _intentar(context, () async {
                      await repo.publicar(c.id);
                      if (!context.mounted) return;
                      refrescar();
                      mostrarMensaje(context, 'Publicado: les avisamos a los alumnos');
                    });
                  },
                  child: const Text('Publicar'),
                ),
              ),
            if (c != null)
              PopupMenuButton<String>(
                tooltip: 'Más opciones',
                onSelected: (op) async {
                  switch (op) {
                    case 'ajustes':
                      final d = await pedirCuestionario(context, inicial: c);
                      if (d == null || !context.mounted) return;
                      await _intentar(context, () async {
                        await repo.guardar(id: c.id, datos: d);
                        if (context.mounted) refrescar();
                      });
                    case 'borrar':
                      final ok = await confirmar(
                        context,
                        titulo: '¿Eliminar «${c.titulo}»?',
                        mensaje: 'Se borran también los intentos y las notas de los alumnos.',
                        accion: 'Eliminar',
                        peligroso: true,
                      );
                      if (!ok || !context.mounted) return;
                      await _intentar(context, () async {
                        await repo.borrar(c.id);
                        if (!context.mounted) return;
                        ref.invalidate(cuestionariosProvider(cursoId));
                        context.go(Routes.curso(cursoId));
                      });
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'ajustes', child: ListTile(leading: Icon(Icons.tune), title: Text('Ajustes'))),
                  PopupMenuItem(value: 'borrar', child: ListTile(leading: Icon(Icons.delete_outline), title: Text('Eliminar'))),
                ],
              ),
          ],
        ),
        body: switch (cuestionario) {
          AsyncValue(:final error?) => Aviso(
              icono: Icons.quiz_outlined,
              texto: error is CuestionariosFailure ? error.mensaje : 'Algo salió mal. Probá de nuevo',
              accion: FilledButton(onPressed: refrescar, child: const Text('Reintentar')),
            ),
          AsyncValue(value: final Cuestionario c) => TabBarView(children: [
              _Preguntas(cuestionario: c),
              _Resultados(cuestionario: c),
            ]),
          _ => const Center(child: CircularProgressIndicator()),
        },
      ),
    );
  }
}

class _Preguntas extends ConsumerWidget {
  const _Preguntas({required this.cuestionario});
  final Cuestionario cuestionario;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = cuestionario;
    final preguntas = ref.watch(preguntasConClaveProvider(c.id));
    // Con intentos ya no se pueden cambiar (mientras no se sabe, tampoco).
    final hayIntentos = ref.watch(resultadosProvider(c.id)).value?.any((a) => a.intentos.isNotEmpty) ?? true;
    final theme = Theme.of(context);

    Future<void> guardar(List<Pregunta> nuevas) async {
      try {
        await ref.read(cuestionariosRepositoryProvider).guardarPreguntas(c.id, nuevas);
        if (context.mounted) ref.invalidate(preguntasConClaveProvider(c.id));
      } on CuestionariosFailure catch (e) {
        if (context.mounted) mostrarMensaje(context, e.mensaje, error: true);
      }
    }

    return switch (preguntas) {
      AsyncValue(:final error?) => Aviso(
          icono: Icons.cloud_off_outlined,
          texto: error is CuestionariosFailure ? error.mensaje : 'Algo salió mal. Probá de nuevo',
          accion: FilledButton(
              onPressed: () => ref.invalidate(preguntasConClaveProvider(c.id)), child: const Text('Reintentar')),
        ),
      AsyncValue(value: final List<Pregunta> ps) => Builder(builder: (context) {
          final total = ps.fold<num>(0, (s, p) => s + p.puntos);
          final agregar = FilledButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Agregar pregunta'),
            onPressed: () async {
              final p = await pedirPregunta(context);
              if (p != null) await guardar([...ps, p]);
            },
          );
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 800),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(
                            [
                              if (c.publicado) formatearCierre(c, DateTime.now()) else 'Sin publicar',
                              c.duracionMin == null ? 'sin tiempo límite' : '${c.duracionMin} min',
                              c.intentos == 1 ? '1 intento' : '${c.intentos} intentos',
                              switch (c.topeSalidas) {
                                null => 'sin tope de salidas',
                                0 => 'se entrega si sale de la pantalla',
                                1 => 'se entrega si sale más de 1 vez',
                                final t => 'se entrega si sale más de $t veces',
                              },
                            ].join(' · '),
                            style: theme.textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            ps.isEmpty
                                ? 'Agregá preguntas. Las de opción y respuesta corta se corrigen solas; las de desarrollo las corregís vos.'
                                : '${ps.length == 1 ? '1 pregunta' : '${ps.length} preguntas'} · ${formatearNota(total)} ${total == 1 ? 'punto' : 'puntos'} '
                                    '(se pasa a nota sobre ${formatearNota(c.notaMaxima)})',
                            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                          ),
                          if (hayIntentos) ...[
                            const SizedBox(height: 8),
                            Text('Ya hay alumnos que lo empezaron: las preguntas no se pueden cambiar.',
                                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.tertiary)),
                          ],
                        ]),
                      ),
                    ),
                    for (final (n, p) in ps.indexed)
                      _TarjetaPregunta(
                        n: n + 1,
                        p: p,
                        onEditar: hayIntentos
                            ? null
                            : () async {
                                final nueva = await pedirPregunta(context, inicial: p);
                                if (nueva != null) await guardar([...ps]..[n] = nueva);
                              },
                        onSubir: hayIntentos || n == 0
                            ? null
                            : () => guardar([...ps]
                              ..removeAt(n)
                              ..insert(n - 1, p)),
                        onBajar: hayIntentos || n == ps.length - 1
                            ? null
                            : () => guardar([...ps]
                              ..removeAt(n)
                              ..insert(n + 1, p)),
                        onBorrar: hayIntentos ? null : () => guardar([...ps]..removeAt(n)),
                      ),
                    if (!hayIntentos) ...[
                      const SizedBox(height: 12),
                      Align(alignment: Alignment.centerRight, child: agregar),
                    ],
                  ]),
                ),
              ),
            ],
          );
        }),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }
}

class _TarjetaPregunta extends StatelessWidget {
  const _TarjetaPregunta({
    required this.n,
    required this.p,
    required this.onEditar,
    required this.onSubir,
    required this.onBajar,
    required this.onBorrar,
  });
  final int n;
  final Pregunta p;
  final VoidCallback? onEditar;
  final VoidCallback? onSubir;
  final VoidCallback? onBajar;
  final VoidCallback? onBorrar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onEditar,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 4, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(
                child: Text('$n · ${p.tipo.texto} · ${formatearNota(p.puntos)} ${p.puntos == 1 ? 'punto' : 'puntos'}',
                    style: theme.textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant)),
              ),
              if (onEditar != null)
                PopupMenuButton<String>(
                  tooltip: 'Opciones de la pregunta',
                  onSelected: (op) => switch (op) {
                    'editar' => onEditar?.call(),
                    'subir' => onSubir?.call(),
                    'bajar' => onBajar?.call(),
                    _ => onBorrar?.call(),
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'editar', child: Text('Editar')),
                    if (onSubir != null) const PopupMenuItem(value: 'subir', child: Text('Subir')),
                    if (onBajar != null) const PopupMenuItem(value: 'bajar', child: Text('Bajar')),
                    const PopupMenuItem(value: 'borrar', child: Text('Borrar')),
                  ],
                ),
            ]),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Text(p.enunciado, style: theme.textTheme.titleMedium),
            ),
            const SizedBox(height: 6),
            if (p.tipo.conOpciones)
              for (final (i, o) in p.opciones.indexed)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(children: [
                    Icon(p.correctas.contains(i) ? Icons.check_circle : Icons.circle_outlined,
                        size: 18, color: p.correctas.contains(i) ? scheme.primary : scheme.onSurfaceVariant),
                    const SizedBox(width: 8),
                    Expanded(child: Text(o)),
                  ]),
                ),
            if (p.tipo == TipoPregunta.corta)
              Text('Se acepta: ${p.aceptadas.join(' / ')}',
                  style: theme.textTheme.bodySmall?.copyWith(color: scheme.primary)),
            if (p.tipo == TipoPregunta.desarrollo)
              Text('La corregís vos', style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          ]),
        ),
      ),
    );
  }
}

// Diálogo de pregunta --------------------------------------------------------------------

Future<Pregunta?> pedirPregunta(BuildContext context, {Pregunta? inicial}) =>
    showDialog<Pregunta>(context: context, builder: (_) => _PreguntaDialog(inicial: inicial));

class _PreguntaDialog extends StatefulWidget {
  const _PreguntaDialog({this.inicial});
  final Pregunta? inicial;

  @override
  State<_PreguntaDialog> createState() => _PreguntaDialogState();
}

class _PreguntaDialogState extends State<_PreguntaDialog> {
  final _form = GlobalKey<FormState>();
  late TipoPregunta _tipo = widget.inicial?.tipo ?? TipoPregunta.opcion;
  late final _enunciado = TextEditingController(text: widget.inicial?.enunciado);
  late final _puntos = TextEditingController(text: formatearNota(widget.inicial?.puntos ?? 1));
  late final _aceptadas = TextEditingController(text: widget.inicial?.aceptadas.join('\n'));
  late final List<TextEditingController> _opciones = [
    for (final o in (widget.inicial?.opciones.isNotEmpty ?? false) ? widget.inicial!.opciones : ['', ''])
      TextEditingController(text: o),
  ];
  late Set<int> _correctas = {...?widget.inicial?.correctas};
  String? _errorOpciones;

  @override
  void dispose() {
    for (final c in [_enunciado, _puntos, _aceptadas, ..._opciones]) {
      c.dispose();
    }
    super.dispose();
  }

  void _verdaderoFalso() {
    for (final c in _opciones) {
      c.dispose();
    }
    setState(() {
      _tipo = TipoPregunta.opcion;
      _opciones
        ..clear()
        ..addAll([TextEditingController(text: 'Verdadero'), TextEditingController(text: 'Falso')]);
      _correctas = {};
    });
  }

  void _guardar() {
    final ok = _form.currentState!.validate();
    String? errorOpciones;
    if (_tipo.conOpciones) {
      if (_opciones.length < 2) {
        errorOpciones = 'Poné al menos 2 opciones';
      } else if (_correctas.isEmpty) {
        errorOpciones = _tipo == TipoPregunta.opcion ? 'Marcá la opción correcta' : 'Marcá al menos una correcta';
      }
    }
    setState(() => _errorOpciones = errorOpciones);
    if (!ok || errorOpciones != null) return;
    Navigator.pop(
      context,
      Pregunta(
        id: widget.inicial?.id,
        tipo: _tipo,
        enunciado: _enunciado.text.trim(),
        opciones: [for (final c in _opciones) c.text.trim()],
        correctas: (_correctas.toList()..sort()),
        aceptadas: [
          for (final l in _aceptadas.text.split('\n'))
            if (l.trim().isNotEmpty) l.trim(),
        ],
        puntos: leerNota(_puntos.text)!,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(widget.inicial == null ? 'Nueva pregunta' : 'Editar pregunta'),
      content: SizedBox(
        width: 560,
        child: Form(
          key: _form,
          autovalidateMode: validarAlCorregir,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(
                  child: DropdownButtonFormField<TipoPregunta>(
                    initialValue: _tipo,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Tipo'),
                    items: [for (final t in TipoPregunta.values) DropdownMenuItem(value: t, child: Text(t.texto))],
                    onChanged: (t) => setState(() {
                      _tipo = t ?? _tipo;
                      if (_tipo == TipoPregunta.opcion && _correctas.length > 1) _correctas = {_correctas.first};
                    }),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 110,
                  child: TextFormField(
                    controller: _puntos,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Puntos', hintText: 'Ej.: 2'),
                    validator: (v) {
                      final n = leerNota(v ?? '');
                      if (n == null) return 'Ingresá los puntos';
                      if (n <= 0 || n > 100) return 'De 0,5 a 100';
                      return null;
                    },
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              TextFormField(
                controller: _enunciado,
                autofocus: widget.inicial == null,
                minLines: 2,
                maxLines: 6,
                maxLength: 2000,
                decoration: const InputDecoration(
                  labelText: 'Pregunta',
                  hintText: 'Ej.: ¿De qué depende el período de un péndulo simple?',
                  alignLabelWithHint: true,
                ),
                validator: Validar.texto(vacio: 'Escribí la pregunta', max: 2000),
              ),
              if (_tipo.conOpciones) ...[
                Row(children: [
                  Expanded(
                    child: Text(
                      _tipo == TipoPregunta.opcion ? 'Opciones (marcá la correcta)' : 'Opciones (marcá todas las correctas)',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  TextButton(onPressed: _verdaderoFalso, child: const Text('Verdadero o falso')),
                ]),
                RadioGroup<int>(
                  groupValue: _correctas.firstOrNull,
                  onChanged: (v) => setState(() => _correctas = {?v}),
                  child: Column(children: [
                    for (final (i, c) in _opciones.indexed)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(children: [
                          if (_tipo == TipoPregunta.opcion)
                            Radio<int>(value: i)
                          else
                            Checkbox(
                              value: _correctas.contains(i),
                              onChanged: (v) => setState(() => v == true ? _correctas.add(i) : _correctas.remove(i)),
                            ),
                          Expanded(
                            child: TextFormField(
                              controller: c,
                              maxLength: 300,
                              decoration: InputDecoration(
                                hintText: 'Ej.: ${['Del largo del hilo', 'De la masa', 'De la amplitud', 'De g'][i % 4]}',
                                counterText: '',
                                isDense: true,
                              ),
                              validator: Validar.texto(vacio: 'Escribí la opción', max: 300),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Quitar opción',
                            icon: const Icon(Icons.close),
                            onPressed: _opciones.length <= 2
                                ? null
                                : () => setState(() {
                                      _opciones.removeAt(i).dispose();
                                      _correctas = {
                                        for (final x in _correctas)
                                          if (x != i) x > i ? x - 1 : x,
                                      };
                                    }),
                          ),
                        ]),
                      ),
                  ]),
                ),
                if (_errorOpciones != null)
                  Text(_errorOpciones!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
                if (_opciones.length < 10)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Agregar opción'),
                      onPressed: () => setState(() => _opciones.add(TextEditingController())),
                    ),
                  ),
              ],
              if (_tipo == TipoPregunta.corta)
                TextFormField(
                  controller: _aceptadas,
                  minLines: 2,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    labelText: 'Respuestas aceptadas (una por línea)',
                    hintText: 'Ej.: 9,8\n9,81',
                    helperText: 'No importan mayúsculas, tildes ni espacios de más; "2,5" y "2.50" valen igual.',
                    helperMaxLines: 2,
                    alignLabelWithHint: true,
                  ),
                  validator: (v) {
                    final ls = (v ?? '').split('\n').where((l) => l.trim().isNotEmpty).toList();
                    if (ls.isEmpty) return 'Escribí al menos una respuesta';
                    if (ls.length > 10) return 'Hasta 10 respuestas';
                    if (ls.any((l) => l.trim().length > 200)) return 'Cada una, hasta 200 caracteres';
                    return null;
                  },
                ),
              if (_tipo == TipoPregunta.desarrollo)
                Text('El alumno escribe un texto y vos le ponés el puntaje en Resultados.',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ]),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _guardar, child: const Text('Guardar')),
      ],
    );
  }
}

// Resultados ------------------------------------------------------------------------------

class _Resultados extends ConsumerStatefulWidget {
  const _Resultados({required this.cuestionario});
  final Cuestionario cuestionario;

  @override
  ConsumerState<_Resultados> createState() => _ResultadosState();
}

class _ResultadosState extends ConsumerState<_Resultados> {
  Timer? _refresco;

  @override
  void initState() {
    super.initState();
    // Mientras alguien rinde, se actualiza solo (salidas y entregas).
    _refresco = Timer.periodic(const Duration(seconds: 20), (_) {
      final lista = ref.read(resultadosProvider(widget.cuestionario.id)).value ?? const <ResultadoAlumno>[];
      if (lista.any((a) => a.intentos.any((i) => !i.entregado))) {
        ref.invalidate(resultadosProvider(widget.cuestionario.id));
      }
    });
  }

  @override
  void dispose() {
    _refresco?.cancel();
    super.dispose();
  }

  Future<void> _bajar(List<ResultadoAlumno> alumnos) async {
    final c = widget.cuestionario;
    try {
      await guardarEnDispositivo(
          Uint8List.fromList(utf8.encode(planillaDeResultados(c, alumnos))), nombreResultados(c.titulo), 'text/csv');
    } catch (_) {
      if (mounted) mostrarMensaje(context, 'No pudimos armar la planilla. Probá de nuevo', error: true);
    }
  }

  void _abrir(BuildContext context, ResultadoAlumno a) async {
    final c = widget.cuestionario;
    if (a.intentos.isEmpty) return;
    var elegido = a.intentos.length == 1 ? a.intentos.first : null;
    elegido ??= await showModalBottomSheet<Intento>(
      context: context,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(title: Text('Intentos de ${a.nombre}')),
          for (final i in a.intentos)
            ListTile(
              leading: CircleAvatar(child: Text('${i.numero}')),
              title: Text(i.entregado ? (i.pendiente ? 'Falta corregir' : textoNota(i, c)) : 'Rindiendo ahora'),
              subtitle: Text([estadoIntento(i), if (i.salidas > 0) textoSalidas(i.salidas)].join(' · ')),
              onTap: () => Navigator.pop(ctx, i),
            ),
        ]),
      ),
    );
    if (elegido != null && context.mounted) context.push(Routes.intentoDocente(c.cursoId, c.id, elegido.id));
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.cuestionario;
    final resultados = ref.watch(resultadosProvider(c.id));
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return switch (resultados) {
      AsyncValue(:final error?) => Aviso(
          icono: Icons.cloud_off_outlined,
          texto: error is CuestionariosFailure ? error.mensaje : 'Algo salió mal. Probá de nuevo',
          accion: FilledButton(onPressed: () => ref.invalidate(resultadosProvider(c.id)), child: const Text('Reintentar')),
        ),
      AsyncValue(value: final List<ResultadoAlumno> alumnos) => Builder(builder: (context) {
          final rindieron = alumnos.where((a) => a.intentos.any((i) => i.entregado)).toList();
          final ahora = alumnos.where((a) => a.intentos.any((i) => !i.entregado)).length;
          final notas = [
            for (final a in rindieron)
              if (a.principal case final i? when i.nota != null && !i.pendiente) i.nota!,
          ];
          final porCorregir = alumnos.where((a) => a.intentos.any((i) => i.pendiente)).length;
          final conSalidas = alumnos.where((a) => a.salidas > 0).length;
          return RefreshIndicator(
            onRefresh: () => ref.refresh(resultadosProvider(c.id).future),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 900),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Wrap(
                            spacing: 24,
                            runSpacing: 12,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              _Dato('Rindieron', '${rindieron.length} de ${alumnos.length}'),
                              if (ahora > 0) _Dato('Rindiendo ahora', '$ahora'),
                              _Dato('Promedio',
                                  notas.isEmpty ? '—' : formatearNota(notas.reduce((a, b) => a + b) / notas.length)),
                              _Dato('Por corregir', '$porCorregir'),
                              _Dato('Salieron de la pantalla', '$conSalidas'),
                              if (alumnos.isNotEmpty)
                                TextButton.icon(
                                  icon: const Icon(Icons.download_outlined, size: 18),
                                  label: const Text('Bajar resultados'),
                                  onPressed: () => _bajar(alumnos),
                                ),
                            ],
                          ),
                        ),
                      ),
                      if (alumnos.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('Todavía no hay alumnos en el curso.', textAlign: TextAlign.center),
                        ),
                      for (final a in alumnos)
                        Builder(builder: (context) {
                          final i = a.principal;
                          return Card(
                            margin: const EdgeInsets.only(top: 8),
                            child: ListTile(
                              title: Text(a.nombre),
                              subtitle: Text.rich(TextSpan(children: [
                                TextSpan(text: [
                                  if (a.grupo != null) a.grupo!,
                                  if (i == null) 'No lo hizo' else estadoIntento(i),
                                  if (a.intentos.length > 1) '${a.intentos.length} intentos',
                                ].join(' · ')),
                                if (a.salidas > 0)
                                  TextSpan(
                                    text: ' · ${textoSalidas(a.salidas)} (${formatearSegundos(a.segundosAfuera)} afuera)',
                                    style: TextStyle(color: scheme.tertiary, fontWeight: FontWeight.w600),
                                  ),
                                if (i != null && i.afuera)
                                  TextSpan(text: ' · ahora fuera de la pantalla', style: TextStyle(color: scheme.tertiary)),
                              ])),
                              trailing: i == null
                                  ? null
                                  : Text(
                                      !i.entregado
                                          ? 'Rindiendo'
                                          : i.pendiente
                                              ? 'Por corregir'
                                              : i.nota == null
                                                  ? '—'
                                                  : formatearNota(i.nota!),
                                      style: theme.textTheme.titleMedium?.copyWith(
                                          color: i.pendiente ? scheme.tertiary : null),
                                    ),
                              onTap: a.intentos.isEmpty ? null : () => _abrir(context, a),
                            ),
                          );
                        }),
                    ]),
                  ),
                ),
              ],
            ),
          );
        }),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }
}

class _Dato extends StatelessWidget {
  const _Dato(this.etiqueta, this.valor);
  final String etiqueta;
  final String valor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(valor, style: theme.textTheme.titleLarge),
      Text(etiqueta, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
    ]);
  }
}
