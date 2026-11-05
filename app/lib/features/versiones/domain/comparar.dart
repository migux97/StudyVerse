/// Comparación de dos textos línea por línea (como el "diff" de GitHub), con
/// lo que cambió dentro de cada línea marcado palabra por palabra.
library;

enum TipoLinea { igual, agregada, quitada }

/// Un pedazo de una línea; [cambiado] si es lo que se agregó o quitó.
class Fragmento {
  const Fragmento(this.texto, {this.cambiado = false});
  final String texto;
  final bool cambiado;

  @override
  bool operator ==(Object other) => other is Fragmento && other.texto == texto && other.cambiado == cambiado;

  @override
  int get hashCode => Object.hash(texto, cambiado);

  @override
  String toString() => cambiado ? '[$texto]' : texto;
}

class LineaDiff {
  const LineaDiff(this.tipo, this.texto, {this.numAntes, this.numDespues, this.fragmentos});
  final TipoLinea tipo;
  final String texto;

  /// Número de línea en la versión anterior / nueva (1, 2, 3…).
  final int? numAntes;
  final int? numDespues;

  /// Solo en líneas modificadas: qué parte cambió.
  final List<Fragmento>? fragmentos;

  LineaDiff conFragmentos(List<Fragmento> t) =>
      LineaDiff(tipo, texto, numAntes: numAntes, numDespues: numDespues, fragmentos: t);

  @override
  String toString() =>
      '${switch (tipo) {
        TipoLinea.igual => ' ',
        TipoLinea.agregada => '+',
        TipoLinea.quitada => '-',
      }}$texto';
}

class Comparacion {
  const Comparacion(this.lineas, {this.cortada = false});
  final List<LineaDiff> lineas;

  /// Si los textos eran tan largos que se comparó solo el principio.
  final bool cortada;

  int get agregadas => lineas.where((l) => l.tipo == TipoLinea.agregada).length;
  int get quitadas => lineas.where((l) => l.tipo == TipoLinea.quitada).length;
  bool get sinCambios => agregadas == 0 && quitadas == 0;
}

/// Hasta acá se compara (más que esto es un archivo enorme: se avisa).
const maxLineasComparadas = 20000;
const _maxTokensPorBloque = 4000;

/// Compara [antes] con [despues].
Comparacion compararTextos(String antes, String despues) {
  var a = _lineas(antes);
  var b = _lineas(despues);
  final cortada = a.length > maxLineasComparadas || b.length > maxLineasComparadas;
  if (a.length > maxLineasComparadas) a = a.sublist(0, maxLineasComparadas);
  if (b.length > maxLineasComparadas) b = b.sublist(0, maxLineasComparadas);

  final ops = diffListas(a, b);
  final lineas = <LineaDiff>[];
  var na = 0, nb = 0;
  for (final op in ops) {
    switch (op) {
      case TipoLinea.igual:
        lineas.add(LineaDiff(TipoLinea.igual, a[na], numAntes: ++na, numDespues: ++nb));
      case TipoLinea.quitada:
        lineas.add(LineaDiff(TipoLinea.quitada, a[na], numAntes: ++na));
      case TipoLinea.agregada:
        lineas.add(LineaDiff(TipoLinea.agregada, b[nb], numDespues: ++nb));
    }
  }
  return Comparacion(_marcarCambiosEnLinea(lineas), cortada: cortada);
}

List<String> _lineas(String t) {
  if (t.isEmpty) return const [];
  final l = t.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
  // Un salto de línea al final no es una línea vacía más.
  if (l.length > 1 && l.last.isEmpty) l.removeLast();
  return l;
}

/// Operaciones para pasar de [a] a [b] (algoritmo de Myers, el de git), con
/// lo común del principio y del final recortado antes para ir rápido.
List<TipoLinea> diffListas<T>(List<T> a, List<T> b) {
  var inicio = 0;
  while (inicio < a.length && inicio < b.length && a[inicio] == b[inicio]) {
    inicio++;
  }
  var finA = a.length, finB = b.length;
  while (finA > inicio && finB > inicio && a[finA - 1] == b[finB - 1]) {
    finA--;
    finB--;
  }
  return [
    for (var i = 0; i < inicio; i++) TipoLinea.igual,
    ..._myers(a.sublist(inicio, finA), b.sublist(inicio, finB)),
    for (var i = finA; i < a.length; i++) TipoLinea.igual,
  ];
}

