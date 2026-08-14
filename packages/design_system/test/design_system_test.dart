import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:design_system/design_system.dart';

void main() {
  test('токены совпадают с брендбуком', () {
    expect(TkColors.primary, const Color(0xFFE8730C));
    expect(TkColors.graphite, const Color(0xFF1A1D21));
    expect(TkRadius.card, 12);
    expect(TkRadius.button, 10);
  });

  test('статусная карта покрывает все статусы уникальными цветами', () {
    final colors = TkStatus.values.map((s) => s.color.toARGB32()).toSet();
    expect(colors.length, TkStatus.values.length, reason: 'цвета статусов должны различаться');
    expect(TkStatus.inProgress.color, TkColors.primary);
    expect(TkStatus.completed.color, TkColors.success);
  });

  testWidgets('темы строятся; primary в тёмной чуть глуше', (tester) async {
    expect(TkTheme.light.brightness, Brightness.light);
    expect(TkTheme.dark.brightness, Brightness.dark);
    expect(TkTheme.dark.colorScheme.primary, TkColors.primaryDark);
  });

  testWidgets('TkButton рендерится и кликается', (tester) async {
    var tapped = false;
    await tester.pumpWidget(MaterialApp(
      theme: TkTheme.light,
      home: Scaffold(
        body: TkButton(label: 'Далее', onPressed: () => tapped = true),
      ),
    ));
    expect(find.text('Далее'), findsOneWidget);
    await tester.tap(find.text('Далее'));
    expect(tapped, isTrue);
  });

  testWidgets('TkStatusBadge показывает подпись и цвет статуса', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: TkTheme.light,
      home: const Scaffold(
        body: TkStatusBadge(status: TkStatus.bidding, label: 'Идёт торг'),
      ),
    ));
    expect(find.text('Идёт торг'), findsOneWidget);
  });
}
