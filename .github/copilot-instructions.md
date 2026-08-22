# GitHub Copilot Instructions

## Verbindlicher Arbeitsablauf

- Lies diese Datei vor jeder Änderung vollständig und prüfe den Auftrag gegen
  die hier dokumentierten Entscheidungen.
- Ändere keine dieser Grundentscheidungen stillschweigend. Wenn ein Auftrag
  ihnen widerspricht oder eine Entscheidung ersetzen, erweitern oder
  relativieren würde, frage den Benutzer vor der Umsetzung.
- Dokumentiere neue dauerhafte Produkt- oder Architekturentscheidungen in
  dieser Datei. Temporäre Implementierungsdetails gehören nicht hierher.
- Aktualisiere `CHANGELOG.md` bei jeder relevanten funktionalen, technischen oder betrieblichen Änderung. Nicht rückwärtskompatible Änderungen müssen ausdrücklich unter `Breaking Changes` stehen.
- Dokumentiere jeden nicht automatisierbaren Aktualisierungsschritt vollständig in `CHANGELOG.md` und im Aktualisierungsabschnitt der `README.md`; insbesondere müssen erforderliche SQL-Migrationen, Konfigurationswerte und ihre Ausführungsreihenfolge genannt werden.
- `docs/WEBSPACE-DEPLOYMENT.md` ist die maßgebliche ausführliche Anleitung für Installation, Deployment, Updates und Rollback auf Webspace. Andere Dokumente verlinken darauf, statt dieselben Schritte zu duplizieren.
- Aktualisiere `DATENMODELL.md` bei jeder Änderung am Code, damit Tabellen,
  Beziehungen, Datenformate und fachliche Regeln immer dem aktuellen
  Implementierungsstand entsprechen.
- Größere Änderungen an Anwendung, Berechtigungen, Datenmodell oder
  Infrastruktur müssen vor Abschluss einen Security Review durchlaufen.
  Dokumentiere Befunde und Entscheidungen in `SECURITY-REVIEW.md`.
- Halte Änderungen klein und vollständig. Verwende zuerst vorhandenen Code,
  dann PHP-, MySQL- oder Browser-Funktionen und erst danach zusätzliche
  Abhängigkeiten.

## Produkt und Sprache

- Die Anwendung erstellt und konsolidiert Einsatzberichte für Feuerwehren.
- Oberfläche, Validierungsfehler und fachliche Begriffe sind deutsch.
- Eine Organisation beziehungsweise Wehr ist ein Mandant und besitzt mehrere
  Einheiten.
- Die Anwendung bleibt eine einfache, responsive Weboberfläche ohne
  Frontend-Framework.

## Technische Architektur

- Zielbetrieb ist regulärer Webspace mit FTP- oder SFTP-Zugang, PHP 8.2 oder
  neuer, Apache und MySQL 8.0 oder neuer.
- Backend: `api.php` mit PHP-Standardfunktionen und PDO MySQL.
- Frontend: `public/index.html` mit nativem HTML, CSS und JavaScript.
- Es gibt keine Composer-Laufzeitabhängigkeiten.
- Lokale Entwicklung läuft über `compose.yaml` mit PHP 8.2/Apache, MySQL 8.4
  und einem ausschließlich lokalen, selbstsignierten HTTPS-Zertifikat.
- Das initiale MySQL-Schema liegt in `schema.sql`. Spätere Schemaänderungen
  benötigen kleine, vor dem Anwendungscode auszuführende SQL-Migrationen.
- Apache leitet `/api/*` über `.htaccess` an `api.php` weiter und liefert
  `public/index.html` als Startseite aus.
- Die Anwendung unterstützt ohne separate Pfadkonfiguration sowohl den Betrieb im Dokumentenstamm als auch in einem Unterverzeichnis.
- Nach erfolgreichen Tests eines Pushs auf `main` lädt der Deployment-Workflow
  nur `.htaccess`, `api.php` und `public/index.html` per verpflichtendem FTPS
  hoch. Konfiguration und SQL-Dateien werden nie automatisch deployt.
