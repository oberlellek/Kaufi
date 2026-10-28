import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kaufi/catalog/catalog.dart';
import 'package:kaufi/core/day.dart';
import 'package:kaufi/logic/plan_import.dart';

void main() {
  final catalog = Catalog.fromJsonString(File('assets/catalog.json').readAsStringSync());

  group('catalog matching', () {
    test('matches ids, names, synonyms and plurals', () {
      expect(catalog.match(id: 'egg')?.id, 'egg');
      expect(catalog.match(id: 'en:rolled-oats')?.id, 'rolled-oats');
      expect(catalog.match(id: 'rolled_oats')?.id, 'rolled-oats');
      expect(catalog.match(name: 'Eier')?.id, 'egg');
      expect(catalog.match(name: 'Ei')?.id, 'egg');
      expect(catalog.match(name: 'eggs')?.id, 'egg');
      expect(catalog.match(name: 'Bio Haferflocken, zart')?.id, 'rolled-oats');
      expect(catalog.match(name: 'Möhren')?.id, 'carrot');
      expect(catalog.match(name: 'Zwiebel')?.id, 'onion');
      expect(catalog.match(name: 'rote Zwiebeln')?.id, 'red-onion');
      expect(catalog.match(name: 'Tomatenmark')?.id, 'tomato-paste');
      expect(catalog.match(name: 'Kimchi'), isNull);
    });

    test('catalog ids are unique and every entry converts its own pack', () {
      final ids = catalog.all.map((d) => d.id).toList();
      expect(ids.toSet().length, ids.length);
      for (final d in catalog.all) {
        expect(d.pack, isNotNull, reason: d.id);
      }
    });
  });

  group('parsePlan', () {
    test('reads a plan wrapped in a chat answer', () {
      const text = '''
Hier ist dein Plan:
```json
{
  "kaufi": 1,
  "title": "Woche 1",
  "shoppingDays": 7,
  "meals": [
    {"date": "2026-11-02", "name": "Oats", "items": [
      {"id": "rolled-oats", "amount": 80, "unit": "g"},
      {"name": "Haferflocken", "amount": 0.02, "unit": "kg"},
      {"name": "Milch", "amount": 2, "unit": "dl"}
    ]},
    {"date": "2026-11-03", "name": "Rührei", "items": [
      {"name": "Eier", "amount": 3},
      {"name": "Salz"}
    ]}
  ]
}
```
Guten Appetit!''';
      final imp = parsePlan(text, catalog);
      expect(imp.title, 'Woche 1');
      expect(imp.shoppingDays, 7);
      expect(imp.meals, hasLength(2));
      final oats = imp.meals.first.needs;
      expect(oats.firstWhere((n) => n.key == 'rolled-oats').amount, closeTo(100, 1e-9));
      expect(oats.firstWhere((n) => n.key == 'milk').amount, closeTo(200, 1e-9));
      final eggs = imp.meals[1].needs.firstWhere((n) => n.key == 'egg');
      expect(eggs.amount, 3);
      expect(imp.meals[1].needs.any((n) => n.key == 'salt'), isTrue);
      expect(imp.unknownNames, isEmpty);
      expect(imp.needsStartDate, isFalse);
    });

    test('relative days need a start date', () {
      final imp = parsePlan(
          '{"meals":[{"day":1,"name":"A","items":[{"name":"Reis","amount":"150 g"}]},'
          '{"day":3,"name":"B","items":[]}]}',
          catalog);
      expect(imp.needsStartDate, isTrue);
      final meals = imp.toMeals(Day.tryParse('2026-11-02')!);
      expect(meals[0].day.iso, '2026-11-02');
      expect(meals[1].day.iso, '2026-11-04');
      expect(meals[0].needs.single.key, 'rice');
      expect(meals[0].needs.single.amount, 150);
    });

    test('unknown ingredients from two sources end up as one', () {
      final a = parsePlan(
          '{"meals":[{"day":1,"name":"A","items":[{"name":"Kimchi","amount":100,"unit":"g"}]}]}',
          catalog);
      expect(a.unknownNames, ['Kimchi']);
      final key = a.meals.single.needs.single.key;
      expect(key, startsWith('custom:'));
      final b = parsePlan(
          '{"meals":[{"day":1,"name":"B","items":[{"name":"kimchi (scharf)","amount":50,"unit":"g"}]}]}',
          catalog,
          existingCustom: a.newCustomDefs);
      expect(b.meals.single.needs.single.key, key);
      expect(b.newCustomDefs, isEmpty);
    });

    test('custom ingredient definitions in the file', () {
      final imp = parsePlan('''
{"ingredients":[{"id":"x1","name":"Kimchi","unit":"g","pack":{"amount":400,"unit":"g"},"category":"canned","price":{"min":3,"max":5}}],
 "meals":[{"date":"2026-11-02","name":"Bowl","items":[{"id":"x1","amount":1,"unit":"Glas"}]}]}''', catalog);
      final def = imp.newCustomDefs.values.single;
      expect(def.pack, 400);
      expect(def.category, Category.canned);
      expect(def.priceMax, 5);
      expect(imp.meals.single.needs.single.amount, 400);
    });

    test('units that do not convert are tracked separately', () {
      // Paprika is tracked in pieces and has a weight per piece, so grams work.
      final ok = parsePlan(
          '{"meals":[{"day":1,"name":"A","items":[{"name":"Paprika","amount":320,"unit":"g"}]}]}',
          catalog);
      expect(ok.meals.single.needs.single.key, 'bell-pepper');
      expect(ok.meals.single.needs.single.amount, closeTo(2, 1e-9));
      // Spring onions are counted in bunches without a known weight: grams
      // cannot be converted, but the line must not be dropped either.
      final odd = parsePlan(
          '{"meals":[{"day":1,"name":"A","items":[{"name":"Frühlingszwiebeln","amount":100,"unit":"g"}]}]}',
          catalog);
      expect(odd.meals.single.needs.single.key, 'custom:spring-onion@g');
    });

    test('also accepts days with nested meals', () {
      final imp = parsePlan(
          '{"days":[{"date":"2026-11-02","meals":[{"name":"A","ingredients":[{"name":"Eier","amount":2}]}]}]}',
          catalog);
      expect(imp.meals.single.day!.iso, '2026-11-02');
    });

    test('helpful errors', () {
      expect(() => parsePlan('hallo', catalog), throwsA(isA<PlanImportException>()));
      expect(() => parsePlan('{"meals": []}', catalog), throwsA(isA<PlanImportException>()));
      expect(() => parsePlan('{"meals": [{"name": "X"}]}', catalog),
          throwsA(isA<PlanImportException>()));
      expect(() => parsePlan('{"meals": [', catalog), throwsA(isA<PlanImportException>()));
    });

    test('the example plan in the repository imports cleanly', () {
      final imp = parsePlan(File('examples/beispiel-plan.json').readAsStringSync(), catalog);
      expect(imp.meals, isNotEmpty);
      expect(imp.warnings, isEmpty);
    });
  });
}
