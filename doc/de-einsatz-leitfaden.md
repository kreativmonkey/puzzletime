# PuzzleTime in Deutschland einsetzen — Praxisleitfaden (Ist-Stand)

Stand: 2026-07-04 · Gilt für den unveränderten aktuellen Stand (ohne die
Anpassungen aus [de-markt-anpassungen.md](de-markt-anpassungen.md)).

Dieser Leitfaden beschreibt, wie das Tool **heute** für deutsche
Arbeitsverhältnisse betrieben werden kann: Konfiguration, Vorgehen pro Fall,
was nicht abgebildet wird und welcher Workaround gilt.

## Grundprinzip: Was die Flags wirklich bedeuten

Das Verständnis der zwei `Absence`-Flags ist der Schlüssel zu allem:

| Flag | Bedeutung im Tool (nicht die Beschriftung!) | Wirkung |
|---|---|---|
| `payed` = true | **sollzeitwirksam** — der Tag gilt als erfüllt | Keine Minusstunden, Überstundenkonto unberührt |
| `payed` = false | **geht zulasten des Überstundenkontos** | Gebuchte Stunden senken den Überstundensaldo |
| `vacation` = true | bucht zusätzlich **vom Urlaubskonto** ab | Stunden ÷ Tagessollstunden = verbrauchte Urlaubstage |

`payed` heißt **nicht** „vom Arbeitgeber vergütet". Ob Geld fließt (Arbeitgeber,
Krankenkasse, gar nicht), entscheidet die Lohnabrechnung — die läuft immer
außerhalb des Tools.

**Buchungsregel für alle Absenzen:** Es werden die Stunden gebucht, die an dem
Tag ausgefallen wären (persönliche Tagessollzeit = `Sollstunden/Tag × Pensum`).
Ein ganzer freier Tag bei 100 % und 8h-Soll = 8 h; bei 50 % (halbtags) = 4 h.
Damit stimmen Urlaubskonto und Teilzeit-Umrechnung automatisch.

---

## 1. Grundkonfiguration

### Umgebung / Settings

