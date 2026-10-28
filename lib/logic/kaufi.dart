import 'dart:math' as math;

import '../catalog/catalog.dart';
import '../core/day.dart';
import '../core/units.dart';
import '../model/app_state.dart';
import 'plan_import.dart';

const _eps = 1e-6;

/// A shopping trip counts as finished when nothing was checked for this long.
const tripTimeout = Duration(hours: 4);

/// Whether [def] is bought in exactly the amount missing rather than in whole
/// packages of [pack].
bool buysExactly(IngredientDef def, double? pack) => def.loose || pack == null || pack <= 0;

/// Rounds up to what can be bought: whole pieces, whole grams or millilitres.
double roundUpToWhole(double amount) => math.max(0, (amount - _eps).ceil()).toDouble();

/// "3 Stück", "2 Zehen", "250 g". Amounts too small to buy, like a pinch of
/// salt or a teaspoon of cumin, read "etwas": what matters is that it is in
/// the house. With [whole], rounds up to whole pieces or grams.
String formatNeed(IngredientDef def, double amount, {bool whole = true}) {
  if (def.unit != Dim.count && amount < 5) return 'etwas';
  return def.format(whole ? roundUpToWhole(amount) : amount);
}

class ShoppingItem {
  ShoppingItem({
    required this.def,
    required this.need,
    required this.atHome,
    required this.buy,
    this.pack,
    this.tripEntry,
    this.usedIn = const [],
  });

  final IngredientDef def;

  /// Needed within the shopping window.
  final double need;

  /// In the pantry, including what is already in the basket.
  final double atHome;

  /// What checking off puts into the basket (unchecked) or what was bought
  /// (checked): whole packages, or exactly what is missing for loose items.
  final double buy;
  final double? pack;
  final TripEntry? tripEntry;

  /// Names of the meals in the window that need this ingredient.
  final List<String> usedIn;

  bool get checked => tripEntry != null;
  String get key => def.id;
  double get missing => math.max(0, need - atHome);
  bool get exact => buysExactly(def, pack);

  int? get packs => pack == null ? null : (buy / pack! - _eps).ceil().clamp(1, 999);

  double? get priceMin => _price(def.priceMin);
  double? get priceMax => _price(def.priceMax);

  double? _price(double? perPack) {
    if (!def.hasPrice || perPack == null) return null;
    if (def.loose) return buy / def.pack! * perPack;
    return packs == null ? null : packs! * perPack;
  }

  /// What is still missing: "3 Stück", "2 Zehen", "etwas".
  String get needLabel => formatNeed(def, missing);

  /// What is in the basket: "1 Knolle", "2 × 400 g", "3 Stück".
  String get buyLabel {
    final p = packs;
    if (!exact && p != null && (p * pack! - buy).abs() < 0.01) {
      final label = def.packLabel;
      if (label != null) return '$p ${p == 1 ? label.$1 : label.$2}';
      // One piece per package reads better as a plain count.
      if (!(def.unit == Dim.count && pack == 1)) {
        final size = def.format(pack!);
        return p == 1 ? size : '$p × $size';
      }
    }
    return def.format(buy);
  }
}

class ShoppingList {
  ShoppingList({
    required this.from,
    required this.to,
    required this.open,
    required this.checked,
    this.meal,
    this.alreadyHome = 0,
  });

  final Day from;
  final Day to;
  final List<ShoppingItem> open;
  final List<ShoppingItem> checked;

  /// Set when the list is narrowed down to one meal.
  final Meal? meal;

  /// Ingredients of [meal] that need no shopping because they are at home.
  final int alreadyHome;

  /// Only what [meal] needs, in the same order.
  ShoppingList forMeal(Meal meal) {
    final keys = {for (final n in meal.needs) n.key};
    final o = open.where((i) => keys.contains(i.key)).toList();
    final c = checked.where((i) => keys.contains(i.key)).toList();
    return ShoppingList(
      from: from,
      to: to,
      open: o,
      checked: c,
      meal: meal,
      alreadyHome: keys.length - o.length - c.length,
    );
  }

  Iterable<ShoppingItem> get all => [...open, ...checked];
  bool get isEmpty => open.isEmpty && checked.isEmpty;

  double get priceMin => all.fold(0, (s, i) => s + (i.priceMin ?? 0));
  double get priceMax => all.fold(0, (s, i) => s + (i.priceMax ?? 0));
  int get unpriced => all.where((i) => i.priceMin == null).length;
}

/// The app's domain logic, operating on an [AppState]. No I/O, no Flutter.
class Kaufi {
  Kaufi(this.state, this.catalog);

  final AppState state;
  final Catalog catalog;

