enum Plan { free, premium }

class Profile {
  const Profile({
    required this.id,
    required this.nombre,
    this.avatarUrl,
    this.plan = Plan.free,
    required this.createdAt,
  });

  final String id;
  final String nombre;
  final String? avatarUrl;
  final Plan plan;
  final DateTime createdAt;

  /// Iniciales para el avatar cuando no hay foto ("Ana María" → "AM").
  String get iniciales {
    final partes =
        nombre.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (partes.isEmpty) return '?';
    if (partes.length == 1) return partes.first[0].toUpperCase();
    return (partes[0][0] + partes[1][0]).toUpperCase();
  }

  factory Profile.fromMap(Map<String, dynamic> map) => Profile(
        id: map['id'] as String,
        nombre: map['nombre'] as String,
        avatarUrl: map['avatar_url'] as String?,
        plan: Plan.values.byName(map['plan'] as String? ?? 'free'),
        createdAt: DateTime.parse(map['created_at'] as String),
      );

  Profile copyWith({String? nombre, String? avatarUrl}) => Profile(
        id: id,
        nombre: nombre ?? this.nombre,
        avatarUrl: avatarUrl ?? this.avatarUrl,
        plan: plan,
        createdAt: createdAt,
      );
}
