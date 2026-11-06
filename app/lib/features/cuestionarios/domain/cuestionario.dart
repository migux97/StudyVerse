import 'dart:math';

import '../../../core/errors.dart';
import '../../entregas/domain/trabajo.dart' show formatearNota;

class CuestionariosFailure extends AppFailure {
  const CuestionariosFailure(super.mensaje);
}

/// Abrir el cuestionario en otra pestaña o dispositivo deja sin efecto esta.
class OtraSesionFailure extends CuestionariosFailure {
  const OtraSesionFailure(super.mensaje);
}

enum TipoPregunta {
  opcion('Opción única', 'opcion'),
  varias('Varias correctas', 'varias'),
  corta('Respuesta corta', 'corta'),
  desarrollo('Desarrollo', 'desarrollo');

  const TipoPregunta(this.texto, this.db);
  final String texto;
  final String db;

  static TipoPregunta desde(String v) => values.where((t) => t.db == v).firstOrNull ?? desarrollo;

  bool get conOpciones => this == opcion || this == varias;

  /// Las de desarrollo las corrige el docente.
  bool get automatica => this != desarrollo;
}

enum EstadoCuestionario {
  borrador('Sin publicar'),
  programado('Programado'),
  abierto('Abierto'),
  cerrado('Cerrado');

  const EstadoCuestionario(this.texto);
  final String texto;
}

class Cuestionario {
  const Cuestionario({
    required this.id,
    required this.cursoId,
    required this.titulo,
    this.descripcion,
    required this.abreAt,
    required this.cierraAt,
    this.duracionMin,
    required this.intentos,
    required this.resultadosAlCerrar,
    required this.mezclar,
    this.topeSalidas,
    required this.notaMaxima,
    this.publicadoAt,
  });

  final String id;
  final String cursoId;
  final String titulo;
  final String? descripcion;
  final DateTime abreAt;
  final DateTime cierraAt;

  /// Minutos para rendir desde que se empieza (null: hasta que cierra).
  final int? duracionMin;
  final int intentos;

  /// El alumno ve la nota y las correctas recién cuando cierra.
  final bool resultadosAlCerrar;
  final bool mezclar;

  /// Salidas permitidas: con una más se entrega solo (null: sin tope).
  final int? topeSalidas;
  final num notaMaxima;
  final DateTime? publicadoAt;

  bool get publicado => publicadoAt != null;

  EstadoCuestionario estado(DateTime ahora) {
    if (!publicado) return EstadoCuestionario.borrador;
    if (ahora.isBefore(abreAt)) return EstadoCuestionario.programado;
    if (!ahora.isBefore(cierraAt)) return EstadoCuestionario.cerrado;
    return EstadoCuestionario.abierto;
  }

  factory Cuestionario.fromMap(Map<String, dynamic> m) => Cuestionario(
        id: m['id'] as String,
        cursoId: m['curso_id'] as String,
        titulo: m['titulo'] as String,
        descripcion: m['descripcion'] as String?,
        abreAt: DateTime.parse(m['abre_at'] as String),
        cierraAt: DateTime.parse(m['cierra_at'] as String),
        duracionMin: (m['duracion_min'] as num?)?.toInt(),
        intentos: (m['intentos'] as num).toInt(),
        resultadosAlCerrar: m['resultados'] == 'al_cerrar',
        mezclar: m['mezclar'] as bool? ?? false,
        topeSalidas: (m['tope_salidas'] as num?)?.toInt(),
        notaMaxima: m['nota_maxima'] as num,
        publicadoAt: m['publicado_at'] == null ? null : DateTime.parse(m['publicado_at'] as String),
      );
}

/// Lo que carga el docente en el diálogo de ajustes.
typedef DatosCuestionario = ({
  String titulo,
  String? descripcion,
  DateTime abreAt,
  DateTime cierraAt,
  int? duracionMin,
  int intentos,
  bool resultadosAlCerrar,
  bool mezclar,
  int? topeSalidas,
  num notaMaxima,
});

class Pregunta {
  const Pregunta({
    this.id,
    required this.tipo,
    required this.enunciado,
    this.opciones = const [],
    this.correctas = const [],
    this.aceptadas = const [],
    this.puntos = 1,
  });

  final String? id;
  final TipoPregunta tipo;
  final String enunciado;
  final List<String> opciones;

  /// Índices de las opciones correctas (solo los ve el docente).
  final List<int> correctas;

