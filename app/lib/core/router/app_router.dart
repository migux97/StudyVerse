import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/auth_providers.dart';
import '../../features/auth/presentation/forgot_password_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/profile_screen.dart';
import '../../features/auth/presentation/register_screen.dart';
import '../../features/groups/presentation/groups_screen.dart';

class Routes {
  static const login = '/login';
  static const registro = '/registro';
  static const recuperar = '/recuperar';
  static const grupos = '/';
  static const perfil = '/perfil';

  static const publicas = {login, registro, recuperar};
}

/// Decide a dónde redirigir según haya sesión o no. `null` = quedarse.
String? authRedirect({required bool loggedIn, required String location}) {
  final esPublica = Routes.publicas.contains(location);
  if (!loggedIn && !esPublica) return Routes.login;
  if (loggedIn && esPublica) return Routes.grupos;
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
    ),
    routes: [
      GoRoute(path: Routes.login, builder: (_, _) => const LoginScreen()),
      GoRoute(path: Routes.registro, builder: (_, _) => const RegisterScreen()),
      GoRoute(path: Routes.recuperar, builder: (_, _) => const ForgotPasswordScreen()),
      GoRoute(path: Routes.grupos, builder: (_, _) => const GroupsScreen()),
      GoRoute(path: Routes.perfil, builder: (_, _) => const ProfileScreen()),
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
