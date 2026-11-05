import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/forms/validar.dart';
import '../../../core/router/app_router.dart';
import '../../../core/widgets/auth_layout.dart';
import '../../../core/widgets/pagina.dart';
import '../../groups/presentation/groups_providers.dart';
import '../domain/calendario.dart';
import 'calendario_providers.dart';

/// Color de cada tipo de fecha (del tema, para que se vea bien en claro y oscuro).
Color colorDe(TipoFecha t, ColorScheme s) => switch (t) {
      TipoFecha.tarea => s.primary,
      TipoFecha.parcial => s.error,
      TipoFecha.entrega => s.tertiary,
      TipoFecha.clase => s.secondary,
      TipoFecha.otro => s.outline,
    };

IconData iconoDe(TipoFecha t) => switch (t) {
      TipoFecha.tarea => Icons.task_alt_rounded,
      TipoFecha.parcial => Icons.edit_note_rounded,
      TipoFecha.entrega => Icons.outbox_rounded,
      TipoFecha.clase => Icons.school_outlined,
      TipoFecha.otro => Icons.event_outlined,
    };

/// Entregas, parciales y fechas límite de todos tus grupos.
class CalendarioScreen extends ConsumerStatefulWidget {
  const CalendarioScreen({super.key});

  @override
  ConsumerState<CalendarioScreen> createState() => _CalendarioScreenState();
}

class _CalendarioScreenState extends ConsumerState<CalendarioScreen> {
  var _mes = DateTime(DateTime.now().year, DateTime.now().month);
  var _dia = soloDia(DateTime.now());

  void _cambiarMes(int delta) => setState(() => _mes = DateTime(_mes.year, _mes.month + delta));

  void _hoy() => setState(() {
        final hoy = DateTime.now();
        _mes = DateTime(hoy.year, hoy.month);
        _dia = soloDia(hoy);
      });

  @override
  Widget build(BuildContext context) {
    final fechas = ref.watch(fechasDelMesProvider(_mes));
    final mapa = porDia(fechas.value ?? const []);
    final ancho = MediaQuery.sizeOf(context).width >= 900;

    final grilla = _Grilla(
      mes: _mes,
      seleccionado: _dia,
      porDia: mapa,
      cargando: fechas.isLoading && !fechas.hasValue,
      alElegir: (d) => setState(() {
        _dia = d;
        if (d.month != _mes.month) _mes = DateTime(d.year, d.month);
      }),
      alCambiarMes: _cambiarMes,
      alIrAHoy: _hoy,
    );
    final lista = _ListaDelDia(dia: _dia, fechas: mapa[_dia] ?? const [], error: fechas.hasError);

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.canPop() ? context.pop() : context.go(Routes.grupos)),
        title: const Text('Calendario'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Nuevo evento'),
        onPressed: () => _nuevoEvento(context),
      ),
      body: ancho
          ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: SingleChildScrollView(padding: const EdgeInsets.all(16), child: grilla)),
              const VerticalDivider(width: 1),
              SizedBox(width: 380, child: lista),
            ])
          : Column(children: [
              Padding(padding: const EdgeInsets.fromLTRB(8, 0, 8, 8), child: grilla),
              const Divider(height: 1),
              Expanded(child: lista),
            ]),
    );
  }

  Future<void> _nuevoEvento(BuildContext context) async {
    final evento = await showDialog<EventoNuevo>(context: context, builder: (_) => _EventoDialog(dia: _dia));
    if (evento == null || !context.mounted) return;
    try {
      await ref.read(calendarioRepositoryProvider).crearEvento(evento);
      if (!mounted) return;
      ref.invalidate(fechasDelMesProvider);
      ref.invalidate(proximasFechasProvider);
      if (!context.mounted) return;
      setState(() {
        _dia = soloDia(evento.dia);
        _mes = DateTime(evento.dia.year, evento.dia.month);
      });
      mostrarMensaje(context, 'Agregamos «${evento.titulo}» al calendario');
    } on CalendarioFailure catch (e) {
      if (context.mounted) mostrarMensaje(context, e.mensaje, error: true);
    }
  }
}

class _Grilla extends StatelessWidget {
  const _Grilla({
    required this.mes,
    required this.seleccionado,
    required this.porDia,
    required this.cargando,
    required this.alElegir,
    required this.alCambiarMes,
    required this.alIrAHoy,
  });

