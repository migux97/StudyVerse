import '../../../core/errors.dart';

class CalendarioFailure extends AppFailure {
  const CalendarioFailure(super.mensaje);
}

/// Qué es cada cosa del calendario.
enum TipoFecha {
  tarea('Tarea'),
  parcial('Parcial'),
  entrega('Entrega'),
  clase('Clase'),
  otro('Otro');

  const TipoFecha(this.texto);
  final String texto;

  /// Los que se pueden crear como evento (las tareas se crean en Tareas).
  static const deEvento = [parcial, entrega, clase, otro];
}

/// Una fecha del calendario: la fecha límite de una tarea o un evento del grupo.
class FechaCalendario {
  const FechaCalendario({
    required this.id,
    required this.tipo,
    required this.titulo,
    required this.dia,
    this.hora,
    required this.groupId,
    required this.grupo,
    this.nota,
    this.hecha = false,
    this.creadoPor,
  });

  final String id;
  final TipoFecha tipo;
  final String titulo;

  /// Solo la fecha (sin hora).
  final DateTime dia;

  /// "14:30", si tiene.
  final String? hora;
  final String groupId;
  final String grupo;
  final String? nota;

  /// Tarea ya hecha.
  final bool hecha;
  final String? creadoPor;

  bool get esTarea => tipo == TipoFecha.tarea;

  factory FechaCalendario.deTarea(Map<String, dynamic> m) => FechaCalendario(
        id: m['id'] as String,
        tipo: TipoFecha.tarea,
        titulo: m['titulo'] as String,
        dia: DateTime.parse(m['due_date'] as String),
        groupId: m['group_id'] as String,
        grupo: (m['grupo'] as Map<String, dynamic>?)?['nombre'] as String? ?? '',
        hecha: m['estado'] == 'hecha',
      );

  factory FechaCalendario.deEvento(Map<String, dynamic> m) => FechaCalendario(
        id: m['id'] as String,
        tipo: TipoFecha.values.byName(m['tipo'] as String),
        titulo: m['titulo'] as String,
        dia: DateTime.parse(m['fecha'] as String),
        hora: (m['hora'] as String?)?.substring(0, 5),
        groupId: m['group_id'] as String,
        grupo: (m['grupo'] as Map<String, dynamic>?)?['nombre'] as String? ?? '',
        nota: m['nota'] as String?,
        creadoPor: m['created_by'] as String?,
      );
}

DateTime soloDia(DateTime d) => DateTime(d.year, d.month, d.day);

/// Agrupa por día, ordenando cada día por hora (sin hora al final) y título.
Map<DateTime, List<FechaCalendario>> porDia(Iterable<FechaCalendario> fechas) {
  final m = <DateTime, List<FechaCalendario>>{};
  for (final f in fechas) {
    m.putIfAbsent(soloDia(f.dia), () => []).add(f);
  }
  for (final l in m.values) {
    l.sort((a, b) {
      final h = (a.hora ?? '99').compareTo(b.hora ?? '99');
      return h != 0 ? h : a.titulo.toLowerCase().compareTo(b.titulo.toLowerCase());
    });
  }
  return m;
}

/// Lo que viene en los próximos [dias] días (sin tareas hechas), en orden.
List<FechaCalendario> proximas(Iterable<FechaCalendario> fechas, DateTime hoy, {int dias = 7}) {
  final desde = soloDia(hoy);
  final hasta = desde.add(Duration(days: dias));
  final l = fechas.where((f) => !f.hecha && !f.dia.isBefore(desde) && f.dia.isBefore(hasta)).toList()
    ..sort((a, b) {
      final d = a.dia.compareTo(b.dia);
      return d != 0 ? d : (a.hora ?? '99').compareTo(b.hora ?? '99');
    });
  return l;
}

/// "Hoy", "Mañana", "Jueves 14", "14 nov".
String cuandoEs(DateTime dia, DateTime hoy) {
  final d = soloDia(dia).difference(soloDia(hoy)).inDays;
  if (d == 0) return 'Hoy';
  if (d == 1) return 'Mañana';
  if (d > 1 && d < 7) return '${diasSemana[dia.weekday - 1]} ${dia.day}';
  return '${dia.day} ${mesesCortos[dia.month - 1]}';
}

const diasSemana = ['Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado', 'Domingo'];
const meses = [
  'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
  'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
];
const mesesCortos = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];

/// Días que se muestran en la grilla de un mes: de lunes a domingo, completando
/// con días del mes anterior y siguiente.
List<DateTime> diasDeLaGrilla(DateTime mes) {
  final primero = DateTime(mes.year, mes.month);
  final inicio = primero.subtract(Duration(days: primero.weekday - 1));
  final ultimo = DateTime(mes.year, mes.month + 1, 0);
  final fin = ultimo.add(Duration(days: 7 - ultimo.weekday));
  final n = fin.difference(inicio).inDays + 1;
  return [for (var i = 0; i < n; i++) DateTime(inicio.year, inicio.month, inicio.day + i)];
}

/// Datos de un evento nuevo.
class EventoNuevo {
  const EventoNuevo({
    required this.groupId,
    required this.titulo,
    required this.tipo,
    required this.dia,
    this.hora,
    this.nota,
  });
  final String groupId;
  final String titulo;
  final TipoFecha tipo;
  final DateTime dia;
  final String? hora;
  final String? nota;
}

abstract interface class CalendarioRepository {
  /// Tareas con fecha y eventos de todos mis grupos entre [desde] y [hasta].
  Future<List<FechaCalendario>> fechas(DateTime desde, DateTime hasta);
  Future<void> crearEvento(EventoNuevo e);
  Future<void> borrarEvento(String id);
}