  /// Respuestas aceptadas de una pregunta corta (solo las ve el docente).
  final List<String> aceptadas;
  final num puntos;

  factory Pregunta.fromMap(Map<String, dynamic> m) {
    final tipo = TipoPregunta.desde(m['tipo'] as String);
    final c = m['correctas'] as List<dynamic>?;
    return Pregunta(
      id: m['id'] as String?,
      tipo: tipo,
      enunciado: m['enunciado'] as String,
      opciones: [for (final o in (m['opciones'] as List<dynamic>? ?? const [])) o as String],
      correctas: tipo.conOpciones && c != null ? [for (final x in c) (x as num).toInt()] : const [],
      aceptadas: tipo == TipoPregunta.corta && c != null ? [for (final x in c) x as String] : const [],
      puntos: m['puntos'] as num? ?? 1,
    );
  }

  Map<String, dynamic> toMap() => {
        'tipo': tipo.db,
        'enunciado': enunciado,
        'opciones': tipo.conOpciones ? opciones : const <String>[],
        'correctas': switch (tipo) {
          TipoPregunta.opcion || TipoPregunta.varias => correctas,
          TipoPregunta.corta => aceptadas,
          TipoPregunta.desarrollo => null,
        },
        'puntos': puntos,
      };
}

/// Un intento de un alumno. La nota viene solo cuando ya se puede ver ([visible]).
class Intento {
  const Intento({
    required this.id,
    required this.cuestionarioId,
    required this.userId,
    required this.numero,
    required this.empezadoAt,
    required this.venceAt,
    this.entregadoAt,
    this.entregaAuto,
    required this.salidas,
    required this.segundosAfuera,
    required this.afuera,
    required this.visible,
    this.puntaje,
    this.puntajeMax,
    this.pendiente = false,
    this.nota,
  });

  final String id;
  final String cuestionarioId;
  final String userId;
  final int numero;
  final DateTime empezadoAt;
  final DateTime venceAt;
  final DateTime? entregadoAt;

  /// null: lo entregó el alumno; 'tiempo' o 'salidas': se entregó solo.
  final String? entregaAuto;
  final int salidas;
  final int segundosAfuera;

  /// Ahora mismo está fuera de la pantalla.
  final bool afuera;
  final bool visible;
  final num? puntaje;
  final num? puntajeMax;

  /// Quedan preguntas de desarrollo sin corregir.
  final bool pendiente;
  final num? nota;

  bool get entregado => entregadoAt != null;

  factory Intento.fromMap(Map<String, dynamic> m) => Intento(
        id: m['id'] as String,
        cuestionarioId: m['cuestionario_id'] as String,
        userId: m['user_id'] as String,
        numero: (m['numero'] as num).toInt(),
        empezadoAt: DateTime.parse(m['empezado_at'] as String),
        venceAt: DateTime.parse(m['vence_at'] as String),
        entregadoAt: m['entregado_at'] == null ? null : DateTime.parse(m['entregado_at'] as String),
        entregaAuto: m['entrega_auto'] as String?,
        salidas: (m['salidas'] as num?)?.toInt() ?? 0,
        segundosAfuera: (m['segundos_afuera'] as num?)?.toInt() ?? 0,
        afuera: m['afuera'] as bool? ?? false,
        visible: m['visible'] as bool? ?? false,
        puntaje: m['puntaje'] as num?,
        puntajeMax: m['puntaje_max'] as num?,
        pendiente: m['pendiente'] as bool? ?? false,
        nota: m['nota'] as num?,
      );
}

/// Lo que necesita la pantalla para rendir.
class IntentoAbierto {
  const IntentoAbierto({
    required this.desfase,
    required this.cuestionario,
    required this.intento,
    required this.preguntas,
    required this.respuestas,
  });

  /// Hora del servidor menos la del dispositivo (para que el reloj no dependa
  /// de la hora del celular).
  final Duration desfase;
  final Cuestionario cuestionario;
  final Intento intento;
  final List<Pregunta> preguntas;

  /// Respuesta guardada por id de pregunta: `List<int>` (opciones) o `String`.
  final Map<String, Object> respuestas;

