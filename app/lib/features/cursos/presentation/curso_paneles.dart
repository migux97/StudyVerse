import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/forms/validar.dart';
import '../../../core/router/app_router.dart';
import '../../../core/web/guardar_archivo.dart';
import '../../../core/widgets/avisos.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/text_input_dialog.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../entregas/domain/trabajo.dart';
import '../../entregas/presentation/entregas_providers.dart';
import '../../files/domain/file_item.dart' show fileKindFor, formatBytes, formatearFecha, nombreVisible;
import '../../files/presentation/file_icon.dart';
import '../../groups/presentation/group_shell.dart' show Aviso;
import '../domain/curso.dart';
import '../domain/exportar.dart';
import 'cursos_providers.dart';

void _error(BuildContext context, Object e) {
  if (!context.mounted) return;
  mostrarMensaje(
    context,
    switch (e) {
      CursosFailure(:final mensaje) => mensaje,
      EntregasFailure(:final mensaje) => mensaje,
      _ => 'Algo salió mal. Probá de nuevo',
    },
    error: true,
  );
}

// Tablero ---------------------------------------------------------------------------

/// Resumen arriba de los grupos: cuántos hay, cuántas entregas faltan corregir y
/// cuántos grupos están quietos.
class ResumenCurso extends ConsumerWidget {
  const ResumenCurso({super.key, required this.cursoId, required this.grupos, required this.soloInactivos, required this.onSoloInactivos});
  final String cursoId;
  final List<GrupoDelCurso> grupos;
  final bool soloInactivos;
  final ValueChanged<bool> onSoloInactivos;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ahora = DateTime.now();
    final entregas = ref.watch(entregasDelCursoProvider(cursoId)).value ?? const <Entrega>[];
    final porCorregir = entregas.where((e) => e.estado == EstadoEntrega.entregada).length;
    final inactivos = grupos.where((g) => g.inactivo(ahora)).length;
    final vencidas = grupos.fold<int>(0, (s, g) => s + g.tareasVencidas);

    Widget dato(IconData icono, String numero, String texto, {Color? color}) => Expanded(
          child: Card(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
              child: Column(children: [
                Icon(icono, color: color),
                const SizedBox(height: 4),
                Text(numero, style: Theme.of(context).textTheme.titleLarge?.copyWith(color: color)),
                Text(texto, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
              ]),
            ),
          ),
        );

    final scheme = Theme.of(context).colorScheme;
    final datos = [
      dato(Icons.groups_outlined, '${grupos.length}', grupos.length == 1 ? 'grupo' : 'grupos'),
      dato(Icons.rate_review_outlined, '$porCorregir', 'entregas por corregir',
          color: porCorregir > 0 ? scheme.primary : null),
      dato(Icons.bedtime_outlined, '$inactivos', 'sin actividad hace 7 días',
          color: inactivos > 0 ? scheme.tertiary : null),
      dato(Icons.event_busy_outlined, '$vencidas', 'tareas vencidas', color: vencidas > 0 ? scheme.error : null),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // En el celular, de a dos por fila.
      LayoutBuilder(
        builder: (_, c) => c.maxWidth >= 560
            ? Row(children: datos)
            : Column(children: [
                Row(children: datos.sublist(0, 2)),
                const SizedBox(height: 8),
                Row(children: datos.sublist(2)),
              ]),
      ),
      const SizedBox(height: 8),
      if (inactivos > 0)
        FilterChip(
          label: const Text('Ver solo los grupos sin actividad'),
          selected: soloInactivos,
          onSelected: onSoloInactivos,
        ),
    ]);
  }
}

/// "Hace 3 días" / "Sin actividad todavía".
String ultimaActividad(DateTime? d, DateTime ahora) =>
    d == null ? 'Sin actividad todavía' : 'Última actividad: ${formatearFecha(d, ahora)}';

// Alumnos y aportes -------------------------------------------------------------------

/// Pestaña "Alumnos": lo que aportó cada uno, y la planilla de notas para bajar.
class AlumnosDelCurso extends ConsumerWidget {
  const AlumnosDelCurso({super.key, required this.curso});
  final Curso curso;

