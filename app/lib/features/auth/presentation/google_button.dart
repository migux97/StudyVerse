import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../core/config/env.dart';
import '../../../core/widgets/auth_layout.dart';
import '../domain/auth_repository.dart';
import 'auth_providers.dart';

/// Si el servidor tiene configurado el login con Google. Sin credenciales, el
/// botón no se muestra (si no, Google mostraría su página de error).
final googleDisponibleProvider = FutureProvider<bool>((ref) async {
  try {
    final r = await http.get(
      Uri.parse('${Env.resolvedSupabaseUrl}/auth/v1/settings'),
      headers: {'apikey': Env.supabasePublishableKey},
    ).timeout(const Duration(seconds: 8));
    if (r.statusCode != 200) return false;
    final settings = jsonDecode(r.body) as Map<String, dynamic>;
    return (settings['external'] as Map<String, dynamic>?)?['google'] == true;
  } on Exception {
    return false;
  }
});

/// "Continuar con Google", con el logo de Google. Incluye su espacio de
/// arriba, así no queda un hueco cuando no está disponible.
class GoogleButton extends ConsumerStatefulWidget {
  const GoogleButton({super.key, this.espacioArriba = 12});
  final double espacioArriba;

  @override
  ConsumerState<GoogleButton> createState() => _GoogleButtonState();
}

class _GoogleButtonState extends ConsumerState<GoogleButton> {
  bool _yendo = false;

  Future<void> _entrar() async {
    setState(() => _yendo = true);
    try {
      await ref.read(authRepositoryProvider).signInWithGoogle();
    } on AuthFailure catch (e) {
      if (mounted) mostrarMensaje(context, e.mensaje, error: true);
    } finally {
      // En la web la página se va a Google; si vuelve sin entrar, se habilita.
      if (mounted) setState(() => _yendo = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(googleDisponibleProvider).value != true) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.only(top: widget.espacioArriba),
      child: OutlinedButton.icon(
        icon: _yendo
            ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : const SizedBox.square(dimension: 18, child: CustomPaint(painter: _LogoGoogle())),
        label: const Text('Continuar con Google'),
        onPressed: _yendo ? null : _entrar,
      ),
    );
  }
}

/// La "G" de Google en sus cuatro colores.
class _LogoGoogle extends CustomPainter {
  const _LogoGoogle();

  static const _azul = Color(0xFF4285F4);
  static const _verde = Color(0xFF34A853);
  static const _amarillo = Color(0xFFFBBC05);
  static const _rojo = Color(0xFFEA4335);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final grosor = s * 0.2;
    final rect = Rect.fromCircle(center: size.center(Offset.zero), radius: (s - grosor) / 2);
    final pincel = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = grosor;
    double g(double grados) => grados * math.pi / 180;

    // Ángulos en sentido horario desde las 3 en punto.
    canvas.drawArc(rect, g(-40), g(-100), false, pincel..color = _rojo);
    canvas.drawArc(rect, g(-140), g(-90), false, pincel..color = _amarillo);
    canvas.drawArc(rect, g(130), g(-95), false, pincel..color = _verde);
    canvas.drawArc(rect, g(0), g(35), false, pincel..color = _azul);
    // La barra horizontal de la G.
    canvas.drawRect(
      Rect.fromLTRB(size.center(Offset.zero).dx, rect.center.dy - grosor / 2, rect.right + grosor / 2,
          rect.center.dy + grosor / 2),
      Paint()..color = _azul,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
