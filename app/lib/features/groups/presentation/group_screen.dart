import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/widgets/auth_layout.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../files/domain/file_item.dart';
import '../../files/domain/folder_tree.dart';
import '../../files/presentation/explorer_list.dart';
import '../../files/presentation/file_actions.dart';
import '../../files/presentation/file_details_panel.dart';
import '../../files/presentation/files_providers.dart';
import '../../files/presentation/uploads_panel.dart';
import '../domain/group.dart';
import 'group_shell.dart';

/// Explorador de un grupo: carpetas y archivos, estilo Drive.
/// [folderId] null = raíz del grupo.
class GroupScreen extends StatelessWidget {
  const GroupScreen({super.key, required this.groupId, this.folderId});
  final String groupId;
  final String? folderId;

  @override
  Widget build(BuildContext context) => GroupLoader(
        groupId: groupId,
        builder: (g) => _Explorador(grupo: g, folderId: folderId),
      );
}

class _Explorador extends ConsumerStatefulWidget {
  const _Explorador({required this.grupo, required this.folderId});
  final Group grupo;
  final String? folderId;

  @override
  ConsumerState<_Explorador> createState() => _ExploradorState();
}

class _ExploradorState extends ConsumerState<_Explorador> {
  /// Ancho desde el que se muestra el panel lateral de detalles.
  static const _anchoPanel = 1000.0;

  String? _seleccionado;
  bool _arrastrando = false;

  Group get grupo => widget.grupo;
  String? get folderId => widget.folderId;

  @override
  void didUpdateWidget(_Explorador old) {
    super.didUpdateWidget(old);
    if (old.folderId != folderId) _seleccionado = null;
  }

  void _abrirCarpeta(String? id) => context.go(
        id == null ? Routes.grupo(grupo.id) : Routes.carpeta(grupo.id, id),
      );

  /// Arrastrar y soltar (web): sube los archivos a la carpeta actual.
  Future<void> _soltar(DropDoneDetails detalle, List<FileItem> existentes, String? miId) async {
    setState(() => _arrastrando = false);
    final archivos = detalle.files.whereType<DropItemFile>().toList();
    if (archivos.length < detalle.files.length) {
      mostrarMensaje(context, 'Las carpetas no se pueden soltar: subí los archivos de adentro', error: true);
    }
    final locales = <ArchivoLocal>[
      for (final f in archivos) (nombre: f.name, tamano: await f.length(), leer: f.readAsBytes),
    ];
    if (!mounted) return;
    await subirArchivos(context, ref,
        groupId: grupo.id, folderId: folderId, existentes: existentes, miId: miId, archivos: locales);
  }

  @override
  Widget build(BuildContext context) {
    final carpetas = ref.watch(foldersProvider(grupo.id));
    final archivos = ref.watch(filesProvider((groupId: grupo.id, folderId: folderId)));
    final miId = ref.watch(authStateProvider).value?.id;

    final todas = carpetas.value ?? const <Folder>[];
    final ruta = rutaHasta(folderId, todas);
    final carpetaNoExiste = carpetas.hasValue && folderId != null && ruta.isEmpty;
    final lista = archivos.value ?? const <FileItem>[];
    final nombreCarpeta = ruta.isEmpty ? grupo.nombre : ruta.last.nombre;

    Widget contenido(bool conPanel) => switch ((carpetas, archivos)) {
          (AsyncValue(:final error?), _) || (_, AsyncValue(:final error?)) =>
            Aviso(icono: Icons.error_outline, texto: error.toString()),
          (AsyncValue(hasValue: true), AsyncValue(hasValue: true)) =>
            hijasDe(folderId, todas).isEmpty && lista.isEmpty
                ? _CarpetaVacia(
                    enRaiz: folderId == null,
                    onSubir: () => elegirYSubir(context, ref,
                        groupId: grupo.id, folderId: folderId, existentes: lista, miId: miId),
                    onCarpeta: () => nuevaCarpeta(context, ref, grupo.id, folderId),
                  )
                : RefreshIndicator(
                    onRefresh: () => Future.wait([
                      ref.refresh(foldersProvider(grupo.id).future),
                      ref.refresh(filesProvider((groupId: grupo.id, folderId: folderId)).future),
                    ]),
                    child: ExplorerList(
                      carpetas: hijasDe(folderId, todas),
                      archivos: lista,
                      miId: miId,
                      soyAdmin: grupo.soyAdmin,
                      onAbrirCarpeta: (c) => _abrirCarpeta(c.id),
                      seleccionadoId: conPanel ? _seleccionado : null,
                      onSeleccionar: conPanel ? (a) => setState(() => _seleccionado = a.id) : null,
                    ),
                  ),
          _ => const Center(child: CircularProgressIndicator()),
        };

    final explorador = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Breadcrumbs(grupo: grupo, ruta: ruta, onTap: _abrirCarpeta),
        Expanded(
          child: carpetaNoExiste
              ? Aviso(
                  icono: Icons.folder_off_outlined,
                  texto: 'Esta carpeta ya no existe',
                  accion: FilledButton(
                    onPressed: () => _abrirCarpeta(null),
                    child: Text('Ir a ${grupo.nombre}'),
                  ),
                )
              : LayoutBuilder(builder: (context, constraints) {
                  final conPanel = constraints.maxWidth >= _anchoPanel;
                  if (!conPanel) return contenido(false);
                  final elegido = lista.where((a) => a.id == _seleccionado).firstOrNull;
                  return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Expanded(child: contenido(true)),
                    const VerticalDivider(width: 1),
                    SizedBox(
                      width: 340,
                      child: FileDetailsPanel(
                        archivo: elegido,
                        miId: miId,
                        onCerrar: () => setState(() => _seleccionado = null),
                      ),
                    ),
                  ]);
                }),
        ),
        const UploadsPanel(),
      ],
    );

    return GroupShell(
      grupo: grupo,
      seccion: SeccionGrupo.archivos,
      // Dentro de una carpeta, "atrás" sube un nivel.
      onBack: ruta.isEmpty ? null : () => _abrirCarpeta(ruta.last.parentId),
      floatingActionButton: carpetaNoExiste
          ? null
          : FloatingActionButton.extended(
              icon: const Icon(Icons.add),
              label: const Text('Nuevo'),
              onPressed: () => _menuNuevo(lista, miId),
            ),
      // Arrastrar y soltar archivos desde la PC (solo en la web).
      body: !kIsWeb || carpetaNoExiste
          ? explorador
          : DropTarget(
              onDragEntered: (_) => setState(() => _arrastrando = true),
              onDragExited: (_) => setState(() => _arrastrando = false),
              onDragDone: (d) => _soltar(d, lista, miId),
              child: Stack(children: [
                Positioned.fill(child: explorador),
                if (_arrastrando) Positioned.fill(child: _ZonaSoltar(carpeta: nombreCarpeta)),
              ]),
            ),
    );
  }

  void _menuNuevo(List<FileItem> existentes, String? miId) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 480),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.upload_file_rounded),
            title: const Text('Subir archivos'),
            subtitle: kIsWeb ? const Text('También podés arrastrarlos a la ventana') : null,
            onTap: () {
              Navigator.pop(ctx);
              elegirYSubir(context, ref,
                  groupId: grupo.id, folderId: folderId, existentes: existentes, miId: miId);
            },
          ),
          ListTile(
            leading: const Icon(Icons.create_new_folder_outlined),
            title: const Text('Nueva carpeta'),
            onTap: () {
              Navigator.pop(ctx);
              nuevaCarpeta(context, ref, grupo.id, folderId);
            },
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }
}