  Future<void> _exportar(BuildContext context, WidgetRef ref) async {
    try {
      final repo = ref.read(entregasRepositoryProvider);
      final (alumnos, trabajos, entregas) = await (
        ref.read(cursosRepositoryProvider).aportes(curso.id),
        repo.trabajos(curso.id),
        repo.delCurso(curso.id),
      ).wait;
      final csv = planillaDeNotas(alumnos: alumnos, trabajos: trabajos, entregas: entregas);
      await guardarEnDispositivo(Uint8List.fromList(utf8.encode(csv)), nombrePlanilla(curso.nombre), 'text/csv');
    } on ParallelWaitError<dynamic, dynamic> {
      if (context.mounted) mostrarMensaje(context, 'No pudimos armar la planilla. Probá de nuevo', error: true);
    } catch (e) {
      if (context.mounted) _error(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aportes = ref.watch(aportesDelCursoProvider(curso.id));
    final theme = Theme.of(context);
    final ahora = DateTime.now();
    final exportar = FilledButton.tonalIcon(
      icon: const Icon(Icons.download_outlined),
      label: const Text('Bajar planilla de notas'),
      onPressed: () => _exportar(context, ref),
    );
    return switch (aportes) {
      AsyncValue(:final error?) => Aviso(
          icono: Icons.cloud_off_outlined,
          texto: error is CursosFailure ? error.mensaje : 'Algo salió mal. Probá de nuevo',
          accion: FilledButton(
              onPressed: () => ref.invalidate(aportesDelCursoProvider(curso.id)), child: const Text('Reintentar')),
        ),
      AsyncValue(value: final List<AporteAlumno> lista) when lista.isEmpty => const Aviso(
          icono: Icons.person_outline,
          texto: 'Todavía no hay alumnos',
          detalle: 'Cuando los grupos se sumen al curso, vas a ver lo que aporta cada integrante.',
        ),
      AsyncValue(value: final List<AporteAlumno> lista) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 8,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('${lista.length} alumnos · ${lista.where((a) => a.sinAportes).length} sin aportes',
                    style: theme.textTheme.titleSmall),
                exportar,
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'La planilla trae la nota de cada trabajo (la del grupo) y los aportes de cada alumno. Se abre con Excel.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            for (final grupo in {for (final a in lista) a.groupId: a.grupo}.entries) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
                child: Text(grupo.value, style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary)),
              ),
              for (final a in lista.where((a) => a.groupId == grupo.key))
                Card(
                  margin: const EdgeInsets.only(bottom: 6),
                  child: ListTile(
                    leading: CircleAvatar(child: Text(a.nombre.isEmpty ? '?' : a.nombre[0].toUpperCase())),
                    title: Text(a.nombre),
                    subtitle: Text([
                      '${a.tareasHechas} ${a.tareasHechas == 1 ? 'tarea hecha' : 'tareas hechas'}'
                          '${a.tareasPendientes > 0 ? ' (${a.tareasPendientes} pendientes)' : ''}',
                      '${a.versiones} ${a.versiones == 1 ? 'versión' : 'versiones'}',
                      '${a.comentarios} ${a.comentarios == 1 ? 'comentario' : 'comentarios'}',
                      ultimaActividad(a.ultimaActividad, ahora),
                    ].join(' · ')),
                    trailing: a.sinAportes
                        ? Tooltip(
                            message: 'Sin tareas, versiones ni comentarios',
                            child: Icon(Icons.warning_amber_rounded, color: theme.colorScheme.tertiary),
                          )
                        : null,
                  ),
                ),
            ],
          ],
        ),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }
}

// Material -----------------------------------------------------------------------------

/// Material del curso. El docente sube y borra; los alumnos lo bajan.
class ListaMaterial extends ConsumerStatefulWidget {
  const ListaMaterial({super.key, required this.cursoId, required this.esDocente});
  final String cursoId;
  final bool esDocente;

  @override
  ConsumerState<ListaMaterial> createState() => _ListaMaterialState();
}

class _ListaMaterialState extends ConsumerState<ListaMaterial> {
  bool _subiendo = false;

  Future<void> _subir() async {
    final List<PlatformFile> elegidos;
    try {
      elegidos = await FilePicker.pickFiles(dialogTitle: 'Elegí el material para el curso');
    } catch (_) {
      if (mounted) mostrarMensaje(context, 'No pudimos leer esos archivos', error: true);
      return;
    }
    if (elegidos.isEmpty || !mounted) return;
    final grandes = elegidos.where((f) => (f.lengthSync() ?? 0) > 50 * 1024 * 1024).toList();
    if (grandes.isNotEmpty) {
      return mostrarMensaje(context, '${grandes.first.name} pesa más de 50 MB', error: true);
    }
    setState(() => _subiendo = true);
    var subidos = 0;
    try {
      for (final f in elegidos) {
        final bytes = await f.readAsBytes();
        await ref.read(cursosRepositoryProvider).subirMaterial(widget.cursoId, nombre: f.name, bytes: bytes);
        subidos++;
      }
      if (mounted) {
        mostrarMensaje(context, subidos == 1 ? 'Subimos el material y les avisamos a los grupos' : 'Subimos $subidos archivos');
      }
    } catch (e) {
      if (mounted) _error(context, e);
    } finally {
      ref.invalidate(materialProvider(widget.cursoId));
      if (mounted) setState(() => _subiendo = false);
    }
  }

