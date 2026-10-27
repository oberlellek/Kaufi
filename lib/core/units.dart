/// Units and quantities.
///
/// Internally every amount is stored in the base unit of its dimension:
/// grams, millilitres or pieces. Import files may use any of the spellings
/// below; they are converted on import.
library;

enum Dim {
  mass('g'),
  volume('ml'),
  count('pcs');

  const Dim(this.code);
  final String code;

  static Dim? fromCode(String? code) {
    for (final d in Dim.values) {
      if (d.code == code) return d;
    }
    return null;
  }
}

/// A unit as written in an import file.
sealed class ParsedUnit {
  const ParsedUnit();
}

/// A unit with a fixed factor to a base unit (e.g. kg = 1000 g).
class FixedUnit extends ParsedUnit {
  const FixedUnit(this.dim, this.factor);
  final Dim dim;
  final double factor;
}

/// "1 Packung", "1 Dose": means one package of the ingredient, whatever size
/// the catalog says that is.
class PackUnit extends ParsedUnit {
  const PackUnit();
}

const _units = <String, ParsedUnit>{
  'g': FixedUnit(Dim.mass, 1),
  'gr': FixedUnit(Dim.mass, 1),
  'gramm': FixedUnit(Dim.mass, 1),
  'gram': FixedUnit(Dim.mass, 1),
  'grams': FixedUnit(Dim.mass, 1),
  'kg': FixedUnit(Dim.mass, 1000),
  'kilo': FixedUnit(Dim.mass, 1000),
  'kilogramm': FixedUnit(Dim.mass, 1000),
  'mg': FixedUnit(Dim.mass, 0.001),
  'prise': FixedUnit(Dim.mass, 0.5),
  'prisen': FixedUnit(Dim.mass, 0.5),
  'pinch': FixedUnit(Dim.mass, 0.5),
  'handvoll': FixedUnit(Dim.mass, 30),
  'handful': FixedUnit(Dim.mass, 30),
  'ml': FixedUnit(Dim.volume, 1),
  'milliliter': FixedUnit(Dim.volume, 1),
  'cl': FixedUnit(Dim.volume, 10),
  'dl': FixedUnit(Dim.volume, 100),
  'l': FixedUnit(Dim.volume, 1000),
  'liter': FixedUnit(Dim.volume, 1000),
  'litre': FixedUnit(Dim.volume, 1000),
  'tl': FixedUnit(Dim.volume, 5),
  'teeloeffel': FixedUnit(Dim.volume, 5),
  'tsp': FixedUnit(Dim.volume, 5),
  'el': FixedUnit(Dim.volume, 15),
  'essloeffel': FixedUnit(Dim.volume, 15),
  'tbsp': FixedUnit(Dim.volume, 15),
  'tasse': FixedUnit(Dim.volume, 240),
  'cup': FixedUnit(Dim.volume, 240),
  'pcs': FixedUnit(Dim.count, 1),
  'pc': FixedUnit(Dim.count, 1),
  'piece': FixedUnit(Dim.count, 1),
  'pieces': FixedUnit(Dim.count, 1),
  'stueck': FixedUnit(Dim.count, 1),
  'stk': FixedUnit(Dim.count, 1),
  'st': FixedUnit(Dim.count, 1),
  'x': FixedUnit(Dim.count, 1),
  'zehe': FixedUnit(Dim.count, 1),
  'zehen': FixedUnit(Dim.count, 1),
  'scheibe': FixedUnit(Dim.count, 1),
  'scheiben': FixedUnit(Dim.count, 1),
  'bund': FixedUnit(Dim.count, 1),
  'kopf': FixedUnit(Dim.count, 1),
  'knolle': FixedUnit(Dim.count, 1),
  'packung': PackUnit(),
  'packungen': PackUnit(),
  'pack': PackUnit(),
  'pck': PackUnit(),
  'pkg': PackUnit(),
  'package': PackUnit(),
  'dose': PackUnit(),
  'dosen': PackUnit(),
  'can': PackUnit(),
  'glas': PackUnit(),
  'glaeser': PackUnit(),
  'jar': PackUnit(),
  'becher': PackUnit(),
  'beutel': PackUnit(),
  'flasche': PackUnit(),
  'flaschen': PackUnit(),
  'netz': PackUnit(),
};

String _foldUnit(String s) => s
    .toLowerCase()
    .replaceAll('ä', 'ae')
    .replaceAll('ö', 'oe')
    .replaceAll('ü', 'ue')
    .replaceAll('ß', 'ss')
    .replaceAll('.', '')
    .trim();

/// Returns null for an unknown unit. An empty or missing unit means pieces.
ParsedUnit? parseUnit(String? unit) {
  if (unit == null || unit.trim().isEmpty) return const FixedUnit(Dim.count, 1);
  return _units[_foldUnit(unit)];
}

String _num(double v, {int decimals = 1}) {
  if ((v - v.roundToDouble()).abs() < 0.05) return v.round().toString();
  return v.toStringAsFixed(decimals).replaceAll('.', ',');
}

/// Human readable amount in German, e.g. "1,5 kg", "250 ml", "6 Stück".
String formatAmount(double amount, Dim dim) {
  switch (dim) {
    case Dim.mass:
      if (amount >= 1000) return '${_num(amount / 1000, decimals: 2)} kg';
      return '${_num(amount)} g';
    case Dim.volume:
      if (amount >= 1000) return '${_num(amount / 1000, decimals: 2)} l';
      return '${_num(amount)} ml';
    case Dim.count:
      return '${_num(amount)} Stück';
  }
}
