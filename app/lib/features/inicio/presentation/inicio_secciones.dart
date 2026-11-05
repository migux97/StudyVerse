import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../calendario/domain/calendario.dart';
import '../../calendario/presentation/calendario_providers.dart';
import '../../calendario/presentation/calendario_screen.dart' show colorDe, iconoDe;
import '../../files/domain/file_item.dart';
import '../../files/presentation/file_icon.dart';
import '../../files/presentation/files_providers.dart';
import '../../visor/presentation/visor_screen.dart' show abrirArchivo;

/// Barra "Buscar en StudyVerse", como la de Drive: lleva a la búsqueda.
class BarraBusqueda extends StatelessWidget {
  const BarraBusqueda({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      child: Material(
      color: scheme.surfaceContainerHigh,
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: () => context.push(Routes.buscar),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Row(children: [
            Icon(Icons.search, color: scheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Text('Buscar en StudyVerse', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 16)),
          ]),
        ),
      ),
    ),
    );
  }
}

/// Lo de arriba de "Mis grupos": lo que se viene, destacados y recientes.
/// Cada sección aparece solo si tiene algo.
class InicioSecciones extends ConsumerWidget {
  const InicioSecciones({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final proximas = ref.watch(proximasFechasProvider).value ?? const [];
    final destacados = ref.watch(destacadosProvider).value ?? const [];
    final recientes = ref.watch(recientesProvider).value ?? const [];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const BarraBusqueda(),
      if (proximas.isNotEmpty) ...[
        _Titulo(
          'Se viene en la semana',
          accion: TextButton(onPressed: () => context.push(Routes.calendario), child: const Text('Ver calendario')),
        ),
        _Proximas(fechas: proximas.take(4).toList()),
      ],
      if (destacados.isNotEmpty) ...[
        const _Titulo('Destacados'),
        _Tarjetas(archivos: destacados),
      ],
      if (recientes.isNotEmpty) ...[
        const _Titulo('Recientes'),
        _Tarjetas(archivos: recientes),
      ],
    ]);
  }
}

class _Titulo extends StatelessWidget {
  const _Titulo(this.texto, {this.accion});
  final String texto;
  final Widget? accion;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 0, 6),
        child: Row(children: [
          Expanded(child: Text(texto, style: Theme.of(context).textTheme.titleSmall)),
          ?accion,
        ]),
      );
}

class _Proximas extends StatelessWidget {
  const _Proximas({required this.fechas});
  final List<FechaCalendario> fechas;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hoy = DateTime.now();
    return Card(
      margin: EdgeInsets.zero,
      child: Column(children: [
        for (final (i, f) in fechas.indexed) ...[
          if (i > 0) const Divider(height: 1, indent: 56),
          ListTile(
            leading: Icon(iconoDe(f.tipo), color: colorDe(f.tipo, scheme)),
            title: Text(f.titulo, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              [if (!f.esTarea) f.tipo.texto, f.grupo, ?f.hora].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Text(
              cuandoEs(f.dia, hoy),
              style: TextStyle(
                color: soloDia(f.dia) == soloDia(hoy) ? scheme.error : scheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
            onTap: () => context.push(f.esTarea ? Routes.tareas(f.groupId) : Routes.calendario),
          ),
        ],
      ]),
    );
  }
}

/// Tarjetas de archivos en una fila que se desliza (destacados, recientes).
class _Tarjetas extends StatelessWidget {
  const _Tarjetas({required this.archivos});
  final List<FileItem> archivos;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Crece con el tamaño de letra del sistema.
    return SizedBox(
      height: MediaQuery.textScalerOf(context).scale(92).clamp(92, 160),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: archivos.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final a = archivos[i];
          return SizedBox(
            width: 200,
            child: Card(
              margin: EdgeInsets.zero,
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => abrirArchivo(context, a),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      FileIcon(kind: a.kind, size: 22),
                      const SizedBox(width: 8),
                      Expanded(child: Text(a.visible, maxLines: 1, overflow: TextOverflow.ellipsis)),
                    ]),
                    const Spacer(),
                    Text(a.grupo ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  ]),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
