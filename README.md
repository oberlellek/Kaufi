# Kaufi

Kaufi macht aus deinem Essensplan die Einkaufsliste. Die App merkt sich, was noch zu Hause ist, und lernt deinen Weg durch den Laden. Sie ist für den Moment gebaut, in dem du den Supermarkt betrittst: App auf, Liste da, mit einer Hand abhaken.

Alles bleibt auf dem Gerät. Kein Konto, keine Werbung, und die Release-App hat nicht einmal die Berechtigung, ins Internet zu gehen.

<p>
  <img src="docs/screenshots/einkaufsliste.png" width="230" alt="Einkaufsliste">
  <img src="docs/screenshots/packung.png" width="230" alt="Menge korrigieren">
  <img src="docs/screenshots/essensplan.png" width="230" alt="Essensplan">
</p>

## So funktioniert es

1. **Plan holen.** Im Menü „Prompt für deine KI kopieren“ antippen und den Text in einen KI-Chat einfügen. Dort besprichst du, was du essen willst, und die KI antwortet mit einem Plan im [Kaufi-Format](docs/importformat.md).
2. **Importieren.** Die Antwort kopieren und „Aus der Zwischenablage einfügen“ wählen, oder die Antwort bzw. Datei über „Teilen → Kaufi“ schicken. Eine `.json`-Datei lässt sich auch direkt mit Kaufi öffnen.
3. **Einkaufen.** Kaufi zeigt, was dir für die nächsten Tage noch fehlt: Brauchst du fünf Zwiebeln und hast zwei zu Hause, stehen da drei.

### Bedienung im Laden

| Geste | Wirkung |
| --- | --- |
| Antippen | In den Korb. Der Name fliegt kurz in den Korb unten rechts. Im Korb nochmal antippen holt es zurück. |
| Zur Hand hin ziehen, bei Rechtshändern nach rechts | „Hab ich schon“: Kaufi nimmt an, dass genug zu Hause ist, bei abgepackten Sachen mindestens eine Packung. Die Hand stellst du unter Menü → Einstellungen ein. |
| Rückgängig-Pfeil unten | Nimmt die letzten Schritte zurück, einen nach dem anderen. |
| Lange drücken | Eintragen, wie viel du wirklich nimmst. Kaufi merkt sich, wie du die Zutat kaufst. |
| − / + unten, oder seitlich über die Tage wischen | Für wie viele Tage du einkaufst. |
| Gerichte-Knopf | Nur die Zutaten eines Gerichts zeigen. Nochmal antippen oder „Alle Zutaten“ wählen hebt den Filter auf. |
| „Fertig“ | Zeigt einmal, was in den Vorrat kommt. Stimmt eine Menge nicht, tippst du drauf, sonst auf „Passt“. Ohne Abhaken endet ein Einkauf nach vier Stunden von selbst. |
| „Hast du laut Kaufi noch“ ganz unten | Was du in den nächsten Tagen brauchst, aber laut Vorrat nicht kaufen musst. Antippen, wenn es doch fehlt. |

Wischen, die direkt am Bildschirmrand beginnen, gehören der Zurück-Geste von Android und lösen in der Liste nichts aus. Wischen, die eher nach oben oder unten gehen, scrollen nur.

### Was Kaufi im Hintergrund macht

