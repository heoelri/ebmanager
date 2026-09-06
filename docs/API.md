# API-Vertrag

Die API liegt unter `/api`, bei Unterverzeichnisbetrieb entsprechend unter
`/<installation>/api`. Installation, Updates und Rollback:
[WEBSPACE-DEPLOYMENT.md](WEBSPACE-DEPLOYMENT.md).

## Transport und Typen

- Produktiv ausschließlich HTTPS. Anmeldung setzt `__Host-session` (`Secure`,
  `HttpOnly`, `SameSite=Strict`, zwölf Stunden); weitere Aufrufe verwenden dieses
  Cookie. Alle fachlichen Daten bleiben auf Organisation und erlaubte Einheiten
  beziehungsweise Berichte begrenzt.
- Schreibende Requests verwenden `Content-Type: application/json`, höchstens
  1.000.000 Bytes und ein JSON-**Objekt** als Wurzel. Ein leerer Body entspricht
  `{}`; `[]`, `null` und Skalare an der Wurzel sind ungültig. Ein vorhandener
  `Origin` muss zum eigenen Schema/Host/Port passen. Fehler und JSON-Erfolge
  verwenden `Cache-Control: no-store`.
- Lokale IDs: positive JSON-Integer oder kanonische dezimale Strings, z. B.
  `12`/`"12"`, höchstens `min(PHP_INT_MAX, 9007199254740991)`. Die zweite
  Grenze ist JavaScripts `Number.MAX_SAFE_INTEGER`, keine INT32-Grenze;
  das unveränderte MySQL-Schema verwendet weiterhin `BIGINT UNSIGNED`.
  Keine Booleschen Werte, Fließkommazahlen, Vorzeichen, führenden Nullen,
  Leerzeichen, Exponenten, Suffixe oder Überläufe. Das gilt auch für Pfade,
  Einheitszuordnungen, Besatzung und Quellberichts-IDs. Antworten enthalten lokale
  IDs als Integer. Nicht sicher darstellbare Antwort-Integer führen zu einem
  neutralen HTTP 500 statt zu gerundeten Browserwerten. DIVERA-IDs und
  Fahrzeug-Snapshot-IDs sind dagegen opake Texte.
- Listen sind JSON-Arrays, Objekte JSON-Objekte; die Formen sind nicht
  austauschbar. Ein JSON-String mit eingebettetem JSON ersetzt keines davon.
  Einheits-ID-Listen werden dedupliziert und numerisch sortiert.
- Allgemeine Textfelder akzeptieren aus Kompatibilitätsgründen weiterhin
  Strings, Zahlen und Boolesche Werte; sie werden als Text dargestellt und
  außen getrimmt (`0` → `"0"`, `true` → `"1"`, `false` → `""`). Arrays/Objekte
  sind immer ungültig. Pflichttext darf danach nicht leer sein. Optionaler
  Text wird bei fehlend, `null` oder `""` leer. Fachliche Auswahllisten wie
  `role`, `incidentType` und Klassifikationswerte müssen exakt passen.
- Passwörter sind ausschließlich **ungetrimmte Strings**, ohne NUL-Zeichen,
  höchstens 200 Zeichen; neue Passwörter mindestens zehn Zeichen.
  Bei Benutzeränderungen bedeuten fehlend, `null` und `""`: nicht ändern.
  Anmeldung verändert das eingegebene Passwort nicht.
- Unbekannte Felder werden nicht gespeichert. Insbesondere überschreiben
  mitgesendete DIVERA-Daten keinen serverseitig nachgeladenen Alarm und
  `alarmedAt` überschreibt nicht die Alarmierungszeit des Einsatzes.
- Revisionswerte sind abweichend von IDs ausschließlich JSON-Integer im
  Bereich `1..4294967295`, keine numerischen Strings.

### Zeitpunkte und Reihenfolge

