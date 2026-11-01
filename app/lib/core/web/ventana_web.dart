import 'package:web/web.dart' as web;

class VentanaPendiente {
  VentanaPendiente._(this._ventana);
  final web.Window _ventana;

  /// Abre una pestaña vacía. Llamar sincrónicamente dentro del clic.
  static VentanaPendiente? abrir() {
    final w = web.window.open('', '_blank');
    return w == null ? null : VentanaPendiente._(w);
  }

  void ir(String url) => _ventana.location.href = url;

  void cerrar() => _ventana.close();
}
