/// Validadores de formularios. Devuelven el mensaje de error o `null`.
class Validators {
  static final _emailRegex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  static String? email(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Ingresá tu email';
    if (!_emailRegex.hasMatch(v)) return 'El email no es válido';
    return null;
  }

  static String? password(String? value) {
    final v = value ?? '';
    if (v.isEmpty) return 'Ingresá tu contraseña';
    if (v.length < 8) return 'Mínimo 8 caracteres';
    return null;
  }

  static String? nombre(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Ingresá tu nombre';
    if (v.length > 80) return 'Máximo 80 caracteres';
    return null;
  }

  static String? Function(String?) confirmarPassword(String Function() original) =>
      (value) => value != original() ? 'Las contraseñas no coinciden' : null;
}
