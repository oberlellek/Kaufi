import 'dart:convert';

import '../catalog/catalog.dart';
import '../core/day.dart';
import '../core/units.dart';
import '../model/app_state.dart';

class PlanImportException implements Exception {
  PlanImportException(this.message);
  final String message;
  @override
  String toString() => message;
}

class ImportedMeal {
  ImportedMeal({required this.name, required this.needs, this.day, this.dayOffset});

  final String name;
  final List<Need> needs;

  /// Absolute date, if the file gave one.
  final Day? day;

  /// Otherwise days after the plan's start (0 = first day).
  final int? dayOffset;

  Day resolve(Day start) => day ?? start + (dayOffset ?? 0);
}

/// A parsed, not yet applied import file.
class PlanImport {
  PlanImport({
    required this.meals,
    required this.newCustomDefs,
    required this.unknownNames,
    required this.warnings,
    this.title,
    this.source,
    this.shoppingDays,
    this.startDate,
  });

  final String? title;
  final String? source;
  final int? shoppingDays;
  final Day? startDate;
  final List<ImportedMeal> meals;

  /// Ingredients the catalog does not know and that are new to this device.
  final Map<String, IngredientDef> newCustomDefs;

  /// Display names of ingredients that could not be matched to the catalog.
  final List<String> unknownNames;
  final List<String> warnings;

  /// True when at least one meal is given relative to a start day that the
  /// file does not define, so the user has to pick it.
  bool get needsStartDate =>
      startDate == null && meals.any((m) => m.day == null);

  Set<String> get ingredientKeys => {
        for (final m in meals)
          for (final n in m.needs) n.key,
      };

  List<Meal> toMeals(Day start) {
    final stamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    return [
      for (var i = 0; i < meals.length; i++)
        Meal(
          id: '$stamp-$i',
          day: meals[i].resolve(startDate ?? start),
          name: meals[i].name,
          needs: meals[i].needs,
          plan: title,
        ),
    ];
  }
}

/// Pulls the JSON object out of text that may be wrapped in a chat answer or a
/// Markdown code block.
String extractJson(String text) {
  final fence = RegExp(r'```(?:json)?\s*([\s\S]*?)```').firstMatch(text);
  final body = fence != null ? fence.group(1)! : text;
  final start = body.indexOf('{');
  final end = body.lastIndexOf('}');
  if (start < 0 || end <= start) {
    throw PlanImportException(
        'Im Text wurde kein Plan gefunden. Erwartet wird ein JSON-Objekt im Kaufi-Format.');
  }
  return body.substring(start, end + 1);
}

String customKeyFor(String name) =>
    '${IngredientDef.customPrefix}${stem(normalizeName(name))}';

PlanImport parsePlan(
  String text,
  Catalog catalog, {
  Map<String, IngredientDef> existingCustom = const {},
}) {
  final Object? decoded;
  try {
    decoded = jsonDecode(extractJson(text));
  } on FormatException catch (e) {
    throw PlanImportException('Die Datei ist kein gültiges JSON: ${e.message}');
  }
  if (decoded is! Map<String, dynamic>) {
    throw PlanImportException('Erwartet wird ein JSON-Objekt mit "meals".');
  }
  return _Parser(catalog, existingCustom).parse(decoded);
}

class _Parser {
  _Parser(this.catalog, this.existingCustom);

  final Catalog catalog;
  final Map<String, IngredientDef> existingCustom;
  final newDefs = <String, IngredientDef>{};
  final fileDefs = <String, IngredientDef>{};
  final unknown = <String>{};
  final warnings = <String>[];

  PlanImport parse(Map<String, dynamic> j) {
    final version = j['kaufi'];
    if (version is num && version > 1) {
      warnings.add('Die Datei nutzt Format-Version $version. Diese App kennt Version 1, '
          'unbekannte Felder werden ignoriert.');
    }

    final startDate = Day.tryParse(_str(j['startDate']));
    final days = _int(j['shoppingDays']);

    for (final d in _list(j['ingredients'])) {
      if (d is Map<String, dynamic>) _readDefinition(d);
    }

    final rawMeals = <Map<String, dynamic>>[];
    for (final m in _list(j['meals'])) {
      if (m is Map<String, dynamic>) rawMeals.add(m);
    }
    // Also accept {"days": [{"date": ..., "meals": [...]}]}.
    for (final d in _list(j['days'])) {
      if (d is! Map<String, dynamic>) continue;
      for (final m in _list(d['meals'])) {
        if (m is Map<String, dynamic>) {
          rawMeals.add({'date': d['date'], 'day': d['day'], ...m});
        }
      }
    }
    if (rawMeals.isEmpty) {
      throw PlanImportException('Im Plan stehen keine Gerichte ("meals" fehlt oder ist leer).');
    }

    final meals = [for (var i = 0; i < rawMeals.length; i++) _readMeal(rawMeals[i], i)];

    return PlanImport(
      title: _str(j['title']),
      source: _str(j['source']),
      shoppingDays: days?.clamp(1, 60),
      startDate: startDate,
      meals: meals,
      newCustomDefs: newDefs,
      unknownNames: unknown.toList()..sort(),
      warnings: warnings,
    );
  }

