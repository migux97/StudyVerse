/// Validadores de formularios. Devuelven el mensaje de error o `null`.
class Validators {
  static final _emailRegex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
  static final _usernameRegex = RegExp(r'^[a-z0-9][a-z0-9._]{1,18}[a-z0-9]$');

  static String? email(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Ingresá tu email';
    if (!_emailRegex.hasMatch(v)) return 'Revisá el email, parece incompleto';
    return null;
  }

  /// Para crear o cambiar la contraseña: tiene que cumplir todos los requisitos.
  static String? password(String? value) {
    final v = value ?? '';
    if (v.isEmpty) return 'Elegí una contraseña';
    final falta = RequisitoContrasena.values.where((r) => !r.cumple(v));
    if (falta.isEmpty) return null;
    return 'Le falta: ${falta.map((r) => r.corto).join(', ')}';
  }

  static String? nombre(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Ingresá tu nombre';
    if (v.length > 80) return 'Usá hasta 80 caracteres';
    return null;
  }

  static String? username(String? value) {
    final v = value?.trim().toLowerCase() ?? '';
    if (v.isEmpty) return 'Elegí un nombre de usuario';
    if (v.length < 3) return 'Usá al menos 3 caracteres';
    if (v.length > 20) return 'Usá hasta 20 caracteres';
    if (RegExp(r'[^a-z0-9._]').hasMatch(v)) return 'Solo letras, números, punto y guion bajo';
    if (!_usernameRegex.hasMatch(v)) return 'Tiene que empezar y terminar con letra o número';
    if (RegExp(r'[._]{2}').hasMatch(v)) return 'No pongas dos símbolos seguidos';
    return null;
  }

  /// Campo opcional de hasta 80 caracteres (carrera, universidad).
  static String? opcional(String? value) =>
      (value?.trim().length ?? 0) > 80 ? 'Usá hasta 80 caracteres' : null;

  static String? codigo(String? value) {
    final v = value?.replaceAll(RegExp(r'\s'), '') ?? '';
    if (v.isEmpty) return 'Ingresá el código del correo';
    if (!RegExp(r'^\d{6}$').hasMatch(v)) return 'Son 6 números';
    return null;
  }

  static String? Function(String?) confirmarPassword(String Function() original) =>
      (value) => value != original() ? 'No coincide con la contraseña' : null;
}

/// Lo que pide Supabase Auth (`password_requirements = lower_upper_letters_digits`,
/// mínimo 8). Se muestra en vivo mientras se escribe.
enum RequisitoContrasena {
  largo('8 caracteres o más', '8 caracteres'),
  minuscula('Una minúscula', 'una minúscula'),
  mayuscula('Una mayúscula', 'una mayúscula'),
  numero('Un número', 'un número');

  const RequisitoContrasena(this.texto, this.corto);
  final String texto;
  final String corto;

  bool cumple(String v) => switch (this) {
        largo => v.length >= 8,
        minuscula => RegExp(r'[a-z]').hasMatch(v),
        mayuscula => RegExp(r'[A-Z]').hasMatch(v),
        numero => RegExp(r'\d').hasMatch(v),
      };
}