  final DateTime mes;
  final DateTime seleccionado;
  final Map<DateTime, List<FechaCalendario>> porDia;
  final bool cargando;
  final ValueChanged<DateTime> alElegir;
  final ValueChanged<int> alCambiarMes;
  final VoidCallback alIrAHoy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hoy = soloDia(DateTime.now());
    final dias = diasDeLaGrilla(mes);
    final titulo = '${meses[mes.month - 1][0].toUpperCase()}${meses[mes.month - 1].substring(1)} ${mes.year}';

    return Column(mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        Expanded(child: Text(titulo, style: theme.textTheme.titleLarge, maxLines: 1, overflow: TextOverflow.ellipsis)),
        if (cargando) const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)),
        TextButton(onPressed: alIrAHoy, child: const Text('Hoy')),
        IconButton(tooltip: 'Mes anterior', icon: const Icon(Icons.chevron_left), onPressed: () => alCambiarMes(-1)),
        IconButton(tooltip: 'Mes siguiente', icon: const Icon(Icons.chevron_right), onPressed: () => alCambiarMes(1)),
      ]),
      const SizedBox(height: 4),
      Row(children: [
        for (final d in const ['L', 'M', 'M', 'J', 'V', 'S', 'D'])
          Expanded(
            child: Center(
              child: Text(d, style: theme.textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant)),
            ),
          ),
      ]),
      const SizedBox(height: 4),
      GridView.count(
        crossAxisCount: 7,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        childAspectRatio: MediaQuery.sizeOf(context).width >= 900 ? 1.4 : 1,
        children: [
          for (final d in dias)
            _Celda(
              dia: d,
              delMes: d.month == mes.month,
              esHoy: d == hoy,
              elegido: d == seleccionado,
              fechas: porDia[d] ?? const [],
              alTocar: () => alElegir(d),
            ),
        ],
      ),
    ]);
  }
}

class _Celda extends StatelessWidget {
  const _Celda({
    required this.dia,
    required this.delMes,
    required this.esHoy,
    required this.elegido,
    required this.fechas,
    required this.alTocar,
  });

  final DateTime dia;
  final bool delMes;
  final bool esHoy;
  final bool elegido;
  final List<FechaCalendario> fechas;
  final VoidCallback alTocar;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final numero = Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: elegido ? scheme.primary : (esHoy ? scheme.primaryContainer : null),
      ),
      child: Text(
        '${dia.day}',
        style: TextStyle(
          fontWeight: esHoy || elegido ? FontWeight.w600 : null,
          color: elegido
              ? scheme.onPrimary
              : delMes
                  ? scheme.onSurface
                  : scheme.onSurfaceVariant.withValues(alpha: 0.5),
        ),
      ),
    );
    return Semantics(
      button: true,
      label: '${dia.day} de ${meses[dia.month - 1]}'
          '${fechas.isEmpty ? '' : fechas.length == 1 ? ', 1 fecha' : ', ${fechas.length} fechas'}',
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: alTocar,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          numero,
          const SizedBox(height: 3),
          SizedBox(
            height: 6,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              for (final f in fechas.take(3))
                Container(
                  width: 6,
                  height: 6,
                  margin: const EdgeInsets.symmetric(horizontal: 1.5),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: f.hecha ? scheme.outlineVariant : colorDe(f.tipo, scheme),
                  ),
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _ListaDelDia extends ConsumerWidget {
  const _ListaDelDia({required this.dia, required this.fechas, required this.error});
  final DateTime dia;
  final List<FechaCalendario> fechas;
  final bool error;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final hoy = DateTime.now();
    final titulo = '${diasSemana[dia.weekday - 1]} ${dia.day} de ${meses[dia.month - 1]}';
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        Text(cuandoEs(dia, hoy) == 'Hoy' ? 'Hoy · $titulo' : titulo, style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        if (error)
          const SinVista(motivo: 'No pudimos cargar el calendario. Revisá tu conexión.')
        else if (fechas.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text('Nada para este día.', style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
          )
        else
          for (final f in fechas) _FilaFecha(fecha: f),
      ],
    );
  }
}

class _FilaFecha extends ConsumerWidget {
  const _FilaFecha({required this.fecha});
  final FechaCalendario fecha;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final f = fecha;
    final detalle = [
      if (!f.esTarea) f.tipo.texto,
      f.grupo,
      if (f.hora != null) f.hora!,
      if (f.esTarea) f.hecha ? 'Hecha' : 'Fecha límite',
      if (f.nota != null) f.nota!,
    ].join(' · ');
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: colorDe(f.tipo, scheme).withValues(alpha: 0.15),
          child: Icon(iconoDe(f.tipo), color: colorDe(f.tipo, scheme)),
        ),
        title: Text(
          f.titulo,
          style: f.hecha ? const TextStyle(decoration: TextDecoration.lineThrough) : null,
        ),
        subtitle: Text(detalle, maxLines: 2, overflow: TextOverflow.ellipsis),
        onTap: f.esTarea ? () => context.push(Routes.tareas(f.groupId)) : null,
        trailing: f.esTarea
            ? const Icon(Icons.chevron_right)
            : IconButton(
                tooltip: 'Borrar evento',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _borrar(context, ref),
              ),
      ),
    );
  }

  Future<void> _borrar(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(calendarioRepositoryProvider).borrarEvento(fecha.id);
      ref.invalidate(fechasDelMesProvider);
      ref.invalidate(proximasFechasProvider);
      if (context.mounted) mostrarMensaje(context, 'Borramos «${fecha.titulo}»');
    } on CalendarioFailure catch (e) {
      if (context.mounted) mostrarMensaje(context, e.mensaje, error: true);
    }
  }
}

