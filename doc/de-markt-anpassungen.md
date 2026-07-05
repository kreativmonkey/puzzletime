# PuzzleTime für den deutschen Markt — Analyse und Anpassungskatalog

Stand: 2026-07-04 · Basis: Codeanalyse des aktuellen `master`-Standes

PuzzleTime wurde für das Schweizer Arbeitsrecht entwickelt. Dieses Dokument
gleicht die vorhandenen Konzepte mit dem deutschen Arbeitsrecht ab und listet
die notwendigen Anpassungen — inkl. Priorisierung und Low-hanging Fruits.

> Für den Betrieb **ohne Codeänderungen** siehe den Praxisleitfaden
> [de-einsatz-leitfaden.md](de-einsatz-leitfaden.md) (Vorgehen pro Fall,
> Workarounds, Merkzettel).

## Inhalt

1. [Ist-Zustand: Wie PuzzleTime Abwesenheiten abbildet](#1-ist-zustand)
2. [Detailbefund: Elternzeit-Urlaubsberechnung ist falsch](#2-detailbefund-elternzeit)
3. [Anpassungskatalog](#3-anpassungskatalog)
4. [Priorisierung & Low-hanging Fruits](#4-priorisierung)

---

## 1. Ist-Zustand

Das Abwesenheitsmodell ist bewusst generisch:

- **`Absence`** (`app/models/absence.rb`): nur `name`, `payed` (bezahlt),
  `vacation` (zählt vom Urlaubskonto ab). Keine weitere Semantik, keine
  Kategorien, keine Kontingente, keine Fristen.
- **`Absencetime`** (`app/models/absencetime.rb`): gebuchte Abwesenheit in
  Stunden, Subklasse von `Worktime`.
- **Urlaubsanspruch**: `vacation_days_per_year` global in `WorkingCondition`
  (historisiert über `valid_from`), pro `Employment` überschreibbar.
  Berechnung in `Employment#vacations` → `Period#vacation_factor_sum`:
  **kalendertaggenau** anteilig pro Kalenderjahr
  (`Tage im Zeitraum / Tage im Jahr × Pensum × Tage/Jahr`).
- **Resturlaub**: `EmployeeStatistics#remaining_vacations` =
  Startsaldo (`initial_vacation_days`) + aufgelaufener Anspruch +
  Überstunden-Umbuchungen (`OvertimeVacation`) − verbrauchte Urlaubsstunden /
  Tagessollstunden. **Kumuliert unbegrenzt über alle Jahre, kein Verfall.**
- **Sollzeit**: `must_hours_per_day` (global, historisiert) × Werktage;
  Sa/So pauschal frei (`Holiday.weekend?`).
- **Feiertage**: globale `holidays`-Tabelle (Datum + Sollstunden des Tages,
  halbe Feiertage möglich) plus `regular_holidays` in `config/settings.yml`
  (nur **fixe** Tag/Monat-Paare).
- **Zeiterfassung**: Default-`report_type` ist `absolute_day` (nur
  Stundensumme); Start/Stop-Erfassung optional (`Worktime#guess_report_type`).
- **Überstunden**: `payed_worktime − musttime`, Umbuchung in Urlaub über
  `OvertimeVacation`. Keinerlei Arbeitszeitgesetz-Prüfungen.
- **Locale**: Default `de-CH` (`config/application.rb`), per `RAILS_LOCALE`
  umschaltbar. `models.de-DE.yml` existiert bereits, weitere de-DE-Dateien
  fehlen.

---

## 2. Detailbefund: Elternzeit

### Wie Elternzeit heute abbildbar ist

Es gibt keine Elternzeit-Funktion. Der einzige gangbare Weg ist eine
**0 %-Anstellung** für den Elternzeitraum — `Employment` erlaubt
`percent: 0` (Validierung `inclusion: 0..200`, `employment.rb:37`), der Scope
`Employment.active` (`percent > 0`) existiert bereits. Damit werden Sollzeit
und Urlaubsaufbau im Zeitraum null.

Eine Abbildung als unbezahlte Absenz funktioniert dagegen **nicht**: Die
Sollzeit bliebe voll bestehen und die Überstundenrechnung
(`EmployeeStatistics#overtime = payed_worktime − musttime`) liefe massiv ins
Minus.

### Warum die Urlaubsberechnung damit falsch ist (§ 17 BEEG)

Deutsches Recht: Der Arbeitgeber **kann** den Jahresurlaub um **1/12 pro
vollem Kalendermonat** Elternzeit kürzen (§ 17 Abs. 1 BEEG). Angebrochene
Monate kürzen nicht. Die Kürzung erfordert eine ausdrückliche Erklärung des
Arbeitgebers und entfällt, wenn während der Elternzeit Teilzeit beim selben
Arbeitgeber gearbeitet wird.

PuzzleTime rechnet stattdessen kalendertaggenau. Beispiel:
**Elternzeit 20.01.–19.02.**, sonst 100 %-Anstellung, 30 Urlaubstage/Jahr:

| Anstellung | Zeitraum | Rechnung | Urlaubstage |
|---|---|---|---|
| 100 % | 01.01.–19.01. | 19/365 × 1,0 × 30 | 1,56 |
| 0 % (Elternzeit) | 20.01.–19.02. | 31/365 × 0,0 × 30 | 0,00 |
| 100 % | 20.02.–31.12. | 315/365 × 1,0 × 30 | 25,89 |
| **Summe** | | | **27,45** |

**Rechtlich korrekt: 30 Tage** — kein Kalendermonat ist vollständig von der
Elternzeit abgedeckt, also keine Kürzung. PuzzleTime zieht fälschlich
**~2,5 Tage** ab.

Auch bei vollen Monaten stimmt die taggenaue Rechnung nicht exakt: Ein voller
Februar kürzt in PuzzleTime um 28/365 ≈ 7,67 %, korrekt wären 1/12 ≈ 8,33 %.

### Betroffener Code

- `app/models/employment.rb` — `#vacations`, `#vacations_per_period`
- `app/models/util/period.rb` — `#vacation_factor_sum`, `#vacation_factor`

### Lösungsskizze

1. `Employment` um ein Kennzeichen `kind`/`parental_leave` (o. ä.) erweitern,
   damit Elternzeit von „normaler" 0 %-Phase (z. B. unbezahltem Sabbatical)
   unterscheidbar ist.
2. Alternativer Berechnungsmodus (konfigurierbar, z. B.
   `Settings.vacations.calculation: swiss_pro_rata | german_twelfths`):
   - Basis-Anspruch des Kalenderjahres unverändert lassen,
   - Kürzung nur um `volle Kalendermonate Elternzeit × 1/12`,
   - Kürzung nur wenn als „erklärt" markiert (Flag am Employment),
   - keine Kürzung bei `percent > 0` während der Elternzeit.
3. Dasselbe Zwölftelungs-Modul deckt auch Ein-/Austritt nach § 5 BUrlG ab
   (siehe [B.1](#b-urlaub-burlg)).

---

## 3. Anpassungskatalog

Legende Aufwand: **S** (Stunden), **M** (Tage), **L** (Wochen).

### A. Vorhanden, aber falsch „ausgeschildert"

| # | Anpassung | Details | Betroffene Stellen | Aufwand |
|---|---|---|---|---|
| A.1 | de-DE-Lokalisierung vervollständigen | `models.de-DE.yml` existiert (Urlaub statt Ferien etc.). Es fehlen `views.de-DE.yml`, `crud.de-DE.yml`, `error_messages.de-DE.yml`, `validates_timeliness.de-DE.yml`, `devise.de-DE.yml` — ohne sie fällt die UI bei `RAILS_LOCALE=de-DE` auf Fallbacks zurück. | `config/locales/` | M |
| A.2 | Hartkodierte CH-Begriffe über i18n führen | Strings gehen an der Lokalisierung vorbei: `Absencetime.account_label = 'Absenz'` (`absencetime.rb:31`), „Ferienguthaben bis Ende …" (`extended_capacity_report.rb:34`), Fehlermeldungen direkt in Modellen (`absence.rb:25`, `working_condition.rb:105/111`, `employment.rb:149/151`), diverse Views. | Modelle, Reports, Views | M |
| A.3 | Absenzarten-Seeds für DE | „Militär" ist CH-spezifisch (EO-System). DE-Satz: Urlaub, Krankheit, Kindkrank, Mutterschutz, Elternzeit, Sonderurlaub § 616 BGB (Heirat/Umzug/Todesfall — Heirat und Umzug existieren schon), Überstundenabbau, unbezahlter Urlaub, Bildungsurlaub (landesrechtlich, meist 5 Tage/Jahr). | `db/seeds/development/absences.rb` | S |
| A.4 | Feiertags-Defaults | `regular_holidays` enthält Berchtoldstag (2.1.) und Bundesfeiertag (1.8.); „Stefanstag" heißt in DE „2. Weihnachtsfeiertag". DE-fixe Feiertage: 1.1., 1.5., 3.10., 25./26.12. | `config/settings.yml` | S |
| A.5 | Wirtschafts-Defaults | `vat: 7.7` → 19, `currency: CHF` → EUR, `country: CH` → DE sind per ENV überschreibbar. **Aber:** `business_year_start_month: 7` ist hardcoded ohne ENV — in DE ist das Urlaubsjahr das Kalenderjahr (§ 1 BUrlG) → konfigurierbar machen, Default 1. | `config/settings.yml` | S |
| A.6 | Schwerbehindertenzusatzurlaub ausschildern | § 208 SGB IX (+5 Tage bei 5-Tage-Woche) ist über den `vacation_days_per_year`-Override pro `Employment` bereits abbildbar — nur in Doku/UI als Anwendungsfall benennen. | Doku | S |
| A.7 | Halbe Feiertage dokumentieren | Heiligabend/Silvester sind in DE tariflich oft halbe Tage — `Holiday.musthours_day` kann das schon. Dokumentieren und ggf. seeden. | Doku, Seeds | S |
| A.8 | Elternzeit-Workaround benennen | 0 %-Anstellung als offizieller Weg für Elternzeit/Sabbatical dokumentieren — mit dem klaren Hinweis auf die falsche Urlaubsberechnung (Abschnitt 2), bis B.2 umgesetzt ist. Reibungspunkt: auch 0 %-Anstellungen verlangen `employment_roles_employments`. | Doku | S |

### B. Urlaub (BUrlG)

| # | Anpassung | Details | Betroffene Stellen | Aufwand |
|---|---|---|---|---|
| B.1 | Zwölftelung statt taggenauem Anteil | § 5 BUrlG: bei Ein-/Austritt 1/12 pro vollem Beschäftigungsmonat; Rundung § 5 Abs. 2 (≥ 0,5 → aufrunden). Heute kalendertaggenau (`Period#vacation_factor`). Als umschaltbarer Berechnungsmodus, CH-Verhalten bleibt Default. | `employment.rb`, `util/period.rb`, Settings | M |
| B.2 | Elternzeit-Kürzung § 17 BEEG | Siehe Abschnitt 2: Kürzung nur volle Kalendermonate, nur nach Erklärung, nicht bei Teilzeit in Elternzeit. Baut auf B.1 (gleiches Zwölftel-Modul) auf. | `employment.rb` + Migration | M |
| B.3 | Urlaubsverfall & Übertrag (konfigurierbar) | § 7 Abs. 3 BUrlG: Verfall 31.12., Übertrag bis 31.3. bei Gründen; EuGH/BAG: Verfall nur nach aktivem Hinweis des Arbeitgebers. Heute kumuliert `remaining_vacations` unbegrenzt. Nötig: Jahresabgrenzung (gesetzlicher Mindest- vs. vertraglicher Mehrurlaub getrennt), Verfalls-/Übertragslogik, jährliche Hinweis-Mail (Vorbild: `commit_reminder_job.rb`, `UserNotification`). **Verfallsregel muss pro Firma konfigurierbar sein** (siehe Exkurs unten), nicht hart 31.3. | `employee_statistics.rb`, neuer Job/Mailer, Settings | L |
| B.4 | Mindesturlaub-Validierung | § 3 BUrlG: min. 20 Tage (5-Tage-Woche). `WorkingCondition` erlaubt 0 → Warnung/Validierung bei DE-Modus. | `working_condition.rb` | S |
| B.5 | Wartezeit § 4 BUrlG | Voller Anspruch erst nach 6 Monaten Betriebszugehörigkeit; davor nur Teilanspruch (Zwölftel). `probation_period_end_date` existiert am Employee, hat aber keine Wirkung auf den Anspruch. Eher Anzeige-/Warnthema als harte Sperre. | `employee_statistics.rb`, Views | M |

#### Exkurs zu B.3: Gestaltungsspielraum bei Verfall & Ansparen

Firmen dürfen von § 7 Abs. 3 BUrlG abweichen — deshalb darf die
Verfallslogik im Tool **nicht hart kodiert** sein:

- **Günstigere Regeln sind immer zulässig** (§ 13 BUrlG,
  Günstigkeitsprinzip): z. B. „Verfall erst zum 31.12. des Folgejahres",
  Übertrag ohne Begründung oder gar kein Verfall. In der Praxis häufig per
  Arbeitsvertrag oder Betriebsvereinbarung.
- **Ungünstigere Regeln nur für den vertraglichen Mehrurlaub** (Tage über
  dem gesetzlichen Minimum von 20 Tagen bei 5-Tage-Woche): früherer Verfall,
  keine Abgeltung etc. sind zulässig — aber nach BAG-Rechtsprechung nur bei
  **ausdrücklicher vertraglicher Differenzierung** zwischen gesetzlichem und
  Mehrurlaub. Ohne Trennung folgt der Mehrurlaub den gesetzlichen Regeln.
  → Das Tool muss die beiden Töpfe ohnehin getrennt führen (siehe B.3).
- **Hinweispflicht gilt unabhängig von der gewählten Regel** für den
  gesetzlichen Urlaub: Ohne aktiven, individuellen Hinweis verfällt nichts
  (EuGH „Max-Planck", BAG 2019). Bei Langzeiterkrankten Verfall frühestens
  **15 Monate** nach Ende des Urlaubsjahres (EuGH „KHS/Schulte", BAG 2012).
- **Ansparkonten**: Der gesetzliche Mindesturlaub ist nicht frei ansparbar;
  der **Mehrurlaub** kann per Betriebsvereinbarung über Jahre übertragen oder
  in echte **Langzeit-/Zeitwertkonten** (Wertguthaben, §§ 7b ff. SGB IV,
  z. B. Sabbaticals) eingebracht werden. PuzzleTime hat mit
  `OvertimeVacation` bereits eine Umbuchung Überstunden→Urlaub; ein
  optionales Gegenstück Urlaub→Langzeitkonto wäre das analoge Konzept.

**Konsequenz für die Umsetzung von B.3** — konfigurierbare Verfalls-Engine
pro Instanz/Firma:

1. Verfallsstichtag wählbar: `31.3.` (gesetzlich) / `31.12. Folgejahr` /
   `nie` / eigenes Datum — getrennt einstellbar für gesetzlichen Mindest-
   und Mehrurlaub.
2. 15-Monats-Regel bei Langzeitkrankheit als Sonderfall (setzt eine
   Krankheits-Absenzart voraus → C.1).
3. Hinweis-Mail vor dem jeweils konfigurierten Stichtag (nicht fix vor dem
   31.3.).
4. Optional: Umbuchung von Mehrurlaub auf ein Langzeitkonto statt Verfall.

### C. Krankheit & Familie

| # | Anpassung | Details | Betroffene Stellen | Aufwand |
|---|---|---|---|---|
| C.1 | Absenz-Kategorien einführen | Voraussetzung für alles Weitere: `Absence` braucht neben Freitext-`name` eine Semantik, z. B. `kind: vacation / sick / child_sick / maternity / parental / special / unpaid / overtime_comp`. Ersetzt das implizite „Verhalten nur über payed/vacation-Flags". | `absence.rb` + Migration, Formulare | M |
| C.2 | Entgeltfortzahlung (EFZG) überwachen | 6 Wochen (42 Kalendertage) Lohnfortzahlung pro Erkrankung, danach Krankengeld der Kasse (AG-seitig unbezahlt, aber sollzeitneutral). Nötig: Zählung zusammenhängender Kranktage, Warnung bei Annäherung an 42 Tage, zweite Absenzart „Krankheit > 6 Wochen (Krankengeld)". Wiederholungserkrankung (gleiche Ursache, 6/12-Monats-Fristen) höchstens als Hinweis — keine automatische Bewertung. | Report/Warnung auf Basis C.1 | L |
| C.3 | Kindkrank § 45 SGB V mit Kontingent | Eigene Absenzart; AG-seitig unbezahlt (Kinderkrankengeld), sollzeitmindernd. **Jahreskontingent pro Absenzart** (aktuell 15 AT je Kind und Elternteil, max. 35; Alleinerziehende 30/70) — Kontingent-Konzept existiert im Tool bisher gar nicht (nur `vacation: true` bucht gegen das Urlaubskonto). Minimallösung: konfigurierbares Jahreslimit pro Absenzart + Auswertung; Kind-genaue Verwaltung ist bewusst außerhalb des Scopes (Lohnbuchhaltung). | `absence.rb`, `employee_statistics.rb` | L |
| C.4 | Mutterschutz (MuSchG) | 6 Wochen vor / 8 Wochen nach Geburt Beschäftigungsverbot; gilt als Beschäftigungszeit: Sollzeit wird erfüllt, **Urlaub wird nicht gekürzt** (§ 24 MuSchG). Als bezahlte Absenz (`payed: true`) fast korrekt abbildbar — fehlt: Ausschilderung (via C.1) und optional Buchungssperre für Arbeitszeiten im Verbotszeitraum. | Basis C.1 | M |
| C.5 | AU-/eAU-Nachweis | Attestpflicht ab Tag 4 (bzw. früher je Vertrag). Optionales Feld an `Absencetime` (Flag „Nachweis liegt vor" + Datum) genügt; keine Dokumentenverwaltung nötig. | `absencetime.rb` + Migration | S |
| C.6 | `payed`-Flag korrekt beschriften | Das Flag steuert faktisch nicht „bezahlt", sondern **„sollzeitwirksam"** (`payed_worktime` in `employee_statistics.rb`). Die Krankengeld-Phase (C.2) ist AG-seitig unbezahlt, muss im Tool aber `payed: true` sein, damit Sollzeit/Überstunden nicht ins Minus laufen. Im DE-Locale als „erfüllt Sollzeit" o. ä. beschriften; langfristig vom Vergütungsaspekt entkoppeln. | Locales, ggf. `absence.rb` | S |

#### Exkurs zu C.2: Urlaub bei Langzeitkrankheit (> 6 Wochen)

**Der Urlaub baut sich während Krankheit uneingeschränkt weiter auf** — auch
in der Krankengeld-Phase nach Ablauf der 6 Wochen Entgeltfortzahlung. Der
Anspruch entsteht allein aus dem Bestehen des Arbeitsverhältnisses (EuGH
„Schultz-Hoff" 2009). Anders als bei Elternzeit (§ 17 BEEG) gibt es **keine
Kürzungsmöglichkeit**: Wer zwei Jahre durchgehend krank ist, erwirbt für
beide Jahre den vollen Jahresurlaub.

Das Korrektiv sitzt beim **Verfall**, nicht bei der Entstehung:

- Gesetzlicher Urlaub verfällt bei durchgehender Arbeitsunfähigkeit
  **15 Monate nach Ende des jeweiligen Urlaubsjahres** (EuGH „KHS/Schulte",
  BAG 2012) — Urlaub aus 2024 also zum 31.03.2026. Es sammeln sich damit
  maximal ca. zwei Jahresansprüche plus der laufende an.
- BAG 20.12.2022 (nach EuGH „Fraport/St. Vincenz"): War der Mitarbeiter das
  **ganze Urlaubsjahr** durchgehend krank, greift die 15-Monats-Frist auch
  **ohne** Arbeitgeber-Hinweis. Hat er im Jahr noch **teilweise gearbeitet**,
  verfällt nur bei rechtzeitig erfüllter Hinweispflicht.
- Für vertraglichen Mehrurlaub kann bei sauberer Differenzierung Abweichendes
  gelten (siehe Exkurs zu B.3).

**Konsequenzen für PuzzleTime:**

1. Die Anspruchsseite stimmt im heutigen Modell bereits: Urlaubsaufbau hängt
   an `Employment`, nicht an gebuchten Zeiten. **Warnung für die Doku:** Die
   Krankengeld-Phase darf nicht als 0 %-Anstellung abgebildet werden — das
   würde den Urlaubsaufbau fälschlich stoppen (genau umgekehrt zur
   Elternzeit, A.8).
2. Die Absenzart „Krankheit > 6 Wochen (Krankengeld)" braucht `payed: true`
   im Tool-Sinn (sollzeitwirksam), obwohl AG-seitig unbezahlt → C.6.
3. Die Verfalls-Engine (B.3) muss die 15-Monats-Regel abbilden, inkl. der
   Fallunterscheidung „ganzjährig krank → Verfall ohne Hinweis" vs.
   „teilweise gearbeitet → Verfall nur nach Hinweis". Setzt die
   Krankheits-Absenzart aus C.1 voraus.

### D. Arbeitszeit (ArbZG / Erfassungspflicht)

| # | Anpassung | Details | Betroffene Stellen | Aufwand |
|---|---|---|---|---|
| D.1 | Start/Stop-Erfassung erzwingbar machen | BAG 13.09.2022 (1 ABR 22/21, § 3 ArbSchG) i. V. m. EuGH „CCOO": Beginn, Ende, Dauer sind zu erfassen. Default ist `absolute_day` (nur Summe, `settings.yml` `defaults.report_type`); Start/Stop optional. Nötig: Konfig-Flag, das Start/Stop (inkl. Pausen) für Arbeitszeiten verpflichtend macht. | `worktime.rb`, `report_type.rb`, Settings | M |
| D.2 | ArbZG-Plausibilitätswarnungen | Keinerlei Prüfungen heute. Als **Warnungen/Report**, nicht harte Validierung: > 8 h/Tag (Ausgleichspflicht) bzw. > 10 h/Tag (§ 3), Ruhezeit < 11 h zwischen Buchungen (§ 5), Pausen 30 min ab 6 h / 45 min ab 9 h (§ 4), Buchungen an Sonn-/Feiertagen (§§ 9–10). | neuer Report/Validierungen | L |

### E. Feiertage — strukturell

| # | Anpassung | Details | Betroffene Stellen | Aufwand |
|---|---|---|---|---|
| E.1 | Bewegliche Feiertage | Karfreitag, Ostermontag, Christi Himmelfahrt, Pfingstmontag, Fronleichnam sind osterabhängig; `regular_holidays` kann nur fixe [Tag, Monat]. Lösung: Gauß'sche Osterformel oder `holidays`-Gem als Generator, der die `holidays`-Tabelle jährlich befüllt (Job oder Rake-Task). | `holiday.rb`, Settings, ggf. Gem | M |
| E.2 | Bundesland-abhängige Feiertage | Feiertage gelten heute global. In DE unterscheiden sie sich stark je Bundesland (Fronleichnam, Allerheiligen, Reformationstag, …). Anknüpfungspunkt: das existierende `Workplace`-Modell → Holiday↔Workplace-Zuordnung, `Holiday.musttime(date)` wird standortabhängig. Größerer Eingriff, da `Holiday` überall statisch/gecacht verwendet wird. | `holiday.rb`, `workplace.rb`, Aufrufer | L |

### F. Datenschutz (DSGVO)

| # | Anpassung | Details | Betroffene Stellen | Aufwand |
|---|---|---|---|---|
| F.1 | Sichtbarkeit von Abwesenheitsgründen einschränken | Krankheitsgründe sind Gesundheitsdaten (Art. 9 DSGVO). Ein `private`-Flag auf `Absence` existierte und wurde 2017 entfernt (`db/migrate/20170725121120_remove_absences_private.rb`); Auswertungen zeigen die Absenzart. Wiedereinführung eines Flags „Grund nur für Management/HR sichtbar" — andere sehen nur „abwesend". | `absence.rb`, `ability.rb`, Evaluations | M |

---

## 4. Priorisierung

### Low-hanging Fruits (jeweils ≤ 1 Tag, sofort machbar)

Stand Branch `de_anpassung` (2026-07-05): alle Punkte dieser Liste sowie
**A.1** (de-DE-Locale-Dateien) sind umgesetzt. Offen aus A.x bleibt nur
**A.2** (hartkodierte CH-Begriffe in Views/Modellen über i18n führen).

1. ✅ **A.3** Absenzarten-Seeds (Militär raus, DE-Arten rein)
2. ✅ **A.4** Feiertags-Defaults in `settings.yml`
3. ✅ **A.5** `business_year_start_month` per ENV konfigurierbar, DE-Defaults dokumentieren
4. ✅ **B.4** Mindesturlaub-Warnung (20 Tage)
5. ✅ **C.5** AU-Nachweis-Datum an `Absencetime` (`sick_note_received_on`)
6. ✅ **C.6** `payed`-Flag als „sollzeitwirksam" beschriften
7. ✅ **A.6–A.8** Doku: Zusatzurlaub, halbe Feiertage, Elternzeit-Workaround inkl. Warnhinweis (auch: Krankengeld-Phase nie als 0 %-Anstellung abbilden) — siehe [de-einsatz-leitfaden.md](de-einsatz-leitfaden.md)

### P1 — Markteintritt (ohne das wirkt das Tool „schweizerisch" oder rechnet falsch)

| Punkt | Warum zuerst |
|---|---|
| A.1/A.2 Lokalisierung | Erster Eindruck; „Ferien"/„Absenz"/„Militär" disqualifizieren im DE-Vertrieb sofort. |
| E.1 Bewegliche Feiertage | Ohne Karfreitag & Co. ist jede Sollzeitrechnung ab Woche 1 falsch. |
| B.3 Urlaubsverfall + Hinweispflicht | Unbegrenzt kumulierender Resturlaub ist in DE fachlich falsch und haftungsrelevant (Hinweispflicht). |
| C.1 Absenz-Kategorien | Fundament für alle Krankheits-/Familienthemen; früh einbauen spart Migrationen. |

### P2 — Compliance-Ausbau

| Punkt | Warum |
|---|---|
| B.1/B.2 Zwölftelung + § 17 BEEG | Behebt die nachgewiesen falsche Elternzeit-/Ein-/Austritts-Berechnung (Abschnitt 2). |
| C.2 EFZG-6-Wochen-Überwachung | Größter fachlicher Mehrwert gegenüber „nur Kalender". |
| C.3 Kindkrank-Kontingente | Häufigster Alltagsfall in DE-Teams. |
| C.4 Mutterschutz | Klein, sobald C.1 existiert. |
| D.1 Start/Stop-Pflicht (opt-in) | Rechtslage verlangt Erfassung von Beginn/Ende; als Konfig-Flag ohne Bruch für CH-Bestandskunden. |
| F.1 Absenz-Privacy | DSGVO-Risiko, überschaubarer Aufwand. |

### P3 — Vervollständigung

| Punkt | Warum später |
|---|---|
| E.2 Bundesland-Feiertage | Nur für verteilte Teams relevant; großer Eingriff in gecachte `Holiday`-Statik. Übergangslösung: eine Instanz = ein Bundesland. |
| D.2 ArbZG-Warnreports | Nice-to-have-Compliance; kein Blocker für Einführung. |
| B.5 Wartezeit § 4 BUrlG | Praktisch meist über Absprachen gelöst; Anzeige-Thema. |

### Grundsatzentscheidung

Alle DE-Regeln sollten als **konfigurierbarer Länder-Modus** umgesetzt werden
(z. B. `Settings.defaults.country` steuert Berechnungsmodus, Validierungen,
Seeds), nicht als Fork — das CH-Verhalten bleibt unverändert Default und
Bestandskunden sind nicht betroffen. `RAILS_PTIME_COUNTRY` existiert bereits
und ist der natürliche Schalter.