/// Si las diferencias son enormes, en vez de buscar la mínima (que puede
/// tardar y gastar mucha memoria) se marca todo lo de en medio como quitado y
/// agregado. Lo que se guarda para volver sobre los pasos crece con d², así
/// que con 1500 queda en unos pocos MB.
const _maxD = 1500;

List<TipoLinea> _myers<T>(List<T> a, List<T> b) {
  final n = a.length, m = b.length;
  if (n == 0) return List.filled(m, TipoLinea.agregada);
  if (m == 0) return List.filled(n, TipoLinea.quitada);
  final max = n + m;
  final offset = max;
  final v = List<int>.filled(2 * max + 2, 0);
  // En cada paso d solo se guarda la parte de v que se usa (k de -d-1 a d+1),
  // no v entero: si no, un archivo largo y muy cambiado agota la memoria.
  final trazas = <List<int>>[];
  var dFinal = -1;
  for (var d = 0; d <= max && d <= _maxD; d++) {
    trazas.add(v.sublist(_inicioTraza(offset, d), offset + d + 2));
    for (var k = -d; k <= d; k += 2) {
      int x;
      if (k == -d || (k != d && v[offset + k - 1] < v[offset + k + 1])) {
        x = v[offset + k + 1];
      } else {
        x = v[offset + k - 1] + 1;
      }
      var y = x - k;
      while (x < n && y < m && a[x] == b[y]) {
        x++;
        y++;
      }
      v[offset + k] = x;
      if (x >= n && y >= m) {
        dFinal = d;
        break;
      }
    }
    if (dFinal >= 0) break;
  }
  if (dFinal < 0) {
    return [...List.filled(n, TipoLinea.quitada), ...List.filled(m, TipoLinea.agregada)];
  }

  // Se vuelve sobre los pasos para armar el camino.
  final ops = <TipoLinea>[];
  var x = n, y = m;
  for (var d = dFinal; d > 0; d--) {
    final t = trazas[d];
    final inicio = _inicioTraza(offset, d);
    // v[offset + k] del paso d, dentro de la parte guardada.
    int en(int k) => t[offset + k - inicio];
    final k = x - y;
    final int kPrev;
    if (k == -d || (k != d && en(k - 1) < en(k + 1))) {
      kPrev = k + 1;
    } else {
      kPrev = k - 1;
    }
    final xPrev = en(kPrev);
    final yPrev = xPrev - kPrev;
    while (x > xPrev && y > yPrev) {
      ops.add(TipoLinea.igual);
      x--;
      y--;
    }
    if (x == xPrev) {
      ops.add(TipoLinea.agregada);
    } else {
      ops.add(TipoLinea.quitada);
    }
    x = xPrev;
    y = yPrev;
  }
  while (x > 0 && y > 0) {
    ops.add(TipoLinea.igual);
    x--;
    y--;
  }
  return ops.reversed.toList();
}

int _inicioTraza(int offset, int d) => offset - d - 1 < 0 ? 0 : offset - d - 1;

/// En cada bloque de líneas quitadas seguido de agregadas, empareja una con
/// otra y marca qué palabras cambiaron (si se parecen lo suficiente).
List<LineaDiff> _marcarCambiosEnLinea(List<LineaDiff> lineas) {
  final r = [...lineas];
  var i = 0;
  while (i < r.length) {
    if (r[i].tipo != TipoLinea.quitada) {
      i++;
      continue;
    }
    final iniQ = i;
    while (i < r.length && r[i].tipo == TipoLinea.quitada) {
      i++;
    }
    final iniA = i;
    while (i < r.length && r[i].tipo == TipoLinea.agregada) {
      i++;
    }
    final pares = (iniA - iniQ) < (i - iniA) ? iniA - iniQ : i - iniA;
    for (var p = 0; p < pares; p++) {
      final q = r[iniQ + p], ag = r[iniA + p];
      final tramos = fragmentosPorPalabra(q.texto, ag.texto);
      if (tramos == null) continue;
      r[iniQ + p] = q.conFragmentos(tramos.antes);
      r[iniA + p] = ag.conFragmentos(tramos.despues);
    }
  }
  return r;
}

