/// Fuera de la web no hace falta: [abrir] devuelve null y se usa url_launcher.
class VentanaPendiente {
  const VentanaPendiente._();

  static VentanaPendiente? abrir() => null;

  void ir(String url) {}
  void cerrar() {}
}
