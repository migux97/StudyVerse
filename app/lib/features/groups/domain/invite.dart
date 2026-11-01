/// Códigos y links de invitación.
class Invite {
  static const largoCodigo = 8;
  static const rutaUnirse = '/unirse';

  /// "abcd-2345 " → "ABCD2345".
  static String normalizar(String input) =>
      input.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

  static bool esCodigoValido(String input) =>
      RegExp(r'^[A-HJKMNP-Z2-9]{8}$').hasMatch(normalizar(input));

  /// "ABCD2345" → "ABCD-2345", más fácil de dictar.
  static String formatear(String codigo) {
    final c = normalizar(codigo);
    return c.length == largoCodigo ? '${c.substring(0, 4)}-${c.substring(4)}' : c;
  }

  /// Link para compartir. `base` es el origen de la web, p. ej. https://tpdrive.app
  static String link(String base, String codigo) {
    final origen = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    return '$origen/#$rutaUnirse/${normalizar(codigo)}';
  }

  /// Acepta un código suelto o un link pegado entero. `null` si no hay código.
  static String? extraerCodigo(String input) {
    final texto = input.trim();
    final match = RegExp(r'unirse/([A-Za-z0-9-]+)').firstMatch(texto);
    final candidato = normalizar(match?.group(1) ?? texto);
    return esCodigoValido(candidato) ? candidato : null;
  }
}