class _EventoDialog extends ConsumerStatefulWidget {
  const _EventoDialog({required this.dia});
  final DateTime dia;

  @override
  ConsumerState<_EventoDialog> createState() => _EventoDialogState();
}

class _EventoDialogState extends ConsumerState<_EventoDialog> {
  final _formKey = GlobalKey<FormState>();
  final _titulo = TextEditingController();
  final _nota = TextEditingController();
  String? _grupo;
  var _tipo = TipoFecha.parcial;
  late var _dia = widget.dia;
  TimeOfDay? _hora;

  @override
  void dispose() {
    _titulo.dispose();
    _nota.dispose();
    super.dispose();
  }

  void _guardar() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      EventoNuevo(
        groupId: _grupo!,
        titulo: _titulo.text,
        tipo: _tipo,
        dia: _dia,
        hora: _hora == null
            ? null
            : '${_hora!.hour.toString().padLeft(2, '0')}:${_hora!.minute.toString().padLeft(2, '0')}',
        nota: _nota.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final grupos = ref.watch(myGroupsProvider).value ?? const [];
    _grupo ??= grupos.length == 1 ? grupos.first.id : null;
    final hoy = DateTime.now();
    return AlertDialog(
      title: const Text('Nuevo evento'),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              DropdownButtonFormField<String>(
                initialValue: _grupo,
                decoration: const InputDecoration(labelText: 'Grupo'),
                items: [for (final g in grupos) DropdownMenuItem(value: g.id, child: Text(g.nombre))],
                onChanged: (v) => setState(() => _grupo = v),
                validator: (v) => v == null ? 'Elegí el grupo' : null,
              ),
              const SizedBox(height: 16),
              SegmentedButton<TipoFecha>(
                showSelectedIcon: false,
                segments: [for (final t in TipoFecha.deEvento) ButtonSegment(value: t, label: Text(t.texto))],
                selected: {_tipo},
                onSelectionChanged: (s) => setState(() => _tipo = s.single),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _titulo,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Qué es', hintText: 'Ej.: Primer parcial'),
                textCapitalization: TextCapitalization.sentences,
                inputFormatters: [LengthLimitingTextInputFormatter(120)],
                autovalidateMode: validarAlCorregir,
                validator: Validar.texto(vacio: 'Ingresá un nombre, como Primer parcial', max: 120),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.calendar_today_outlined, size: 18),
                    label: Text(cuandoEs(_dia, hoy)),
                    onPressed: () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate: _dia,
                        firstDate: DateTime(hoy.year - 1),
                        lastDate: DateTime(hoy.year + 3),
                      );
                      if (d != null) setState(() => _dia = d);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.schedule, size: 18),
                    label: Text(_hora == null ? 'Sin hora' : _hora!.format(context)),
                    onPressed: () async {
                      final h = await showTimePicker(context: context, initialTime: _hora ?? const TimeOfDay(hour: 9, minute: 0));
                      if (h != null) setState(() => _hora = h);
                    },
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nota,
                decoration: const InputDecoration(labelText: 'Nota (opcional)', hintText: 'Ej.: Aula 204 · temas 1 a 4'),
                maxLength: 500,
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