  Future<void> _bajar(MaterialCurso m) async {
    try {
      final bytes = await ref.read(cursosRepositoryProvider).bytesDelMaterial(m);
      await guardarEnDispositivo(Uint8List.fromList(bytes), m.nombre, m.mimeType ?? 'application/octet-stream');
    } catch (e) {
      if (mounted) _error(context, e);
    }
  }

  Future<void> _borrar(MaterialCurso m) async {
    final ok = await confirmar(context,
        titulo: '¿Borrar ${nombreVisible(m.nombre)}?',
        mensaje: 'Los grupos dejan de verlo.',
        accion: 'Borrar',
        peligroso: true);
    if (!ok || !mounted) return;
    try {
      await ref.read(cursosRepositoryProvider).borrarMaterial(m.id);
      ref.invalidate(materialProvider(widget.cursoId));
    } catch (e) {
      if (mounted) _error(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final material = ref.watch(materialProvider(widget.cursoId));
    final ahora = DateTime.now();
    final subir = FilledButton.icon(
      icon: _subiendo
          ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.upload_outlined),
      label: Text(_subiendo ? 'Subiendo…' : 'Subir material'),
      onPressed: _subiendo ? null : _subir,
    );
    return switch (material) {
      AsyncValue(:final error?) => Aviso(
          icono: Icons.cloud_off_outlined,
          texto: error is CursosFailure ? error.mensaje : 'Algo salió mal. Probá de nuevo',
          accion: FilledButton(
              onPressed: () => ref.invalidate(materialProvider(widget.cursoId)), child: const Text('Reintentar')),
        ),
      AsyncValue(value: final List<MaterialCurso> ms) when ms.isEmpty => Aviso(
          icono: Icons.folder_special_outlined,
          texto: 'Todavía no hay material',
          detalle: widget.esDocente
              ? 'Subí la consigna, plantillas o apuntes una sola vez: los ven todos los grupos del curso.'
              : 'Cuando tu docente suba consignas o apuntes, los vas a ver acá.',
          accion: widget.esDocente ? subir : null,
        ),
      AsyncValue(value: final List<MaterialCurso> ms) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            if (widget.esDocente) ...[Align(alignment: Alignment.centerRight, child: subir), const SizedBox(height: 8)],
            for (final m in ms)
              Card(
                margin: const EdgeInsets.only(bottom: 6),
                child: ListTile(
                  leading: FileIcon(kind: fileKindFor(m.nombre)),
                  title: Text(nombreVisible(m.nombre), overflow: TextOverflow.ellipsis),
                  subtitle: Text('${formatBytes(m.sizeBytes)} · ${formatearFecha(m.createdAt, ahora)}'),
                  onTap: () => _bajar(m),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(tooltip: 'Descargar', icon: const Icon(Icons.download_outlined), onPressed: () => _bajar(m)),
                    if (widget.esDocente)
                      IconButton(tooltip: 'Borrar', icon: const Icon(Icons.delete_outline), onPressed: () => _borrar(m)),
                  ]),
                ),
              ),
          ],
        ),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }
}

// Fechas -------------------------------------------------------------------------------

const _tipos = {'parcial': 'Parcial', 'entrega': 'Entrega', 'clase': 'Clase', 'otro': 'Otro'};

/// Pestaña "Fechas": parciales y clases que aparecen en el calendario de los alumnos.
class FechasDelCurso extends ConsumerWidget {
  const FechasDelCurso({super.key, required this.cursoId});
  final String cursoId;

