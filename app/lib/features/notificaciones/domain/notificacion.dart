import 'package:flutter/material.dart';

import '../../../core/errors.dart';

class NotificacionesFailure extends AppFailure {
  const NotificacionesFailure(super.mensaje);
}

enum TipoNotificacion {
  mencion(Icons.alternate_email),
  aviso(Icons.campaign_outlined),
  devolucion(Icons.rate_review_outlined),
  revision(Icons.task_alt),
  pedido(Icons.front_hand_outlined),
  tareaAsignada(Icons.assignment_ind_outlined);

  const TipoNotificacion(this.icono);
  final IconData icono;

  static TipoNotificacion desde(String v) =>
      v == 'tarea_asignada' ? tareaAsignada : TipoNotificacion.values.byName(v);
}

/// Una notificación del centro de notificaciones (la campanita).
class Notificacion {
  const Notificacion({
    required this.id,
    required this.tipo,
    required this.titulo,
    this.cuerpo,
    required this.ruta,
    required this.createdAt,
    this.leidaAt,
  });

  final String id;
  final TipoNotificacion tipo;
  final String titulo;
  final String? cuerpo;

  /// Pantalla que abre (ruta de go_router).
  final String ruta;
  final DateTime createdAt;
  final DateTime? leidaAt;

  bool get leida => leidaAt != null;

  factory Notificacion.fromMap(Map<String, dynamic> m) => Notificacion(
        id: m['id'] as String,
        tipo: TipoNotificacion.desde(m['tipo'] as String),
        titulo: m['titulo'] as String,
        cuerpo: m['cuerpo'] as String?,
        ruta: m['ruta'] as String,
        createdAt: DateTime.parse(m['created_at'] as String),
        leidaAt: m['leida_at'] == null ? null : DateTime.parse(m['leida_at'] as String),
      );
}

/// Solo rutas internas de la app (las pone la base, pero por las dudas).
bool rutaValida(String ruta) => RegExp(r'^/[A-Za-z0-9/_-]*$').hasMatch(ruta);

abstract interface class NotificacionesRepository {
  Future<List<Notificacion>> recientes({int limite = 50});
  Future<int> sinLeer();
  Future<void> marcarLeida(String id);
  Future<void> marcarTodas();

  /// Emite cuando llega una notificación nueva.
  Stream<void> cambios(String miId);

  /// Este dispositivo recibe (o deja de recibir) mis push.
  Future<void> registrarDispositivo(String token, String plataforma);
  Future<void> quitarDispositivo(String token);
}
