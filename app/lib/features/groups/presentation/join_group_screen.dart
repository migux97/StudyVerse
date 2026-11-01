import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../domain/groups_repository.dart';
import 'groups_providers.dart';

/// Destino de los links de invitación (`/unirse/CODIGO`): se une y abre el grupo.
class JoinGroupScreen extends ConsumerStatefulWidget {
  const JoinGroupScreen({super.key, required this.codigo});
  final String codigo;

  @override
  ConsumerState<JoinGroupScreen> createState() => _JoinGroupScreenState();
}

class _JoinGroupScreenState extends ConsumerState<JoinGroupScreen> {
  String? _error;

  @override
  void initState() {
    super.initState();
    _unirse();
  }

  Future<void> _unirse() async {
    try {
      final g = await ref.read(groupsRepositoryProvider).join(widget.codigo);
      ref.invalidate(myGroupsProvider);
      if (mounted) context.go(Routes.grupo(g.id));
    } on GroupFailure catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: _error == null
                ? const Column(mainAxisSize: MainAxisSize.min, children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Uniéndote al grupo…'),
                  ])
                : Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.link_off_rounded, size: 56, color: theme.colorScheme.error),
                    const SizedBox(height: 16),
                    Text(_error!, textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text(
                      'Pedile a alguien del grupo que te pase el código actualizado.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: () => context.go(Routes.grupos),
                      child: const Text('Ir a mis grupos'),
                    ),
                  ]),
          ),
        ),
      ),
    );
  }
}
