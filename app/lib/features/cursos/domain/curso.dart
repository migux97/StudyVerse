import '../../../core/errors.dart';

class CursosFailure extends AppFailure {
  const CursosFailure(super.mensaje);
}

/// Un curso de un docente ("Física II · Comisión 3"). Los grupos se suman con
/// su código y el docente los ve en solo lectura.
class Curso {
  const Curso({
    required this.id,
    required this.nombre,
    required this.codigo,
    required this.docenteId,
    this.docenteNombre,
    required this.createdAt,
    this.cantidadGrupos = 0,
    this.soyTitular = true,
  });

  final String id;
  final String nombre;
  final String codigo;
  final String docenteId;
  final String? docenteNombre;
  final DateTime createdAt;
  final int cantidadGrupos;

  /// Lo creé yo (los ayudantes no cambian el curso ni suman docentes).
  final bool soyTitular;

  /// "ABCDE-23456", como los códigos de invitación.
  String get codigoVisible => codigo.length == 10 ? '${codigo.substring(0, 5)}-${codigo.substring(5)}' : codigo;

  /// Fila de `cursos` (con `docente:profiles!cursos_docente_id_fkey(nombre)`) o de `mis_cursos()`.
  factory Curso.fromMap(Map<String, dynamic> m) => Curso(
        id: m['id'] as String,
        nombre: m['nombre'] as String,
        codigo: m['codigo'] as String? ?? '',
        docenteId: m['docente_id'] as String,
        docenteNombre: (m['docente'] as Map<String, dynamic>?)?['nombre'] as String?,
        createdAt: DateTime.parse(m['created_at'] as String),
        cantidadGrupos: (m['cantidad_grupos'] as num?)?.toInt() ?? 0,
        soyTitular: m['soy_titular'] as bool? ?? true,
      );

  Curso conTitular(bool titular) => Curso(
        id: id,
        nombre: nombre,
        codigo: codigo,
        docenteId: docenteId,
        docenteNombre: docenteNombre,
        createdAt: createdAt,
        cantidadGrupos: cantidadGrupos,
        soyTitular: titular,
      );
}

/// Un grupo visto desde el curso: quiénes son y cómo vienen con las tareas.
class GrupoDelCurso {
  const GrupoDelCurso({
    required this.id,
    required this.nombre,
    required this.integrantes,
    required this.tareasHechas,
    required this.tareasTotal,
    required this.entregadas,
    required this.materias,
    this.tareasVencidas = 0,
    this.ultimaActividad,
    this.versionesSemana = 0,
  });

  final String id;
  final String nombre;
  final List<String> integrantes;
  final int tareasHechas;
  final int tareasTotal;

  /// Tareas esperando aprobación.
  final int entregadas;
  final List<String> materias;
  final int tareasVencidas;
  final DateTime? ultimaActividad;

  /// Versiones subidas en los últimos 7 días.
  final int versionesSemana;

  /// Una semana sin movimiento (o nunca tuvo).
  bool inactivo(DateTime ahora) =>
      ultimaActividad == null || ahora.difference(ultimaActividad!) > const Duration(days: 7);