- Das produktive GitHub-Environment heißt `hiba`. Weitere Ziele wie `devpreview` müssen eigene Environments, Secrets, Schutzregeln und Concurrency-Gruppen verwenden; Produktionszugangsdaten werden nicht geteilt.
- Datenbankzugangsdaten, das einmalige Einrichtungstoken, die öffentliche HTTPS-Anwendungsadresse und die Absenderadresse kommen aus Umgebungsvariablen oder der nicht versionierten `config.local.php`.
- API-Fehler haben die Form `{ "error": "..." }`. Eingaben werden an der
  API-Grenze validiert; Fehler dürfen nicht still ignoriert werden.
- `GET /api/bootstrap` prüft Datenbankkonfiguration, Erreichbarkeit und das vollständige Schema. Fehler werden ohne Zugangsdaten mit HTTP 503 gemeldet und in der Oberfläche als Betriebszustand angezeigt.

## Mandanten und Berechtigungen

- Jede Abfrage fachlicher Daten muss über `organization_id` auf den aktuellen
  Mandanten begrenzt sein.
- `wehrleitung` sieht alle Einsätze und Berichte der eigenen Organisation,
  verwaltet Einheiten und Benutzer und schreibt den Gesamtbericht.
- `einheitsleitung` kann mehreren Einheiten angehören. Sie sieht und bearbeitet
  Entwürfe ihrer Einheiten und gibt diese für die Wehrleitung frei.
- `fuehrungskraft` kann mehreren Einheiten angehören und für jede dieser
  Einheiten Berichte schreiben. Sie sieht nur selbst verfasste Berichte.
- Benutzer gehören über `user_units` zu beliebig vielen Einheiten. Das alte
  Feld `users.unit_id` bleibt nur als kompatible Primärzuordnung bestehen.
- Benutzer können durch die Wehrleitung bearbeitet werden. Ein neues Passwort
  ist dabei optional.
- Vergessene Passwörter werden über einen per E-Mail versendeten, nur als SHA-256-Hash gespeicherten Einmal-Token zurückgesetzt. Der Token gilt 30 Minuten, Anforderungen sind pro Benutzer fünf Minuten gesperrt und ein erfolgreicher Reset widerruft alle Sitzungen.
- Freigegebene Berichte sind unveränderlich.
- Sitzungen liegen in einem `HttpOnly`- und `SameSite=Strict`-Cookie und laufen
  nach zwölf Stunden ab.

## Einsätze und Berichte

- Ein Einsatz kann mehreren Einheiten zugeordnet sein.
- Jede beteiligte Einheit verfasst genau einen Bericht pro Einsatz; die Wehrleitung
  konsolidiert diese in `incidents.consolidated_text`.
- Ein DIVERA-Einsatz ist innerhalb einer Organisation über `divera_id`
  eindeutig. Wiederholter Import aktualisiert ihn, statt ihn zu duplizieren.
- `incident_units` ist je Kombination aus Einsatz und Einheit eindeutig.
  Wiederholter Import aktualisiert diese Zuordnung und ihre Fahrzeuge.
- Importierte Einsatzdaten umfassen `foreign_id`, DIVERA-`date`,
  Alarmierungszeit, `title`, `text`, Adresse, `lat`/`lng`, `remark`, `patient`
  und `caller`.
- Jeder Einheitsbericht enthält die Alarmierungszeit des Einsatzes sowie
  `departed_at`, `arrived_at` und `ended_at`. Die Alarmierungszeit ist im
  Bericht nicht frei änderbar und stammt bei DIVERA-Einsätzen aus `date`.
- Einsatzzeiten müssen vollständig und chronologisch sein. Die Einsatzdauer
  wird aus Alarmierungszeit und Einsatzende berechnet und nicht separat
  gespeichert.
