import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Avisos en vivo por canales privados de Realtime Broadcast.
///
/// La base manda un aviso sin datos ("cambió algo") y quien escucha vuelve a
/// leer con su RLS. Qué canales hay y quién puede escuchar cada uno está en la
/// migración `realtime_privado`. No se usa postgres_changes: Supabase no le
/// aplica la RLS a los borrados.
abstract final class Canales {
  static String archivos(String groupId) => 'grupo:$groupId:archivos';
  static String tareas(String groupId) => 'grupo:$groupId:tareas';
  static String actividad(String groupId) => 'grupo:$groupId:actividad';
  static String telegram(String groupId) => 'grupo:$groupId:telegram';
  static String misGrupos(String userId) => 'usuario:$userId:grupos';
  static String pedidos(String userId) => 'usuario:$userId:pedidos';
}

/// Emite el payload de cada aviso `evento` que llega a `canal`.
Stream<Map<String, dynamic>> escucharCanal(
  SupabaseClient client,
  String canal, {
  String evento = 'cambio',
}) {
  late final RealtimeChannel ch;
  final controller = StreamController<Map<String, dynamic>>.broadcast(
    onCancel: () => client.removeChannel(ch),
  );
  ch = client
      .channel(canal, opts: const RealtimeChannelConfig(private: true))
      .onBroadcast(
        event: evento,
        // Los mensajes que manda la base traen los datos dentro de 'payload'.
        callback: (m) => controller.add((m['payload'] as Map?)?.cast<String, dynamic>() ?? m),
      )
      .subscribe();
  return controller.stream;
}
