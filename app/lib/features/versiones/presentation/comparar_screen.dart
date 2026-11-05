import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../files/domain/file_item.dart';
import '../../files/presentation/file_actions.dart';
import '../../files/presentation/files_providers.dart';
import '../domain/comparar.dart';
import '../domain/historial.dart';
import '../domain/texto_comparable.dart';
import 'versiones_providers.dart';

/// Comparar dos versiones de un archivo: lo agregado en verde, lo quitado en
/// rojo, y lo que no cambió plegado (como en GitHub).
class CompararScreen extends ConsumerStatefulWidget {
  const CompararScreen({super.key, required this.groupId, required this.fileId, this.antesId, this.despuesId});
  final String groupId;
  final String fileId;
  final String? antesId;
  final String? despuesId;

  @override
  ConsumerState<CompararScreen> createState() => _CompararScreenState();
}

enum _Vista { ladoALado, unaColumna }

class _CompararScreenState extends ConsumerState<CompararScreen> {
  var _vista = _Vista.ladoALado;
  late String? _antesId = widget.antesId;
  late String? _despuesId = widget.despuesId;

  void _elegir({required String antes, required String despues}) => setState(() {
    _antesId = antes;
    _despuesId = despues;
  });

  @override
  Widget build(BuildContext context) {
    final clave = (groupId: widget.groupId, fileId: widget.fileId);
    final archivo = ref.watch(fileProvider(clave));
    final versiones = ref.watch(versionsProvider(clave));
    final ancho = MediaQuery.sizeOf(context).width >= 900;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Comparar versiones'),
        bottom: archivo.hasValue
            ? PreferredSize(
                preferredSize: const Size.fromHeight(20),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    archivo.requireValue.visible,
                    style: Theme.of(context).textTheme.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
            : null,
        actions: [
          if (ancho)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: SegmentedButton<_Vista>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: _Vista.ladoALado,
                    icon: Icon(Icons.vertical_split_outlined),
                    tooltip: 'Lado a lado',
                  ),
                  ButtonSegment(
                    value: _Vista.unaColumna,
                    icon: Icon(Icons.view_agenda_outlined),
                    tooltip: 'En una columna',
                  ),
                ],
                selected: {_vista},
                onSelectionChanged: (s) => setState(() => _vista = s.first),
              ),
            ),
        ],
      ),
      body: switch ((archivo, versiones)) {
        (AsyncValue(hasError: true), _) || (_, AsyncValue(hasError: true)) => const _Aviso(
          icono: Icons.cloud_off_outlined,
          texto: 'No pudimos cargar las versiones. Probá de nuevo.',
        ),
        (AsyncValue(value: final FileItem a), AsyncValue(value: final List<FileVersion> lista)) => _contenido(
          a,
          lista,
          ancho,
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }

  Widget _contenido(FileItem a, List<FileVersion> lista, bool ancho) {
    if (lista.length < 2) {
      return const _Aviso(
        icono: Icons.history,
        texto: 'Este archivo tiene una sola versión: todavía no hay nada para comparar.',
      );
    }
    // Por defecto: la actual contra la anterior.
    final despues = lista.where((v) => v.id == _despuesId).firstOrNull ?? lista.first;
    final antes = lista.where((v) => v.id == _antesId).firstOrNull ?? anteriorA(lista, despues) ?? lista[1];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Selector(
          versiones: lista,
          antes: antes,
          despues: despues,
          alElegirAntes: (v) => _elegir(antes: v.id, despues: despues.id),
          alElegirDespues: (v) => _elegir(antes: antes.id, despues: v.id),
          alInvertir: () => _elegir(antes: despues.id, despues: antes.id),
        ),
        const Divider(height: 1),
        Expanded(
          child: antes.id == despues.id
              ? const _Aviso(icono: Icons.compare_arrows, texto: 'Elegiste la misma versión de los dos lados.')
              : switch (modoComparacion(a.nombre)) {
                  ModoComparacion.imagen => _CompararImagenes(antes: antes, despues: despues, ladoALado: ancho),
                  ModoComparacion.ninguno => _SinComparacion(
                    archivo: a,
                    antes: antes,
                    despues: despues,
                    motivo: 'Este tipo de archivo no se puede comparar acá.',
                  ),
                  _ => _CompararTexto(
                    clave: (antes: antes, despues: despues, nombre: a.nombre),
                    archivo: a,
                    ladoALado: ancho && _vista == _Vista.ladoALado,
                    monoespaciada: a.kind == FileKind.codigo,
                  ),
                },
        ),
      ],
    );
  }
}

