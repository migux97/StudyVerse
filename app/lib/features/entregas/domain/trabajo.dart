import '../../../core/errors.dart';

class EntregasFailure extends AppFailure {
  const EntregasFailure(super.mensaje);
}

/// Cómo quedó la entrega de un grupo.
enum EstadoEntrega {
  pendiente('Sin entregar', 'pendiente'),
  entregada('Entregada', 'entregada'),
  aprobada('Aprobado', 'aprobada'),
  aRehacer('A rehacer', 'a_rehacer'),
  desaprobada('Desaprobado', 'desaprobada');

  const EstadoEntrega(this.texto, this.db);
  final String texto;
  final String db;

  static EstadoEntrega desde(String v) =>
      EstadoEntrega.values.where((e) => e.db == v).firstOrNull ?? EstadoEntrega.entregada;

  bool get corregida => this == aprobada || this == aRehacer || this == desaprobada;

  /// Las que elige el docente al corregir.
  static const correcciones = [aprobada, aRehacer, desaprobada];
}

/// Un trabajo práctico del curso: consigna, vencimiento y nota máxima.
class Trabajo {
  const Trabajo({
    required this.id,
    required this.cursoId,
    required this.titulo,
    this.consigna,
    required this.venceAt,
    required this.notaMaxima,
    required this.createdAt,
    this.cursoNombre,
  });

  final String id;
  final String cursoId;
  final String titulo;
  final String? consigna;
  final DateTime venceAt;
  final num notaMaxima;
  final DateTime createdAt;
  final String? cursoNombre;

  bool vencido(DateTime ahora) => ahora.isAfter(venceAt);

  factory Trabajo.fromMap(Map<String, dynamic> m) => Trabajo(
        id: m['id'] as String,
        cursoId: m['curso_id'] as String,
        titulo: m['titulo'] as String,
        consigna: m['consigna'] as String?,
        venceAt: DateTime.parse(m['vence_at'] as String),
        notaMaxima: m['nota_maxima'] as num,
        createdAt: DateTime.parse(m['created_at'] as String),
        cursoNombre: (m['curso'] as Map<String, dynamic>?)?['nombre'] as String?,
      );
}

/// Lo que entregó un grupo para un trabajo.
class Entrega {
  const Entrega({
    required this.id,
    required this.trabajoId,
    required this.groupId,
    required this.fileId,
    this.archivoNombre,
    required this.versionNumber,
    this.entregadaPor,
    required this.entregadaAt,
    required this.estado,
    this.nota,
    this.devolucion,
    this.corregidaAt,
  });

  final String id;
  final String trabajoId;
  final String groupId;
  final String fileId;
  final String? archivoNombre;
  final int versionNumber;

  /// Nombre de quien la entregó.
  final String? entregadaPor;
  final DateTime entregadaAt;
  final EstadoEntrega estado;
  final num? nota;
  final String? devolucion;
  final DateTime? corregidaAt;

  bool tarde(Trabajo t) => entregadaAt.isAfter(t.venceAt);

  /// El grupo puede (volver a) entregar mientras no esté aprobada ni desaprobada.
  bool get sePuedeCambiar => estado == EstadoEntrega.entregada || estado == EstadoEntrega.aRehacer;

  factory Entrega.fromMap(Map<String, dynamic> m) => Entrega(
        id: m['id'] as String,
        trabajoId: m['trabajo_id'] as String,
        groupId: m['group_id'] as String,
        fileId: m['file_id'] as String,
        archivoNombre: (m['archivo'] as Map<String, dynamic>?)?['nombre'] as String?,
        versionNumber: (m['version_number'] as num).toInt(),
        entregadaPor: (m['quien'] as Map<String, dynamic>?)?['nombre'] as String?,
        entregadaAt: DateTime.parse(m['entregada_at'] as String),
        estado: EstadoEntrega.desde(m['estado'] as String),
        nota: m['nota'] as num?,
        devolucion: m['devolucion'] as String?,
        corregidaAt: m['corregida_at'] == null ? null : DateTime.parse(m['corregida_at'] as String),
      );
}

/// "8", "7,5", "9,25" (como se escribe en Argentina).
String formatearNota(num n) {
  if (n == n.roundToDouble()) return n.toInt().toString();
  return n.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '').replaceAll('.', ',');
}

/// "7,5" o "7.5" → 7.5. Null si no es un número.
num? leerNota(String texto) => num.tryParse(texto.trim().replaceAll(',', '.'));

/// "Aprobado · 8".
String resultado(Entrega e) => [e.estado.texto, if (e.nota != null) formatearNota(e.nota!)].join(' · ');

/// "vie 14/11 23:59".
String formatearVencimiento(DateTime d) {
  const dias = ['lun', 'mar', 'mié', 'jue', 'vie', 'sáb', 'dom'];
  final l = d.toLocal();
  String dos(int n) => n.toString().padLeft(2, '0');
  return '${dias[l.weekday - 1]} ${dos(l.day)}/${dos(l.month)} ${dos(l.hour)}:${dos(l.minute)}';
}

abstract interface class EntregasRepository {
  Future<List<Trabajo>> trabajos(String cursoId);
  Future<Trabajo> trabajo(String trabajoId);
  Future<Trabajo> crear({
    required String cursoId,
    required String titulo,
    String? consigna,
    required DateTime venceAt,
    required num notaMaxima,
  });
  Future<Trabajo> editar(Trabajo t, {required String titulo, String? consigna, required DateTime venceAt, required num notaMaxima});
  Future<void> borrar(String trabajoId);

  /// Las entregas de todos los grupos del curso (para el docente).
  Future<List<Entrega>> delCurso(String cursoId);

  /// Las entregas de un grupo.
  Future<List<Entrega>> delGrupo(String groupId);

  Future<Entrega> entregar({required String trabajoId, required String groupId, required String fileId});
  Future<Entrega> corregir(String entregaId, {required EstadoEntrega estado, num? nota, String? devolucion});

  /// Los bytes de la versión entregada (para descargarla).
  Future<List<int>> bytesDeLaVersion(String fileId, int version);
}
