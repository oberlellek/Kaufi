import '../catalog/catalog.dart';
import '../core/day.dart';

/// Text the user can paste into any AI chat so that it answers with a plan
/// Kaufi can import. Contains the format and the catalog ids, which is what
/// makes "Haferflocken" from one source the same as "oats" from another.
String buildLlmPrompt(Catalog catalog, Day today) {
  final byCat = <Category, List<IngredientDef>>{};
  for (final d in catalog.all) {
    byCat.putIfAbsent(d.category, () => []).add(d);
  }
  final ids = StringBuffer();
  for (final c in Category.values) {
    final items = byCat[c];
    if (items == null) continue;
    ids.writeln('${c.label}: ${items.map((d) => '${d.id}=${d.name}').join(', ')}');
  }

  return '''
Ich nutze die Einkaufs-App „Kaufi“. Wenn wir meinen Essensplan fertig besprochen haben, gib ihn bitte als JSON im folgenden Format aus, in genau einem Codeblock, damit ich ihn in die App importieren kann. Heute ist ${today.iso}.

```json
{
  "kaufi": 1,
  "title": "Meal-Prep Woche 1",
  "source": "Name der KI oder App",
  "startDate": "JJJJ-MM-TT",
  "shoppingDays": 7,
  "meals": [
    {
      "date": "JJJJ-MM-TT",
      "name": "Overnight Oats mit Beeren",
      "items": [
        {"id": "rolled-oats", "name": "Haferflocken", "amount": 80, "unit": "g"},
        {"id": "frozen-berries", "name": "TK-Beeren", "amount": 100, "unit": "g"}
      ]
    }
  ]
}
```

Regeln:
- Ein Eintrag in "meals" pro Gericht oder Meal-Prep-Session. "date" ist der Tag, an dem die Zutaten spätestens im Haus sein müssen, also der Tag, an dem gekocht wird.
- Statt "date" darf auch "day" stehen (1 = erster Tag des Plans, 2 = zweiter Tag …), wenn das Datum noch offen ist. Dann "startDate" weglassen.
- "amount" ist die Gesamtmenge für dieses Gericht (alle Portionen zusammen), nicht pro Portion.
- Einheiten: g, kg, ml, l, Stück, TL, EL, Prise, Packung, Dose. Bei Gewürzen ohne genaue Menge "amount" weglassen.
- "shoppingDays": für wie viele Tage ich auf einmal einkaufe (z. B. 7 bei Wocheneinkauf), falls wir das besprochen haben, sonst weglassen.
- Nutze für "id" möglichst einen Wert aus der Liste unten. Gibt es keinen passenden, lass "id" weg und schreib nur einen allgemeinen "name" ohne Marke, z. B. "Kimchi".
- Gib nur Zutaten an, die man kauft, keine Zwischenschritte wie „gekochter Reis“.

Bekannte Zutaten (id=Name):
$ids''';
}