Eingaben `startedAt`, `departedAt`, `arrivedAt`, `endedAt` verwenden
`YYYY-MM-DDTHH:mm:ss.SSSZ` (UTC), etwa `2026-08-22T18:00:00.000Z`.
Die bereits unterstützten ein- oder zweistelligen Sekundenbruchteile
(`.1Z`, `.12Z`) bleiben gültig und werden auf Millisekunden normalisiert.
Ungültige Kalenderdaten werden abgewiesen. Statistikgrenzen verwenden `YYYY-MM-DD`.
Technische Zeitantworten sind ISO-8601 in UTC mit `Z`: Einsatz-/Berichtszeiten,
`created_at`, `updated_at`, `released_at`, `consolidated_at` und
`last_divera_import_at` mit Millisekunden, `history[].created_at` und
`loginHistory[]` mit Sekunden. Nicht gesetzte optionale Zeitpunkte sind `null`.
Diese Konvention betrifft nicht die lokalisierte Browseranzeige.

Bestehende MySQL-`DATETIME`-Werte werden als UTC interpretiert. Die noch offene
Vereinheitlichung aller Schreibzeitpunkte/DB-Defaults aus **#87** wird durch
die Formatierung nicht behoben; ältere mit anderer Host-Zeitzone geschriebene
Werte werden nicht nachträglich korrigiert.

Einsätze: `started_at` absteigend, bei Gleichstand ID absteigend. Benutzer,
Einheiten, Mitglieder und Stammfahrzeuge: Name, dann ID aufsteigend.
Berichte: Erstellungszeit, dann ID; Prüfverlauf: Zeitpunkt, dann Übergangs-ID.
Zuordnungen und Besatzung: Einheits- beziehungsweise Mitglieds-ID aufsteigend.
Besatzungszusammenfassungen folgen derselben Mitgliedsreihenfolge.
Qualifikationsanzeigen folgen Qualifikationsname/ID und werden danach
dedupliziert. Zusätzliche Fahrzeuge sind nach Bezeichnung sortiert.
Fahrzeug-Snapshots behalten ihre gespeicherte Reihenfolge und Daten.

## Endpunkte

Rollen: **W** = `wehrleitung`, **E** = `einheitsleitung`,
**F** = `fuehrungskraft`; **A** = alle angemeldeten Rollen.
„Sichtbar“ umfasst immer die serverseitigen Mandanten-, Rollen- und
Einheitsgrenzen. Antworten sind JSON, sofern nicht als PDF bezeichnet.

