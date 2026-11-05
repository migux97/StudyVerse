import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/theme_mode.dart';
import '../../../core/widgets/auth_layout.dart';
import '../../../core/widgets/text_input_dialog.dart';
import '../domain/auth_repository.dart';
import '../domain/cuenta.dart';
import '../domain/profile.dart';
import '../domain/validators.dart';
import 'auth_providers.dart';
import 'campos.dart';
import 'user_avatar.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final perfil = ref.watch(currentProfileProvider);
    final email = ref.watch(authStateProvider).value?.email;

    return Scaffold(
      appBar: AppBar(
        // Si se entró directo por URL no hay a dónde volver: va a "Mis grupos".
        leading: BackButton(
          onPressed: () => context.canPop() ? context.pop() : context.go(Routes.grupos),
        ),
        title: const Text('Tu cuenta'),
      ),
      body: perfil.when(
        skipLoadingOnReload: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const Center(child: Text('No pudimos cargar tu perfil')),
        data: (p) => p == null
            ? const SizedBox.shrink()
            : Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                    children: [
                      _Encabezado(perfil: p, email: email),
                      const SizedBox(height: 24),
                      _Seccion(titulo: 'Tus datos', children: [
                        _Dato(
                          icono: Icons.badge_outlined,
                          titulo: 'Nombre',
                          valor: p.nombre,
                          onTap: () => _editar(context, ref,
                              titulo: 'Tu nombre',
                              etiqueta: 'Nombre y apellido',
                              inicial: p.nombre,
                              ejemplo: 'Ana García',
                              maximo: 80,
                              validator: Validators.nombre,
                              cambios: (v) => CambiosPerfil(nombre: v)),
                        ),
                        _Dato(
                          icono: Icons.alternate_email,
                          titulo: 'Nombre de usuario',
                          valor: p.username == null ? null : '@${p.username}',
                          onTap: () => _editarUsuario(context, ref, p),
                        ),
                        _Dato(
                          icono: Icons.school_outlined,
                          titulo: 'Carrera',
                          valor: p.carrera,
                          vacio: 'Agregá tu carrera',
                          onTap: () => _editar(context, ref,
                              titulo: 'Tu carrera',
                              etiqueta: 'Carrera',
                              inicial: p.carrera,
                              ejemplo: 'Ej.: Ingeniería en Sistemas',
                              maximo: 80,
                              validator: Validators.opcional,
                              cambios: (v) => CambiosPerfil(carrera: v)),
                        ),
                        _Dato(
                          icono: Icons.account_balance_outlined,
                          titulo: 'Universidad',
                          valor: p.universidad,
                          vacio: 'Agregá tu universidad',
                          onTap: () => _editar(context, ref,
                              titulo: 'Tu universidad',
                              etiqueta: 'Universidad o instituto',
                              inicial: p.universidad,
                              ejemplo: 'Ej.: UTN FRBA',
                              maximo: 80,
                              validator: Validators.opcional,
                              cambios: (v) => CambiosPerfil(universidad: v)),
                        ),
                      ]),
                      const SizedBox(height: 16),
                      _Seccion(titulo: 'Seguridad', children: [
                        _Dato(
                          icono: Icons.lock_outline,
                          titulo: 'Contraseña',
                          valor: 'Cambiala cuando quieras',
                          onTap: () => _cambiarContrasena(context, ref),
                        ),
                        _Dato(
                          icono: Icons.devices_outlined,
                          titulo: 'Dispositivos conectados',
                          valor: 'Dónde está abierta tu cuenta',
                          onTap: () => context.push(Routes.dispositivos),
                        ),
                        const _CuentasConectadas(),
                      ]),
                      const SizedBox(height: 16),
                      const _Tema(),
                      const SizedBox(height: 16),
                      _Seccion(titulo: 'Plan', children: [
                        _Dato(
                          icono: Icons.workspace_premium_outlined,
                          titulo: p.plan == Plan.premium ? 'Premium' : 'Gratis',
                          valor: p.plan == Plan.premium
                              ? 'Más espacio e historial completo'
                              : '500 MB por grupo y las últimas 3 versiones',
                        ),
                      ]),
                      const SizedBox(height: 24),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.logout),
                          label: const Text('Cerrar sesión'),
                          onPressed: () => ref.read(authRepositoryProvider).signOut(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Future<void> _editar(
    BuildContext context,
    WidgetRef ref, {
    required String titulo,
    required String etiqueta,
    String? inicial,
    String? ejemplo,
    int? maximo,
    required String? Function(String?) validator,
    required CambiosPerfil Function(String) cambios,
  }) async {
    final nuevo = await pedirTexto(context,
        titulo: titulo,
        etiqueta: etiqueta,
        accion: 'Guardar',
        inicial: inicial,
        ejemplo: ejemplo,
        maximo: maximo,
        validator: validator);
    if (nuevo == null || nuevo == (inicial ?? '') || !context.mounted) return;
    final error = await ref.read(currentProfileProvider.notifier).actualizar(cambios(nuevo));
    if (context.mounted) mostrarMensaje(context, error ?? 'Guardado', error: error != null);
  }

  Future<void> _editarUsuario(BuildContext context, WidgetRef ref, Profile p) async {
    final nuevo = await showDialog<String>(
      context: context,
      builder: (_) => _UsuarioDialog(actual: p.username),
    );
    if (nuevo == null || nuevo == p.username || !context.mounted) return;
    final error = await ref.read(currentProfileProvider.notifier).actualizar(CambiosPerfil(username: nuevo));
    if (context.mounted) mostrarMensaje(context, error ?? 'Ahora sos @$nuevo', error: error != null);
  }

  Future<void> _cambiarContrasena(BuildContext context, WidgetRef ref) async {
    final nueva = await showDialog<String>(context: context, builder: (_) => const _ContrasenaDialog());
    if (nueva == null || !context.mounted) return;
    final repo = ref.read(authRepositoryProvider);
    try {
      try {
        await repo.cambiarPassword(nueva);
      } on AuthFailure catch (e) {
        if (e.codigo != 'reauthentication_needed') rethrow;
        // Hace rato que entraste: como en Google, primero confirmás que sos vos.
        await repo.pedirCodigoParaCambiarPassword();
        if (!context.mounted) return;
        final codigo = await pedirTexto(
          context,
          titulo: 'Confirmá que sos vos',
          etiqueta: 'Código de 6 números',
          ayuda: 'Te lo mandamos por mail. Si no lo ves, revisá la carpeta de spam',
          accion: 'Confirmar',
          teclado: TextInputType.number,
          maximo: 6,
          formatos: [FilteringTextInputFormatter.digitsOnly],
          validator: Validators.codigo,
        );
        if (codigo == null) return;
        await repo.cambiarPassword(nueva, codigo: codigo.replaceAll(' ', ''));
      }
      if (context.mounted) {
        mostrarMensaje(context, 'Contraseña cambiada. Cerramos la sesión en tus otros dispositivos');
      }
    } on AuthFailure catch (e) {
      if (context.mounted) mostrarMensaje(context, e.mensaje, error: true);
    }
  }
}

class _Encabezado extends ConsumerWidget {
  const _Encabezado({required this.perfil, this.email});
  final Profile perfil;
  final String? email;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(children: [
      const SizedBox(height: 8),
      Stack(clipBehavior: Clip.none, children: [
        Tooltip(
          message: 'Cambiar foto',
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () => _opcionesFoto(context, ref),
            child: UserAvatar(profile: perfil, radius: 48),
          ),
        ),
        // Solo indica que la foto se toca; el toque lo recibe el avatar.
        Positioned(
          right: -2,
          bottom: -2,
          child: IgnorePointer(
            child: Material(
              color: scheme.surfaceContainerLowest,
              shape: CircleBorder(side: BorderSide(color: scheme.outlineVariant)),
              child: Padding(
                padding: const EdgeInsets.all(7),
                child: Icon(Icons.photo_camera_outlined, size: 18, color: scheme.primary),
              ),
            ),
          ),
        ),
      ]),
      const SizedBox(height: 16),
      Text(perfil.nombre, textAlign: TextAlign.center, style: theme.textTheme.titleLarge),
      const SizedBox(height: 2),
      Text(
        [if (perfil.username != null) '@${perfil.username}', if (email != null) email].join(' · '),
        textAlign: TextAlign.center,
        style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
      ),
      if (perfil.estudios != null) ...[
        const SizedBox(height: 2),
        Text(perfil.estudios!,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
      ],
    ]);
  }

  Future<void> _opcionesFoto(BuildContext context, WidgetRef ref) async {
    final accion = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Elegir una foto'),
            onTap: () => Navigator.pop(ctx, 'elegir'),
          ),
          if (perfil.avatarUrl != null)
            ListTile(
              leading: const Icon(Icons.hide_image_outlined),
              title: const Text('Quitar la foto'),
              onTap: () => Navigator.pop(ctx, 'quitar'),
            ),
        ]),
      ),
    );
    if (accion == null || !context.mounted) return;
    final perfilNotifier = ref.read(currentProfileProvider.notifier);
    if (accion == 'quitar') {
      final error = await perfilNotifier.quitarFoto();
      if (context.mounted) mostrarMensaje(context, error ?? 'Quitamos tu foto', error: error != null);
      return;
    }
    final Uint8List bytes;
    try {
      final elegida = await FilePicker.pickFile(dialogTitle: 'Elegí tu foto', type: FileType.image);
      if (elegida == null) return;
      bytes = await elegida.readAsBytes();
    } catch (_) {
      if (context.mounted) mostrarMensaje(context, 'No pudimos abrir tus fotos', error: true);
      return;
    }
    if (!context.mounted) return;
    mostrarMensaje(context, 'Subiendo tu foto…');
    final error = await perfilNotifier.subirFoto(bytes);
    if (context.mounted) mostrarMensaje(context, error ?? 'Listo, ya tenés foto nueva', error: error != null);
  }
}

