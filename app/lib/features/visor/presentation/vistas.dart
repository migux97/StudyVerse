import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:video_player/video_player.dart';

import '../../documentos/domain/lectores.dart';
import '../../files/domain/file_item.dart';
import '../../files/presentation/files_providers.dart';
import '../../../core/widgets/pagina.dart';

export '../../../core/widgets/pagina.dart';

/// Espera los bytes de la versión y se los pasa a [builder].
class ConBytes extends ConsumerWidget {
  const ConBytes({super.key, required this.version, required this.builder});
  final FileVersion version;
  final Widget Function(Uint8List bytes) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ref.watch(fileBytesProvider(version)).when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const SinVista(motivo: 'No pudimos traer el archivo. Revisá tu conexión.'),
        data: builder,
      );
}

class VistaImagen extends StatelessWidget {
  const VistaImagen({super.key, required this.bytes});
  final Uint8List bytes;

  @override
  Widget build(BuildContext context) => InteractiveViewer(
        maxScale: 8,
        child: Center(
          child: Image.memory(
            bytes,
            errorBuilder: (_, _, _) => const SinVista(motivo: 'Esta imagen no se puede mostrar acá. Descargala para verla.'),
          ),
        ),
      );
}

class VistaPdf extends StatelessWidget {
  const VistaPdf({super.key, required this.bytes, required this.nombre});
  final Uint8List bytes;
  final String nombre;

  @override
  Widget build(BuildContext context) => PdfViewer.data(
        bytes,
        sourceName: nombre,
        params: PdfViewerParams(
          backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
          margin: 12,
          loadingBannerBuilder: (_, _, _) => const Center(child: CircularProgressIndicator()),
          errorBannerBuilder: (_, _, _, _) =>
              const SinVista(motivo: 'Este PDF no se puede abrir acá. Descargalo para verlo.'),
        ),
      );
}

/// Texto o código, con la letra que corresponde y seleccionable.
class VistaTexto extends StatelessWidget {
  const VistaTexto({super.key, required this.texto, required this.codigo});
  final String texto;
  final bool codigo;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scrollbar(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900, minWidth: double.infinity),
            child: SelectableText(
              texto.isEmpty ? '(El archivo está vacío)' : texto,
              style: TextStyle(
                fontFamily: codigo ? 'monospace' : null,
                fontSize: codigo ? 13 : 15,
                height: 1.5,
                color: texto.isEmpty ? scheme.onSurfaceVariant : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String decodificarTexto(Uint8List bytes) {
  // Quita el BOM de UTF-8 si viene.
  final sinBom = bytes.length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF ? bytes.sublist(3) : bytes;
  return utf8.decode(sinBom, allowMalformed: true);
}

/// Planilla en solapas, con encabezados A, B, C… como en Sheets.
class VistaPlanilla extends StatelessWidget {
  const VistaPlanilla({super.key, required this.hojas});
  final List<Hoja> hojas;

  @override
  Widget build(BuildContext context) {
    if (hojas.isEmpty) return const SinVista(motivo: 'La planilla no tiene hojas con datos.');
    return DefaultTabController(
      length: hojas.length,
      child: Column(children: [
        Expanded(child: TabBarView(children: [for (final h in hojas) _Tabla(hoja: h)])),
        if (hojas.length > 1)
          Material(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            child: TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [for (final h in hojas) Tab(text: h.nombre)]),
          ),
      ]),
    );
  }
}

class _Tabla extends StatelessWidget {
  const _Tabla({required this.hoja});
  final Hoja hoja;

  static String _letra(int i) {
    var n = i + 1;
    var s = '';
    while (n > 0) {
      final r = (n - 1) % 26;
      s = String.fromCharCode(65 + r) + s;
      n = (n - 1) ~/ 26;
    }
    return s;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final columnas = hoja.columnas;
    if (hoja.filas.isEmpty || columnas == 0) return const SinVista(motivo: 'Esta hoja está vacía.');
    final borde = BorderSide(color: scheme.outlineVariant);
    Widget celda(String texto, {bool encabezado = false}) => Container(
          constraints: const BoxConstraints(minWidth: 96, maxWidth: 260),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: encabezado ? scheme.surfaceContainerHigh : null,
            border: Border(right: borde, bottom: borde),
          ),
          child: Text(texto,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              textAlign: encabezado ? TextAlign.center : TextAlign.start,
              style: TextStyle(fontSize: 13, color: encabezado ? scheme.onSurfaceVariant : null)),
        );
    return Scrollbar(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SingleChildScrollView(
          child: Table(
            defaultColumnWidth: const IntrinsicColumnWidth(),
            children: [
              TableRow(children: [celda('', encabezado: true), for (var c = 0; c < columnas; c++) celda(_letra(c), encabezado: true)]),
              for (final (i, f) in hoja.filas.indexed)
                TableRow(children: [
                  celda('${i + 1}', encabezado: true),
                  for (var c = 0; c < columnas; c++) celda(c < f.length ? f[c] : ''),
                ]),
            ],
          ),
        ),
      ),
    );
  }
}