- **Reihenfolge lernen.** Die Reihenfolge, in der du Zutaten zum ersten Mal abhakst, wird zu ihrer Reihenfolge in der Liste. Neue Zutaten landen hinter der, die du davor abgehakt hast. Was noch nie gekauft wurde, steht neben Zutaten aus derselben Abteilung.
- **Vorrat führen.** Was du kaufst, kommt in den Vorrat. Lose Ware wie Zwiebeln, Äpfel oder Kartoffeln zählt genau, bei abgepackten Sachen rechnet Kaufi mit ganzen Packungen: Brauchst du acht Eier, kommen zehn in den Vorrat. Ist ein Tag vorbei, zieht Kaufi ab, was laut Plan gegessen wurde. Übrig gebliebene Eier stehen also nächste Woche nicht wieder auf der Liste. Unter „Vorrat“ kannst du korrigieren.
- **Aus Korrekturen lernen.** Kaufi fragt nicht bei jeder Zutat, sondern merkt sich jede Korrektur als neue Annahme. Nimmst du Eier im 6er, rechnet Kaufi danach mit 6ern. Kaufst du Zwiebeln im Netz, mit Netzen. Nimmst du genau, was fehlt, rechnet Kaufi bei dieser Zutat ab dann genau. Mehr von der üblichen Packung, etwa zwei Flaschen Öl im Angebot, ändert nichts.
- **Plan anpassen.** Unter „Essensplan“ hältst du ein Gericht gedrückt und ziehst es auf einen anderen Tag, oder du schiebst ab einem Tag alles nach hinten. Die Einkaufsliste rechnet sich neu.
- **Preis schätzen.** Der Katalog hat grobe Preisspannen pro Packung, die Liste zeigt die Summe.

## Installieren

Fertige APKs gibt es unter [Releases](../../releases). Mit [Obtainium](https://github.com/ImranR98/Obtainium) kannst du dieses Repository als Quelle eintragen und bekommst Updates automatisch.

## Entwicklung

Kaufi ist eine Flutter-App (Android jetzt, iOS später aus demselben Code).

```sh
flutter pub get
flutter test              # Logik- und Widget-Tests
flutter run               # auf Gerät oder Emulator
flutter run -d chrome     # schnelle Vorschau im Browser
```

| Ordner | Inhalt |
| --- | --- |
| `lib/logic/` | Fachlogik ohne Flutter: Import, Bedarf, Vorrat, Routenlernen, KI-Prompt |
| `lib/catalog/`, `assets/catalog.json` | Zutatenkatalog mit IDs, Synonymen, Packungsgrößen, Preisen |
| `lib/ui/` | Bildschirme |
| `android/.../MainActivity.kt` | Empfang von „Teilen“ und geöffneten Dateien |
| `docs/` | Importformat und JSON-Schema |

Neue Zutaten oder Synonyme gehören in `assets/catalog.json`. Die Tests prüfen, dass IDs eindeutig sind und der Beispielplan sauber importiert.

### Releases signieren

Android installiert ein Update nur, wenn es mit demselben Schlüssel signiert ist. Einmalig einen Schlüssel erzeugen und gut aufheben:

```sh
keytool -genkey -v -keystore kaufi.jks -keyalg RSA -keysize 4096 -validity 10000 -alias kaufi
```

Dann im Repository unter *Settings → Secrets and variables → Actions* diese Secrets anlegen:

| Secret | Inhalt |
| --- | --- |
| `KAUFI_KEYSTORE_BASE64` | Ausgabe von `base64 -w0 kaufi.jks` |
| `KAUFI_KEYSTORE_PASSWORD` | Passwort des Keystores |
| `KAUFI_KEY_ALIAS` | `kaufi` |
| `KAUFI_KEY_PASSWORD` | Passwort des Schlüssels |

Ein Tag wie `v0.1.0` baut dann eine signierte APK und veröffentlicht sie als Release. Auch die Test-APKs aus der CI werden damit signiert und lassen sich als Update übereinander installieren. Ohne Secrets wird mit einem Debug-Schlüssel signiert. Lokal geht dasselbe über `android/key.properties` (`storeFile` relativ zu `android/app`, `storePassword`, `keyAlias`, `keyPassword`).

## Ideen für später

- Mehrere Läden mit eigener Reihenfolge
- Eigenes F-Droid-Repository
- Zutaten zusammenführen, wenn doch einmal zwei Namen dasselbe meinen
- Katalog aus der Zutaten-Taxonomie von Open Food Facts erweitern
- Import direkt aus einem KI-Chat über eine Integration