| Methode / Pfad | Rolle | Eingabe → Erfolgsausgabe |
|---|---|---|
| `GET /bootstrap` | öffentlich | `{needsSetup: boolean}`; Konfigurations-/Schemafehler: 503 |
| `POST /setup` | öffentlich, nur vor Einrichtung | `setupToken, organization, unit, name, email, password` → 201 `{ok:true}` |
| `POST /login` | öffentlich | `email, password` → `{ok:true}` und Sitzungscookie |
| `POST /password-reset/request` | öffentlich | `email` → 202 `{ok:true}`, auch für unbekannte Konten; fünf Minuten Ausgabesperre |
| `POST /password-reset/context` | öffentlich | `token` → `{email}` nur für gültigen Einmallink |
| `POST /password-reset/confirm` | öffentlich | `token, password` → `{ok:true}`; verbraucht Link, widerruft Sitzungen |
| `POST /logout` | A | `{}` → `{ok:true}`, beendet aktuelle Sitzung |
| `GET /me` | A | `id, organization_id, organization_name, name, email, role, unitIds[]` |
| `GET /options` | A | `ranks{}, incidentTypes[], classifications{}, classificationLabels{}` aus `constants.php` |
| `GET /system` | W | kuratierte Objekte `application, database, email`, Listen `units, users`; keine Geheimnisse |
| `GET /units` | A | sichtbare Liste mit `id, name, divera_configured` (0/1), `last_divera_import_at` |
| `POST /units` | W | `name` → 201 `{id}` |
| `GET /units/:id/members` | A, erlaubte Einheit | aktive Mitglieder: `id, name, divera_id, active` (0/1), `qualifications` (Anzeigetext) |
| `GET /units/:id/resources` | A, erlaubte Einheit | `{members:[], vehicles:[]}`; Mitglieder auch inaktiv; Fahrzeuge `id, divera_id, name, shortname, fullname` |
| `GET /statistics?from=…&to=…` | E | einschließlich beider Tage, nur aktuelle Einheit; Standard: Jahresanfang/heute in Europe/Berlin; aggregierte Statistik |
| `GET /users` | W | Liste `id, name, email, role, unit_ids:[], unit_names, loginHistory:[]`; höchstens neuester Login je Benutzer |
| `POST /users` | W | `name, email, role, unitIds[]` (alternativ `unitId`) → 201 `{id}`; siebentägige Einladung, kein Startpasswort |
| `PUT /users/:id` | W | `name, email, role, unitIds[]`, optional `password` → `{ok:true}`; letzte Wehrführung bleibt erhalten |
| `POST /users/:id/invitation` | W, nicht eigener Zugang | `{}` → `{ok:true}`; siebentägige Neueinladung; Widerruf erst bei erfolgreicher Mailannahme |
| `GET /incidents` | A | sichtbare Einsätze einschließlich `assignments:[]`, `units` (Anzeigetext), `reportStatus{}`; siehe unten |
| `POST /incidents` | A, erlaubte Einheiten | `title, startedAt, unitIds[]`, optional `address` → 201 `{id}`, ggf. `warning` |
| `GET /incidents/:id/reports` | A | Liste ausschließlich sichtbarer Berichte; siehe unten |
| `POST /incidents/:id/reports` | A, alarmierte/erlaubte Einheit | Berichtseingabe plus `unitId` → 201 `{id}` |
| `PUT /reports/:id` | Autor in `author_draft` / E in `unit_review` | vollständige Berichtseingabe plus `revision` → `{ok:true}` |
| `POST /reports/:id/submit-to-unit` | ursprünglicher F-Autor | `revision`, optional `comment` → `{ok:true}`, ggf. `warning` |
| `POST /reports/:id/return-to-author` | zuständige E | `revision, comment` → `{ok:true}`, ggf. `warning` |
| `POST /reports/:id/submit-to-command` | zuständige E | `revision`, optional `comment` → `{ok:true}`, ggf. `warning` |
| `POST /reports/:id/return-to-unit` | W | `revision, comment` → `{ok:true}`, ggf. `warning` |
| `PUT /incidents/:id/consolidation` | W | `text, revision, reportVersions:[{id,revision}]` → `{ok:true}` |
| `GET /reports/:id/pdf` | A, sichtbarer Bericht | PDF-Einzelbericht |
| `GET /incidents/:id/pdf` | A, sichtbarer Einsatz | PDF-Akte mit nur sichtbaren Berichten |
| `GET /incidents/:id/consolidation/pdf` | W | PDF-Gesamtbericht; erst nach Konsolidierung |
| `PUT /units/:id/divera` | W/E, erlaubte Einheit | `accessKey` → `{ok:true}`; Schlüssel wird nie zurückgegeben |
| `GET /units/:id/divera?summary=1` | A, erlaubte Einheit | `{alarms:[], vehicles:[]}`; `summary` fehlend/`0`: vollständige Fahrzeuge, `1`: ohne Fahrzeugauflösung; andere Werte ungültig |
| `POST /units/:id/divera/import` | A, erlaubte Einheit | opake DIVERA-`id` → 201 `{id}`, ggf. `warning`; Daten werden serverseitig nachgeladen |
| `POST /units/:id/divera/members/sync` | W/E, erlaubte Einheit | `{}` → Zähler `members, qualifications, count` |
| `POST /units/:id/divera/vehicles/sync` | W/E, erlaubte Einheit | `{}` → Zähler `vehicles, count` |
| `POST /units/:id/divera/sync` | W/E, erlaubte Einheit | `{}` → Zähler `members, qualifications, vehicles, incidentsCreated, incidentsUpdated, assignmentsCreated`, ggf. `warning` |