  void _readDefinition(Map<String, dynamic> d) {
    final id = _str(d['id']);
    final name = _str(d['name']) ?? id;
    if (name == null) return;
    final known = catalog.match(id: id, name: name);
    if (known != null) {
      if (id != null) fileDefs[id] = known;
      return;
    }
    final key = customKeyFor(name);
    final unit = switch (parseUnit(_str(d['unit']))) {
      FixedUnit(:final dim) => dim,
      _ => Dim.count,
    };
    final pack = d['pack'];
    double? packBase;
    if (pack is num) {
      packBase = pack.toDouble();
    } else if (pack is Map<String, dynamic>) {
      final pu = parseUnit(_str(pack['unit']));
      final pa = _num(pack['amount']);
      if (pu is FixedUnit && pa != null && pu.dim == unit) packBase = pa * pu.factor;
    }
    final (pMin, pMax) = _price(d['price']);
    final def = existingCustom[key] ??
        IngredientDef(
          id: key,
          name: name,
          unit: unit,
          category: Category.parse(_str(d['category'])),
          pack: packBase,
          priceMin: pMin,
          priceMax: pMax,
          gramsPerPiece: _num(d['gramsPerPiece']),
        );
    if (!existingCustom.containsKey(key)) newDefs[key] = def;
    unknown.add(def.name);
    fileDefs[id ?? name] = def;
  }

  ImportedMeal _readMeal(Map<String, dynamic> m, int index) {
    final name = _str(m['name']) ?? _str(m['title']) ?? 'Gericht ${index + 1}';
    final date = Day.tryParse(_str(m['date']));
    final dayNo = _int(m['day']);
    if (date == null && dayNo == null) {
      throw PlanImportException(
          '"$name" hat weder "date" (JJJJ-MM-TT) noch "day" (1, 2, 3 …).');
    }
    final sums = <String, double>{};
    for (final it in [..._list(m['items']), ..._list(m['ingredients'])]) {
      final need = _readItem(it, name);
      if (need != null) sums[need.key] = (sums[need.key] ?? 0) + need.amount;
    }
    if (sums.isEmpty) warnings.add('"$name" hat keine Zutaten.');
    return ImportedMeal(
      name: name,
      day: date,
      dayOffset: date == null ? (dayNo! - 1).clamp(0, 365) : null,
      needs: [for (final e in sums.entries) Need(e.key, e.value)],
    );
  }

  Need? _readItem(Object? it, String mealName) {
    String? id, name, unitStr;
    double? amount;
    if (it is String) {
      name = it;
    } else if (it is Map<String, dynamic>) {
      id = _str(it['id']);
      name = _str(it['name']);
      unitStr = _str(it['unit']);
      final a = it['amount'] ?? it['quantity'] ?? it['qty'];
      if (a is num) {
        amount = a.toDouble();
      } else if (a is String) {
        // "200 g"
        final mm = RegExp(r'^\s*([\d.,]+)\s*(.*)$').firstMatch(a);
        if (mm != null) {
          amount = double.tryParse(mm.group(1)!.replaceAll(',', '.'));
          if (mm.group(2)!.trim().isNotEmpty) unitStr ??= mm.group(2)!.trim();
        }
      }
    } else {
      return null;
    }
    if (id == null && name == null) return null;

    final def = _resolve(id, name, unitStr);
    // No amount ("Salz nach Geschmack"): it just has to be in the house.
    if (amount == null && unitStr == null) return Need(def.id, 1);
    var parsed = parseUnit(unitStr);
    if (parsed == null) {
      warnings.add('Unbekannte Einheit "$unitStr" bei ${def.name} ($mealName), als 1 Packung gezählt.');
      parsed = const PackUnit();
      amount = 1;
    }
    final a = amount ?? 1;
    var base = def.toBase(a, parsed);
    if (base != null) return Need(def.id, base);

    // No conversion possible: track this ingredient separately in this unit.
    final dim = parsed is FixedUnit ? parsed.dim : Dim.count;
    final bareId = def.id.replaceFirst(IngredientDef.customPrefix, '');
    final variantKey = '${IngredientDef.customPrefix}$bareId@${dim.code}';
    final variant = existingCustom[variantKey] ??
        newDefs[variantKey] ??
        IngredientDef(id: variantKey, name: def.name, unit: dim, category: def.category);
    if (!existingCustom.containsKey(variantKey)) newDefs[variantKey] = variant;
    base = variant.toBase(a, parsed is PackUnit ? const FixedUnit(Dim.count, 1) : parsed);
    return Need(variantKey, base ?? a);
  }

  IngredientDef _resolve(String? id, String? name, String? unitStr) {
    if (id != null && fileDefs.containsKey(id)) return fileDefs[id]!;
    if (name != null && fileDefs.containsKey(name)) return fileDefs[name]!;
    final known = catalog.match(id: id, name: name);
    if (known != null) return known;

    final display = name ?? id!;
    final key = customKeyFor(display);
    final existing = existingCustom[key] ?? newDefs[key];
    if (existing != null) {
      unknown.add(existing.name);
      return existing;
    }
    final unit = switch (parseUnit(unitStr)) {
      FixedUnit(:final dim) => dim,
      _ => Dim.count,
    };
    final def = IngredientDef(id: key, name: display, unit: unit);
    newDefs[key] = def;
    unknown.add(display);
    return def;
  }
}

List<Object?> _list(Object? o) => o is List ? o : const [];

String? _str(Object? o) {
  if (o is String && o.trim().isNotEmpty) return o.trim();
  if (o is num) return o.toString();
  return null;
}

int? _int(Object? o) {
  if (o is num) return o.toInt();
  if (o is String) return int.tryParse(o.trim());
  return null;
}

double? _num(Object? o) {
  if (o is num) return o.toDouble();
  if (o is String) return double.tryParse(o.replaceAll(',', '.'));
  return null;
}

(double?, double?) _price(Object? o) {
  if (o is List && o.length == 2 && o[0] is num && o[1] is num) {
    return ((o[0] as num).toDouble(), (o[1] as num).toDouble());
  }
  if (o is Map<String, dynamic>) {
    final min = _num(o['min']);
    final max = _num(o['max']) ?? min;
    return (min ?? max, max);
  }
  if (o is num) return (o.toDouble(), o.toDouble());
  return (null, null);
}
