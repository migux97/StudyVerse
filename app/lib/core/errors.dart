import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Error esperado de la app (sin permiso, código inválido…), con un mensaje
/// listo para mostrar. No tiene sentido reintentarlo.
abstract class AppFailure implements Exception {
  const AppFailure(this.mensaje);
  final String mensaje;

  @override
  String toString() => mensaje;
}

/// Política de reintentos de los providers. Riverpod 3 reintenta cualquier
/// excepción hasta 10 veces (~40 s mostrando "cargando"); acá los errores de
/// la app se muestran al toque y los de red se reintentan solo 3 veces.
Duration? reintentoProviders(int intento, Object error) {
  if (error is AppFailure) return null;
  return ProviderContainer.defaultRetry(intento, error, maxRetries: 3);
}
