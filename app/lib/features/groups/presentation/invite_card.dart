import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/env.dart';
import '../../../core/widgets/auth_layout.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../domain/group.dart';
import '../domain/groups_repository.dart';
import '../domain/invite.dart';
import 'groups_providers.dart';

/// Código de invitación con acciones para copiar el código o el link.
class InviteCard extends ConsumerWidget {
  const InviteCard({super.key, required this.grupo});
  final Group grupo;

  Future<void> _copiar(BuildContext context, String texto, String aviso) async {
    await Clipboard.setData(ClipboardData(text: texto));
    if (context.mounted) mostrarMensaje(context, aviso);
  }

  Future<void> _regenerar(BuildContext context, WidgetRef ref) async {
    final ok = await confirmar(
      context,
      titulo: '¿Generar un código nuevo?',
      mensaje: 'El código y el link actuales van a dejar de funcionar. '
          'Los integrantes que ya están en el grupo no se ven afectados.',
      accion: 'Generar',
    );
    if (!ok || !context.mounted) return;
    try {
      await ref.read(groupsRepositoryProvider).regenerateInviteCode(grupo.id);
      ref.invalidate(groupProvider(grupo.id));
      if (context.mounted) mostrarMensaje(context, 'Listo, hay un código nuevo');
    } on GroupFailure catch (e) {
      if (context.mounted) mostrarMensaje(context, e.mensaje, error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final link = Invite.link(Env.webUrl, grupo.inviteCode);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Invitar al grupo', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Pasales este código o el link a tus compañeros.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            SelectableText(
              Invite.formatear(grupo.inviteCode),
              style: theme.textTheme.headlineMedium?.copyWith(
                fontFamily: 'monospace',
                letterSpacing: 4,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton.tonalIcon(
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: const Text('Copiar código'),
                onPressed: () => _copiar(context, Invite.formatear(grupo.inviteCode), 'Código copiado'),
              ),
              FilledButton.tonalIcon(
                icon: const Icon(Icons.link_rounded, size: 18),
                label: const Text('Copiar link'),
                onPressed: () => _copiar(context, link, 'Link copiado'),
              ),
              if (grupo.soyAdmin)
                TextButton.icon(
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Generar otro'),
                  onPressed: () => _regenerar(context, ref),
                ),
            ]),
          ],
        ),
      ),
    );
  }
}
