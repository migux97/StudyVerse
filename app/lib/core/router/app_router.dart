import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/auth_providers.dart';
import '../../features/auth/presentation/forgot_password_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/profile_screen.dart';
import '../../features/auth/presentation/register_screen.dart';
import '../../features/activity/presentation/activity_screen.dart';
import '../../features/groups/presentation/group_screen.dart';
import '../../features/groups/presentation/groups_screen.dart';
import '../../features/groups/presentation/join_group_screen.dart';
import '../../features/groups/presentation/members_screen.dart';
import '../../features/tasks/presentation/contributions_screen.dart';
import '../../features/tasks/presentation/tasks_screen.dart';

class Routes {
  static const login = '/login';
  static const registro = '/registro';
  static const recuperar = '/recuperar';
  static const grupos = '/';
  static const perfil = '/perfil';

  static String grupo(String id) => '/grupos/$id';
  static String miembros(String id) => '/grupos/$id/miembros';
  static String carpeta(String grupoId, String carpetaId) => '/grupos/$grupoId/carpetas/$carpetaId';
  static String tareas(String id) => '/grupos/$id/tareas';
  static String actividad(String id) => '/grupos/$id/actividad';
  static String aportes(String id) => '/grupos/$id/aportes';
  static String unirse(String codigo) => '/unirse/$codigo';

  static const publicas = {login, registro, recuperar};

  /// Agrega `?from=` para volver a donde se quería ir después del login.
  static String conDestino(String ruta, String? from) =>
      from == null ? ruta : '$ruta?from=${Uri.encodeComponent(from)}';
}

/// Decide a dónde redirigir según haya sesión o no. `null` = quedarse.
/// `from` es la ruta a la que se quería ir antes de pedir el login.
String? authRedirect({required bool loggedIn, required String location, String? from}) {
  final esPublica = Routes.publicas.contains(location);
  if (!loggedIn && !esPublica) {
    return Routes.conDestino(Routes.login, location == Routes.grupos ? null : location);
  }
  if (loggedIn && esPublica) {
    // Solo rutas internas, para no redirigir a otro sitio.
    final destinoSeguro = from != null && from.startsWith('/') && !from.startsWith('//');
    return destinoSeguro ? from : Routes.grupos;
  }
  return null;
}

final routerProvider = Provider<GoRouter>((ref) {
  final repo = ref.watch(authRepositoryProvider);
  final refresh = _StreamListenable(repo.authStateChanges());
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: Routes.grupos,
    refreshListenable: refresh,
    redirect: (context, state) => authRedirect(
      loggedIn: repo.currentUser != null,
      location: state.matchedLocation,
      from: state.uri.queryParameters['from'],
    ),
    routes: [
      GoRoute(path: Routes.login, builder: (_, _) => const LoginScreen()),
      GoRoute(path: Routes.registro, builder: (_, _) => const RegisterScreen()),
      GoRoute(path: Routes.recuperar, builder: (_, _) => const ForgotPasswordScreen()),
      GoRoute(path: Routes.grupos, builder: (_, _) => const GroupsScreen()),
      GoRoute(path: Routes.perfil, builder: (_, _) => const ProfileScreen()),
      GoRoute(
        path: '/grupos/:id',
        builder: (_, s) => GroupScreen(groupId: s.pathParameters['id']!),
        routes: [
          GoRoute(
            path: 'miembros',
            builder: (_, s) => MembersScreen(groupId: s.pathParameters['id']!),
          ),
          // Secciones del grupo: sin animación al cambiar de pestaña.
          GoRoute(
            path: 'tareas',
            pageBuilder: (_, s) => NoTransitionPage(child: TasksScreen(groupId: s.pathParameters['id']!)),
          ),
          GoRoute(
            path: 'actividad',
            pageBuilder: (_, s) => NoTransitionPage(child: ActivityScreen(groupId: s.pathParameters['id']!)),
          ),
          GoRoute(
            path: 'aportes',
            pageBuilder: (_, s) =>
                NoTransitionPage(child: ContributionsScreen(groupId: s.pathParameters['id']!)),
          ),
          GoRoute(
            path: 'carpetas/:folderId',
            // Sin animación entre carpetas, como un explorador.
            pageBuilder: (_, s) => NoTransitionPage(
              child: GroupScreen(
                groupId: s.pathParameters['id']!,
                folderId: s.pathParameters['folderId'],
              ),
            ),
          ),
        ],
      ),
      GoRoute(
        path: '/unirse/:codigo',
        builder: (_, s) => JoinGroupScreen(codigo: s.pathParameters['codigo']!),
      ),
    ],
  );
});

class _StreamListenable extends ChangeNotifier {
  _StreamListenable(Stream<Object?> stream) {
    _sub = stream.listen((_) => notifyListeners());
  }
  late final StreamSubscription<Object?> _sub;

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
