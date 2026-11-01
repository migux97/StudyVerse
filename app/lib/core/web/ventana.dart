// Pestaña abierta "de antemano" para no chocar con el bloqueador de pop-ups.
//
// Safari (y a veces otros) bloquean window.open si no ocurre en el mismo
// instante del clic. Como la URL firmada se pide al servidor, se abre la
// pestaña vacía en el clic y después se la manda a la URL.
export 'ventana_stub.dart' if (dart.library.js_interop) 'ventana_web.dart';