- Zulässige Einsatzarten sind: Kleinbrand, Mittelbrand, Großbrand, Wald- und
  Flächenbrand, Schornsteinbrand, Kfz-Brand, Verkehrsunfall,
  Oelunfall/Oelspur, Chemieunfall, Technische Hilfe, Sturmeinsatz,
  Hochwassereinsatz, Fehlalarm BMA, BMA, Fehlalarm, Böswilliger Alarm und
  Sonstiges.
- Die Aufgliederung ist eine Mehrfachauswahl in den drei Gruppen
  `site` (Einsatzstelle), `cause` (Schadensursache) und `technical`
  (Technische Hilfe). Die Werte entsprechen dem Formular
  `FW-Einsatzbericht 66.2026 F4 Hilchenbach.pdf`.
- Andere Felder aus diesem PDF werden vorerst ausdrücklich nicht übernommen.
- `patient` und `caller` sind sensible, mandantengebundene Daten. Sie dürfen
  weder protokolliert noch organisationsübergreifend ausgegeben werden.

## Mitglieder, Qualifikationen und Besatzung

- Mitglieder sind fachliche Personen und von Anmeldebenutzern getrennt.
- Eine Person wird anhand ihrer DIVERA-ID organisationsweit einmal in
  `members` gespeichert und über `member_units` mehreren Einheiten zugeordnet.
- Qualifikationen sind einheitsspezifisch. Der Sync aktualisiert
  `cluster.qualification` und die IDs aus
  `cluster.consumer[*].qualifications`.
- Berichtsbesatzungen liegen strukturiert in `report_crew`. Ein Mitglied kann
  pro Bericht höchstens einmal eingesetzt werden.
- Zulässige Funktionen sind `maschinist`, `einheitsfuehrer` und `besatzung`.
- Je Fahrzeug gibt es höchstens einen Maschinisten und einen Einheitsführer,
  aber beliebig viele Personen in der Besatzung.
- Nur eigene Fahrzeuge der berichtenden Einheit oder „Ohne Fahrzeug“ sind als
  Besatzungsziel zulässig. Der Server erzwingt diese Regel unabhängig von der
  Oberfläche.
- In der Berichtsansicht stehen zuerst die Fahrzeugspalten mit den drei
  Funktionen und darunter eine volle Breite mit verfügbarem Personal.
- Die Box mit verfügbarem Personal ist nativ ein- und ausklappbar.
- Drag-and-Drop ist die primäre Bedienung. Auswahlfelder bleiben als
  barrierearmer Tastatur- und Mobil-Fallback erhalten.

## DIVERA 24/7

- DIVERA wird je Einheit mit einem eigenen Access-Key konfiguriert.
- DIVERA ist strikt nur lesend angebunden. Jeder externe DIVERA-Aufruf muss
  HTTP `GET` verwenden.
- Rufe niemals Endpunkte auf, die Alarme, Rückmeldungen, Status,
  Fahrzeugbesatzungen, Dateien oder andere DIVERA-Daten erstellen, ändern,
  bestätigen, schließen oder löschen.
- Access-Keys dürfen nie geloggt, an den Browser zurückgegeben oder committed
  werden.
- Einsätze werden über `GET /api/v2/alarms` gelesen.
- Mitglieder, Qualifikationen und Fahrzeugstammdaten werden über
  `GET /api/v2/pull/all` gelesen.
- Der Live-Fahrzeugstatus aus `pull/vehicle-status` wird ausdrücklich nicht
  abgerufen, gespeichert oder angezeigt; er ist für Einsatzberichte nicht
  relevant.
- `cluster.vehicle` bestimmt die eigenen Fahrzeuge der konfigurierten Einheit.
  Alle im Alarm enthaltenen Fahrzeuge werden importiert und als eigenes oder
  fremdes Fahrzeug markiert. Nur eigene Fahrzeuge sind Besatzungsziele.
- Die Besatzungs-Endpunkte von DIVERA werden niemals verwendet. Alle
  Personal-Fahrzeug-Zuordnungen existieren ausschließlich lokal.
- Ein lokaler POST-Import oder Sync schreibt nur in MySQL und ist kein
  schreibender DIVERA-Aufruf.

