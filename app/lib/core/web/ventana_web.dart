import 'package:web/web.dart' as web;

class VentanaPendiente {
  VentanaPendiente._(this._ventana);
  final web.Window _ventana;

  /// Abre una pestaña vacía. Llamar sincrónicamente dentro del clic.
  static VentanaPendiente? abrir() {
    final w = web.window.open('', '_blank');
    if (w == null) return null;
    // La pestaña va a mostrar un archivo subido por otro: que no pueda tocar
    // esta (reverse tabnabbing). Se puede porque about:blank es del mismo origen.
    w.opener = null;
    return VentanaPendiente._(w);
  }

  void ir(String url) => _ventana.location.href = url;

  void cerrar() => _ventana.close();
}
