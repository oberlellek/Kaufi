import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../catalog/catalog.dart';
import '../core/day.dart';
import '../logic/kaufi.dart';
import '../logic/plan_import.dart';
import '../model/app_state.dart';

const _stateKey = 'kaufi.state';

/// Holds the app state, persists every change locally and tells the UI.
///
/// Nothing leaves the device: the state is one JSON document in the
/// platform's key-value storage.
class AppController extends ChangeNotifier {
  AppController(this.catalog, AppState state, {this.prefs, DateTime Function()? clock})
      : kaufi = Kaufi(state, catalog),
        _clock = clock ?? DateTime.now {
    kaufi.settle(today, now);
  }

  static Future<AppController> load() async {
    final catalog = Catalog.fromJsonString(await rootBundle.loadString('assets/catalog.json'));
    final prefs = await SharedPreferences.getInstance();
    var state = AppState();
    final raw = prefs.getString(_stateKey);
    if (raw != null) {
      try {
        state = AppState.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      } catch (e) {
        // Keep the broken data around instead of silently overwriting it.
        await prefs.setString('$_stateKey.broken.${DateTime.now().millisecondsSinceEpoch}', raw);
        debugPrint('Kaufi: could not read saved state: $e');
      }
    }
    return AppController(catalog, state, prefs: prefs);
  }

  final Catalog catalog;
  final Kaufi kaufi;
  final SharedPreferences? prefs;
  final DateTime Function() _clock;

  AppState get state => kaufi.state;
  DateTime get now => _clock();
  Day get today => Day.today(now);

  ShoppingList get shoppingList => kaufi.shoppingList(today);

  /// The meal the shopping list is narrowed down to. Not persisted: opening
  /// the app fresh always shows everything.
  String? _mealFilter;

  Meal? get filteredMeal {
    final id = _mealFilter;
    if (id == null) return null;
    for (final m in kaufi.mealsInWindow(today)) {
      if (m.id == id) return m;
    }
    return null;
  }

  void setMealFilter(String? mealId) {
    if (_mealFilter == mealId) return;
    _mealFilter = mealId;
    notifyListeners();
  }
  bool get hasPlan => kaufi.upcomingMeals.isNotEmpty;

  void _changed() {
    notifyListeners();
    prefs?.setString(_stateKey, jsonEncode(state.toJson()));
  }

  /// Call when the app comes back to the foreground: a new day may have begun.
  void refresh() {
    if (kaufi.settle(today, now)) {
      // Meals were eaten or the trip timed out: older steps no longer apply.
      _undo.clear();
      _changed();
    } else {
      notifyListeners();
    }
  }

  void setShoppingDays(int days) {
    final d = days.clamp(1, 30);
    if (d == state.shoppingDays) return;
    state.shoppingDays = d;
    _changed();
  }

  void setLeftHanded(bool value) {
    if (value == state.leftHanded) return;
    state.leftHanded = value;
    _changed();
  }

  /// Steps taken in the shopping list, newest last, for the undo button.
  final _undo = <_Snapshot>[];

  /// What the undo button would take back, or null when there is nothing.
  String? get undoLabel => _undo.isEmpty ? null : _undo.last.label;

  void _remember(String label) {
    _undo.add(_Snapshot(state, label));
    if (_undo.length > 30) _undo.removeAt(0);
  }

  void undo() {
    if (_undo.isEmpty) return;
    _undo.removeLast().restore(state);
    _changed();
  }

  String _name(String key) => kaufi.def(key).name;

  void check(String key, {double? amount}) {
    _remember('${_name(key)} in den Korb');
    kaufi.check(key, today, now, amount: amount);
    _changed();
  }

  void uncheck(String key) {
    _remember('${_name(key)} aus dem Korb');
    kaufi.uncheck(key, now);
    _changed();
  }

  /// Puts an item into the basket, or corrects it there, with the amount the
  /// user picked. Kaufi learns from it how the item is bought.
  void setBought(String key, double amount) {
    _remember('Menge von ${_name(key)}');
    kaufi.setBought(key, amount, today, now);
    _changed();
  }

  void markAtHome(String key) {
    _remember('${_name(key)} vorrätig');
    kaufi.markAtHome(key, today);
    _changed();
  }

  /// Kaufi thought [key] was at home, but it is not: back on the list.
  void notAtHome(String key) {
    _remember('${_name(key)} wieder auf der Liste');
    kaufi.setPantry(key, 0);
    _changed();
  }

  void finishTrip() {
    _remember('Einkauf abschließen');
    kaufi.finishTrip();
    _changed();
  }

  /// A correction in the pantry screen. It overrides what the shopping steps
  /// before it did, so those can no longer be undone.
  void setPantry(String key, double amount) {
    _undo.clear();
    kaufi.setPantry(key, amount);
    _changed();
  }

  void moveMeal(String id, Day to) {
    kaufi.moveMeal(id, to, today);
    _changed();
  }

  void shiftFrom(Day from, int days) {
    kaufi.shiftFrom(from, days, today);
    _changed();
  }

  void deleteMeal(String id) {
    kaufi.deleteMeal(id);
    _changed();
  }

  PlanImport parse(String text) =>
      parsePlan(text, catalog, existingCustom: state.customDefs);

  /// Returns how many meals were skipped because they lie in the past.
  int applyImport(PlanImport imp, Day start, {required bool replace}) {
    _undo.clear();
    final skipped = kaufi.applyImport(imp, start, today, replace: replace);
    _changed();
    return skipped;
  }
}

/// What a shopping step can change, so the undo button can restore it.
/// Meals and settings are left out on purpose: undoing "in den Korb" must not
/// undo a meal moved in the meantime.
class _Snapshot {
  _Snapshot(AppState s, this.label)
      : pantry = Map.of(s.pantry),
        packOverrides = Map.of(s.packOverrides),
        route = List.of(s.route),
        trip = List.of(s.trip),
        tripLastActivity = s.tripLastActivity;

  final String label;
  final Map<String, double> pantry;
  final Map<String, double> packOverrides;
  final List<String> route;
  final List<TripEntry> trip;
  final DateTime? tripLastActivity;

  void restore(AppState s) {
    s.pantry
      ..clear()
      ..addAll(pantry);
    s.packOverrides
      ..clear()
      ..addAll(packOverrides);
    s.route
      ..clear()
      ..addAll(route);
    s.trip
      ..clear()
      ..addAll(trip);
    s.tripLastActivity = tripLastActivity;
  }
}
