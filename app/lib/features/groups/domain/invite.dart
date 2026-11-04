/// Códigos y links de invitación.
class Invite {
  /// Los códigos nuevos tienen 10 caracteres; los de 8 (anteriores) siguen valiendo.
  static const largosCodigo = {8, 10};
  static const rutaUnirse = '/unirse';

  /// "abcd-2345 " → "ABCD2345".
  static String normalizar(String input) =>
      input.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

  static bool esCodigoValido(String input) =>
      RegExp(r'^([A-HJKMNP-Z2-9]{8}|[A-HJKMNP-Z2-9]{10})$').hasMatch(normalizar(input));

  /// "ABCDE23456" → "ABCDE-23456" (y "ABCD2345" → "ABCD-2345"), más fácil de dictar.
  static String formatear(String codigo) {
    final c = normalizar(codigo);
    if (!largosCodigo.contains(c.length)) return c;
    final mitad = c.length ~/ 2;
    return '${c.substring(0, mitad)}-${c.substring(mitad)}';
  }

  /// Link para compartir. `base` es el origen de la web, p. ej. https://studyverse.app
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
