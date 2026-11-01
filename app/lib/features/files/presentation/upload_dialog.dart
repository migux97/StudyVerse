import 'package:flutter/material.dart';

import '../domain/file_item.dart';
import '../domain/files_repository.dart';
import 'file_icon.dart';
import 'uploads_controller.dart';

/// Muestra qué se va a subir (archivo nuevo o versión nueva) y pide una nota
/// opcional. Devuelve la nota (`''` si no hay) o `null` si se cancela.
Future<String?> confirmarSubida(BuildContext context, List<Subida> subidas) =>
    showDialog<String>(context: context, builder: (_) => _SubidaDialog(subidas: subidas));

class _SubidaDialog extends StatefulWidget {
  const _SubidaDialog({required this.subidas});
  final List<Subida> subidas;

  @override
  State<_SubidaDialog> createState() => _SubidaDialogState();
}

class _SubidaDialogState extends State<_SubidaDialog> {
  final _nota = TextEditingController();

  @override
  void dispose() {
    _nota.dispose();
    super.dispose();
  }

  bool _muyGrande(Subida s) => (s.tamano ?? 0) > maxBytesPorArchivo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final validas = widget.subidas.where((s) => !_muyGrande(s)).toList();
    final hayVersiones = validas.any((s) => s.versionDe != null);
    final titulo = widget.subidas.length == 1
        ? (hayVersiones ? 'Subir nueva versión' : 'Subir archivo')
        : 'Subir ${widget.subidas.length} archivos';

    return AlertDialog(
      title: Text(titulo),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final s in widget.subidas)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: FileIcon(kind: fileKindFor(s.nombre), size: 24),
                      title: Text(s.nombre, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                        _muyGrande(s)
                            ? 'Supera el máximo de ${maxBytesPorArchivo ~/ 1024 ~/ 1024} MB: no se va a subir'
                            : [
                                if (s.tamano != null) formatBytes(s.tamano!),
                                s.versionDe != null ? 'nueva versión' : 'archivo nuevo',
                              ].join(' · '),
                        style: TextStyle(color: _muyGrande(s) ? theme.colorScheme.error : null),
                      ),
                    ),
                ],
              ),
            ),
            if (hayVersiones) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _nota,
                maxLength: 500,
                decoration: const InputDecoration(
                  labelText: '¿Qué cambiaste? (opcional)',
                  hintText: 'Ej.: corregí la conclusión',
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(88, 40)),
          onPressed: validas.isEmpty ? null : () => Navigator.pop(context, _nota.text.trim()),
          child: const Text('Subir'),
        ),
      ],
    );
  }
}
