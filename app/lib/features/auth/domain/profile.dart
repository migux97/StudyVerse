enum Plan { free, premium }

/// Lo que se elige al registrarse.
enum TipoCuenta {
  estudiante('Estudiante'),
  docente('Docente');

  const TipoCuenta(this.etiqueta);
  final String etiqueta;
}

class Profile {
  const Profile({
    required this.id,
    required this.nombre,
    this.username,
    this.avatarUrl,
    this.carrera,
    this.universidad,
    this.plan = Plan.free,
    required this.createdAt,
    this.tipo = TipoCuenta.estudiante,
  });

  final String id;
  final String nombre;

  /// Sin @. Puede faltar en datos que vienen de consultas que no lo piden.
  final String? username;

  /// URL (Google) o `storage:{ruta}` para una foto subida a StudyVerse.
  final String? avatarUrl;
  final String? carrera;
  final String? universidad;
  final Plan plan;
  final DateTime createdAt;
  final TipoCuenta tipo;

  bool get esDocente => tipo == TipoCuenta.docente;

  /// Iniciales para el avatar cuando no hay foto ("Ana María" → "AM").
  String get iniciales {
    final partes =
        nombre.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (partes.isEmpty) return '?';
    if (partes.length == 1) return partes.first[0].toUpperCase();
    return (partes[0][0] + partes[1][0]).toUpperCase();
  }

  /// Ruta en el bucket `avatares` si la foto se subió a StudyVerse.
  String? get avatarPath =>
      avatarUrl != null && avatarUrl!.startsWith('storage:') ? avatarUrl!.substring(8) : null;

  /// "Ingeniería en Sistemas · UTN", o null si no cargó nada.
  String? get estudios {
    final partes = [carrera, universidad].whereType<String>().where((s) => s.trim().isNotEmpty);
    return partes.isEmpty ? null : partes.join(' · ');
  }

  factory Profile.fromMap(Map<String, dynamic> map) => Profile(
        id: map['id'] as String,
        nombre: map['nombre'] as String,
        username: map['username'] as String?,
        avatarUrl: map['avatar_url'] as String?,
        carrera: map['carrera'] as String?,
        universidad: map['universidad'] as String?,
        plan: Plan.values.byName(map['plan'] as String? ?? 'free'),
        createdAt: DateTime.parse(map['created_at'] as String),
        tipo: map['tipo_cuenta'] == 'docente' ? TipoCuenta.docente : TipoCuenta.estudiante,
      );
}

/// Campos editables del perfil. `null` = no cambiar; '' = borrar (carrera y universidad).
class CambiosPerfil {
  const CambiosPerfil({this.nombre, this.username, this.carrera, this.universidad, this.tipo});
  final String? nombre;
  final String? username;
  final String? carrera;
  final String? universidad;
  final TipoCuenta? tipo;

  Map<String, dynamic> toMap() => {
        if (tipo != null) 'tipo_cuenta': tipo!.name,
        if (nombre != null) 'nombre': nombre!.trim(),
        if (username != null) 'username': username!.trim().toLowerCase(),
        if (carrera != null) 'carrera': carrera!.trim().isEmpty ? null : carrera!.trim(),
        if (universidad != null) 'universidad': universidad!.trim().isEmpty ? null : universidad!.trim(),
      };
}
