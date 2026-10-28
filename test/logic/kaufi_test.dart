import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kaufi/catalog/catalog.dart';
import 'package:kaufi/core/day.dart';
import 'package:kaufi/logic/kaufi.dart';
import 'package:kaufi/logic/plan_import.dart';
import 'package:kaufi/model/app_state.dart';

void main() {
  final catalog = Catalog.fromJsonString(File('assets/catalog.json').readAsStringSync());
  final monday = Day.tryParse('2026-11-02')!;
  final now = DateTime(2026, 11, 2, 10);

  Kaufi withPlan(String json, {int? days}) {
    final k = Kaufi(AppState(), catalog);
    k.applyImport(parsePlan(json, catalog), monday, monday, replace: true);
    if (days != null) k.state.shoppingDays = days;
    return k;
  }

  const week = '''
{"shoppingDays": 7, "meals": [
  {"day": 1, "name": "Rührei", "items": [{"name": "Eier", "amount": 4}, {"name": "Milch", "amount": 100, "unit": "ml"}]},
  {"day": 2, "name": "Oats", "items": [{"name": "Haferflocken", "amount": 80, "unit": "g"}, {"name": "Banane", "amount": 1}]},
  {"day": 3, "name": "Rührei", "items": [{"name": "Eier", "amount": 4}]},
  {"day": 9, "name": "Später", "items": [{"name": "Eier", "amount": 2}]}
]}''';

  test('the list shows what is missing, the basket gets whole packages', () {
    final k = withPlan(week);
    final list = k.shoppingList(monday);
    final eggs = list.open.firstWhere((i) => i.key == 'egg');
    expect(eggs.need, 8); // day 9 is outside the 7 day window
    expect(eggs.needLabel, '8 Stück');
    expect(eggs.buy, 10);
    expect(eggs.buyLabel, '10 Stück');
    final oats = list.open.firstWhere((i) => i.key == 'rolled-oats');
    expect(oats.needLabel, '80 g');
    expect(oats.buy, 500);
    expect(list.priceMin, greaterThan(0));
    expect(list.to, monday + 6);

    k.state.shoppingDays = 14;
    final longer = k.shoppingList(monday).open.firstWhere((i) => i.key == 'egg');
    expect(longer.need, 10);
    expect(longer.buy, 10);
  });

  test('loose produce is bought exactly, pieces have their own names', () {
    final k = withPlan('''
{"meals":[{"day":1,"name":"Chili","items":[
  {"name":"Zwiebel","amount":5},{"name":"Knoblauch","amount":2,"unit":"Zehen"},
  {"name":"Gurke","amount":0.5},{"name":"Salat","amount":0.75},{"name":"Salz"}]}]}''');
    k.setPantry('onion', 2);
    ShoppingItem item(String key) => k.shoppingList(monday).open.firstWhere((i) => i.key == key);

    expect(item('onion').needLabel, '3 Stück');
    expect(item('cucumber').needLabel, '1 Stück');
    expect(item('lettuce').needLabel, '1 Kopf');
    expect(item('garlic').needLabel, '2 Zehen');
    expect(item('salt').needLabel, 'etwas');

    expect(item('onion').priceMax, closeTo(0.6, 1e-9)); // 3 of a net of 10 at 2 €
    k.check('onion', monday, now);
    expect(k.pantry('onion'), 5);
    k.check('garlic', monday, now);
    expect(k.pantry('garlic'), 10);
    expect(k.shoppingList(monday).checked.firstWhere((i) => i.key == 'garlic').buyLabel, '1 Knolle');

    // "Hab ich schon" on a loose item assumes just enough, not a whole net.
    expect(k.markAtHome('cucumber', monday), 0.5);
  });

  test('checking adds to the pantry, leftovers are remembered next time', () {
    final k = withPlan(week);
    k.check('egg', monday, now);
    expect(k.pantry('egg'), 10);
    expect(k.shoppingList(monday).checked.single.key, 'egg');

    // A week later: the 8 eggs of this week were eaten, 2 are left, and the
    // meal on day 9 needs exactly 2.
    final nextMonday = monday + 7;
    k.settle(nextMonday, now.add(const Duration(days: 7)));
    expect(k.state.trip, isEmpty, reason: 'old trip is closed');
    expect(k.pantry('egg'), 2);
    expect(k.shoppingList(nextMonday).open.where((i) => i.key == 'egg'), isEmpty);
  });

  test('uncheck restores the pantry and forgets a mis-tapped route entry', () {
    final k = withPlan(week);
    k.check('egg', monday, now);
    k.uncheck('egg', now);
    expect(k.pantry('egg'), 0);
    expect(k.state.route, isEmpty);
    expect(k.shoppingList(monday).open.any((i) => i.key == 'egg'), isTrue);
  });

  test('learns the order of the first trip and keeps it', () {
    final k = withPlan(week);
    // Walk: bananas, milk, eggs, oats.
    for (final key in ['banana', 'milk', 'egg', 'rolled-oats']) {
      k.check(key, monday, now);
    }
    expect(k.state.route, ['banana', 'milk', 'egg', 'rolled-oats']);
    k.finishTrip();

    // Second trip in a different order does not reshuffle known items, and a
    // new item is placed after the item checked right before it.
    k.state.pantry.clear();
    k.applyImport(
        parsePlan(
            '{"meals":[{"day":1,"name":"X","items":[{"name":"Eier","amount":2},{"name":"Milch","amount":100,"unit":"ml"},{"name":"Butter","amount":10,"unit":"g"},{"name":"Bananen","amount":1}]}]}',
            catalog),
        monday,
        monday,
        replace: true);
    k.check('egg', monday, now);
    k.check('butter', monday, now);
    expect(k.state.route, ['banana', 'milk', 'egg', 'butter', 'rolled-oats']);

    final order = k.shoppingList(monday).open.map((i) => i.key).toList();
    expect(order, ['banana', 'milk']);
  });

  test('unlearned items sit next to learned items of the same section', () {
    final k = withPlan('''
{"meals":[{"day":1,"name":"X","items":[
  {"name":"Bananen","amount":1},{"name":"Eier","amount":2},{"name":"Joghurt","amount":200,"unit":"g"},
  {"name":"Gurke","amount":1},{"name":"Reis","amount":100,"unit":"g"}]}]}''');
    k.state.route.addAll(['egg', 'banana', 'rice']);
    final order = k.sortByRoute(k.shoppingList(monday).open).map((i) => i.key).toList();
    // yogurt (dairy) after egg (dairy), cucumber (produce) after banana.
    expect(order, ['egg', 'yogurt', 'banana', 'cucumber', 'rice']);
  });

  test('marking as already at home assumes at least one package', () {
    final k = withPlan(week);
    final added = k.markAtHome('rolled-oats', monday);
    expect(added, 500);
    expect(k.shoppingList(monday).open.any((i) => i.key == 'rolled-oats'), isFalse);
    k.undoMarkAtHome('rolled-oats', added);
    expect(k.pantry('rolled-oats'), 0);
  });

  test('a corrected amount can become the new package size', () {
    final k = withPlan(week);
    k.check('egg', monday, now, amount: 6);
    k.rememberPack('egg', 6);
    expect(k.pantry('egg'), 6);
    k.uncheck('egg', now);
    expect(k.shoppingList(monday).open.firstWhere((i) => i.key == 'egg').buy, 12);
  });

  test('moving meals changes what has to be bought now', () {
    final k = withPlan(week, days: 2);
    expect(k.shoppingList(monday).open.any((i) => i.key == 'rolled-oats'), isTrue);
    final oats = k.state.meals.firstWhere((m) => m.name == 'Oats');
    k.moveMeal(oats.id, monday + 5, monday);
    expect(k.shoppingList(monday).open.any((i) => i.key == 'rolled-oats'), isFalse);

    k.shiftFrom(monday, 1, monday);
    expect(k.state.meals.firstWhere((m) => m.name == 'Rührei').day, monday + 1);

    k.moveMeal(oats.id, monday - 3, monday);
    expect(oats.day, monday, reason: 'cannot move into the past');
  });

  test('replace import keeps eaten meals, skips meals in the past', () {
    final k = withPlan(week);
    k.settle(monday + 2, now);
    expect(k.state.meals.where((m) => m.consumed), hasLength(2));
    final skipped = k.applyImport(
        parsePlan('{"meals":[{"date":"2026-11-01","name":"Alt","items":[]},{"date":"2026-11-05","name":"Neu","items":[]}]}', catalog),
        monday,
        monday + 2,
        replace: true);
    expect(skipped, 1);
    expect(k.upcomingMeals.map((m) => m.name), ['Neu']);
  });

  test('the list can be narrowed down to one meal', () {
    final k = withPlan(week);
    final list = k.shoppingList(monday);
    final scramble = k.state.meals.firstWhere((m) => m.name == 'Rührei');
    final narrowed = list.forMeal(scramble);
    expect(narrowed.open.map((i) => i.key), unorderedEquals(['egg', 'milk']));
    expect(narrowed.meal, scramble);
    expect(narrowed.alreadyHome, 0);

    k.check('milk', monday, now);
    final after = k.shoppingList(monday).forMeal(scramble);
    expect(after.open.map((i) => i.key), ['egg']);
    expect(after.checked.map((i) => i.key), ['milk']);

    k.finishTrip();
    expect(k.shoppingList(monday).forMeal(scramble).alreadyHome, 1);

    // Only meals inside the shopping window are offered.
    k.state.shoppingDays = 2;
    expect(k.mealsInWindow(monday).map((m) => m.name), ['Rührei', 'Oats']);
  });

  test('state survives a JSON round trip', () {
    final k = withPlan(week);
    k.check('egg', monday, now);
    final copy = AppState.fromJson(k.state.toJson());
    expect(copy.toJson(), k.state.toJson());
  });
}
