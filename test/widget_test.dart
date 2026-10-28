import 'dart:io';

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

  testWidgets('the meal button opens a list to filter by meal', (tester) async {
    final c = controller();
    c.applyImport(c.parse(File('examples/beispiel-plan.json').readAsStringSync()), Day.today(now),
        replace: true);
    await tester.pumpWidget(KaufiApp(controller: c));

    await tester.tap(find.byIcon(Icons.restaurant_menu));
    await tester.pumpAndSettle();
    expect(find.text('Alle Zutaten'), findsOneWidget);
    final meal = c.kaufi.mealsInWindow(c.today).first;
    await tester.tap(find.text(meal.name).last);
    await tester.pumpAndSettle();

    expect(c.filteredMeal?.id, meal.id);
    expect(find.text(meal.name), findsWidgets);
    expect(find.byTooltip('Filter aus'), findsOneWidget);

    // Tapping the button again turns the filter off.
    await tester.tap(find.byIcon(Icons.restaurant_menu));
    await tester.pumpAndSettle();
    expect(c.filteredMeal, isNull);
  });

  testWidgets('the list shows what is still missing, not whole packages', (tester) async {
    final c = controller();
    c.applyImport(c.parse(File('examples/beispiel-plan.json').readAsStringSync()), Day.today(now),
        replace: true);
    await tester.pumpWidget(KaufiApp(controller: c));

    Finder label(String key, String text) =>
        find.descendant(of: find.byKey(ValueKey('open-$key')), matching: find.text(text));
    // The chili needs one onion and two cloves of garlic.
    await tester.scrollUntilVisible(label('onion', '1 Stück'), 300);
    await tester.scrollUntilVisible(label('garlic', '2 Zehen'), 300);

    // Onions are bought loose, garlic by the bulb.
    await tester.tap(find.text('Zwiebeln'));
    await tester.tap(find.text('Knoblauch'));
    await tester.pump();
    expect(c.kaufi.pantry('onion'), 1);
    expect(c.kaufi.pantry('garlic'), 10);
  });

  testWidgets('Fertig shows what goes into the pantry, corrections are learned', (tester) async {
    final c = controller();
    c.applyImport(c.parse(File('examples/beispiel-plan.json').readAsStringSync()), Day.today(now),
        replace: true);
    await tester.pumpWidget(KaufiApp(controller: c));
    await tester.tap(find.text('Champignons'));
    await tester.pump();
    expect(c.kaufi.pantry('mushrooms'), 250);

    await tester.tap(find.text('Fertig'));
    await tester.pumpAndSettle();
    expect(find.text('Das kommt in den Vorrat'), findsOneWidget);

    // Only 120 g were needed, and that is what was taken.
    await tester.tap(find.text('Champignons').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Was fehlt · 120 g'));
    await tester.pump();
    await tester.tap(find.text('Ich habe 120 g'));
    await tester.pumpAndSettle();
    expect(c.kaufi.pantry('mushrooms'), 120);
    expect(c.kaufi.purchaseUnit('mushrooms'), isNull, reason: 'bought loose from now on');

    await tester.tap(find.text('Passt'));
    await tester.pumpAndSettle();
    expect(c.state.trip, isEmpty);
    expect(c.kaufi.pantry('mushrooms'), 120);
  });

  testWidgets('what Kaufi thinks is at home can go back on the list', (tester) async {
    final c = controller();
    c.applyImport(c.parse(File('examples/beispiel-plan.json').readAsStringSync()), Day.today(now),
        replace: true);
    c.setPantry('mushrooms', 500);
    await tester.pumpWidget(KaufiApp(controller: c));
    expect(find.text('Champignons'), findsNothing);

    final header = find.textContaining('Hast du laut Kaufi noch');
    await tester.scrollUntilVisible(header, 500);
    await tester.tap(header);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Champignons'), 300);
    await tester.tap(find.text('Champignons'));
    await tester.pumpAndSettle();
    expect(c.kaufi.pantry('mushrooms'), 0);
    expect(c.shoppingList.open.any((i) => i.key == 'mushrooms'), isTrue);
    expect(find.text('Champignons steht wieder auf der Liste'), findsOneWidget);
  });
}
