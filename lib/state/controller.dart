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
  bool get hasPlan => kaufi.upcomingMeals.isNotEmpty;

  void _changed() {
    notifyListeners();
    prefs?.setString(_stateKey, jsonEncode(state.toJson()));
  }

  /// Call when the app comes back to the foreground: a new day may have begun.
  void refresh() {
    if (kaufi.settle(today, now)) {
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

  void check(String key, {double? amount}) {
    kaufi.check(key, today, now, amount: amount);
    _changed();
  }

  void uncheck(String key) {
    kaufi.uncheck(key, now);
    _changed();
  }

  /// Puts an item into the basket (or corrects it) with a package size the
  /// user picked; the size is remembered for next time.
  void buyPacks(String key, double packSize, int count) {
    kaufi.rememberPack(key, packSize);
    final amount = packSize * count;
    if (state.trip.any((t) => t.key == key)) {
      kaufi.changeBought(key, amount, now);
    } else {
      kaufi.check(key, today, now, amount: amount);
    }
    _changed();
  }

  double markAtHome(String key) {
    final added = kaufi.markAtHome(key, today);
    _changed();
    return added;
  }

  void undoMarkAtHome(String key, double added) {
    kaufi.undoMarkAtHome(key, added);
    _changed();
  }

  void finishTrip() {
    kaufi.finishTrip();
    _changed();
  }

  void setPantry(String key, double amount) {
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
    final skipped = kaufi.applyImport(imp, start, today, replace: replace);
    _changed();
    return skipped;
  }
}
