import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/theme_mode.dart';
import '../../../core/widgets/auth_layout.dart';
import '../domain/profile.dart';
import '../domain/validators.dart';
import 'auth_providers.dart';
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
        title: const Text('Mi perfil'),
      ),
      body: perfil.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const Center(child: Text('No se pudo cargar tu perfil')),
        data: (p) => p == null
            ? const SizedBox.shrink()
            : Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      Center(child: UserAvatar(profile: p, radius: 40)),
                      const SizedBox(height: 16),
                      Text(p.nombre,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleLarge),
                      if (email != null)
                        Text(email,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium),
                      const SizedBox(height: 32),
                      Card(
                        child: Column(children: [
                          ListTile(
                            leading: const Icon(Icons.badge_outlined),
                            title: const Text('Nombre'),
                            subtitle: Text(p.nombre),
                            trailing: const Icon(Icons.edit_outlined),
                            onTap: () => _editarNombre(context, ref, p),
                          ),
                          const Divider(height: 1),
                          ListTile(
                            leading: const Icon(Icons.workspace_premium_outlined),
                            title: const Text('Plan'),
                            subtitle: Text(p.plan == Plan.premium ? 'Premium' : 'Gratis'),
                          ),
                        ]),
                      ),
                      const SizedBox(height: 16),
                      const _Tema(),
                      const SizedBox(height: 24),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.logout),
                        label: const Text('Cerrar sesión'),
                        onPressed: () => ref.read(authRepositoryProvider).signOut(),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Future<void> _editarNombre(BuildContext context, WidgetRef ref, Profile p) async {
    final nuevo = await showDialog<String>(
      context: context,
      builder: (_) => _EditarNombreDialog(inicial: p.nombre),
    );
    if (nuevo == null) return;
    await ref.read(currentProfileProvider.notifier).updateNombre(nuevo);
    if (context.mounted && ref.read(currentProfileProvider).hasError) {
      mostrarMensaje(context, 'No se pudo guardar el nombre', error: true);
    }
  }
}

class _Tema extends ConsumerWidget {
  const _Tema();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final modo = ref.watch(themeModeProvider);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Apariencia', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.brightness_auto_outlined), label: Text('Sistema')),
                ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode_outlined), label: Text('Claro')),
                ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode_outlined), label: Text('Oscuro')),
              ],
              selected: {modo},
              onSelectionChanged: (s) => ref.read(themeModeProvider.notifier).elegir(s.single),
            ),
          ),
        ]),
      ),
    );
  }
}

/// El diálogo es dueño de su controller: se libera recién cuando termina la
/// animación de cierre, no antes.
class _EditarNombreDialog extends StatefulWidget {
  const _EditarNombreDialog({required this.inicial});
  final String inicial;

  @override
  State<_EditarNombreDialog> createState() => _EditarNombreDialogState();
}

class _EditarNombreDialogState extends State<_EditarNombreDialog> {
  late final _controller = TextEditingController(text: widget.inicial);
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _guardar() {
    if (_formKey.currentState!.validate()) Navigator.pop(context, _controller.text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Cambiar nombre'),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _controller,
          autofocus: true,
          validator: Validators.nombre,
          onFieldSubmitted: (_) => _guardar(),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(88, 40)),
          onPressed: _guardar,
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