/// "Antes [v7 ▾]  ⇄  Después [v8 ▾]".
class _Selector extends StatelessWidget {
  const _Selector({
    required this.versiones,
    required this.antes,
    required this.despues,
    required this.alElegirAntes,
    required this.alElegirDespues,
    required this.alInvertir,
  });

  final List<FileVersion> versiones;
  final FileVersion antes;
  final FileVersion despues;
  final ValueChanged<FileVersion> alElegirAntes;
  final ValueChanged<FileVersion> alElegirDespues;
  final VoidCallback alInvertir;

  @override
  Widget build(BuildContext context) {
    final ahora = DateTime.now();
    Widget menu(String etiqueta, FileVersion actual, ValueChanged<FileVersion> alElegir, Color color) =>
        DropdownButtonFormField<String>(
          // La clave hace que tome el valor nuevo al invertir.
          key: ValueKey('$etiqueta-${actual.id}'),
          initialValue: actual.id,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: etiqueta,
            isDense: true,
            prefixIcon: Icon(Icons.circle, size: 12, color: color),
          ),
          items: [
            for (final v in versiones)
              DropdownMenuItem(
                value: v.id,
                child: Text(
                  '${etiquetaVersion(v)} · ${v.uploaderNombre ?? 'Alguien'} · ${formatearFecha(v.createdAt, ahora)}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (id) => alElegir(versiones.firstWhere((v) => v.id == id)),
        );
    final colores = ColoresDiff.de(context);
    final invertir = IconButton(tooltip: 'Invertir', icon: const Icon(Icons.swap_vert), onPressed: alInvertir);
    // En el celular, uno arriba del otro para que se lean enteros.
    final angosto = MediaQuery.sizeOf(context).width < 600;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: angosto
          ? Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      menu('Antes', antes, alElegirAntes, colores.quitadaFuerte),
                      const SizedBox(height: 12),
                      menu('Después', despues, alElegirDespues, colores.agregadaFuerte),
                    ],
                  ),
                ),
                invertir,
              ],
            )
          : Row(
              children: [
                Expanded(child: menu('Antes', antes, alElegirAntes, colores.quitadaFuerte)),
                RotatedBox(quarterTurns: 1, child: invertir),
                Expanded(child: menu('Después', despues, alElegirDespues, colores.agregadaFuerte)),
              ],
            ),
    );
  }
}

/// Colores del diff, legibles en claro y en oscuro.
class ColoresDiff {
  const ColoresDiff(this.agregada, this.agregadaFuerte, this.quitada, this.quitadaFuerte);
  final Color agregada, agregadaFuerte, quitada, quitadaFuerte;

  static ColoresDiff de(BuildContext context) => Theme.of(context).brightness == Brightness.dark
      ? const ColoresDiff(Color(0x2E34A853), Color(0x8034A853), Color(0x2EEA4335), Color(0x80EA4335))
      : const ColoresDiff(Color(0xFFE6F4EA), Color(0xFFA8DAB5), Color(0xFFFCE8E6), Color(0xFFF5B7B1));
}

class _CompararTexto extends ConsumerStatefulWidget {
  const _CompararTexto({
    required this.clave,
    required this.archivo,
    required this.ladoALado,
    required this.monoespaciada,
  });
  final ClaveComparacion clave;
  final FileItem archivo;
  final bool ladoALado;
  final bool monoespaciada;

  @override
  ConsumerState<_CompararTexto> createState() => _CompararTextoState();
}

class _CompararTextoState extends ConsumerState<_CompararTexto> {
  /// Bloques plegados que se abrieron (por posición).
  final _abiertos = <int>{};

