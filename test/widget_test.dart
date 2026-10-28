import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaufi/catalog/catalog.dart';
import 'package:kaufi/core/day.dart';
import 'package:kaufi/model/app_state.dart';
import 'package:kaufi/state/controller.dart';
import 'package:kaufi/ui/app.dart';

void main() {
  final catalog = Catalog.fromJsonString(File('assets/catalog.json').readAsStringSync());
  final now = DateTime(2026, 11, 2, 18);

  AppController controller() => AppController(catalog, AppState(), clock: () => now);

  testWidgets('first start offers import', (tester) async {
    await tester.pumpWidget(KaufiApp(controller: controller()));
    expect(find.text('Plan importieren'), findsOneWidget);
    expect(find.text('Prompt für deine KI kopieren'), findsOneWidget);
  });

  testWidgets('tapping an item puts it into the basket and back', (tester) async {
    final c = controller();
    c.applyImport(c.parse(File('examples/beispiel-plan.json').readAsStringSync()), Day.today(now),
        replace: true);
    await tester.pumpWidget(KaufiApp(controller: c));

    expect(find.text('Einkauf'), findsOneWidget);
    expect(find.text('Für 7 Tage'), findsOneWidget);
    expect(find.text('Champignons'), findsOneWidget);
    expect(find.text('Im Korb · 1'), findsNothing);

    await tester.tap(find.text('Champignons'));
    await tester.pump();
    expect(find.textContaining('1 von 48'), findsOneWidget);
    expect(find.text('Fertig'), findsOneWidget);
    expect(c.kaufi.pantry('mushrooms'), 250);

    // The basket is below the open items.
    await tester.scrollUntilVisible(find.text('Im Korb · 1'), 400);
    await tester.pump();
    await tester.tap(find.text('Champignons'));
    await tester.pump();
    expect(find.text('Im Korb · 1'), findsNothing);
    expect(c.kaufi.pantry('mushrooms'), 0);
  });

  testWidgets('days control changes the window', (tester) async {
    final c = controller();
    c.applyImport(c.parse(File('examples/beispiel-plan.json').readAsStringSync()), Day.today(now),
        replace: true);
    await tester.pumpWidget(KaufiApp(controller: c));
    await tester.tap(find.byTooltip('Einen Tag weniger'));
    await tester.pump();
    expect(c.state.shoppingDays, 6);
    expect(find.text('Für 6 Tage'), findsOneWidget);
    // Salmon is only needed on day 7.
    expect(c.shoppingList.open.any((i) => i.key == 'frozen-salmon'), isFalse);
  });

  testWidgets('swipes from the screen edge are left to the system back gesture', (tester) async {
    final c = controller();
    c.applyImport(c.parse(File('examples/beispiel-plan.json').readAsStringSync()), Day.today(now),
        replace: true);
    await tester.pumpWidget(KaufiApp(controller: c));
    final row = tester.getCenter(find.text('Champignons'));
    final width = tester.view.physicalSize.width / tester.view.devicePixelRatio;
    // Back gesture from the right edge towards the left.
    await tester.dragFrom(Offset(width - 4, row.dy), const Offset(-500, 0));
    await tester.pumpAndSettle();
    // And from the left edge towards the right.
    await tester.dragFrom(Offset(4, row.dy), const Offset(500, 0));
    await tester.pumpAndSettle();
    expect(c.kaufi.pantry('mushrooms'), 0);
    expect(c.state.trip, isEmpty);
  });

  testWidgets('swipe left marks an item as already at home', (tester) async {
    final c = controller();
    c.applyImport(c.parse(File('examples/beispiel-plan.json').readAsStringSync()), Day.today(now),
        replace: true);
    await tester.pumpWidget(KaufiApp(controller: c));
    await tester.drag(find.text('Champignons'), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(find.text('Champignons'), findsNothing);
    expect(find.textContaining('als vorrätig gemerkt'), findsOneWidget);
    expect(c.kaufi.pantry('mushrooms'), 250);
    expect(find.byType(SnackBar), findsOneWidget);
    // The undo hint goes away on its own.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('drag the meal button to the middle and turn to filter by meal', (tester) async {
    final c = controller();
    c.applyImport(c.parse(File('examples/beispiel-plan.json').readAsStringSync()), Day.today(now),
        replace: true);
    await tester.pumpWidget(KaufiApp(controller: c));

    final size = tester.view.physicalSize / tester.view.devicePixelRatio;
    final center = Offset(size.width / 2, size.height * 0.45);
    final gesture = await tester.startGesture(tester.getCenter(find.byIcon(Icons.restaurant_menu)));
    await gesture.moveBy(const Offset(-20, -20));
    await tester.pump();
    expect(find.text('In die Mitte ziehen'), findsOneWidget);

    await gesture.moveTo(center + const Offset(0, -80));
    await tester.pump();
    expect(find.text('Drehen zum Wechseln · Loslassen wählt aus'), findsOneWidget);
    // A quarter turn clockwise, in small steps.
    for (var deg = -90; deg <= 0; deg += 10) {
      final a = deg * math.pi / 180;
      await gesture.moveTo(center + Offset(math.cos(a), math.sin(a)) * 80);
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();

    final meal = c.filteredMeal;
    expect(meal, isNotNull);
    expect(find.text(meal!.name), findsWidgets);
    expect(find.byTooltip('Filter aus'), findsOneWidget);

    // Tapping the button turns the filter off again.
    await tester.tap(find.byIcon(Icons.restaurant_menu));
    await tester.pumpAndSettle();
    expect(c.filteredMeal, isNull);
  });
}