final _token = RegExp(r'\s+|[\p{L}\p{N}_]+|.', unicode: true);

/// Qué cambió entre dos líneas, palabra por palabra. `null` si son tan
/// distintas que marcarlo no ayuda (se muestra la línea entera).
({List<Fragmento> antes, List<Fragmento> despues})? fragmentosPorPalabra(String antes, String despues) {
  final a = _token.allMatches(antes).map((m) => m[0]!).toList();
  final b = _token.allMatches(despues).map((m) => m[0]!).toList();
  if (a.length + b.length > _maxTokensPorBloque) return null;
  final ops = diffListas(a, b);
  final ta = <Fragmento>[], tb = <Fragmento>[];
  var ia = 0, ib = 0, iguales = 0;
  void agregar(List<Fragmento> t, String s, bool cambiado) {
    if (t.isNotEmpty && t.last.cambiado == cambiado) {
      t[t.length - 1] = Fragmento(t.last.texto + s, cambiado: cambiado);
    } else {
      t.add(Fragmento(s, cambiado: cambiado));
    }
  }

  for (final op in ops) {
    switch (op) {
      case TipoLinea.igual:
        iguales += a[ia].trim().isEmpty ? 0 : a[ia].length;
        agregar(ta, a[ia++], false);
        agregar(tb, b[ib++], false);
      case TipoLinea.quitada:
        agregar(ta, a[ia++], true);
      case TipoLinea.agregada:
        agregar(tb, b[ib++], true);
    }
  }
  // Si casi nada quedó igual, son líneas distintas, no una modificada.
  final largo = antes.trim().length > despues.trim().length ? antes.trim().length : despues.trim().length;
  if (largo == 0 || iguales / largo < 0.3) return null;
  return (antes: ta, despues: tb);
}

/// Lo que se muestra: líneas con cambios y [contexto] líneas alrededor; lo
/// demás queda plegado ("Mostrar 25 líneas sin cambios").
sealed class Bloque {
  const Bloque();
}

class BloqueLineas extends Bloque {
  const BloqueLineas(this.lineas);
  final List<LineaDiff> lineas;
}

class BloquePlegado extends Bloque {
  const BloquePlegado(this.lineas);
  final List<LineaDiff> lineas;
}

List<Bloque> plegar(List<LineaDiff> lineas, {int contexto = 3}) {
  final visible = List<bool>.filled(lineas.length, false);
  for (var i = 0; i < lineas.length; i++) {
    if (lineas[i].tipo == TipoLinea.igual) continue;
    for (var j = i - contexto; j <= i + contexto; j++) {
      if (j >= 0 && j < lineas.length) visible[j] = true;
    }
  }
  final bloques = <Bloque>[];
  var i = 0;
  while (i < lineas.length) {
    final v = visible[i];
    final ini = i;
    while (i < lineas.length && visible[i] == v) {
      i++;
    }
    final tramo = lineas.sublist(ini, i);
    // Plegar 1 o 2 líneas no ahorra nada.
    bloques.add(v || tramo.length <= 2 ? BloqueLineas(tramo) : BloquePlegado(tramo));
  }
  return bloques;
}

/// Filas para la vista "lado a lado": cada fila tiene la línea de antes y la
/// de después (una de las dos puede faltar).
List<({LineaDiff? antes, LineaDiff? despues})> filasLadoALado(List<LineaDiff> lineas) {
  final filas = <({LineaDiff? antes, LineaDiff? despues})>[];
  var i = 0;
  while (i < lineas.length) {
    final l = lineas[i];
    if (l.tipo == TipoLinea.igual) {
      filas.add((antes: l, despues: l));
      i++;
      continue;
    }
    final quitadas = <LineaDiff>[], agregadas = <LineaDiff>[];
    while (i < lineas.length && lineas[i].tipo == TipoLinea.quitada) {
      quitadas.add(lineas[i++]);
    }
    while (i < lineas.length && lineas[i].tipo == TipoLinea.agregada) {
      agregadas.add(lineas[i++]);
    }
    final n = quitadas.length > agregadas.length ? quitadas.length : agregadas.length;
    for (var j = 0; j < n; j++) {
      filas.add((antes: quitadas.elementAtOrNull(j), despues: agregadas.elementAtOrNull(j)));
    }
  }
  return filas;
}