  @override
  void didUpdateWidget(_CompararTexto old) {
    super.didUpdateWidget(old);
    if (old.clave != widget.clave) _abiertos.clear();
  }

  @override
  Widget build(BuildContext context) {
    final r = ref.watch(comparacionProvider(widget.clave));
    return switch (r) {
      AsyncValue(value: ComparacionImposible(:final motivo)) => _SinComparacion(
        archivo: widget.archivo,
        antes: widget.clave.antes,
        despues: widget.clave.despues,
        motivo: motivo,
      ),
      AsyncValue(value: ComparacionLista(:final comparacion)) => _diff(comparacion),
      AsyncValue(hasError: true) => const _Aviso(
        icono: Icons.cloud_off_outlined,
        texto: 'No pudimos traer las versiones. Probá de nuevo.',
      ),
      _ => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [CircularProgressIndicator(), SizedBox(height: 16), Text('Comparando…')],
        ),
      ),
    };
  }

  Widget _diff(Comparacion c) {
    final theme = Theme.of(context);
    if (c.sinCambios) {
      return const _Aviso(icono: Icons.check_circle_outline, texto: 'El texto de las dos versiones es igual.');
    }
    final bloques = plegar(c.lineas);
    final colores = ColoresDiff.de(context);
    final estilo =
        (widget.monoespaciada
                ? theme.textTheme.bodyMedium?.copyWith(fontFamily: 'monospace', fontSize: 13)
                : theme.textTheme.bodyMedium)!
            .copyWith(height: 1.45);

    final filas = <_Fila>[];
    for (var i = 0; i < bloques.length; i++) {
      final b = bloques[i];
      final lineas = switch (b) {
        BloqueLineas(:final lineas) => lineas,
        BloquePlegado(:final lineas) => _abiertos.contains(i) ? lineas : null,
      };
      if (lineas == null) {
        filas.add(_FilaPlegada(i, (b as BloquePlegado).lineas.length));
      } else if (widget.ladoALado) {
        filas.addAll(filasLadoALado(lineas).map((f) => _FilaPar(f.antes, f.despues)));
      } else {
        filas.addAll(lineas.map(_FilaUnica.new));
      }
    }

    Widget fila(_Fila f) => switch (f) {
      _FilaPlegada(:final bloque, :final cantidad) => _Plegado(
        cantidad: cantidad,
        alAbrir: () => setState(() => _abiertos.add(bloque)),
      ),
      _FilaUnica(:final linea) => _Linea(linea: linea, lado: _Lado.unica, colores: colores, estilo: estilo),
      _FilaPar(:final antes, :final despues) => IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _Linea(linea: antes, lado: _Lado.antes, colores: colores, estilo: estilo),
            ),
            VerticalDivider(width: 1, color: theme.colorScheme.outlineVariant),
            Expanded(
              child: _Linea(linea: despues, lado: _Lado.despues, colores: colores, estilo: estilo),
            ),
          ],
        ),
      ),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Resumen(comparacion: c),
        Expanded(
          child: SelectionArea(
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 32),
              itemCount: filas.length,
              itemBuilder: (_, i) => fila(filas[i]),
            ),
          ),
        ),
      ],
    );
  }
}

class _Resumen extends StatelessWidget {
  const _Resumen({required this.comparacion});
  final Comparacion comparacion;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colores = ColoresDiff.de(context);
    Widget chip(String texto, Color fondo) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: fondo, borderRadius: BorderRadius.circular(8)),
      child: Text(texto, style: theme.textTheme.labelMedium),
    );
    final a = comparacion.agregadas, q = comparacion.quitadas;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          chip('+$a ${a == 1 ? 'línea agregada' : 'líneas agregadas'}', colores.agregada),
          chip('−$q ${q == 1 ? 'línea quitada' : 'líneas quitadas'}', colores.quitada),
          if (comparacion.cortada)
            Text(
              'Es muy largo: se comparó el principio.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
        ],
      ),
    );
  }
}

enum _Lado { antes, despues, unica }

sealed class _Fila {
  const _Fila();
}