| Einstellung | Wert für DE | Hinweis |
|---|---|---|
| `RAILS_PTIME_COUNTRY` | `DE` | Steuert Länderauswahl-Defaults |
| `RAILS_PTIME_CURRENCY` | `EUR` | |
| `RAILS_PTIME_VAT` | `19` | |
| `RAILS_LOCALE` | `de-DE` | Seit Branch `de_anpassung` vollständig (alle Locale-Dateien). Hinweis: einzelne direkt in Views/Modellen hartkodierte CH-Begriffe („Absenz") bleiben, bis A.2 aus dem Anpassungskatalog umgesetzt ist. |
| `RAILS_PTIME_INITIAL_VACATION_DAYS_EDITABLE` | `true` | Wird als Korrekturventil gebraucht (siehe Urlaubsverfall, Elternzeit) |
| `RAILS_PTIME_BUSINESS_YEAR_START_MONTH` | — (Default bei `DE`: `1`) | Seit Branch `de_anpassung` per ENV konfigurierbar; bei `RAILS_PTIME_COUNTRY=DE` automatisch Kalenderjahr. **Die Urlaubsberechnung ist davon unabhängig** und rechnet immer pro Kalenderjahr — für BUrlG also korrekt. |

### Arbeitsbedingungen (Verwaltung > Arbeitsbedingungen)

- `Sollstunden/Tag`: z. B. `8.0` bei 40h-Woche (Vollzeitwert; Teilzeit läuft über das Pensum der Anstellung).
- `Urlaubstage/Jahr`: Firmenstandard, z. B. `30`. **Nie unter 20** (gesetzliches Minimum bei 5-Tage-Woche — seit Branch `de_anpassung` validiert das Tool das im DE-Modus).
- Änderungen mit `Gültig ab` historisieren, nie den Ersteintrag überschreiben.

### Feiertage (Verwaltung > Feiertage)

- **Jährlich manuell pflegen** — es gibt keinen Automatismus, und bewegliche
  Feiertage (Karfreitag, Ostermontag, Christi Himmelfahrt, Pfingstmontag,
  ggf. Fronleichnam) müssen jedes Jahr neu eingetragen werden.
  Fixe DE-Feiertage: 01.01., 01.05., 03.10., 25.12., 26.12. + Bundesland.
- Halbe Tage (24.12./31.12., falls betrieblich üblich): `Sollstunden` des
  Tages auf den halben Wert setzen (z. B. `4.0`).
- **Feiertage gelten global für alle** — daher: eine Instanz = ein Bundesland.
  Mitarbeiter in einem Bundesland mit *zusätzlichem* Feiertag: siehe
  Fall 12. Umgekehrt (weniger
  Feiertage) ist nicht sauber abbildbar — Kalender am Sitz-Bundesland bzw.
  an der Mehrheit ausrichten.

### Absenzarten (Verwaltung > Absenzen)

Empfohlener Katalog für DE:

| Name | payed | vacation | Verwendung |
|---|---|---|---|
| Urlaub | ja | ja | Erholungsurlaub |
| Krankheit | ja | – | Bis 6 Wochen (Entgeltfortzahlung) |
| Krankheit (Krankengeld) | ja | – | Ab Woche 7; `payed` trotzdem „ja", sonst Minusstunden — Vergütung regelt die Lohnabrechnung |
| Kindkrank | ja | – | § 45 SGB V; `payed` „ja" aus demselben Grund |
| Mutterschutz | ja | – | Beschäftigungsverbote |
| Sonderurlaub | ja | – | § 616 BGB: Heirat, Todesfall, Umzug, Arzttermin |
| Bildungsurlaub | ja | – | Landesrecht, meist 5 Tage/Jahr |
| Feiertag (Bundesland) | ja | – | Nur bei Standorten in mehreren Bundesländern |
| Überstundenabbau | – | – | Einzige sinnvolle unbezahlte Absenz (senkt Überstundenkonto) |

**Keine Absenzart anlegen für:** Elternzeit, Sabbatical, unbezahlten Urlaub —
diese laufen über die Anstellung (siehe Fälle 6–8). Eine unbezahlte Absenz
würde das Überstundenkonto ins Minus reißen.

**Namensdisziplin (DSGVO):** Absenzarten-Namen erscheinen in Auswertungen.
Keine zu granularen Arten anlegen („Kur", „Reha", „Therapie") — alles unter
„Krankheit" fassen.

---

## 2. Die Fälle im Einzelnen

### 1. Urlaub

- **Erfassen:** Absenz „Urlaub", pro Tag die persönliche Tagessollzeit; für
  Zeiträume die Mehrtages-Erfassung nutzen (Feld „Dauer" beim Erfassen der
  Absenz — bucht automatisch nur Werktage, lässt Feiertage aus).
- **Anspruch:** kommt aus Arbeitsbedingung bzw. Override
  `Urlaubstage/Jahr` an der Anstellung. Saldo sichtbar im Ferienplan
  (Management) und in der Mitarbeiter-Übersicht.
- **Nicht abgebildet — Verfall & Übertrag (§ 7 BUrlG):** Der Saldo kumuliert
  unbegrenzt über Jahre.
  - *Workaround:* Jährlich zum Stichtag (31.03. bzw. betriebliche Regel) den
    Resturlaub prüfen; verfallene Tage über das Feld „Anfänglicher Urlaub"
    (`initial_vacation_days`) am Mitarbeiter abziehen.
  - *Achtung:* Diese Korrektur wirkt **rückwirkend auf alle Auswertungen**
    (es ist ein einziger Startsaldo, kein Jahresbuchungssatz). Änderung mit
    Datum und Grund extern dokumentieren.
  - *Pflicht daneben:* Die **Hinweispflicht** (individuelle Mitteilung
    „X Tage verfallen zum Y") kann das Tool nicht — ohne diese Mail verfällt
    rechtlich nichts. Jährlich im Herbst manuell verschicken, Nachweis
    aufbewahren.
- **Nicht abgebildet — Zwölftelung (§ 5 BUrlG):** Bei unterjährigem Ein-/
  Austritt rechnet das Tool kalendertaggenau statt in Zwölfteln, und die
  Aufrundung halber Tage (§ 5 Abs. 2) fehlt. Differenz meist < 1 Tag —
  bei Bedarf über „Anfänglicher Urlaub" ausgleichen.
- **Wartezeit (§ 4 BUrlG):** Das Tool gewährt anteiligen Urlaub ab Tag 1 und
  blockiert nichts in den ersten 6 Monaten. Organisatorisch steuern
  (Genehmigungsprozess liegt ohnehin außerhalb des Tools — es gibt **keinen
  Antrags-/Genehmigungsworkflow**, jede Buchung ist sofort wirksam).

### 2. Krankheit bis 6 Wochen (Entgeltfortzahlung)

- **Erfassen:** Absenz „Krankheit", Tagessollzeit pro Krankheitstag
  (Mehrtages-Erfassung für längere AU).
- **AU-Nachweis:** kein Feld vorhanden. *Workaround:* Bemerkungsfeld, nur
  neutral („eAU bis 24.03. liegt vor") — **niemals Diagnosen** eintragen.
- **Worauf achten:** Krankheit an einem Feiertag/Wochenende wird nicht
  gebucht (Soll = 0). Teilzeitkräfte buchen ihre reduzierte Tagessollzeit.

### 3. Krankheit über 6 Wochen (Krankengeld)

- **Erfassen:** Ab Tag 43 auf die Absenzart „Krankheit (Krankengeld)"
  wechseln. Sie bleibt `payed: true` — das ist gewollt: Sollzeit bleibt
  erfüllt, keine Minusstunden. Dass der Arbeitgeber nicht mehr zahlt, bildet
  die Lohnabrechnung ab, nicht das Tool.
- **Nicht abgebildet — die 42-Tage-Frist selbst:** Das Tool warnt nicht.
  *Workaround:* Auswertungen > Absenzen pro Mitarbeiter zeigt Stunden je
  Absenzart und Zeitraum; Stunden ÷ Tagessollzeit = Kranktage. Bei längeren
  AUs manuell zählen (Kalendertage ab Tag 1 der AU, nicht Arbeitstage!).
  Wiederholungserkrankungen (gleiche Ursache, 6/12-Monats-Fristen) kann nur
  die Personalabteilung beurteilen.
- **Urlaub läuft korrekt weiter auf** — das Tool macht das automatisch
  richtig, weil der Anspruch an der Anstellung hängt. **Deshalb: die
  Anstellung unverändert weiterlaufen lassen, niemals auf 0 % setzen.**
- **15-Monats-Verfall** bei Langzeitkranken: manuell wie beim normalen
  Verfall handhaben (Korrektur über „Anfänglicher Urlaub"), Stichtag ist der
  31.03. des übernächsten Jahres.

### 4. Kindkrank (§ 45 SGB V)

- **Erfassen:** Absenz „Kindkrank", Tagessollzeit pro Tag.
- **Nicht abgebildet — Kontingente:** 15 Arbeitstage je Kind und Elternteil
  (max. 35; Alleinerziehende 30/70) prüft das Tool nicht, und „pro Kind"
  kennt es nicht.
  *Workaround:* Auswertung Absenzen je Mitarbeiter/Jahr liefert die Summe;
  das kindbezogene Kontingent führt die Lohnbuchhaltung (die die Anträge auf
  Kinderkrankengeld ohnehin sieht). Das Tool ist hier nur Zeitkonto.

### 5. Mutterschutz

- **Erfassen:** Absenz „Mutterschutz" über den gesamten Zeitraum
  (6 Wochen vor bis 8 Wochen nach Geburt, bei Früh-/Mehrlingsgeburten 12)
  per Mehrtages-Erfassung.
- **Verhalten ist korrekt:** Sollzeit gilt als erfüllt, Urlaub baut sich
  ungekürzt weiter auf (§ 24 MuSchG verlangt genau das).
- **Worauf achten:** Das Tool verhindert keine Zeitbuchungen im
  Beschäftigungsverbot — organisatorisch sicherstellen, dass keine
  Arbeitszeiten erfasst werden.

### 6. Elternzeit — **wichtigster Sonderfall**

- **Erfassen:** Anstellung der/des Mitarbeitenden zum Beginn der Elternzeit
  beenden und eine neue Anstellung mit **Pensum 0 %** für den
  Elternzeitraum anlegen (Funktionsanteil ist Pflichtfeld — bisherige
  Funktion mit 0 % eintragen). Nach der Elternzeit neue Anstellung mit dem
  regulären Pensum. Nicht als Absenz buchen.
- **Wirkung:** Sollzeit = 0, keine Minusstunden, kein Urlaubsaufbau im
  Zeitraum — grob richtig, **aber die Urlaubskürzung ist rechtlich falsch
  berechnet**: Das Tool kürzt kalendertaggenau, § 17 BEEG erlaubt nur
  1/12 pro **vollem Kalendermonat** und nur nach ausdrücklicher
  Kürzungserklärung des Arbeitgebers.
  - Beispiel Elternzeit 20.01.–19.02. (30 Tage Anspruch): Tool zieht
    ~2,5 Tage ab, korrekt wäre **0** (kein voller Kalendermonat).
  - *Workaround:* Korrekten Anspruch manuell rechnen
    (`Jahresurlaub − Jahresurlaub × volle Elternzeit-Kalendermonate / 12`,
    nur bei erklärter Kürzung), mit dem Tool-Wert vergleichen, Differenz über
    „Anfänglicher Urlaub" gutschreiben. Rechnung extern dokumentieren.
- **Keine Kürzung erklärt?** Dann die vollen Zwölftel zurückgeben — die
  Kürzung ist ein Wahlrecht des Arbeitgebers, kein Automatismus.

### 7. Teilzeit während der Elternzeit

- **Erfassen:** Anstellung mit dem tatsächlichen Teilzeit-Pensum
  (z. B. 50 %) statt 0 %.
- **Worauf achten:** Für Monate mit Teilzeitarbeit ist die
  § 17-Kürzung **unzulässig** — der (anteilige) Urlaub entsteht regulär.
  Das taggenaue Pro-rata des Tools auf dem Teilzeit-Pensum ist hier
  näherungsweise richtig; Abweichungen wie in Fall 6 prüfen.

### 8. Unbezahlter Urlaub / Sabbatical

- **Erfassen:** Wie Elternzeit über eine 0 %-Anstellung für den Zeitraum.
  **Nicht** als unbezahlte Absenz — die würde das Überstundenkonto ins
  Minus ziehen.
- **Rechtlich passt das grob:** Bei ruhendem Arbeitsverhältnis entsteht nach
  BAG (2019) kein Urlaubsanspruch; die taggenaue Kürzung des Tools ist hier
  näher an der Rechtslage als bei der Elternzeit. Für einzelne unbezahlte
  Tage (kein Ruhen) den Anspruch ungekürzt lassen und die Differenz ggf.
  über „Anfänglicher Urlaub" zurückgeben.

### 9. Sonderurlaub (§ 616 BGB) und Bildungsurlaub

- **Erfassen:** entsprechende bezahlte Absenz, Tagessollzeit.
- **Worauf achten:** Bildungsurlaubs-Kontingent (meist 5 Tage/Jahr,
  Landesrecht) wird nicht geprüft — Auswertung Absenzen je Jahr manuell
  kontrollieren. § 616 kann vertraglich abbedungen sein — dann existiert der
  Anspruch nicht; Absenzart nur anlegen, wenn er gilt.

### 10. Zusatzurlaub für schwerbehinderte Menschen (§ 208 SGB IX)

- **Erfassen:** An der Anstellung `Urlaubstage/Jahr` individuell auf
  Standard + 5 setzen (bei 5-Tage-Woche; anteilig bei weniger Tagen).
- **Worauf achten:** Der Override gilt pro Anstellung — bei jeder neuen
  Anstellung (Pensumswechsel!) neu setzen, sonst fällt der Zusatzurlaub
  still weg.

### 11. Überstunden

- **Aufbau:** automatisch (Ist − Soll), sichtbar in der Mitarbeiterübersicht.
- **Abbau in Freizeit:** Absenz „Überstundenabbau" (`payed: false`) buchen —
  senkt das Überstundenkonto, nicht das Urlaubskonto.
- **Umwandlung in Urlaub:** Funktion „Überstunden-Urlaub Umbuchung"
  (`OvertimeVacation`): Stunden vom Überstundenkonto aufs Urlaubskonto.
  Nur positive Beträge möglich — die Gegenrichtung (Urlaub zu Überstunden)
  gibt es nicht.
- **Nicht abgebildet — ArbZG-Grenzen:** Keine Prüfung auf > 10 h/Tag,
  Ruhezeit 11 h, Pausenregeln, Sonn-/Feiertagsarbeit. Das Tool nimmt jede
  Buchung an. *Workaround:* wöchentliche Auswertung der Arbeitszeiten durch
  Vorgesetzte; Verantwortung liegt organisatorisch beim Arbeitgeber.

### 12. Mitarbeiter in anderen Bundesländern

- **Zusätzlicher Feiertag am Wohn-/Arbeitsort** (z. B. Fronleichnam in BY,
  Instanz auf BE eingestellt): betroffene Person bucht die bezahlte Absenz
  „Feiertag (Bundesland)" mit Tagessollzeit.
- **Fehlender Feiertag** (Instanz-Feiertag gilt am Ort der Person nicht):
  nicht sauber abbildbar — die Person bekommt das reduzierte Soll geschenkt.
  Feiertagskalender deshalb am restriktivsten vertretenen Standort
  ausrichten und großzügigere Orte über die Absenz lösen.

### 13. Arbeitszeiterfassung (BAG-Pflicht: Beginn, Ende, Dauer)

- Das Tool **kann** Start/Stop (Felder „Von"/„Bis"), erzwingt es aber nicht —
  Default ist die reine Stundensumme.
- *Workaround:* Arbeitsanweisung, dass Arbeitszeiten (nicht Absenzen) immer
  mit Von/Bis erfasst werden; Pausen entstehen durch getrennte Einträge
  (z. B. 08:00–12:00 und 12:45–17:00). Stichprobenkontrolle über die
  Auswertungen. Ohne Anweisung + Kontrolle ist die Erfassungspflicht nicht
  erfüllt.

---

## 3. Datenschutz im Betrieb (DSGVO)

- Der **Ferienplan** zeigt Kollegen nur „Abwesenheit" (farbig, ohne Art) —
  das ist unkritisch. **Management-Auswertungen** zeigen die Absenzart:
  Zugriff auf Management-Rollen beschränken und das im
  Verarbeitungsverzeichnis dokumentieren.
- Bemerkungsfelder von Absenzen: keine Diagnosen, keine Gründe über die
  Absenzart hinaus. Für den AU-Nachweis gibt es seit Branch `de_anpassung`
  im DE-Modus das Datumsfeld „AU-Nachweis vom" an der Abwesenheit —
  Bemerkungen dafür nicht mehr nötig.
- Absenzarten grob schneiden (siehe Namensdisziplin oben).

---

## 4. Grenzen & Workarounds auf einen Blick

| Thema | Nicht abgebildet | Workaround | Restrisiko |
|---|---|---|---|
| Urlaubsverfall/Übertrag | Kein Verfall, keine Hinweis-Mail | Jährliche manuelle Korrektur über „Anfänglicher Urlaub" + manuelle Hinweis-Mails | Korrektur wirkt rückwirkend; Hinweispflicht leicht zu vergessen, dann verfällt dann rechtlich nicht |
| Zwölftelung (§ 5 BUrlG, § 17 BEEG) | Taggenaue statt monatsweiser Rechnung | Manuell rechnen, Differenz über „Anfänglicher Urlaub" | Fehleranfällig, extern zu dokumentieren |
| EFZG 6-Wochen-Frist | Keine Warnung, keine Wiederholungserkrankungs-Logik | Manuelle Zählung (Kalendertage!), Wechsel der Absenzart ab Tag 43 | Fristversäumnis führt zu Lohnabrechnungsfehlern |
| Kindkrank-Kontingent | Kein Limit, kein Kind-Bezug | Jahresauswertung + führendes System ist die Lohnbuchhaltung | Doppelpflege |
| Elternzeit | Keine eigene Funktion | 0 %-Anstellung + manuelle Urlaubskorrektur | Urlaubsberechnung ohne Korrektur falsch |
| Bewegliche Feiertage | Keine Osterformel | Jährliche manuelle Pflege | Vergessene Pflege = falsches Soll für alle |
| Bundesland-Feiertage | Ein Kalender für alle | Zusatz-Feiertage als bezahlte Absenz | Fehlende Feiertage nicht abbildbar |
| ArbZG-Prüfungen | Keine | Organisatorische Kontrolle | Compliance liegt vollständig beim Arbeitgeber |
| Erfassungspflicht (Beginn/Ende) | Nicht erzwungen | Arbeitsanweisung Von/Bis + Kontrolle | Ohne Kontrolle nicht erfüllt |
| Urlaubsantrag/Genehmigung | Kein Workflow | Prozess außerhalb (Mail/Chat), Buchung erst nach Zusage | Direktbuchungen möglich |
| AU-Nachweis | Kein Feld | Bemerkungsfeld (neutral) | Kein Fristen-Tracking |

## 5. Merkzettel für die Personalverwaltung (jährlich/laufend)

- [ ] **Januar:** Feiertage des neuen Jahres eintragen (inkl. bewegliche, halbe Tage)
- [ ] **Herbst:** individuelle Verfalls-Hinweise verschicken (Nachweis ablegen)
- [ ] **31.03.:** verfallenen Übertrags-Urlaub über „Anfänglicher Urlaub" ausbuchen; 15-Monats-Fälle (Langzeitkranke) prüfen
- [ ] **Laufend:** AU-Fälle Richtung 42 Kalendertage beobachten, ab Tag 43 Absenzart wechseln
- [ ] **Bei Elternzeit:** Kürzungserklärung ja/nein entscheiden, Zwölftel rechnen, Korrektur buchen und dokumentieren
- [ ] **Bei Pensumswechsel:** individuelle `Urlaubstage/Jahr`-Overrides (z. B. Schwerbehinderten-Zusatzurlaub) auf die neue Anstellung übertragen
