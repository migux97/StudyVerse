import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Detecta cuando el alumno sale de la pantalla mientras rinde.
///
/// - Celular: la app pasa a segundo plano (otra app, inicio, bloquear la
///   pantalla). "inactive" solo (bajar la cortina de notificaciones, un
///   diálogo del sistema) no cuenta.
/// - Web: cambiar de pestaña o minimizar cuenta en el acto; que la ventana
///   pierda el foco (otra ventana u otro programa) cuenta si dura más de
///   [gracia], para no contar un clic en la barra de direcciones.
///
/// Avisa una sola vez por salida: [alSalir] al irse y [alVolver] con el tiempo
/// que estuvo afuera.
class DetectorSalidas {
  DetectorSalidas({
    required this.alSalir,
    required this.alVolver,
    bool? esWeb,
    this.gracia = const Duration(seconds: 2),
    DateTime Function()? reloj,
    Timer Function(Duration, void Function())? crearTimer,
  })  : esWeb = esWeb ?? kIsWeb,
        _reloj = reloj ?? DateTime.now,
        _crearTimer = crearTimer ?? Timer.new;

  final VoidCallback alSalir;
  final void Function(Duration afuera) alVolver;
  final bool esWeb;
  final Duration gracia;
  final DateTime Function() _reloj;
  final Timer Function(Duration, void Function()) _crearTimer;

  DateTime? _afueraDesde;
  DateTime? _inactivaDesde;
  Timer? _espera;

  bool get afuera => _afueraDesde != null;

  void cambio(AppLifecycleState estado) {
    switch (estado) {
      case AppLifecycleState.resumed:
        _espera?.cancel();
        _espera = null;
        _inactivaDesde = null;
        if (_afueraDesde case final desde?) {
          _afueraDesde = null;
          alVolver(_reloj().difference(desde));
        }
      case AppLifecycleState.inactive:
        if (!esWeb || afuera || _espera != null) return;
        _inactivaDesde = _reloj();
        _espera = _crearTimer(gracia, () {
          _espera = null;
          if (_inactivaDesde case final desde?) _salir(desde);
        });
      case AppLifecycleState.hidden || AppLifecycleState.paused || AppLifecycleState.detached:
        _salir(_inactivaDesde ?? _reloj());
    }
  }

  void _salir(DateTime desde) {
    _espera?.cancel();
    _espera = null;
    _inactivaDesde = null;
    if (afuera) return;
    _afueraDesde = desde;
    alSalir();
  }

  void dispose() => _espera?.cancel();
}