class _FilaPlegada extends _Fila {
  const _FilaPlegada(this.bloque, this.cantidad);
  final int bloque;
  final int cantidad;
}

class _FilaUnica extends _Fila {
  const _FilaUnica(this.linea);
  final LineaDiff linea;
}

class _FilaPar extends _Fila {
  const _FilaPar(this.antes, this.despues);
  final LineaDiff? antes;
  final LineaDiff? despues;
}

class _Linea extends StatelessWidget {
  const _Linea({required this.linea, required this.lado, required this.colores, required this.estilo});
  final LineaDiff? linea;
  final _Lado lado;
  final ColoresDiff colores;
  final TextStyle estilo;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l = linea;
    if (l == null) return ColoredBox(color: scheme.surfaceContainerLow, child: const SizedBox(height: 1));
    final (fondo, fuerte, signo) = switch (l.tipo) {
      TipoLinea.agregada => (colores.agregada, colores.agregadaFuerte, '+'),
      TipoLinea.quitada => (colores.quitada, colores.quitadaFuerte, '−'),
      TipoLinea.igual => (null, null, ' '),
    };
    final numero = switch (lado) {
      _Lado.antes => l.numAntes,
      _Lado.despues => l.numDespues,
      _Lado.unica => l.numDespues ?? l.numAntes,
    };
    final gris = estilo.copyWith(color: scheme.onSurfaceVariant, fontSize: (estilo.fontSize ?? 14) - 2);
    return Container(
      color: fondo,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 40,
            child: SelectionContainer.disabled(
              child: Text(numero?.toString() ?? '', textAlign: TextAlign.right, style: gris),
            ),
          ),
          SizedBox(
            width: 20,
            child: SelectionContainer.disabled(
              child: Text(signo, textAlign: TextAlign.center, style: gris),
            ),
          ),
          Expanded(
            child: l.fragmentos == null
                ? Text(l.texto.isEmpty ? ' ' : l.texto, style: estilo)
                : Text.rich(
                    TextSpan(
                      style: estilo,
                      children: [
                        for (final f in l.fragmentos!)
                          TextSpan(
                            text: f.texto,
                            style: f.cambiado ? TextStyle(backgroundColor: fuerte) : null,
                          ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _Plegado extends StatelessWidget {
  const _Plegado({required this.cantidad, required this.alAbrir});
  final int cantidad;
  final VoidCallback alAbrir;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainer,
      child: InkWell(
        onTap: alAbrir,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.unfold_more, size: 18, color: scheme.primary),
              const SizedBox(width: 8),
              Text(
                'Mostrar $cantidad ${cantidad == 1 ? 'línea' : 'líneas'} sin cambios',
                style: TextStyle(color: scheme.primary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Imágenes: lado a lado, o una sobre otra con un deslizador.
class _CompararImagenes extends ConsumerStatefulWidget {
  const _CompararImagenes({required this.antes, required this.despues, required this.ladoALado});
  final FileVersion antes;
  final FileVersion despues;
  final bool ladoALado;

  @override
  ConsumerState<_CompararImagenes> createState() => _CompararImagenesState();
}

class _CompararImagenesState extends ConsumerState<_CompararImagenes> {
  var _deslizar = false;
  var _corte = 0.5;

  @override
  Widget build(BuildContext context) {
    if (widget.antes.sizeBytes > maxBytesComparacion || widget.despues.sizeBytes > maxBytesComparacion) {
      return const _Aviso(
        icono: Icons.image_outlined,
        texto: 'Estas imágenes son muy grandes para compararlas acá. Descargalas para verlas.',
      );
    }
    final a = ref.watch(fileBytesProvider(widget.antes));
    final b = ref.watch(fileBytesProvider(widget.despues));
    if (a.hasError || b.hasError) {
      return const _Aviso(icono: Icons.broken_image_outlined, texto: 'No pudimos traer las imágenes. Probá de nuevo.');
    }
    if (!a.hasValue || !b.hasValue) return const Center(child: CircularProgressIndicator());
    final colores = ColoresDiff.de(context);
    Widget imagen(FileVersion v, Uint8List bytes, Color color, String etiqueta) => Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.circle, size: 10, color: color),
              const SizedBox(width: 6),
              Text('$etiqueta · ${etiquetaVersion(v)}'),
            ],
          ),
        ),
        Expanded(child: InteractiveViewer(child: _imagen(bytes))),
      ],
    );

    // En el celular no entran dos imágenes al lado: siempre se desliza.
    final usarDeslizador = _deslizar || !widget.ladoALado;
    return Column(
      children: [
        if (widget.ladoALado)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Lado a lado'), icon: Icon(Icons.vertical_split_outlined)),
                ButtonSegment(value: true, label: Text('Deslizar'), icon: Icon(Icons.compare)),
              ],
              selected: {usarDeslizador},
              onSelectionChanged: (s) => setState(() => _deslizar = s.first),
            ),
          ),
        Expanded(
          child: usarDeslizador
              ? Column(
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: LayoutBuilder(
                          builder: (_, c) => Stack(
                            fit: StackFit.expand,
                            children: [
                              _imagen(a.requireValue),
                              ClipRect(clipper: _CorteIzquierdo(_corte), child: _imagen(b.requireValue)),
                              Positioned(
                                left: c.maxWidth * _corte - 1,
                                top: 0,
                                bottom: 0,
                                child: Container(width: 2, color: Theme.of(context).colorScheme.primary),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Row(
                        children: [
                          Text(etiquetaVersion(widget.antes)),
                          Expanded(
                            child: Slider(
                              value: _corte,
                              semanticFormatterCallback: (v) => 'Muestra ${(v * 100).round()} % de la versión nueva',
                              onChanged: (v) => setState(() => _corte = v),
                            ),
                          ),
                          Text(etiquetaVersion(widget.despues)),
                        ],
                      ),
                    ),
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: imagen(widget.antes, a.requireValue, colores.quitadaFuerte, 'Antes')),
                    const VerticalDivider(width: 1),
                    Expanded(child: imagen(widget.despues, b.requireValue, colores.agregadaFuerte, 'Después')),
                  ],
                ),
        ),
      ],
    );
  }
}

/// La imagen se decodifica achicada (una enorme no agota la memoria).
Widget _imagen(Uint8List bytes) => Image.memory(
  bytes,
  fit: BoxFit.contain,
  cacheWidth: 2000,
  errorBuilder: (context, _, _) =>
      const _Aviso(icono: Icons.broken_image_outlined, texto: 'No pudimos mostrar esta imagen. Descargala para verla.'),
);

/// Muestra la imagen nueva a la izquierda del corte (la vieja queda a la derecha).
class _CorteIzquierdo extends CustomClipper<Rect> {
  const _CorteIzquierdo(this.fraccion);
  final double fraccion;

