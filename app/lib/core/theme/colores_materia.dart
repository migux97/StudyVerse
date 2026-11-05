import 'package:flutter/material.dart';

/// Los 8 colores de materia (como los de las carpetas de Drive), con una
/// versión más clara para el modo oscuro.
const coloresMateria = <({String nombre, Color claro, Color oscuro})>[
  (nombre: 'Azul', claro: Color(0xFF1A73E8), oscuro: Color(0xFF8AB4F8)),
  (nombre: 'Verde', claro: Color(0xFF188038), oscuro: Color(0xFF81C995)),
  (nombre: 'Naranja', claro: Color(0xFFE8710A), oscuro: Color(0xFFFCAD70)),
  (nombre: 'Violeta', claro: Color(0xFF9334E6), oscuro: Color(0xFFC58AF9)),
  (nombre: 'Rojo', claro: Color(0xFFD93025), oscuro: Color(0xFFF28B82)),
  (nombre: 'Turquesa', claro: Color(0xFF129EAF), oscuro: Color(0xFF78D9EC)),
  (nombre: 'Rosa', claro: Color(0xFFD01884), oscuro: Color(0xFFFF8BCB)),
  (nombre: 'Marrón', claro: Color(0xFF795548), oscuro: Color(0xFFBCAAA4)),
];

/// Color de una materia (0 a 7) según el tema.
Color colorMateria(BuildContext context, int? color) {
  final c = coloresMateria[(color ?? 0).clamp(0, coloresMateria.length - 1)];
  return Theme.of(context).brightness == Brightness.dark ? c.oscuro : c.claro;
}
