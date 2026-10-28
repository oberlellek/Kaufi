import 'dart:convert';

import '../core/units.dart';

/// Store sections. The order is a guess at a typical German supermarket and is
/// only used for ingredients whose position in the store has not been learned
/// yet.
enum Category {
  produce('Obst & Gemüse'),
  bakery('Brot & Backwaren'),
  meat('Fleisch & Wurst'),
  fish('Fisch'),
  dairy('Kühlregal'),
  dry('Nudeln, Reis & Getreide'),
  canned('Konserven & Gläser'),
  baking('Backzutaten'),
  spices('Gewürze'),
  condiments('Öle, Saucen & Aufstriche'),
  snacks('Nüsse & Snacks'),
  drinks('Getränke'),
  frozen('Tiefkühl'),
  other('Sonstiges');

  const Category(this.label);
  final String label;

  static Category parse(String? s) {
    for (final c in Category.values) {
      if (c.name == s) return c;
    }
    return Category.other;
  }
}

/// An ingredient independent of brand, e.g. "Haferflocken".
class IngredientDef {
  const IngredientDef({
    required this.id,
    required this.name,
    required this.unit,
    this.category = Category.other,
    this.pack,
    this.packLabel,
    this.countLabel,
    this.loose = false,
    this.priceMin,
    this.priceMax,
    this.gramsPerPiece,
    this.density = 1,
    this.synonyms = const [],
  });

  static const customPrefix = 'custom:';

  /// Catalog id such as `rolled-oats`, or `custom:<name>` for ingredients the
  /// catalog does not know.
  final String id;
  final String name;
  final Category category;

  /// The unit amounts of this ingredient are tracked in.
  final Dim unit;

  /// Typical package size in [unit]. What is bought is assumed to be whole
  /// packages, unless the ingredient is [loose].
  final double? pack;

  /// How a package is called when it is not just pieces, singular and
  /// plural: ("Knolle", "Knollen") for garlic counted in cloves.
  final (String, String)? packLabel;

  /// How one piece is called when it is not "Stück": ("Zehe", "Zehen").
  final (String, String)? countLabel;

  /// Sold by the piece or by weight, so you buy exactly what is missing.
  /// [pack] is then only the amount [priceMin] and [priceMax] refer to.
  final bool loose;

  /// Rough price range per package in EUR.
  final double? priceMin;
  final double? priceMax;

  final double? gramsPerPiece;

  /// Grams per millilitre, used to convert between mass and volume.
  final double density;
  final List<String> synonyms;

  bool get isCustom => id.startsWith(customPrefix);
  bool get hasPrice => pack != null && priceMin != null && priceMax != null;

  /// "2 Zehen", "250 g".
  String format(double amount) => formatAmount(amount, unit, label: countLabel);

  IngredientDef copyWith({double? pack}) => IngredientDef(
        id: id,
        name: name,
        unit: unit,
        category: category,
        pack: pack ?? this.pack,
        packLabel: packLabel,
        countLabel: countLabel,
        loose: loose,
        priceMin: priceMin,
        priceMax: priceMax,
        gramsPerPiece: gramsPerPiece,
        density: density,
        synonyms: synonyms,
      );

  /// Converts [amount] given in [unit] to this ingredient's base unit.
  /// Returns null when there is no sensible conversion (e.g. grams of an
  /// ingredient tracked in pieces without a known weight per piece).
  double? toBase(double amount, ParsedUnit parsed) {
    switch (parsed) {
      case PackUnit():
        return pack == null ? null : amount * pack!;
      case FixedUnit(:final dim, :final factor):
        final v = amount * factor;
        if (dim == unit) return v;
        final grams = switch (dim) {
          Dim.mass => v,
          Dim.volume => v * density,
          Dim.count => gramsPerPiece == null ? null : v * gramsPerPiece!,
        };
        if (grams == null) return null;
        return switch (unit) {
          Dim.mass => grams,
          Dim.volume => grams / density,
          Dim.count => gramsPerPiece == null ? null : grams / gramsPerPiece!,
        };
    }
  }