  @override
  Rect getClip(Size size) => Rect.fromLTWH(0, 0, size.width * fraccion, size.height);

  @override
  bool shouldReclip(_CorteIzquierdo old) => old.fraccion != fraccion;
}

/// Cuando no se puede comparar: por qué, y abrir cada versión.
class _SinComparacion extends ConsumerWidget {
  const _SinComparacion({required this.archivo, required this.antes, required this.despues, required this.motivo});
  final FileItem archivo;
  final FileVersion antes;
  final FileVersion despues;
  final String motivo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _Aviso(
      icono: Icons.difference_outlined,
      texto: motivo,
      acciones: [
        for (final v in [antes, despues])
          OutlinedButton.icon(
            icon: const Icon(Icons.download_rounded, size: 18),
            label: Text('Descargar ${etiquetaVersion(v)}'),
            onPressed: () => abrirVersion(context, ref, v, archivo.nombre, descargar: true),
          ),
      ],
    );
  }
}

class _Aviso extends StatelessWidget {
  const _Aviso({required this.icono, required this.texto, this.acciones = const []});
  final IconData icono;
  final String texto;
  final List<Widget> acciones;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icono, size: 48, color: scheme.onSurfaceVariant),
              const SizedBox(height: 16),
              Text(texto, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge),
              if (acciones.isNotEmpty) ...[
                const SizedBox(height: 20),
                Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: acciones),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