/// Diapositivas de un .pptx: solo el texto de cada una.
class VistaPresentacion extends StatelessWidget {
  const VistaPresentacion({super.key, required this.diapositivas});
  final List<List<String>> diapositivas;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: diapositivas.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
        if (i == 0) {
          return Text('Vista de solo texto. Para ver el diseño, descargala.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant));
        }
        final textos = diapositivas[i - 1];
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('$i', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                    const SizedBox(height: 8),
                    if (textos.isNotEmpty) Text(textos.first, style: theme.textTheme.titleLarge, maxLines: 2),
                    const SizedBox(height: 8),
                    Expanded(
                      child: Text(textos.skip(1).join('\n'),
                          style: theme.textTheme.bodyMedium, overflow: TextOverflow.fade),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Documento de Word mostrado con el editor en modo lectura.
class VistaDocumento extends StatefulWidget {
  const VistaDocumento({super.key, required this.ops});
  final List<dynamic> ops;

  @override
  State<VistaDocumento> createState() => _VistaDocumentoState();
}

class _VistaDocumentoState extends State<VistaDocumento> {
  late final _controller = QuillController(
    document: Document.fromJson(widget.ops),
    selection: const TextSelection.collapsed(offset: 0),
    readOnly: true,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PaginaDocumento(child: QuillEditor.basic(controller: _controller));
}

/// Video o audio con controles simples.
class VistaMedia extends StatefulWidget {
  const VistaMedia({super.key, required this.url, required this.audio});
  final String url;
  final bool audio;

  @override
  State<VistaMedia> createState() => _VistaMediaState();
}

class _VistaMediaState extends State<VistaMedia> {
  late final _ctrl = VideoPlayerController.networkUrl(Uri.parse(widget.url));
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _ctrl.initialize().then((_) {
      if (mounted) setState(() {});
    }, onError: (_) {
      if (mounted) setState(() => _error = true);
    });
    _ctrl.addListener(_alCambiar);
  }

  void _alCambiar() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _ctrl.removeListener(_alCambiar);
    _ctrl.dispose();
    super.dispose();
  }

  static String _tiempo(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    if (_error) return const SinVista(motivo: 'No se puede reproducir acá. Descargalo para verlo.');
    final v = _ctrl.value;
    if (!v.isInitialized) return const Center(child: CircularProgressIndicator());
    final scheme = Theme.of(context).colorScheme;
    final total = v.duration.inMilliseconds.toDouble();
    final controles = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(children: [
        IconButton.filledTonal(
          tooltip: v.isPlaying ? 'Pausar' : 'Reproducir',
          icon: Icon(v.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
          onPressed: () => v.isPlaying ? _ctrl.pause() : _ctrl.play(),
        ),
        Expanded(
          child: Slider(
            value: v.position.inMilliseconds.clamp(0, total.toInt()).toDouble(),
            max: total <= 0 ? 1 : total,
            onChanged: (x) => _ctrl.seekTo(Duration(milliseconds: x.toInt())),
          ),
        ),
        Text('${_tiempo(v.position)} / ${_tiempo(v.duration)}', style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()])),
      ]),
    );
    if (widget.audio) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Card(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const SizedBox(height: 24),
              Icon(Icons.graphic_eq_rounded, size: 56, color: scheme.primary),
              const SizedBox(height: 8),
              controles,
            ]),
          ),
        ),
      );
    }
    return Column(children: [
      Expanded(
        child: ColoredBox(
          color: Colors.black,
          child: Center(child: AspectRatio(aspectRatio: v.aspectRatio, child: VideoPlayer(_ctrl))),
        ),
      ),
      controles,
    ]);
  }
}
