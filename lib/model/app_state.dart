import '../catalog/catalog.dart';
import '../core/day.dart';

/// How much of one ingredient a meal needs, in the ingredient's base unit.
class Need {
  const Need(this.key, this.amount);

  /// Ingredient id (catalog or custom).
  final String key;
  final double amount;

  factory Need.fromJson(Map<String, dynamic> j) =>
      Need(j['k'] as String, (j['a'] as num).toDouble());
  Map<String, dynamic> toJson() => {'k': key, 'a': amount};
}

class Meal {
  Meal({
    required this.id,
    required this.day,
    required this.name,
    required this.needs,
    this.consumed = false,
    this.plan,
  });

  final String id;

  /// The day by which the ingredients have to be at home.
  Day day;
  final String name;
  final List<Need> needs;

  /// Set once the day has passed and the ingredients were subtracted from the
  /// pantry.
  bool consumed;

  /// Title of the imported plan this meal came from.
  final String? plan;

  /// [name] without notes in parentheses, e.g. "(4 Portionen)".
  String get displayName => name.replaceAll(RegExp(r'\s*\(.*?\)'), '');

  factory Meal.fromJson(Map<String, dynamic> j) => Meal(
        id: j['id'] as String,
        day: Day(j['day'] as int),
        name: j['name'] as String,
        needs: [
          for (final n in j['needs'] as List) Need.fromJson(n as Map<String, dynamic>),
        ],
        consumed: j['consumed'] as bool? ?? false,
        plan: j['plan'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'day': day.epochDay,
        'name': name,
        'needs': [for (final n in needs) n.toJson()],
        if (consumed) 'consumed': true,
        if (plan != null) 'plan': plan,
      };
}

/// Something put into the basket during the current shopping trip.
class TripEntry {
  const TripEntry(this.key, this.amount, {this.learnedRoute = false});

  final String key;

  /// Amount that was added to the pantry when it was checked.
  final double amount;

  /// Whether checking this item added it to the learned route. Unchecking it
  /// then removes it again, so a mis-tap does not spoil the order.
  final bool learnedRoute;

  factory TripEntry.fromJson(Map<String, dynamic> j) => TripEntry(
        j['k'] as String,
        (j['a'] as num).toDouble(),
        learnedRoute: j['l'] as bool? ?? false,
      );
  Map<String, dynamic> toJson() =>
      {'k': key, 'a': amount, if (learnedRoute) 'l': true};
}

/// Everything the app persists. Kept as one JSON document: the data is small
/// (a few weeks of meals) and this keeps storage trivial and portable.
class AppState {
  AppState({
    List<Meal>? meals,
    Map<String, IngredientDef>? customDefs,
    Map<String, double>? pantry,
    Map<String, double>? packOverrides,
    List<String>? route,
    List<TripEntry>? trip,
    this.tripLastActivity,
    this.shoppingDays = 7,
    this.leftHanded = false,
  })  : meals = meals ?? [],
        customDefs = customDefs ?? {},
        pantry = pantry ?? {},
        packOverrides = packOverrides ?? {},
        route = route ?? [],
        trip = trip ?? [];

  static const schemaVersion = 1;

  final List<Meal> meals;

  /// Ingredients that are not in the bundled catalog.
  final Map<String, IngredientDef> customDefs;

  /// What is at home right now, per ingredient, in base units.
  final Map<String, double> pantry;

  /// How the user buys an ingredient, learned from their corrections: the
  /// size of one package, or 0 for exactly what is missing.
  final Map<String, double> packOverrides;

  /// Learned order of ingredients through the store.
  final List<String> route;

  final List<TripEntry> trip;
  DateTime? tripLastActivity;

  /// How many days ahead to shop for.
  int shoppingDays;

  /// Which hand holds the phone while shopping. Swipes go towards it.
  bool leftHanded;

  factory AppState.fromJson(Map<String, dynamic> j) => AppState(
        meals: [
          for (final m in j['meals'] as List? ?? const [])
            Meal.fromJson(m as Map<String, dynamic>),
        ],
        customDefs: {
          for (final d in j['customDefs'] as List? ?? const [])
            (d as Map<String, dynamic>)['id'] as String: IngredientDef.fromJson(d),
        },
        pantry: _doubleMap(j['pantry']),
        packOverrides: _doubleMap(j['packOverrides']),
        route: [for (final r in j['route'] as List? ?? const []) r as String],
        trip: [
          for (final t in j['trip'] as List? ?? const [])
            TripEntry.fromJson(t as Map<String, dynamic>),
        ],
        tripLastActivity: j['tripLastActivity'] == null
            ? null
            : DateTime.tryParse(j['tripLastActivity'] as String),
        shoppingDays: j['shoppingDays'] as int? ?? 7,
        leftHanded: j['leftHanded'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'v': schemaVersion,
        'meals': [for (final m in meals) m.toJson()],
        'customDefs': [for (final d in customDefs.values) d.toJson()],
        'pantry': pantry,
        'packOverrides': packOverrides,
        'route': route,
        'trip': [for (final t in trip) t.toJson()],
        if (tripLastActivity != null)
          'tripLastActivity': tripLastActivity!.toIso8601String(),
        'shoppingDays': shoppingDays,
        if (leftHanded) 'leftHanded': true,
      };
}

Map<String, double> _doubleMap(Object? o) => {
      for (final e in (o as Map<String, dynamic>? ?? const {}).entries)
        e.key: (e.value as num).toDouble(),
    };