DIVERA-Aufrufe bleiben ausschließlich GET auf `/api/v2/alarms` und
`/api/v2/pull/all`; die lokalen POST-Routen schreiben nur lokal.
Die Discovery-Alarme enthalten `id, foreignId, date, title, startedAt, text,
address, lat, lng, remark, patient, caller, vehicles`; Koordinaten sind
Zahlen oder `null`. Ein Import nimmt ausschließlich die ID entgegen.
Die Statistik liefert `range`, `unit`, `totals`, `alarmedVehicles`,
`additionalVehicles`, `members`, `years`, `months`, `weekdays`,
`workPeriods`, `dayPeriods` und `periods`; Summen-/Ranglisten enthalten
Anzahlwerte, keine fremden Berichts- oder Personendetails.

Bei Benutzerzuordnungen hat eine explizite `unitIds`-Liste Vorrang vor dem
kompatiblen Einzelwert `unitId`. Fehlend oder `null` verwendet diesen
Einzelwert, sofern vorhanden, sonst `[]`. Die Wehrführung hat keine Zuordnung,
eine Einheitsführung benötigt genau eine, eine Führungskraft mindestens eine.

## Berichte und strukturierte Antworten

Berichtseingabe: Pflichtfelder `runningNumber` (max. 50 Zeichen), `narrative`
(max. 10.000), `incidentType` und `endedAt`. Alarmierung stammt ausschließlich
aus dem Einsatz. `departedAt` und `arrivedAt` dürfen fehlen, `null` oder `""`
sein; alle vorhandenen Zeitpunkte müssen chronologisch sein. PUT ersetzt die
bearbeitbaren Berichtsinhalte, ist kein partielles PATCH.

Optionale Objekte `damagedParty`, `damagingParty` enthalten `name, phone`
(je max. 200), `address` (max. 500). `incidentCommand` enthält
`rank, name, additionalRank, additionalName` (je max. 200; historischer Text
bleibt zulässig). Fehlend, `null` oder `{}` leeren die enthaltenen Texte.
`[]` ist hier ungültig. `classification` ist ein Objekt mit den Listen
`site, cause, technical`; fehlend, `null` und `{}` bedeuten leere Gruppen.
Auch eine fehlende oder `null`-Gruppe bedeutet `[]`. Werte müssen aus
`/options` stammen; Duplikate werden entfernt.

`crew` ist eine Liste von Objekten `{memberId, vehicle, role}`; `vehicle`
fehlend/`null`/`""` bedeutet „Ohne Fahrzeug“, `role` fehlend/`null` bedeutet
`besatzung`. Weitere Rollen: `maschinist`, `einheitsfuehrer`.
`additionalVehicles` ist eine Liste eigener Fahrzeugbezeichnungen.
Beide Listen werden bei fehlend/`null`/`[]` geleert. Kein Mitglied doppelt,
Führungs-/Maschinistenfunktion höchstens einmal je Fahrzeug. Bestehende
historische Zuordnungen dürfen unverändert erhalten bleiben; inaktive
Mitglieder und nicht mehr aktuelle Fahrzeuge sind keine neuen Auswahlziele.

Antworten behalten die bestehenden Schlüsselnamen:

- `users[].unit_ids`: Integer-Liste, auch leer `[]`.
- `incidents[].assignments`: Liste mit `unitId`, `vehicles` (Liste gespeicherter
  Fahrzeugtexte oder -objekte), `hasReport` (0/1), ggf. `reportAuthorName`
  für eine andere Führungskraft. Keine zusätzliche Einheitsprojektion für
  nicht berechtigte Rollen. Nur W erhält `consolidated_text` und die
  Einsatz-`revision`; `consolidated_at`/`reportStatus` bleiben rollenabhängig
  verfügbare Zustandsdaten.