class _Seccion extends StatelessWidget {
  const _Seccion({required this.titulo, required this.children});
  final String titulo;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
        child: Text(titulo, style: Theme.of(context).textTheme.titleSmall),
      ),
      Card(
        child: Column(children: [
          for (final (i, c) in children.indexed) ...[
            if (i > 0) const Divider(height: 1, indent: 56),
            c,
          ],
        ]),
      ),
    ]);
  }
}

class _Dato extends StatelessWidget {
  const _Dato({required this.icono, required this.titulo, this.valor, this.vacio, this.onTap});
  final IconData icono;
  final String titulo;
  final String? valor;
  final String? vacio;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sinValor = valor == null || valor!.isEmpty;
    return ListTile(
      leading: Icon(icono),
      title: Text(titulo),
      subtitle: Text(sinValor ? (vacio ?? '—') : valor!,
          style: sinValor && vacio != null ? TextStyle(color: scheme.primary) : null),
      trailing: onTap == null ? null : const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

class _CuentasConectadas extends ConsumerWidget {
  const _CuentasConectadas();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final estado = ref.watch(cuentasVinculadasProvider);
    if (!estado.hasValue) {
      return ListTile(
        leading: const Icon(Icons.link),
        title: const Text('Google'),
        subtitle: Text(estado.hasError ? 'No pudimos ver tus cuentas conectadas' : 'Cargando…'),
        trailing: estado.hasError
            ? TextButton(
                onPressed: () => ref.invalidate(cuentasVinculadasProvider), child: const Text('Reintentar'))
            : null,
      );
    }
    final cuentas = estado.requireValue;
    final google = cuentas.where((c) => c.proveedor == 'google').firstOrNull;
    return ListTile(
      leading: const Icon(Icons.link),
      title: const Text('Google'),
      subtitle: Text(google == null
          ? 'Conectala para entrar con un toque'
          : 'Conectada${google.email == null ? '' : ' · ${google.email}'}'),
      trailing: google == null
          ? TextButton(onPressed: () => _conectar(context, ref), child: const Text('Conectar'))
          : cuentas.length > 1
              ? TextButton(onPressed: () => _desconectar(context, ref, google), child: const Text('Desconectar'))
              : null,
    );
  }

  Future<void> _conectar(BuildContext context, WidgetRef ref) async {
    try {
      // Abre Google; al volver, la cuenta queda conectada.
      await ref.read(authRepositoryProvider).vincularGoogle();
    } on AuthFailure catch (e) {
      if (context.mounted) mostrarMensaje(context, e.mensaje, error: true);
    }
  }

  Future<void> _desconectar(BuildContext context, WidgetRef ref, CuentaVinculada c) async {
    try {
      await ref.read(authRepositoryProvider).desvincular(c.id);
      if (!context.mounted) return;
      ref.invalidate(cuentasVinculadasProvider);
      mostrarMensaje(context, 'Desconectamos tu cuenta de Google');
    } on AuthFailure catch (e) {
      if (context.mounted) mostrarMensaje(context, e.mensaje, error: true);
    }
  }
}

class _Tema extends ConsumerWidget {
  const _Tema();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final modo = ref.watch(themeModeProvider);
    return _Seccion(titulo: 'Apariencia', children: [
      Padding(
        padding: const EdgeInsets.all(16),
        child: SizedBox(
          width: double.infinity,
          child: SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.brightness_auto_outlined), label: Text('Sistema')),
              ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode_outlined), label: Text('Claro')),
              ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode_outlined), label: Text('Oscuro')),
            ],
            selected: {modo},
            // Sin el tilde extra entra bien en un celular de 360 px.
            showSelectedIcon: false,
            onSelectionChanged: (s) => ref.read(themeModeProvider.notifier).elegir(s.single),
          ),
        ),
      ),
    ]);
  }
}

