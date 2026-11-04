/// Un dispositivo con la sesión iniciada (Perfil › Dispositivos conectados).
class Dispositivo {
  const Dispositivo({
    required this.id,
    required this.nombre,
    required this.esApp,
    this.ip,
    required this.creada,
    required this.ultimoUso,
    required this.actual,
  });

  final String id;

  /// "Chrome en Windows", "App de StudyVerse"…
  final String nombre;
  final bool esApp;
  final String? ip;
  final DateTime creada;
  final DateTime ultimoUso;
  final bool actual;

  factory Dispositivo.fromMap(Map<String, dynamic> m) {
    final (nombre, esApp) = describirDispositivo(m['user_agent'] as String?);
    return Dispositivo(
      id: m['id'] as String,
      nombre: nombre,
      esApp: esApp,
      ip: m['ip'] as String?,
      creada: DateTime.parse(m['creada'] as String).toLocal(),
      ultimoUso: DateTime.parse(m['ultimo_uso'] as String).toLocal(),
      actual: m['actual'] as bool? ?? false,
    );
  }
}

/// Nombre legible a partir del User-Agent, como lo muestra Google.
(String, bool) describirDispositivo(String? ua) {
  final u = ua ?? '';
  // La app (Dart fuera del navegador) no manda un User-Agent de navegador.
  if (u.startsWith('Dart/') || u.contains('dart:io')) return ('App de StudyVerse', true);

  String? so;
  if (u.contains('Android')) {
    so = 'Android';
  } else if (u.contains('iPhone') || u.contains('iPad')) {
    so = 'iOS';
  } else if (u.contains('Windows')) {
    so = 'Windows';
  } else if (u.contains('Mac OS X') || u.contains('Macintosh')) {
    so = 'Mac';
  } else if (u.contains('CrOS')) {
    so = 'ChromeOS';
  } else if (u.contains('Linux')) {
    so = 'Linux';
  }

  String? navegador;
  if (u.contains('Edg/')) {
    navegador = 'Edge';
  } else if (u.contains('OPR/') || u.contains('Opera')) {
    navegador = 'Opera';
  } else if (u.contains('Firefox/')) {
    navegador = 'Firefox';
  } else if (u.contains('Chrome/') || u.contains('CriOS/')) {
    navegador = 'Chrome';
  } else if (u.contains('Safari/')) {
    navegador = 'Safari';
  }

  if (navegador == null && so == null) return ('Dispositivo desconocido', false);
  if (navegador == null) return (so!, false);
  return (so == null ? navegador : '$navegador en $so', false);
}

/// Forma de entrar vinculada a la cuenta (email y contraseña, Google).
class CuentaVinculada {
  const CuentaVinculada({required this.id, required this.proveedor, this.email});
  final String id;
  final String proveedor;
  final String? email;

  String get nombre => switch (proveedor) {
        'google' => 'Google',
        'email' => 'Email y contraseña',
        _ => proveedor,
      };
}