  factory IngredientDef.fromJson(Map<String, dynamic> j) {
    final price = j['price'];
    double? pMin, pMax;
    if (price is List && price.length == 2) {
      pMin = (price[0] as num).toDouble();
      pMax = (price[1] as num).toDouble();
    }
    (String, String)? label(Object? l) => l is List && l.length == 2 ? (l[0] as String, l[1] as String) : null;
    return IngredientDef(
      id: j['id'] as String,
      name: j['name'] as String,
      category: Category.parse(j['cat'] as String?),
      unit: Dim.fromCode(j['unit'] as String?) ?? Dim.count,
      pack: (j['pack'] as num?)?.toDouble(),
      packLabel: label(j['pl']),
      countLabel: label(j['cl']),
      loose: j['loose'] == true,
      priceMin: pMin,
      priceMax: pMax,
      gramsPerPiece: (j['pc'] as num?)?.toDouble(),
      density: (j['dens'] as num?)?.toDouble() ?? 1,
      synonyms: [for (final s in (j['syn'] as List? ?? const [])) s as String],
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'cat': category.name,
        'unit': unit.code,
        if (pack != null) 'pack': pack,
        if (packLabel != null) 'pl': [packLabel!.$1, packLabel!.$2],
        if (countLabel != null) 'cl': [countLabel!.$1, countLabel!.$2],
        if (loose) 'loose': true,
        if (priceMin != null && priceMax != null) 'price': [priceMin, priceMax],
        if (gramsPerPiece != null) 'pc': gramsPerPiece,
        if (density != 1) 'dens': density,
        if (synonyms.isNotEmpty) 'syn': synonyms,
      };
}

/// Lower case, umlauts folded, punctuation removed.
String normalizeName(String s) {
  var t = s
      .toLowerCase()
      .replaceAll('ä', 'ae')
      .replaceAll('ö', 'oe')
      .replaceAll('ü', 'ue')
      .replaceAll('ß', 'ss')
      .replaceAll(RegExp(r'[éèê]'), 'e')
      .replaceAll(RegExp(r'\(.*?\)'), ' ');
  // "Haferflocken, zart" -> "Haferflocken"
  final comma = t.indexOf(',');
  if (comma > 0) t = t.substring(0, comma);
  t = t.replaceAll(RegExp(r'[^a-z0-9 ]'), ' ');
  final words = t
      .split(' ')
      .where((w) => w.isNotEmpty && !_fillerWords.contains(w))
      .toList();
  return words.join(' ');
}

/// Words that describe quality or origin rather than the ingredient itself.
const _fillerWords = {
  'bio', 'frisch', 'frische', 'frischer', 'frisches', 'organic', 'fresh',
  'zart', 'zarte', 'kernig', 'kernige', 'natur', 'naturbelassen', 'regional',
  'deutsche', 'deutscher', 'klein', 'kleine', 'gross', 'grosse', 'mittelgross',
  'mittelgrosse', 'reif', 'reife', 'ca', 'etwa', 'optional', 'fein', 'feine',
};

/// Very rough German/English singular/plural folding: good enough to treat
/// "Ei"/"Eier", "Zwiebel"/"Zwiebeln" and "Tomate"/"Tomaten" as one word.
String stem(String normalized) {
  return normalized.split(' ').map((w) {
    for (final suffix in const ['ern', 'en', 'er', 'es', 'n', 'e', 's']) {
      if (w.length > suffix.length + 2 && w.endsWith(suffix)) {
        return w.substring(0, w.length - suffix.length);
      }
    }
    return w;
  }).join(' ');
}

/// The bundled ingredient catalog plus name matching.
class Catalog {
  Catalog(List<IngredientDef> items) {
    for (final it in items) {
      _byId[it.id] = it;
      for (final n in [it.id.replaceAll('-', ' '), it.name, ...it.synonyms]) {
        final norm = normalizeName(n);
        if (norm.isEmpty) continue;
        _byName.putIfAbsent(norm, () => it);
        _byStem.putIfAbsent(stem(norm), () => it);
      }
    }
  }

  factory Catalog.fromJsonString(String json) {
    final data = jsonDecode(json) as Map<String, dynamic>;
    return Catalog([
      for (final j in data['ingredients'] as List)
        IngredientDef.fromJson(j as Map<String, dynamic>),
    ]);
  }

  final _byId = <String, IngredientDef>{};
  final _byName = <String, IngredientDef>{};
  final _byStem = <String, IngredientDef>{};

  Iterable<IngredientDef> get all => _byId.values;

  IngredientDef? byId(String id) => _byId[id];

  /// Finds a catalog ingredient by id or by (fuzzy) name.
  IngredientDef? match({String? id, String? name}) {
    if (id != null) {
      // Accept Open Food Facts style ids like "en:rolled-oats".
      final clean = id.trim().toLowerCase().replaceFirst(RegExp(r'^[a-z]{2}:'), '');
      final hit = _byId[clean] ?? _byId[clean.replaceAll('_', '-')];
      if (hit != null) return hit;
    }
    for (final candidate in [name, id]) {
      if (candidate == null) continue;
      final norm = normalizeName(candidate.replaceAll(RegExp(r'[-_]'), ' '));
      if (norm.isEmpty) continue;
      final hit = _byName[norm] ?? _byStem[stem(norm)];
      if (hit != null) return hit;
    }
    return null;
  }
}
