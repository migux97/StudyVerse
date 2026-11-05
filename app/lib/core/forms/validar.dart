import 'package:flutter/widgets.dart';

/// Validadores de uso general para los formularios de la app.
class Validar {
  /// Texto obligatorio con largo máximo. `vacio` es el mensaje si falta
  /// ("Ingresá el nombre del grupo").
  static String? Function(String?) texto({required String vacio, required int max, int min = 1}) =>
      (value) {
        final t = value?.trim() ?? '';
        if (t.isEmpty) return vacio;
        if (t.length < min) return 'Usá $min caracteres o más';
        if (t.length > max) return 'Usá $max caracteres como máximo';
        return null;
      };

  /// Texto opcional con largo máximo.
  static String? Function(String?) opcional(int max) =>
      (value) => (value?.trim().length ?? 0) > max ? 'Usá $max caracteres como máximo' : null;

  static final _prohibidos = RegExp(r'[/\\:*?"<>|]');

  /// Nombre de archivo o carpeta: los mismos caracteres que rechaza Windows,
  /// así se puede descargar sin que cambie el nombre.
  static String? Function(String?) nombreArchivo({String vacio = 'Ingresá un nombre', int max = 120}) =>
      (value) {
        final t = value?.trim() ?? '';
        if (t.isEmpty) return vacio;
        if (t.length > max) return 'Usá $max caracteres como máximo';
        if (_prohibidos.hasMatch(t)) return r'No uses estos caracteres: / \ : * ? " < > |';
        if (t.startsWith('.')) return 'El nombre no puede empezar con un punto';
        if (t.endsWith('.')) return 'El nombre no puede terminar con un punto';
        return null;
      };
}

/// Cómo valida cada campo: el error aparece al salir del campo o al enviar, y
/// desde ahí se actualiza mientras escribís (se va apenas lo corregís).
const validarAlCorregir = AutovalidateMode.onUserInteractionIfError;
