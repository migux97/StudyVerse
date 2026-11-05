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
  });

  final String id;
  final String nombre;
  final String codigo;
  final String docenteId;
  final String? docenteNombre;
  final DateTime createdAt;
  final int cantidadGrupos;

  /// "ABCDE-23456", como los códigos de invitación.
  String get codigoVisible => codigo.length == 10 ? '${codigo.substring(0, 5)}-${codigo.substring(5)}' : codigo;

  /// Fila de `cursos` (con `docente:profiles(nombre)`) o de `mis_cursos()`.
  factory Curso.fromMap(Map<String, dynamic> m) => Curso(
        id: m['id'] as String,
        nombre: m['nombre'] as String,
        codigo: m['codigo'] as String? ?? '',
        docenteId: m['docente_id'] as String,
        docenteNombre: (m['docente'] as Map<String, dynamic>?)?['nombre'] as String?,
        createdAt: DateTime.parse(m['created_at'] as String),
        cantidadGrupos: (m['cantidad_grupos'] as num?)?.toInt() ?? 0,
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
  });

  final String id;
  final String nombre;
  final List<String> integrantes;
  final int tareasHechas;
  final int tareasTotal;

  /// Tareas esperando aprobación.
  final int entregadas;
  final List<String> materias;

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
    );
  }
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
}
