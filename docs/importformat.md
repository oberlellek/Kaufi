# Kaufi-Importformat (Version 1)

Kaufi bekommt einen Essensplan als JSON. Daraus berechnet die App, welche Zutaten bis zu welchem Tag im Haus sein müssen. Das Format ist absichtlich klein, damit jede KI, jede App und jedes Skript es erzeugen kann.

Ein vollständiges Beispiel liegt in [`examples/beispiel-plan.json`](../examples/beispiel-plan.json), ein JSON-Schema in [`kaufi-plan.schema.json`](kaufi-plan.schema.json).

## Aufbau

```json
{
  "kaufi": 1,
  "title": "Meal-Prep Woche 1",
  "source": "Claude",
  "startDate": "2026-11-02",
  "shoppingDays": 7,
  "ingredients": [],
  "meals": [
    {
      "date": "2026-11-02",
      "name": "Chili con Carne (4 Portionen)",
      "items": [
        {"id": "ground-beef", "name": "Rinderhack", "amount": 500, "unit": "g"},
        {"id": "canned-tomatoes", "name": "Gehackte Tomaten", "amount": 2, "unit": "Dose"},
        {"id": "salt", "name": "Salz"}
      ]
    }
  ]
}
```

| Feld | Pflicht | Bedeutung |
| --- | --- | --- |
| `kaufi` | nein | Formatversion, aktuell `1`. |
| `title` | nein | Name des Plans, wird beim Import angezeigt. |
| `source` | nein | Wer den Plan erzeugt hat. |
| `startDate` | nein | Erster Tag des Plans (`JJJJ-MM-TT`). Nur nötig, wenn Gerichte `day` statt `date` nutzen. Fehlt es, fragt die App beim Import. |
| `shoppingDays` | nein | Für wie viele Tage auf einmal eingekauft wird (1–60). Überschreibt die Einstellung in der App. |
| `ingredients` | nein | Eigene Zutaten, die nicht im Katalog stehen (siehe unten). |
| `meals` | ja | Gerichte oder Meal-Prep-Sessions. |

### Gerichte

| Feld | Pflicht | Bedeutung |
| --- | --- | --- |
| `date` oder `day` | ja | `date`: der Tag, an dem die Zutaten spätestens im Haus sein müssen, also der Kochtag. `day`: dasselbe relativ, `1` ist der erste Tag des Plans. |
| `name` | nein | Anzeigename. |
| `items` | nein | Zutaten mit der **Gesamtmenge** für dieses Gericht, nicht pro Portion. `ingredients` wird als Alias akzeptiert. |

### Zutaten in `items`

| Feld | Bedeutung |
| --- | --- |
| `id` | ID aus dem [Katalog](../assets/catalog.json), z. B. `rolled-oats`. Auch `en:rolled-oats` (Open-Food-Facts-Stil) und `rolled_oats` werden erkannt. |
| `name` | Allgemeiner Name ohne Marke. Wird benutzt, wenn `id` fehlt oder unbekannt ist. |
| `amount` | Zahl. Fehlt sie (und `unit` auch), muss die Zutat nur im Haus sein, z. B. Salz. `"200 g"` als Text geht auch. |
| `unit` | `g`, `kg`, `ml`, `l`, `Stück`, `TL`, `EL`, `Prise`, `Handvoll`, `Bund`, `Zehe`, `Scheibe`, `Packung`, `Dose`, `Glas`, `Becher` … Fehlt sie, sind Stück gemeint. |

Eine Zutat darf auch nur ein Text sein: `"items": ["Salz", "Pfeffer"]`.

### Eigene Zutaten

```json
"ingredients": [
  {"id": "x-kimchi", "name": "Kimchi", "unit": "g", "pack": {"amount": 400, "unit": "g"},
   "category": "canned", "price": {"min": 3, "max": 5}}
]
```

In `items` wird die Zutat dann über `"id": "x-kimchi"` angesprochen. `category` ist eine der Abteilungen `produce`, `bakery`, `meat`, `fish`, `dairy`, `dry`, `canned`, `baking`, `spices`, `condiments`, `snacks`, `drinks`, `frozen`, `other`. `price` gilt pro Packung in Euro.

## Wie Kaufi Zutaten zuordnet

Damit „Haferflocken“ von einer Quelle und „oats“ von einer anderen dieselbe Zutat sind, geht Kaufi so vor:

1. **ID aus dem Katalog.** Der eindeutigste Weg. Der Prompt in der App („Prompt für deine KI kopieren“) enthält die Liste aller IDs.
2. **Name und Synonyme.** Jeder Katalogeintrag hat deutsche und englische Synonyme. Groß- und Kleinschreibung, Umlaute, Zusätze wie „Bio“, „frisch“ oder alles nach einem Komma bzw. in Klammern werden ignoriert, Einzahl und Mehrzahl gleichgesetzt.
3. **Unbekannt.** Bleibt nichts übrig, legt Kaufi eine eigene Zutat unter dem Namen an. Sie wird beim nächsten Import über denselben Namen wiedererkannt.

Mengen werden in die Einheit umgerechnet, in der Kaufi die Zutat führt. Stück und Gramm lassen sich ineinander umrechnen, wenn der Katalog ein Stückgewicht kennt (z. B. Paprika 160 g), Gramm und Milliliter über die Dichte.

## Was beim Import passiert

- **Ersetzen** (Standard) verwirft alle noch nicht gegessenen Gerichte und übernimmt den neuen Plan. **Ergänzen** fügt hinzu.
- Gerichte mit einem Datum vor heute werden übersprungen.
- Der Vorrat bleibt unverändert.
