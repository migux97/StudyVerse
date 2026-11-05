import '../../auth/domain/profile.dart';

enum GroupRole { admin, miembro }

class Group {
  const Group({
    required this.id,
    required this.nombre,
    this.materia,
    required this.inviteCode,
    this.plan = Plan.free,
    this.storageUsed = 0,
    this.createdBy,
    required this.createdAt,
    this.miRol,
    this.cantidadMiembros,
    this.materias = const [],
    this.aprobarTareas = false,
  });

  final String id;
  final String nombre;
  final String? materia;
  final String inviteCode;
  final Plan plan;
  final int storageUsed;
  final String? createdBy;
  final DateTime createdAt;

  /// Rol del usuario actual (si se pidió junto con el grupo).
  final GroupRole? miRol;
  final int? cantidadMiembros;

  /// Nombres de las materias del grupo (sus carpetas de materia).
  final List<String> materias;

  /// Las tareas las aprueba un admin (quien la hace la marca como entregada).
  final bool aprobarTareas;

  /// Con aprobación, solo un admin deja una tarea como hecha.
  bool get puedoCerrarTareas => !aprobarTareas || soyAdmin;

  bool get soyAdmin => miRol == GroupRole.admin;

  factory Group.fromMap(Map<String, dynamic> map, {GroupRole? miRol, int? cantidadMiembros}) =>
      Group(
        id: map['id'] as String,
        nombre: map['nombre'] as String,
        materia: map['materia'] as String?,
        inviteCode: map['invite_code'] as String,
        plan: Plan.values.byName(map['plan'] as String? ?? 'free'),
        storageUsed: (map['storage_used'] as num?)?.toInt() ?? 0,
        createdBy: map['created_by'] as String?,
        createdAt: DateTime.parse(map['created_at'] as String),
        miRol: miRol,
        cantidadMiembros: cantidadMiembros,
        materias: [
          for (final m in (map['materias'] as List?) ?? const [])
            if (m is Map && (m['es_materia'] ?? true) == true) m['nombre'] as String,
        ]..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase())),
        aprobarTareas: map['aprobar_tareas'] as bool? ?? false,
      );
}

class GroupMember {
  const GroupMember({required this.profile, required this.rol, required this.joinedAt});

  final Profile profile;
  final GroupRole rol;
  final DateTime joinedAt;

  bool get esAdmin => rol == GroupRole.admin;

  /// Fila de `group_members` con el perfil embebido (`profiles(*)`).
  factory GroupMember.fromMap(Map<String, dynamic> map) => GroupMember(
        profile: Profile.fromMap(map['profiles'] as Map<String, dynamic>),
        rol: GroupRole.values.byName(map['rol'] as String),
        joinedAt: DateTime.parse(map['joined_at'] as String),
      );
}

/// Admins primero, después por nombre.
List<GroupMember> ordenarMiembros(Iterable<GroupMember> miembros) => miembros.toList()
  ..sort((a, b) {
    if (a.esAdmin != b.esAdmin) return a.esAdmin ? -1 : 1;
    return a.profile.nombre.toLowerCase().compareTo(b.profile.nombre.toLowerCase());
  });