- Berichte: `crew` als Liste, `damaged_party`, `damaging_party`,
  `incident_command`, `classification` als Objekte; historische SQL-NULL-
  Kontakte werden `{}`. Neu gespeicherte leere Kontakte enthalten leere
  Textfelder, eine leere Klassifikation die drei leeren Gruppenlisten.
  `history` und `additionalVehicles` bleiben Listen. Außerdem u. a.
  Integer-`revision`, `editable` (boolean), `duration_minutes` (Integer/null)
  sowie die unveränderten fachlichen Spalten und Autoren-/Einheitsnamen.

**Breaking Change (#92):** Die genannten Strukturen waren teilweise
JSON-kodierte **Strings innerhalb der JSON-Antwort**. Clients müssen sie nun
direkt verwenden und dürfen kein zusätzliches `JSON.parse` ausführen.
Das Speicherschema der JSON-Spalten bleibt unverändert.

## Revisionen und Fehler

Bearbeitungen und Übergänge benötigen die zuletzt geladene Berichtsrevision.
Die Konsolidierung benötigt die zuletzt geladene Einsatzrevision und genau
alle aktuellen Quellberichte mit deren geladenen Revisionen; jede alarmierte
Einheit muss in `wehr_review` sein. Fehlende/falsch typisierte Vorbedingungen:
400. Veraltete oder abweichende Stände: 409 ohne fachliche Änderungen.
Kein automatisches Wiederholen einer kollidierten Mutation.

Fehler haben ausschließlich die Form `{"error":"Deutsche Meldung"}`.
Erfolgreich gespeicherte Vorgänge mit anschließendem Benachrichtigungsfehler
bleiben erfolgreich und können zusätzlich `warning` enthalten.

| Status | Bedeutung |
|---|---|
| 400 | Ungültiger Typ/Wert, unvollständige Revision, ungültiger Einmallink oder nicht konfigurierte DIVERA-Einheit |
| 401 | Keine gültige Sitzung oder falsche Anmeldedaten |
| 403 | Rolle/Einheit/Aktion nicht erlaubt oder unzulässiger Origin |
| 404 | Route oder zugreifbare Ressource nicht gefunden |
| 409 | Fachlicher Konflikt, veraltete Revision, unzulässiger Workflowstand |
| 413 | Request-Body größer als 1.000.000 Bytes |
| 415 | Schreibender Request ohne `application/json` |
| 500 | Unerwarteter interner/DB-Fehler, auch unbekannte Unique-Constraints; nur `Interner Fehler` |
| 502 | Fehlerhafte/fehlgeschlagene DIVERA-Antwort |
| 503 | Fehlende Konfiguration, Bootstrap-/Schemafehler, nicht verfügbarer Mail- oder PDF-Dienst |

Bekannte Unique-Konflikte erhalten genau diese 409-Meldungen:

- „Eine Einheit mit diesem Namen existiert bereits in dieser Organisation“
- „Diese E-Mail-Adresse wird bereits verwendet“
- „Für diese Einheit existiert bereits ein Einsatzbericht“
- „Diese laufende Nummer wird in dieser Einheit und diesem Kalenderjahr bereits verwendet“

Weitere 409-Fälle umfassen abgeschlossene Ersteinrichtung, letzte Wehrführung,
Zurücksetzen des eigenen Zugangs, fehlende Quellberichte, nicht abgeschlossene
Gesamtberichte, veraltete Revisionen und wiederholte Übergaben.
SQL, Constraint-Rohmeldungen und personenbezogene Fehlerwerte werden weder
im Fehlervertrag noch in allgemeinen Fehlerlogs ausgegeben.