  IngredientDef def(String key) =>
      state.customDefs[key] ??
      catalog.byId(key) ??
      IngredientDef(id: key, name: key.replaceFirst(IngredientDef.customPrefix, ''), unit: Dim.count);

  double? packFor(String key) => state.packOverrides[key] ?? def(key).pack;

  double pantry(String key) => state.pantry[key] ?? 0;

  void _addPantry(String key, double delta) {
    final v = pantry(key) + delta;
    if (v <= _eps) {
      state.pantry.remove(key);
    } else {
      state.pantry[key] = v;
    }
  }

  /// Brings the state up to date with the calendar: meals of past days are
  /// considered eaten and leave the pantry, a stale shopping trip is closed.
  /// Returns whether anything changed.
  bool settle(Day today, DateTime now) {
    var changed = false;
    for (final m in state.meals) {
      if (!m.consumed && m.day < today) {
        for (final n in m.needs) {
          _addPantry(n.key, -n.amount);
        }
        m.consumed = true;
        changed = true;
      }
    }
    final before = state.meals.length;
    state.meals.removeWhere((m) => m.consumed && m.day < today - 60);
    changed |= state.meals.length != before;

    final last = state.tripLastActivity;
    if (state.trip.isNotEmpty && last != null && now.difference(last) > tripTimeout) {
      finishTrip();
      changed = true;
    }
    return changed;
  }

  /// Meal names per ingredient for meals in `[from, from + days)`.
  Map<String, List<String>> usage(Day from, int days) {
    final out = <String, List<String>>{};
    for (final m in upcomingMeals) {
      if (m.day < from || m.day >= from + days) continue;
      final name = m.displayName;
      for (final n in m.needs) {
        final list = out.putIfAbsent(n.key, () => []);
        if (!list.contains(name)) list.add(name);
      }
    }
    return out;
  }

  /// Total needs per ingredient for meals in `[from, from + days)`.
  Map<String, double> needs(Day from, int days) {
    final to = from + days;
    final out = <String, double>{};
    for (final m in state.meals) {
      if (m.consumed || m.day < from || m.day >= to) continue;
      for (final n in m.needs) {
        out[n.key] = (out[n.key] ?? 0) + n.amount;
      }
    }
    return out;
  }

  /// What checking off puts into the pantry: exactly what is missing for
  /// loose items, otherwise whole packages.
  double suggestedBuy(String key, double missing) {
    final pack = packFor(key);
    if (buysExactly(def(key), pack)) return roundUpToWhole(missing);
    return (missing / pack! - _eps).ceil() * pack;
  }

  ShoppingList shoppingList(Day today) {
    final days = state.shoppingDays;
    final need = needs(today, days);
    final inTrip = {for (final t in state.trip) t.key: t};
    final used = usage(today, days);

    final open = <ShoppingItem>[];
    for (final e in need.entries) {
      if (inTrip.containsKey(e.key)) continue;
      final missing = e.value - pantry(e.key);
      if (missing <= _eps) continue;
      open.add(ShoppingItem(
        def: def(e.key),
        need: e.value,
        atHome: pantry(e.key),
        buy: suggestedBuy(e.key, missing),
        pack: packFor(e.key),
        usedIn: used[e.key] ?? const [],
      ));
    }

    final checked = [
      for (final t in state.trip)
        ShoppingItem(
          def: def(t.key),
          need: need[t.key] ?? 0,
          atHome: pantry(t.key),
          buy: t.amount,
          pack: packFor(t.key),
          tripEntry: t,
          usedIn: used[t.key] ?? const [],
        ),
    ];

    return ShoppingList(
      from: today,
      to: today + (days - 1),
      open: sortByRoute(open),
      checked: checked,
    );
  }

  /// Orders items the way the user walked through the store the first time
  /// they bought them. Items never bought before go next to learned items of
  /// the same store section, or to the end grouped by section.
  List<ShoppingItem> sortByRoute(List<ShoppingItem> items) {
    final index = {for (var i = 0; i < state.route.length; i++) state.route[i]: i};
    final lastOfCategory = <Category, int>{};
    for (var i = 0; i < state.route.length; i++) {
      lastOfCategory[def(state.route[i]).category] = i;
    }
    double position(ShoppingItem it) {
      final i = index[it.key];
      if (i != null) return i.toDouble();
      final anchor = lastOfCategory[it.def.category];
      if (anchor != null) return anchor + 0.5;
      return state.route.length + 1.0 + it.def.category.index;
    }

    return [...items]..sort((a, b) {
        final c = position(a).compareTo(position(b));
        return c != 0 ? c : a.def.name.compareTo(b.def.name);
      });
  }

