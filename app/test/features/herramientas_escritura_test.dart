import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studyverse/features/cuestionarios/presentation/herramientas_escritura.dart';

TextEditingValue _v(String t, int cursor, [int? fin]) =>
    TextEditingValue(text: t, selection: TextSelection(baseOffset: cursor, extentOffset: fin ?? cursor));

void main() {
  group('insertarEn', () {
    test('inserta donde está el cursor y lo deja después', () {
      final r = insertarEn(_v('9,8 m/s', 7), '²');
      expect(r.text, '9,8 m/s²');
      expect(r.selection.baseOffset, 8);
    });

    test('reemplaza lo seleccionado', () {
      final r = insertarEn(_v('a >= b', 2, 4), '≥');
      expect(r.text, 'a ≥ b');
      expect(r.selection.baseOffset, 3);
    });

    test('sin cursor, agrega al final', () {
      final r = insertarEn(const TextEditingValue(text: 'x'), 'π');
      expect(r.text, 'xπ');
    });
  });

  group('insertarVineta', () {
    test('en una línea vacía, empieza la viñeta ahí', () {
      expect(insertarVineta(_v('', 0)).text, '• ');
      expect(insertarVineta(_v('Causas:\n', 8)).text, 'Causas:\n• ');
    });

    test('en una viñeta vacía no agrega otra', () {
      expect(insertarVineta(_v('Causas:\n• ', 10)).text, 'Causas:\n• ');
      expect(insertarVineta(_v('• ', 0)).text, '• ');
    });

    test('con el cursor al principio, antes de un salto de línea', () {
      expect(insertarVineta(_v('\nhola', 0)).text, '• \nhola');
    });

    test('en una línea con texto, pasa a una línea nueva', () {
      final r = insertarVineta(_v('Causas:', 7));
      expect(r.text, 'Causas:\n• ');
      expect(r.selection.baseOffset, r.text.length);
    });
  });

  testWidgets('un símbolo va donde está el cursor y el campo sigue con el foco', (tester) async {
    await tester.pumpWidget(const _Campo());
    await tester.enterText(find.byType(TextField), 'm/s');
    final st = tester.state<_CampoState>(find.byType(_Campo));
    st.c.selection = const TextSelection.collapsed(offset: 3);
    await tester.tap(find.byTooltip('Símbolos'));
    await tester.pump();
    await tester.tap(find.text('²'));
    await tester.pump();
    expect(st.c.text, 'm/s²');
    expect(st.c.selection.baseOffset, 4);
    expect(st.f.hasFocus, isTrue);
    expect(st.cambios.last, 'm/s²');
  });

  testWidgets('la barra no pasa el tope de caracteres', (tester) async {
    await tester.pumpWidget(const _Campo(maxLength: 3));
    await tester.enterText(find.byType(TextField), 'abc');
    final st = tester.state<_CampoState>(find.byType(_Campo));
    await tester.tap(find.byTooltip('Símbolos'));
    await tester.pump();
    await tester.tap(find.text('π'));
    await tester.pump();
    expect(st.c.text, 'abc');
  });

  test('contarPalabras', () {
    expect(contarPalabras(''), 0);
    expect(contarPalabras('  hola   mundo\n• uno '), 3);
    expect(contarPalabras('T = 2π√(L/g):\n• ñandú'), 3);
  });
}

class _Campo extends StatefulWidget {
  const _Campo({this.maxLength});
  final int? maxLength;
  @override
  State<_Campo> createState() => _CampoState();
}

class _CampoState extends State<_Campo> {
  final c = TextEditingController();
  final h = UndoHistoryController();
  final f = FocusNode();
  final cambios = <String>[];

  @override
  void dispose() {
    c.dispose();
    h.dispose();
    f.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Scaffold(
          body: Column(children: [
            HerramientasEscritura(
                controller: c, deshacer: h, focusNode: f, maxLength: widget.maxLength, alCambiar: cambios.add),
            TextField(controller: c, undoController: h, focusNode: f, maxLength: widget.maxLength),
          ]),
        ),
      );
}