  Future<void> _nueva(BuildContext context, WidgetRef ref) async {
    final d = await showDialog<_FechaNueva>(context: context, builder: (_) => const _FechaDialog());
    if (d == null || !context.mounted) return;
    try {
      await ref
          .read(cursosRepositoryProvider)
          .crearFecha(cursoId, titulo: d.titulo, tipo: d.tipo, fecha: d.fecha, hora: d.hora, nota: d.nota);
      ref.invalidate(fechasCursoProvider(cursoId));
      if (context.mounted) mostrarMensaje(context, 'Agregamos «${d.titulo}» al calendario del curso');
    } catch (e) {
      if (context.mounted) _error(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fechas = ref.watch(fechasCursoProvider(cursoId));
    final loc = MaterialLocalizations.of(context);
    final hoy = DateTime.now();
    final boton = FilledButton.icon(
      icon: const Icon(Icons.add),
      label: const Text('Agregar fecha'),
      onPressed: () => _nueva(context, ref),
    );
    return switch (fechas) {
      AsyncValue(:final error?) => Aviso(
          icono: Icons.cloud_off_outlined,
          texto: error is CursosFailure ? error.mensaje : 'Algo salió mal. Probá de nuevo',
          accion: FilledButton(onPressed: () => ref.invalidate(fechasCursoProvider(cursoId)), child: const Text('Reintentar')),
        ),
      AsyncValue(value: final List<FechaCurso> fs) when fs.isEmpty => Aviso(
          icono: Icons.event_outlined,
          texto: 'Todavía no hay fechas',
          detalle: 'Cargá parciales, clases especiales o entregas: aparecen en el calendario de todos los alumnos. '
              'Los vencimientos de los trabajos ya aparecen solos.',
          accion: boton,
        ),
      AsyncValue(value: final List<FechaCurso> fs) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            Align(alignment: Alignment.centerRight, child: boton),
            const SizedBox(height: 8),
            for (final f in fs)
              Opacity(
                opacity: f.fecha.isBefore(DateTime(hoy.year, hoy.month, hoy.day)) ? 0.6 : 1,
                child: Card(
                  margin: const EdgeInsets.only(bottom: 6),
                  child: ListTile(
                    leading: const Icon(Icons.event_outlined),
                    title: Text(f.titulo),
                    subtitle: Text([
                      _tipos[f.tipo] ?? f.tipo,
                      loc.formatMediumDate(f.fecha),
                      ?f.hora,
                      ?f.nota,
                    ].join(' · ')),
                    trailing: IconButton(
                      tooltip: 'Borrar',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        try {
                          await ref.read(cursosRepositoryProvider).borrarFecha(f.id);
                          ref.invalidate(fechasCursoProvider(cursoId));
                        } catch (e) {
                          if (context.mounted) _error(context, e);
                        }
                      },
                    ),
                  ),
                ),
              ),
          ],
        ),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }
}

typedef _FechaNueva = ({String titulo, String tipo, DateTime fecha, String? hora, String? nota});

class _FechaDialog extends StatefulWidget {
  const _FechaDialog();

  @override
  State<_FechaDialog> createState() => _FechaDialogState();
}

class _FechaDialogState extends State<_FechaDialog> {
  final _form = GlobalKey<FormState>();
  final _titulo = TextEditingController();
  final _nota = TextEditingController();
  String _tipo = 'parcial';
  DateTime? _fecha;
  TimeOfDay? _hora;
  bool _sinFecha = false;

  @override
  void dispose() {
    _titulo.dispose();
    _nota.dispose();
    super.dispose();
  }