/// Lo que se ve mientras se arrastran archivos sobre la ventana.
class _ZonaSoltar extends StatelessWidget {
  const _ZonaSoltar({required this.carpeta});
  final String carpeta;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IgnorePointer(
      child: Container(
        margin: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: scheme.primaryContainer.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: scheme.primary, width: 2),
        ),
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.cloud_upload_outlined, size: 56, color: scheme.onPrimaryContainer),
            const SizedBox(height: 12),
            Text(
              'Soltá los archivos para subirlos a "$carpeta"',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(color: scheme.onPrimaryContainer),
            ),
          ]),
        ),
      ),
    );
  }
}

/// "TP 2 - Grupo 4 › Informe › Anexos". Cada tramo lleva a esa carpeta.
class _Breadcrumbs extends StatelessWidget {
  const _Breadcrumbs({required this.grupo, required this.ruta, required this.onTap});
  final Group grupo;
  final List<Folder> ruta;
  final void Function(String? folderId) onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tramos = <(String?, String)>[(null, grupo.nombre), for (final c in ruta) (c.id, c.nombre)];
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        reverse: true, // si no entra, que se vea la carpeta actual
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        // minWidth: si entra, que quede alineado a la izquierda.
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: constraints.maxWidth - 24),
          child: Row(children: [
            for (final (i, (id, nombre)) in tramos.indexed) ...[
              if (i > 0) Icon(Icons.chevron_right, size: 20, color: theme.colorScheme.outline),
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: i == tramos.length - 1
                      ? theme.colorScheme.onSurface
                      : theme.colorScheme.onSurfaceVariant,
                  textStyle: theme.textTheme.titleMedium,
                ),
                onPressed: i == tramos.length - 1 ? null : () => onTap(id),
                child: Text(nombre),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}

class _CarpetaVacia extends StatelessWidget {
  const _CarpetaVacia({required this.enRaiz, required this.onSubir, required this.onCarpeta});
  final bool enRaiz;
  final VoidCallback onSubir;
  final VoidCallback onCarpeta;

  @override
  Widget build(BuildContext context) {
    return Aviso(
      icono: Icons.cloud_upload_outlined,
      texto: 'Esta carpeta está vacía',
      // Archivos chicos = menos bloqueos cruzados entre integrantes.
      detalle: [
        if (enRaiz)
          'Armá una carpeta por TP. Tip: dividí el trabajo en varios archivos '
              '(1-Introducción, 2-Desarrollo…) así cada uno edita su parte sin esperar a nadie.'
        else
          'Subí el primer archivo o armá subcarpetas para ordenar el TP.',
        if (kIsWeb) 'También podés arrastrar archivos desde tu compu.',
      ].join('\n\n'),
      accion: Wrap(spacing: 12, runSpacing: 12, alignment: WrapAlignment.center, children: [
        FilledButton.icon(
          icon: const Icon(Icons.upload_file_rounded),
          label: const Text('Subir archivos'),
          onPressed: onSubir,
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.create_new_folder_outlined),
          label: const Text('Nueva carpeta'),
          onPressed: onCarpeta,
        ),
      ]),
    );
  }
}