  /// Un elemento de `grupos_del_curso()`: integrantes, estados de las tareas y materias.
  factory GrupoDelCurso.fromMap(Map<String, dynamic> m) {
    final tareas = [for (final t in (m['tareas'] as List?) ?? const []) t as String];
    return GrupoDelCurso(
      id: m['id'] as String,
      nombre: m['nombre'] as String,
      integrantes: [for (final n in (m['integrantes'] as List?) ?? const []) n as String],
      tareasHechas: tareas.where((e) => e == 'hecha').length,
      tareasTotal: tareas.length,
      entregadas: tareas.where((e) => e == 'entregada').length,
      materias: [for (final n in (m['materias'] as List?) ?? const []) n as String],
      tareasVencidas: (m['tareas_vencidas'] as num?)?.toInt() ?? 0,
      ultimaActividad: m['ultima_actividad'] == null ? null : DateTime.parse(m['ultima_actividad'] as String),
      versionesSemana: (m['versiones_semana'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Titular o ayudante del curso.
class DocenteDelCurso {
  const DocenteDelCurso({required this.id, required this.nombre, this.username, this.avatarUrl, required this.titular});
  final String id;
  final String nombre;
  final String? username;
  final String? avatarUrl;
  final bool titular;

  factory DocenteDelCurso.fromMap(Map<String, dynamic> m) => DocenteDelCurso(
        id: m['id'] as String,
        nombre: m['nombre'] as String,
        username: m['username'] as String?,
        avatarUrl: m['avatar_url'] as String?,
        titular: m['titular'] as bool? ?? false,
      );
}

/// Lo que aportó un alumno en su grupo (para evaluar a cada uno).
class AporteAlumno {
  const AporteAlumno({
    required this.userId,
    required this.nombre,
    this.username,
    required this.groupId,
    required this.grupo,
    required this.tareasHechas,
    required this.tareasPendientes,
    required this.versiones,
    required this.comentarios,
    this.ultimaActividad,
  });

  final String userId;
  final String nombre;
  final String? username;
  final String groupId;
  final String grupo;
  final int tareasHechas;
  final int tareasPendientes;
  final int versiones;
  final int comentarios;
  final DateTime? ultimaActividad;

  /// No hizo nada visible: ni tareas, ni versiones, ni comentarios.
  bool get sinAportes => tareasHechas == 0 && versiones == 0 && comentarios == 0;

  factory AporteAlumno.fromMap(Map<String, dynamic> m) {
    int n(String k) => (m[k] as num?)?.toInt() ?? 0;
    return AporteAlumno(
      userId: m['user_id'] as String,
      nombre: m['nombre'] as String,
      username: m['username'] as String?,
      groupId: m['group_id'] as String,
      grupo: m['grupo'] as String,
      tareasHechas: n('tareas_hechas'),
      tareasPendientes: n('tareas_pendientes'),
      versiones: n('versiones'),
      comentarios: n('comentarios'),
      ultimaActividad: m['ultima_actividad'] == null ? null : DateTime.parse(m['ultima_actividad'] as String),
    );
  }
}

/// Un archivo que el docente comparte con todo el curso.
class MaterialCurso {
  const MaterialCurso({
    required this.id,
    required this.cursoId,
    required this.nombre,
    required this.storagePath,
    required this.sizeBytes,
    this.mimeType,
    required this.createdAt,
  });

  final String id;
  final String cursoId;
  final String nombre;
  final String storagePath;
  final int sizeBytes;
  final String? mimeType;
  final DateTime createdAt;

  factory MaterialCurso.fromMap(Map<String, dynamic> m) => MaterialCurso(
        id: m['id'] as String,
        cursoId: m['curso_id'] as String,
        nombre: m['nombre'] as String,
        storagePath: m['storage_path'] as String,
        sizeBytes: (m['size_bytes'] as num).toInt(),
        mimeType: m['mime_type'] as String?,
        createdAt: DateTime.parse(m['created_at'] as String),
      );
}

/// Una fecha que el docente carga para todo el curso.
class FechaCurso {
  const FechaCurso({
    required this.id,
    required this.titulo,
    required this.tipo,
    required this.fecha,
    this.hora,
    this.nota,
  });

  final String id;
  final String titulo;

  /// parcial, entrega, clase u otro.
  final String tipo;
  final DateTime fecha;
  final String? hora;
  final String? nota;

  factory FechaCurso.fromMap(Map<String, dynamic> m) => FechaCurso(
        id: m['id'] as String,
        titulo: m['titulo'] as String,
        tipo: m['tipo'] as String,
        fecha: DateTime.parse(m['fecha'] as String),
        hora: (m['hora'] as String?)?.substring(0, 5),
        nota: m['nota'] as String?,
      );
}

abstract interface class CursosRepository {
  /// Los cursos que doy (solo docentes).
  Future<List<Curso>> misCursos();
  Future<Curso> curso(String cursoId);
  Future<Curso> crear(String nombre);
  Future<void> renombrar(String cursoId, String nombre);
  Future<void> borrar(String cursoId);
  Future<String> regenerarCodigo(String cursoId);
  Future<List<GrupoDelCurso>> grupos(String cursoId);

  /// Desde un grupo (admin): sumarlo a un curso con el código del docente.
  Future<Curso> sumarGrupo(String groupId, String codigo);

  /// Lo saca del curso (admin del grupo o el docente).
  Future<void> quitarGrupo(String groupId);

  /// ¿Lo creé yo? (los ayudantes no cambian el curso).
  Future<bool> soyTitular(String cursoId);

  Future<List<DocenteDelCurso>> docentes(String cursoId);
  Future<DocenteDelCurso> sumarAyudante(String cursoId, String usuario);
  Future<void> quitarAyudante(String cursoId, String userId);

  Future<List<AporteAlumno>> aportes(String cursoId);

  Future<List<MaterialCurso>> material(String cursoId);
  Future<MaterialCurso> subirMaterial(String cursoId, {required String nombre, required List<int> bytes});
  Future<void> borrarMaterial(String id);
  Future<List<int>> bytesDelMaterial(MaterialCurso m);

  Future<List<FechaCurso>> fechas(String cursoId);
  Future<void> crearFecha(String cursoId,
      {required String titulo, required String tipo, required DateTime fecha, String? hora, String? nota});
  Future<void> borrarFecha(String id);
}