  void _guardar() {
    final ok = _form.currentState!.validate();
    if (_fecha == null) setState(() => _sinFecha = true);
    if (!ok || _fecha == null) return;
    String dos(int n) => n.toString().padLeft(2, '0');
    Navigator.pop<_FechaNueva>(context, (
      titulo: _titulo.text.trim(),
      tipo: _tipo,
      fecha: _fecha!,
      hora: _hora == null ? null : '${dos(_hora!.hour)}:${dos(_hora!.minute)}',
      nota: _nota.text.trim().isEmpty ? null : _nota.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final loc = MaterialLocalizations.of(context);
    final hoy = DateTime.now();
    return AlertDialog(
      title: const Text('Nueva fecha del curso'),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _form,
          autovalidateMode: validarAlCorregir,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextFormField(
                controller: _titulo,
                autofocus: true,
                maxLength: 120,
                decoration: const InputDecoration(labelText: 'Qué es', hintText: 'Ej.: Primer parcial'),
                validator: Validar.texto(vacio: 'Ingresá qué es', max: 120),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _tipo,
                decoration: const InputDecoration(labelText: 'Tipo'),
                items: [for (final e in _tipos.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                onChanged: (v) => setState(() => _tipo = v ?? 'otro'),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: InputDecorator(
                    decoration: InputDecoration(labelText: 'Día', errorText: _sinFecha ? 'Elegí el día' : null),
                    child: InkWell(
                      onTap: () async {
                        final d = await showDatePicker(
                          context: context,
                          initialDate: _fecha ?? hoy,
                          firstDate: DateTime(hoy.year - 1),
                          lastDate: DateTime(hoy.year + 2),
                        );
                        if (d != null) setState(() => (_fecha = d, _sinFecha = false));
                      },
                      child: Text(_fecha == null ? 'Elegir día' : loc.formatMediumDate(_fecha!)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 130,
                  child: InputDecorator(
                    decoration: const InputDecoration(labelText: 'Hora (opcional)'),
                    child: InkWell(
                      onTap: () async {
                        final h = await showTimePicker(context: context, initialTime: _hora ?? const TimeOfDay(hour: 18, minute: 0));
                        if (h != null) setState(() => _hora = h);
                      },
                      child: Text(_hora?.format(context) ?? 'Sin hora'),
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nota,
                maxLength: 500,
                decoration: const InputDecoration(labelText: 'Nota (opcional)', hintText: 'Ej.: Aula 12 · entran unidades 1 a 3'),
                validator: Validar.opcional(500),
              ),
            ]),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _guardar, child: const Text('Agregar')),
      ],
    );
  }
}

// Docentes -------------------------------------------------------------------------------

/// Titular y ayudantes. El titular suma por @usuario; un ayudante puede irse.
Future<void> verDocentes(BuildContext context, {required Curso curso, required bool soyTitular}) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (_) => _Docentes(curso: curso, soyTitular: soyTitular),
    );

class _Docentes extends ConsumerWidget {
  const _Docentes({required this.curso, required this.soyTitular});
  final Curso curso;
  final bool soyTitular;

  Future<void> _sumar(BuildContext context, WidgetRef ref) async {
    final usuario = await pedirTexto(
      context,
      titulo: 'Sumar un docente',
      etiqueta: 'Usuario',
      ejemplo: 'Ej.: @mgarcia',
      ayuda: 'Tiene que tener una cuenta de docente. Va a ver los grupos, corregir y mandar avisos.',
      accion: 'Sumar',
      maximo: 40,
      validator: Validar.texto(vacio: 'Ingresá el usuario', max: 40),
    );
    if (usuario == null || !context.mounted) return;
    try {
      final d = await ref.read(cursosRepositoryProvider).sumarAyudante(curso.id, usuario);
      ref.invalidate(docentesDelCursoProvider(curso.id));
      if (context.mounted) mostrarMensaje(context, 'Sumamos a ${d.nombre} y le avisamos');
    } catch (e) {
      if (context.mounted) _error(context, e);
    }
  }

  Future<void> _quitar(BuildContext context, WidgetRef ref, DocenteDelCurso d, {required bool yo}) async {
    final ok = await confirmar(
      context,
      titulo: yo ? '¿Dejar el curso?' : '¿Quitar a ${d.nombre}?',
      mensaje: yo ? 'Vas a dejar de ver los grupos de ${curso.nombre}.' : 'Deja de ver los grupos de ${curso.nombre}.',
      accion: yo ? 'Dejar el curso' : 'Quitar',
      peligroso: true,
    );
    if (!ok || !context.mounted) return;
    try {
      await ref.read(cursosRepositoryProvider).quitarAyudante(curso.id, d.id);
      ref.invalidate(docentesDelCursoProvider(curso.id));
      if (yo && context.mounted) {
        ref.invalidate(misCursosProvider);
        Navigator.pop(context);
        context.go(Routes.grupos);
      }
    } catch (e) {
      if (context.mounted) _error(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final docentes = ref.watch(docentesDelCursoProvider(curso.id)).value ?? const <DocenteDelCurso>[];
    final miId = ref.watch(authStateProvider).value?.id;
    return SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          title: const Text('Docentes del curso'),
          subtitle: const Text('Los ayudantes ven los grupos, corrigen y mandan avisos'),
          trailing: soyTitular
              ? FilledButton.tonalIcon(
                  icon: const Icon(Icons.person_add_alt, size: 18),
                  label: const Text('Sumar'),
                  onPressed: () => _sumar(context, ref),
                )
              : null,
        ),
        for (final d in docentes)
          ListTile(
            leading: CircleAvatar(child: Text(d.nombre.isEmpty ? '?' : d.nombre[0].toUpperCase())),
            title: Text(d.nombre),
            subtitle: Text([if (d.username != null) '@${d.username}', d.titular ? 'Titular' : 'Ayudante'].join(' · ')),
            trailing: d.titular
                ? null
                : soyTitular
                    ? IconButton(
                        tooltip: 'Quitar',
                        icon: const Icon(Icons.person_remove_outlined),
                        onPressed: () => _quitar(context, ref, d, yo: false),
                      )
                    : d.id == miId
                        ? TextButton(onPressed: () => _quitar(context, ref, d, yo: true), child: const Text('Dejar el curso'))
                        : null,
          ),
        const SizedBox(height: 12),
      ]),
    );
  }
}