  factory IntentoAbierto.fromMap(Map<String, dynamic> m, {DateTime? ahoraLocal}) => IntentoAbierto(
        desfase: DateTime.parse(m['ahora'] as String).difference(ahoraLocal ?? DateTime.now()),
        cuestionario: Cuestionario.fromMap(m['cuestionario'] as Map<String, dynamic>),
        intento: Intento.fromMap(m['intento'] as Map<String, dynamic>),
        preguntas: [for (final p in m['preguntas'] as List<dynamic>) Pregunta.fromMap(p as Map<String, dynamic>)],
        respuestas: {
          for (final e in (m['respuestas'] as Map<String, dynamic>).entries)
            e.key: ?leerValor(e.value),
        },
      );
}

/// jsonb de una respuesta → `List<int>` (opciones) o `String`.
Object? leerValor(Object? v) => switch (v) {
      final List<dynamic> l => [for (final x in l) (x as num).toInt()],
      final String s => s,
      _ => null,
    };

class PreguntaRespondida {
  const PreguntaRespondida({required this.pregunta, this.valor, this.puntaje, this.comentario});
  final Pregunta pregunta;
  final Object? valor;
  final num? puntaje;
  final String? comentario;

  bool get respondida => switch (valor) {
        final List<int> l => l.isNotEmpty,
        final String s => s.trim().isNotEmpty,
        _ => false,
      };

  /// De desarrollo, respondida y sin puntaje todavía.
  bool get porCorregir => pregunta.tipo == TipoPregunta.desarrollo && respondida && puntaje == null;
}

class EventoIntento {
  const EventoIntento({required this.tipo, this.segundos, this.detalle, required this.at});
  final String tipo;
  final int? segundos;
  final String? detalle;
  final DateTime at;

  factory EventoIntento.fromMap(Map<String, dynamic> m) => EventoIntento(
        tipo: m['tipo'] as String,
        segundos: (m['segundos'] as num?)?.toInt(),
        detalle: m['detalle'] as String?,
        at: DateTime.parse(m['at'] as String),
      );

  /// "Salió de la pantalla", "Volvió (estuvo 1 min 5 s afuera)"…
  String get texto => switch (tipo) {
        'empezo' => 'Empezó',
        'salio' => 'Salió de la pantalla',
        'volvio' => segundos == null ? 'Volvió' : 'Volvió (estuvo ${formatearSegundos(segundos!)} afuera)',
        'reabrio' => segundos == null
            ? 'Lo volvió a abrir (recargó, cerró la app u otra pestaña)'
            : 'Lo volvió a abrir después de ${formatearSegundos(segundos!)}',
        'entrego' => switch (detalle) {
            'tiempo' => 'Se entregó solo: se terminó el tiempo',
            'salidas' => 'Se entregó solo: salió más veces de las permitidas',
            _ => 'Entregó',
          },
        _ => tipo,
      };

  bool get esSalida => tipo == 'salio' || tipo == 'reabrio';
}

class DetalleIntento {
  const DetalleIntento({
    required this.cuestionario,
    required this.intento,
    this.alumno,
    this.grupo,
    required this.preguntas,
    required this.eventos,
    this.detalleVisible = false,
  });

  final Cuestionario cuestionario;
  final Intento intento;
  final String? alumno;
  final String? grupo;
  final List<PreguntaRespondida> preguntas;
  final List<EventoIntento> eventos;

  /// Se ven las respuestas correctas y el puntaje de cada pregunta (cuando ya
  /// no puede volver a rendir, o para el docente).
  final bool detalleVisible;

  factory DetalleIntento.fromMap(Map<String, dynamic> m) => DetalleIntento(
        cuestionario: Cuestionario.fromMap(m['cuestionario'] as Map<String, dynamic>),
        intento: Intento.fromMap(m['intento'] as Map<String, dynamic>),
        alumno: m['alumno'] as String?,
        grupo: m['grupo'] as String?,
        preguntas: [
          for (final p in (m['preguntas'] as List<dynamic>).cast<Map<String, dynamic>>())
            PreguntaRespondida(
              pregunta: Pregunta.fromMap(p),
              valor: leerValor(p['valor']),
              puntaje: p['puntaje'] as num?,
              comentario: p['comentario'] as String?,
            ),
        ],
        eventos: [for (final e in m['eventos'] as List<dynamic>) EventoIntento.fromMap(e as Map<String, dynamic>)],
        detalleVisible: m['detalle_visible'] as bool? ?? false,
      );
}

/// Un alumno del curso con sus intentos (resultados del docente).
class ResultadoAlumno {
  const ResultadoAlumno({required this.userId, required this.nombre, this.grupo, required this.intentos});
  final String userId;
  final String nombre;
  final String? grupo;
  final List<Intento> intentos;