## Oberfläche

- Hauptnavigation: Einsätze, Mitglieder & Fahrzeuge, rollenabhängig
  Verwaltung und DIVERA sowie Abmelden.
- Der Tab „Mitglieder & Fahrzeuge“ zeigt je zugänglicher Einheit
  synchronisierte Mitglieder und Qualifikationen sowie eigene und fremde
  Fahrzeuge aus den letzten Einsatzimporten.
- Die DIVERA-Seite konfiguriert den Access-Key, synchronisiert Mitglieder und
  Qualifikationen und importiert Einsätze.
- Bereits für die ausgewählte Einheit importierte DIVERA-Einsätze zeigen einen
  deaktivierten Import-Button.
- Einzelberichte zeigen Besatzungen nach Fahrzeug gruppiert; innerhalb des
  Fahrzeugs stehen Einheitsführer, Maschinist und Besatzung.
- Externe Kartenlinks verwenden OpenStreetMap und öffnen mit
  `rel="noopener"`.

## Datenschutz und Sicherheit

- Passwörter werden mit `password_hash` gespeichert und mit
  `password_verify` geprüft.
- Die öffentliche Ersteinrichtung erfordert ein zufälliges, mindestens 32
  Zeichen langes `SETUP_TOKEN`.
- Sitzungscookies sind `HttpOnly`, `SameSite=Strict` und bei HTTPS `Secure`.
  Eine Passwortänderung widerruft alle Sitzungen des betroffenen Benutzers.
- Das Sitzungscookie heißt unter HTTPS `__Host-session` und während des temporären HTTP-Betriebs `session`. Alle schreibenden API-Anfragen erfordern `application/json`; vorhandene `Origin`-Header müssen exakt der Anwendungsorigin mit dem tatsächlich verwendeten Schema entsprechen.
- Passwort-Hashes, Sitzungswerte und DIVERA-Schlüssel werden nie über die API
  ausgegeben.
- Mandanten- und Einheitsgrenzen werden serverseitig geprüft; reine
  UI-Ausblendung ist keine Berechtigungsprüfung.
- Behalte die Größenbegrenzung für Request-Bodies und validiere IDs,
  Koordinaten, Rollen und Freitextlängen.

## Tests und CI

- Tests verwenden PHP-, MySQL- und Shell-Bordmittel ohne Testframework.
- GitHub Actions prüft PHP-Syntax, importiert `schema.sql` in MySQL 8 und
  führt `test/smoke.sh` aus.
- Ein unabhängiger CI-Job baut die Docker-Images und führt den Smoke-Test
  gegen Apache/HTTPS und MySQL aus. Der Test-Workflow ist nur erfolgreich,
  wenn beide Jobs bestehen.
- Docker Compose führt denselben Smoke-Test gegen die lokale
  HTTPS-/MySQL-Umgebung aus.
- Pull Requests führen ausschließlich Tests aus und erhalten keinen Zugriff auf die Secrets des GitHub-Environments `hiba` oder zukünftiger Deployment-Environments.
- Dependabot prüft GitHub Actions, Dockerfiles und Docker Compose wöchentlich.
  Minor- und Patch-Updates werden je Ökosystem gruppiert; Major-Updates
  bleiben einzeln prüfbar.
- Ergänze für nicht triviale Änderungen einen fokussierten Test im bestehenden
  End-to-End-Fluss, besonders für Mandantentrennung, Rollen,
  Import-Idempotenz und externe Nur-Lese-Grenzen.
- Führe kein Testframework ein, solange die fokussierten HTTP-Checks
  ausreichen.

## Betrieb und Zurücksetzen

- Es gibt absichtlich keine Lösch- oder Reset-Funktion in der Oberfläche.
- Ein vollständiger einmaliger Reset erfolgt durch Löschen aller
  MySQL-Tabellen und erneuten Import von `schema.sql`.
- Ein Reset löscht alle Benutzer, Einsätze und Berichte endgültig.
