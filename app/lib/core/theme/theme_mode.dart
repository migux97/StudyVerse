import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Preferencias del dispositivo. Se carga en main() antes de arrancar; si no
/// se pudo (modo privado del navegador), queda null y se usan los valores por defecto.
final sharedPreferencesProvider = Provider<SharedPreferences?>((ref) => null);

const _clave = 'tema';

/// Tema elegido por el usuario: sistema (por defecto), claro u oscuro.
class ThemeModeController extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    final guardado = ref.watch(sharedPreferencesProvider)?.getString(_clave);
    return ThemeMode.values.asNameMap()[guardado] ?? ThemeMode.system;
  }

  Future<void> elegir(ThemeMode modo) async {
    state = modo;
    try {
      await ref.read(sharedPreferencesProvider)?.setString(_clave, modo.name);
    } catch (_) {
      // Si no se puede guardar, el cambio vale igual para esta sesión.
    }
  }
}

final themeModeProvider = NotifierProvider<ThemeModeController, ThemeMode>(ThemeModeController.new);
