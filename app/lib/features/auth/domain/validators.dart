/// Validadores de los datos de la cuenta. Devuelven el mensaje de error o `null`.
///
/// Los mensajes siguen lo que usan casi todas las apps (Google, Drive): dicen qué
/// falta y, si sirve, muestran un ejemplo.
class Validators {
  static final _usernameRegex = RegExp(r'^[a-z0-9][a-z0-9._]{1,18}[a-z0-9]$');
  // Parte local: lo que permite casi cualquier proveedor. Dominio: etiquetas
  // separadas por punto y un final de al menos 2 letras (.com, .ar, .edu.ar).
  static final _localRegex = RegExp(r"^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+$");
  static final _dominioRegex =
      RegExp(r'^(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,}$');
  static final _letra = RegExp(r'\p{L}', unicode: true);

  static const emailEjemplo = 'nombre@ejemplo.com';
  static const _emailInvalido = 'Ingresá un email válido, como $emailEjemplo';

  static String? email(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Ingresá tu email';
    if (v.contains(RegExp(r'\s'))) return 'El email no puede tener espacios';
    final arroba = '@'.allMatches(v).length;
    if (arroba == 0) return 'Falta el @ en el email';
    if (arroba > 1) return 'El email tiene más de un @';
    final [local, dominio] = v.split('@');
    if (local.isEmpty) return 'Falta lo que va antes del @';
    if (dominio.isEmpty) return 'Falta lo que va después del @, como gmail.com';
    if (!dominio.contains('.')) return 'Al email le falta el final, como .com';
    if (v.length > 254) return 'El email es demasiado largo';
    if (!_localRegex.hasMatch(local) ||
        local.startsWith('.') ||
        local.endsWith('.') ||
        local.contains('..') ||
        !_dominioRegex.hasMatch(dominio)) {
      return _emailInvalido;
    }
    return null;
  }

  /// Si el dominio parece mal escrito ("gmial.com"), el email corregido.
  static String? sugerenciaEmail(String? value) {
    final v = value?.trim().toLowerCase() ?? '';
    final i = v.lastIndexOf('@');
    if (i <= 0 || i == v.length - 1) return null;
    final dominio = v.substring(i + 1);
    final corregido = _dominiosMalEscritos[dominio];
    return corregido == null ? null : '${value!.trim().substring(0, i)}@$corregido';
  }

  static const _dominiosMalEscritos = {
    'gmial.com': 'gmail.com',
    'gmai.com': 'gmail.com',
    'gamil.com': 'gmail.com',
    'gmail.co': 'gmail.com',
    'gmail.con': 'gmail.com',
    'gmail.cm': 'gmail.com',
    'gmal.com': 'gmail.com',
    'gnail.com': 'gmail.com',
    'gmail.com.ar': 'gmail.com',
    'hotmial.com': 'hotmail.com',
    'hotmai.com': 'hotmail.com',
    'hotmail.con': 'hotmail.com',
    'hotmal.com': 'hotmail.com',
    'hotmail.co': 'hotmail.com',
    'outlok.com': 'outlook.com',
    'outlook.con': 'outlook.com',
    'yahooo.com': 'yahoo.com',
    'yaho.com': 'yahoo.com',
    'yahoo.con': 'yahoo.com',
    'iclod.com': 'icloud.com',
    'icloud.con': 'icloud.com',
  };

  /// Para crear o cambiar la contraseña: tiene que cumplir todos los requisitos.
  static String? password(String? value) {
    final v = value ?? '';
    if (v.isEmpty) return 'Ingresá una contraseña';
    if (v.length > 72) return 'Usá 72 caracteres como máximo';
    final falta = RequisitoContrasena.values.where((r) => !r.cumple(v)).toList();
    if (falta.isEmpty) return null;
    if (falta.first == RequisitoContrasena.largo) return 'Usá 8 caracteres o más';
    return 'La contraseña necesita ${_lista(falta.map((r) => r.corto).toList())}';
  }

  static String? nombre(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Ingresá tu nombre';
    if (v.length < 2) return 'El nombre es muy corto';
    if (v.length > 80) return 'Usá 80 caracteres como máximo';
    if (!_letra.hasMatch(v)) return 'Ingresá un nombre válido, como Ana García';
    return null;
  }

  static String? username(String? value) {
    final v = value?.trim().toLowerCase() ?? '';
    if (v.isEmpty) return 'Elegí un nombre de usuario';
    if (v.length < 3) return 'Usá 3 caracteres o más';
    if (v.length > 20) return 'Usá 20 caracteres como máximo';
    if (RegExp(r'[^a-z0-9._]').hasMatch(v)) return 'Usá solo letras, números, punto (.) y guion bajo (_)';
    if (!_usernameRegex.hasMatch(v)) return 'Tiene que empezar y terminar con una letra o un número';
    if (RegExp(r'[._]{2}').hasMatch(v)) return 'No pongas dos símbolos seguidos';
    return null;
  }

  /// Campo opcional de hasta 80 caracteres (carrera, universidad).
  static String? opcional(String? value) =>
      (value?.trim().length ?? 0) > 80 ? 'Usá 80 caracteres como máximo' : null;

  static String? codigo(String? value) {
    final v = value?.replaceAll(RegExp(r'[\s-]'), '') ?? '';
    if (v.isEmpty) return 'Ingresá el código';
    if (RegExp(r'\D').hasMatch(v)) return 'El código tiene solo números';
    if (v.length != 6) return 'El código tiene 6 números';
    return null;
  }

  static String? Function(String?) confirmarPassword(String Function() original) => (value) {
        if ((value ?? '').isEmpty) return 'Confirmá la contraseña';
        return value != original() ? 'Las contraseñas no coinciden. Probá de nuevo' : null;
      };

  static String _lista(List<String> items) => items.length == 1
      ? items.single
      : '${items.sublist(0, items.length - 1).join(', ')} y ${items.last}';
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
