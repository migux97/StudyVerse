import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/notificaciones/domain/notificacion.dart';
import '../../features/notificaciones/presentation/notificaciones_providers.dart';
import '../config/env.dart';

/// Si las notificaciones push están activas en este dispositivo.
enum EstadoPush {
  /// Falta la configuración de Firebase: solo funciona la campanita.
  noConfigurado,

  /// Todavía no se pidió permiso (en la web hay que tocar un botón).
  sinPedir,
  activo,

  /// Se bloquearon en el navegador o en el sistema.
  bloqueado,
}

/// Push con Firebase Cloud Messaging. Todo es opcional: sin la configuración
/// (dart-defines FIREBASE_*), no hace nada.
///
/// Se usa el token de registro clásico (getToken/onTokenRefresh), que es lo
/// que acepta `messages:send` de la API HTTP v1 que usa la función
/// `enviar-push`. El register()/onRegistered nuevo devuelve un Firebase
/// Installation ID para otro modo de envío.
// ignore_for_file: deprecated_member_use
class Push {
  Push(this._ref);
  final Ref _ref;

  static bool _iniciado = false;
  StreamSubscription<String>? _renovacion;

  /// Se llama una vez al arrancar (en main), antes de runApp.
  static Future<void> iniciar() async {
    if (!Env.firebaseConfigurado || _iniciado) return;
    try {
      await Firebase.initializeApp(options: Env.firebaseOptions);
      _iniciado = true;
    } catch (e) {
      debugPrint('Firebase no arrancó: $e');
    }
  }

  bool get disponible => _iniciado;

  String get _plataforma => kIsWeb ? 'web' : 'android';

  Future<EstadoPush> estado() async {
    if (!_iniciado) return EstadoPush.noConfigurado;
    final s = await FirebaseMessaging.instance.getNotificationSettings();
    return switch (s.authorizationStatus) {
      AuthorizationStatus.authorized || AuthorizationStatus.provisional => EstadoPush.activo,
      AuthorizationStatus.denied || AuthorizationStatus.deniedPermanently => EstadoPush.bloqueado,
      AuthorizationStatus.notDetermined => EstadoPush.sinPedir,
    };
  }

  /// Pide permiso (en la web, desde un toque del usuario) y registra el
  /// dispositivo para mi cuenta.
  Future<EstadoPush> activar() async {
    if (!_iniciado) return EstadoPush.noConfigurado;
    final s = await FirebaseMessaging.instance.requestPermission();
    if (s.authorizationStatus case AuthorizationStatus.denied || AuthorizationStatus.deniedPermanently) {
      return EstadoPush.bloqueado;
    }
    if (s.authorizationStatus == AuthorizationStatus.notDetermined) return EstadoPush.sinPedir;
    await registrar();
    return EstadoPush.activo;
  }

  /// Si ya hay permiso, asegura que este dispositivo esté registrado (al
  /// entrar). No pide nada.
  Future<void> registrarSiHayPermiso() async {
    if (await estado() == EstadoPush.activo) await registrar();
  }

  Future<void> registrar() async {
    final token = await FirebaseMessaging.instance.getToken(vapidKey: kIsWeb ? Env.firebaseVapidKey : null);
    if (token == null) return;
    final repo = _ref.read(notificacionesRepositoryProvider);
    await repo.registrarDispositivo(token, _plataforma);
    await _renovacion?.cancel();
    _renovacion = FirebaseMessaging.instance.onTokenRefresh.listen(
      (nuevo) => repo.registrarDispositivo(nuevo, _plataforma).catchError((_) {}),
    );
  }

  /// Al entrar en Android: pide permiso la primera vez y después solo
  /// registra (si dijo que no o cerró el diálogo, no se vuelve a pedir: queda
  /// la tarjeta de la campanita).
  Future<void> alEntrar({required bool yaSePidio, required Future<void> Function() marcarPedido}) async {
    if (!_iniciado) return;
    if (kIsWeb || yaSePidio) {
      await registrarSiHayPermiso();
      return;
    }
    await marcarPedido();
    await activar();
  }

  /// Antes de cerrar sesión: este dispositivo deja de recibir mis push. Con
  /// tope de tiempo: sin conexión, cerrar sesión no se queda esperando.
  Future<void> alCerrarSesion() async {
    if (!_iniciado) return;
    await _quitar().timeout(const Duration(seconds: 3), onTimeout: () {});
  }

  Future<void> _quitar() async {
    try {
      await _renovacion?.cancel();
      final token = await FirebaseMessaging.instance.getToken(vapidKey: kIsWeb ? Env.firebaseVapidKey : null);
      if (token != null) await _ref.read(notificacionesRepositoryProvider).quitarDispositivo(token);
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {
      // Sin conexión: el token viejo se borra solo cuando FCM lo dé por muerto.
    }
  }

  /// Pantallas a abrir cuando se toca una notificación (con la app cerrada o
  /// en segundo plano).
  Stream<String> get rutasTocadas async* {
    if (!_iniciado) return;
    final inicial = await FirebaseMessaging.instance.getInitialMessage();
    if (inicial?.data['ruta'] case final String r when rutaValida(r)) yield r;
    yield* FirebaseMessaging.onMessageOpenedApp
        .map((m) => m.data['ruta'])
        .where((r) => r is String && rutaValida(r))
        .cast<String>();
  }
}

final pushProvider = Provider<Push>(Push.new);

final estadoPushProvider = FutureProvider.autoDispose<EstadoPush>((ref) => ref.watch(pushProvider).estado());