  /// Puts an item into the basket. [amount] defaults to the suggested amount.
  void check(String key, Day today, DateTime now, {double? amount}) {
    if (state.trip.any((t) => t.key == key)) return;
    final missing = math.max(0.0, (needs(today, state.shoppingDays)[key] ?? 0) - pantry(key));
    final bought = amount ?? suggestedBuy(key, missing);

    var learned = false;
    if (!state.route.contains(key)) {
      // Insert right after the last item of this trip that has a place in the
      // route; for the first item of a trip, at the start.
      var at = 0;
      for (final t in state.trip.reversed) {
        final i = state.route.indexOf(t.key);
        if (i >= 0) {
          at = i + 1;
          break;
        }
      }
      state.route.insert(at, key);
      learned = true;
    }

    _addPantry(key, bought);
    state.trip.add(TripEntry(key, bought, learnedRoute: learned));
    state.tripLastActivity = now;
  }

  void uncheck(String key, DateTime now) {
    final i = state.trip.indexWhere((t) => t.key == key);
    if (i < 0) return;
    final t = state.trip.removeAt(i);
    _addPantry(key, -t.amount);
    if (t.learnedRoute) state.route.remove(key);
    state.tripLastActivity = now;
  }

  /// Changes the amount of an item already in the basket.
  void changeBought(String key, double amount, DateTime now) {
    final i = state.trip.indexWhere((t) => t.key == key);
    if (i < 0) return;
    final t = state.trip[i];
    _addPantry(key, amount - t.amount);
    state.trip[i] = TripEntry(key, amount, learnedRoute: t.learnedRoute);
    state.tripLastActivity = now;
  }

  void rememberPack(String key, double pack) {
    if (pack > _eps) state.packOverrides[key] = pack;
  }

  /// "Hab ich schon": the item is at home already. Without knowing how much,
  /// assume enough for the window, and at least one package of things that
  /// come in packages. Returns the amount added so the caller can undo it.
  double markAtHome(String key, Day today) {
    final missing = math.max(0.0, (needs(today, state.shoppingDays)[key] ?? 0) - pantry(key));
    final pack = packFor(key);
    final add = buysExactly(def(key), pack) ? missing : math.max(missing, pack!);
    _addPantry(key, add);
    return add;
  }

  void undoMarkAtHome(String key, double added) => _addPantry(key, -added);

  void finishTrip() {
    state.trip.clear();
    state.tripLastActivity = null;
  }

  void setPantry(String key, double amount) {
    state.pantry.remove(key);
    _addPantry(key, amount);
  }

  Meal? meal(String id) {
    for (final m in state.meals) {
      if (m.id == id) return m;
    }
    return null;
  }

  void moveMeal(String id, Day to, Day today) {
    final m = meal(id);
    if (m == null || m.consumed) return;
    m.day = to < today ? today : to;
  }

  /// Moves every upcoming meal on or after [from] by [days].
  void shiftFrom(Day from, int days, Day today) {
    for (final m in state.meals) {
      if (m.consumed || m.day < from) continue;
      final d = m.day + days;
      m.day = d < today ? today : d;
    }
  }

  void deleteMeal(String id) => state.meals.removeWhere((m) => m.id == id);

  /// Adds an imported plan. With [replace], upcoming meals are dropped first.
  /// Meals dated before today are skipped; returns how many.
  int applyImport(PlanImport imp, Day start, Day today, {required bool replace}) {
    if (replace) state.meals.removeWhere((m) => !m.consumed);
    for (final e in imp.newCustomDefs.entries) {
      state.customDefs.putIfAbsent(e.key, () => e.value);
    }
    var skipped = 0;
    for (final m in imp.toMeals(start)) {
      if (m.day < today) {
        skipped++;
      } else {
        state.meals.add(m);
      }
    }
    state.meals.sort((a, b) => a.day.compareTo(b.day));
    if (imp.shoppingDays != null) state.shoppingDays = imp.shoppingDays!;
    return skipped;
  }

  /// Meals within the shopping window that need any ingredient, by day.
  List<Meal> mealsInWindow(Day today) {
    final end = today + state.shoppingDays;
    return upcomingMeals.where((m) => m.day >= today && m.day < end && m.needs.isNotEmpty).toList();
  }

  /// Upcoming (not yet eaten) meals, by day.
  List<Meal> get upcomingMeals =>
      state.meals.where((m) => !m.consumed).toList()..sort((a, b) => a.day.compareTo(b.day));

  /// Pantry entries with something left, sorted by name.
  List<(IngredientDef, double)> get pantryItems {
    final out = [for (final e in state.pantry.entries) (def(e.key), e.value)];
    out.sort((a, b) => a.$1.name.compareTo(b.$1.name));
    return out;
  }
}