  /// El que cuenta: el de mejor nota entre los entregados (o el último).
  Intento? get principal {
    final entregados = intentos.where((i) => i.entregado).toList();
    if (entregados.isEmpty) return intentos.lastOrNull;
    entregados.sort((a, b) => (b.nota ?? -1).compareTo(a.nota ?? -1));
    return entregados.first;
  }

  int get salidas => intentos.fold(0, (s, i) => s + i.salidas);
  int get segundosAfuera => intentos.fold(0, (s, i) => s + i.segundosAfuera);

  factory ResultadoAlumno.fromMap(Map<String, dynamic> m) => ResultadoAlumno(
        userId: m['user_id'] as String,
        nombre: m['nombre'] as String? ?? 'Alguien',
        grupo: m['grupo'] as String?,
        intentos: [for (final i in m['intentos'] as List<dynamic>) Intento.fromMap(i as Map<String, dynamic>)],
      );
}

/// "45 s", "3 min", "1 min 20 s", "1 h 5 min".
String formatearSegundos(int s) {
  if (s < 60) return '$s s';
  if (s < 3600) {
    final m = s ~/ 60, r = s % 60;
    return r == 0 ? '$m min' : '$m min $r s';
  }
  final h = s ~/ 3600, m = (s % 3600) ~/ 60;
  return m == 0 ? '$h h' : '$h h $m min';
}

/// Reloj de cuenta regresiva: "12:05" o "1:02:05".
String textoReloj(Duration d) {
  if (d.isNegative) d = Duration.zero;
  String dos(int n) => n.toString().padLeft(2, '0');
  final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
  return h > 0 ? '$h:${dos(m)}:${dos(s)}' : '${dos(d.inMinutes)}:${dos(s)}';
}

/// "1 salida", "3 salidas".
String textoSalidas(int n) => n == 1 ? '1 salida' : '$n salidas';

/// Regla del tope de salidas, para el alumno ("" si no hay tope).
String textoTope(int? tope) => switch (tope) {
      null => '',
      0 => 'Si salís, se entrega solo.',
      1 => 'Si salís más de 1 vez, se entrega solo.',
      final t => 'Si salís más de $t veces, se entrega solo.',
    };

/// "7,5 / 10" o "Sin nota".
String textoNota(Intento i, Cuestionario c) {
  if (i.nota == null) return 'Sin nota';
  return '${formatearNota(i.nota!)} / ${formatearNota(c.notaMaxima)}';
}

/// Cómo terminó un intento, en pocas palabras.
String estadoIntento(Intento i) {
  if (!i.entregado) return 'Rindiendo ahora';
  return switch (i.entregaAuto) {
    'tiempo' => 'Se entregó solo (tiempo)',
    'salidas' => 'Se entregó solo (salidas)',
    _ => 'Entregado',
  };
}

/// Orden mezclado pero siempre igual para el mismo intento (así no cambia si
/// recarga). [semilla]: el id del intento.
List<T> mezclarCon<T>(List<T> lista, String semilla) {
  var h = 0;
  for (final c in semilla.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return [...lista]..shuffle(Random(h));
}

abstract interface class CuestionariosRepository {
  Future<List<Cuestionario>> delCurso(String cursoId);
  Future<Cuestionario> cuestionario(String id);
  Future<Cuestionario> guardar({String? id, String? cursoId, required DatosCuestionario datos});
  Future<void> publicar(String id);
  Future<void> borrar(String id);

  /// Con las respuestas correctas (docente).
  Future<List<Pregunta>> preguntasConClave(String cuestionarioId);
  Future<void> guardarPreguntas(String cuestionarioId, List<Pregunta> preguntas);
  Future<List<ResultadoAlumno>> resultados(String cuestionarioId);
  Future<void> corregir(String intentoId, String preguntaId, {required num puntaje, String? comentario});

  /// Alumno.
  Future<List<Intento>> misIntentos(String cuestionarioId);
  Future<String> empezar(String cuestionarioId);
  Future<IntentoAbierto> abrir(String intentoId, String sesion);
  Future<void> responder(String intentoId, String sesion, String preguntaId, Object? valor);

  /// Devuelve las salidas contadas y si con esta se entregó solo.
  Future<({int salidas, bool entregado})> avisarSalida(String intentoId, String sesion,
      {required bool volvio, int segundos = 0});
  Future<void> entregar(String intentoId);

  Future<DetalleIntento> detalle(String intentoId);
}