/// Cambiar el usuario, avisando en vivo si está libre.
class _UsuarioDialog extends StatefulWidget {
  const _UsuarioDialog({this.actual});
  final String? actual;

  @override
  State<_UsuarioDialog> createState() => _UsuarioDialogState();
}

class _UsuarioDialogState extends State<_UsuarioDialog> {
  late final _controller = TextEditingController(text: widget.actual);
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Tu nombre de usuario'),
      content: SizedBox(
        width: 400,
        child: Form(key: _formKey, child: CampoUsuario(controller: _controller, actual: widget.actual)),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(88, 40)),
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              Navigator.pop(context, _controller.text.trim().toLowerCase());
            }
          },
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

class _ContrasenaDialog extends StatefulWidget {
  const _ContrasenaDialog();

  @override
  State<_ContrasenaDialog> createState() => _ContrasenaDialogState();
}

class _ContrasenaDialogState extends State<_ContrasenaDialog> {
  final _nueva = TextEditingController();
  final _repetir = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _nueva.dispose();
    _repetir.dispose();
    super.dispose();
  }

  void _ok() {
    if (_formKey.currentState!.validate()) Navigator.pop(context, _nueva.text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Cambiar contraseña'),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            CampoContrasena(
              controller: _nueva,
              etiqueta: 'Contraseña nueva',
              nueva: true,
              textInputAction: TextInputAction.next,
              validator: Validators.password,
            ),
            RequisitosContrasena(controller: _nueva),
            const SizedBox(height: 16),
            CampoContrasena(
              controller: _repetir,
              etiqueta: 'Confirmá la contraseña',
              nueva: true,
              onSubmitted: (_) => _ok(),
              validator: Validators.confirmarPassword(() => _nueva.text),
            ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(88, 40)),
          onPressed: _ok,
          child: const Text('Cambiar'),
        ),
      ],
    );
  }
}
