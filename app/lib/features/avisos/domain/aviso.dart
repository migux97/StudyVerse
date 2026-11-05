import '../../../core/errors.dart';

class AvisosFailure extends AppFailure {
  const AvisosFailure(super.mensaje);
}

/// Un aviso del docente: a todo el curso ([groupId] null) o a un grupo.
class AvisoDocente {
  const AvisoDocente({
    required this.id,
    required this.cursoId,
    this.groupId,
    this.autorNombre,
    required this.texto,
    required this.createdAt,
    this.grupoNombre,
  });

  final String id;
  final String cursoId;
  final String? groupId;
  final String? autorNombre;
  final String texto;
  final DateTime createdAt;

  /// Para el docente: a qué grupo fue (si fue a uno).
  final String? grupoNombre;

  bool get paraTodoElCurso => groupId == null;

  /// Fila de `avisos` con `autor_perfil:profiles(nombre)`.
  factory AvisoDocente.fromMap(Map<String, dynamic> m) => AvisoDocente(
        id: m['id'] as String,
        cursoId: m['curso_id'] as String,
        groupId: m['group_id'] as String?,
        autorNombre: (m['autor_perfil'] as Map<String, dynamic>?)?['nombre'] as String?,
        texto: m['texto'] as String,
        createdAt: DateTime.parse(m['created_at'] as String),
      );

  AvisoDocente conGrupo(String? nombre) => AvisoDocente(
        id: id,
        cursoId: cursoId,
        groupId: groupId,
        autorNombre: autorNombre,
        texto: texto,
        createdAt: createdAt,
        grupoNombre: nombre,
      );
}

/// Devolución del docente sobre una tarea.
class Devolucion {
  const Devolucion({
    required this.id,
    required this.taskId,
    required this.groupId,
    this.autor,
    this.autorNombre,
    required this.texto,
    required this.createdAt,
    this.tareaTitulo,
  });

  final String id;
  final String taskId;
  final String groupId;
  final String? autor;
  final String? autorNombre;
  final String texto;
  final DateTime createdAt;
  final String? tareaTitulo;

  /// Fila de `devoluciones` con `autor_perfil:profiles(nombre)` (y `tarea:tasks(titulo)`).
  factory Devolucion.fromMap(Map<String, dynamic> m) => Devolucion(
        id: m['id'] as String,
        taskId: m['task_id'] as String,
        groupId: m['group_id'] as String,
        autor: m['autor'] as String?,
        autorNombre: (m['autor_perfil'] as Map<String, dynamic>?)?['nombre'] as String?,
        texto: m['texto'] as String,
        createdAt: DateTime.parse(m['created_at'] as String),
        tareaTitulo: (m['tarea'] as Map<String, dynamic>?)?['titulo'] as String?,
      );
}

/// Lo que llega en vivo a un integrante: un aviso nuevo o una devolución.
sealed class AvisoEntrante {
  const AvisoEntrante();
}

class AvisoNuevo extends AvisoEntrante {
  const AvisoNuevo(this.aviso, {this.groupId});
  final AvisoDocente aviso;

  /// Grupo mío al que llegó (para ir a verlo).
  final String? groupId;

  String get mensaje => '${aviso.autorNombre ?? 'Tu docente'}: ${aviso.texto}';
}

class DevolucionNueva extends AvisoEntrante {
  const DevolucionNueva(this.devolucion);
  final Devolucion devolucion;

  String get mensaje =>
      '${devolucion.autorNombre ?? 'Tu docente'} dejó una devolución en «${devolucion.tareaTitulo ?? 'una tarea'}»';
}

abstract interface class AvisosRepository {
  /// Los avisos que ve un grupo (los de todo su curso y los dirigidos a él).
  Future<List<AvisoDocente>> delGrupo(String groupId, String cursoId);

  /// Para el docente: todos los avisos de su curso.
  Future<List<AvisoDocente>> delCurso(String cursoId);
  Future<void> mandar({required String cursoId, String? groupId, required String texto});
  Future<void> borrar(String avisoId);

  /// Devoluciones de las tareas de un grupo.
  Future<List<Devolucion>> devoluciones(String groupId);
  Future<void> devolver({required String taskId, required String groupId, required String texto});
  Future<void> borrarDevolucion(String id);

  /// Emite cuando llegan avisos nuevos al grupo.
  Stream<void> cambios(String groupId);

  /// Avisos y devoluciones que me llegan, en vivo.
  Stream<AvisoEntrante> entrantes(String miId);
}
