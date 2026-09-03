# GitHub Copilot Instructions

## Arbeitsweise und Dokumentation

- Lies diese Datei vor jeder Änderung vollständig. Ändere dokumentierte Grundentscheidungen nicht stillschweigend; frage bei widersprechenden Anforderungen nach.
- Halte Änderungen klein und vollständig. Nutze zuerst vorhandenen Code, dann PHP-, MySQL- oder Browserfunktionen und erst zuletzt neue Abhängigkeiten.
- Schreibe Oberfläche, Validierungsfehler und fachliche Begriffe auf Deutsch.
- Dokumentiere relevante Änderungen in `CHANGELOG.md`. Kennzeichne inkompatible Änderungen unter `Breaking Changes` und beschreibe manuelle Schritte in ihrer Ausführungsreihenfolge.
- `docs/WEBSPACE-DEPLOYMENT.md` ist die kanonische Anleitung für Installation, Deployment, Updates und Rollback. Andere Dokumente verlinken darauf, statt sie zu duplizieren.
- Halte `DATENMODELL.md` bei Änderungen an Tabellen, Beziehungen, Datenformaten oder fachlichen Regeln synchron.
- Dokumentiere neue dauerhafte Produkt- und Architekturentscheidungen hier. Temporäre Implementierungsdetails gehören nicht in diese Datei.
- Änderungen an Authentifizierung, Berechtigungen, sensiblen Daten oder Infrastruktur benötigen vor Abschluss einen dokumentierten Review in `SECURITY-REVIEW.md`.

## Produkt und Architektur

- Die Anwendung erstellt Einheitsberichte für Feuerwehreinsätze und konsolidiert sie zu einem Gesamtbericht.
- Eine Organisation beziehungsweise Wehr ist ein strikt getrennter Mandant mit mehreren Einheiten. Einheitsnamen sind innerhalb einer Organisation über `(organization_id, name)` eindeutig.
- Zielbetrieb ist klassischer Webspace mit HTTPS, SFTP, PHP 8.2 oder neuer, Apache und MySQL 8.0 oder neuer.
- `api.php` enthält Routing und Fachlogik. `constants.php` ist die zentrale Quelle für Rollen und fachliche Auswahllisten. `support.php` enthält gemeinsame HTTP-, PDO-, Validierungs- und Mailfunktionen.
- `public/index.html` enthält das native HTML, `public/app.js` die browserseitige Logik ohne Inline-Eventhandler und `public/styles.css` die lokal ausgelieferten, responsiven Styles. Es gibt kein Frontend-Framework und keine Composer-Laufzeitabhängigkeiten.
- `.htaccess` erzwingt HTTPS, schützt nicht öffentliche Dateien, leitet `/api/*` an `api.php` weiter und liefert `public/index.html` aus.
- Root- und Unterverzeichnis-Deployment funktionieren ohne separate Pfadkonfiguration.
- API-Fehler haben die Form `{ "error": "..." }`. Eingaben werden an der API-Grenze validiert; Fehler werden weder verschluckt noch als Erfolg dargestellt.
- `GET /api/bootstrap` meldet fehlende Konfiguration, Datenbankfehler und unvollständige Schemata ohne Zugangsdaten mit HTTP 503.

## Datenbank und Migrationen

- `schema.sql` definiert das vollständige aktuelle Schema für neue Installationen.
- Jede spätere Schemaänderung erhält eine kleine, fortlaufend nummerierte Datei unter `migrations/`, die vor dem zugehörigen Anwendungscode ausgeführt wird.
- Arbeite jede Migration zusätzlich in `schema.sql` ein und markiere sie dort in `schema_migrations` als angewendet.
- Lokales Docker Compose führt ausstehende Migrationen mit `docker/migrate.sh` vor dem Webstart genau einmal aus. Bestehende Dev-Volumes müssen ohne Verlust fachlicher Daten aktualisiert werden.
- Produktionsmigrationen werden nicht per SFTP automatisiert; dokumentiere ihre manuelle Ausführung in `CHANGELOG.md` und `docs/WEBSPACE-DEPLOYMENT.md`.

## Mandanten, Rollen und Benutzer

- Begrenze jede fachliche Abfrage serverseitig auf die `organization_id` des aktuellen Benutzers. UI-Ausblendung ersetzt keine Berechtigungsprüfung.
- `wehrleitung` hat keine Einheitszuordnung, verwaltet Einheiten und Benutzer, sieht nach der Übergabe an sie alle Berichte ihrer Organisation, sieht die Systemübersicht und schreibt den Gesamtbericht. Fremde Einheitsberichte bearbeitet sie nicht.
- `einheitsleitung` gehört exakt einer Einheit an, sieht deren Berichte nach der ersten Übergabe an die Einheitsführung und bearbeitet sie ausschließlich in `unit_review`.
- `fuehrungskraft` gehört mindestens einer und optional mehreren Einheiten an, schreibt dort Berichte und sieht ausschließlich ihre eigenen Berichte.
- `user_units` enthält die rollenabhängigen Einheitszuordnungen. `users.unit_id` bleibt als kompatible Primärzuordnung für Einheitsführung und Führungskräfte bestehen.
- Eine Organisation muss immer mindestens eine `wehrleitung` behalten.
- Neue Benutzer erhalten kein Startpasswort, sondern einen sieben Tage gültigen Einmallink zur Aktivierung; die Einladung nennt den Ablaufzeitpunkt in `Europe/Berlin`. Vergessene Passwörter bleiben 30 Minuten gültig, verwenden denselben gehashten Tokenmechanismus und sind pro Benutzer fünf Minuten gesperrt.
- Die Wehrleitung kann fremde Benutzerzugänge zurücksetzen und eine neue siebentägige Einladung senden. Erst nach erfolgreicher Mailannahme werden Passwort, Sitzungen und frühere Einmallinks ungültig; der eigene Zugang ist ausgeschlossen.
- Eine Passwortänderung widerruft alle Sitzungen des Benutzers.
- Erfolgreiche Anmeldungen werden mit Benutzer und UTC-Zeitpunkt in `login_history` gespeichert. Nur die Wehrleitung sieht den neuesten Eintrag je Benutzer. Speichere keine IP-Adressen, Browserdaten oder fehlgeschlagenen Anmeldungen.

## Sitzungen, Requests und E-Mail

- Die Anwendung läuft produktiv ausschließlich über HTTPS. Das Cookie `__Host-session` ist `Secure`, `HttpOnly`, `SameSite=Strict` und zwölf Stunden gültig.
- Die Datenbank speichert nur den SHA-256-Hash des zufälligen Sitzungswerts.
- Schreibende API-Anfragen verwenden `application/json`; vorhandene `Origin`-Header müssen exakt der konfigurierten HTTPS-Origin entsprechen.
- Behalte die Größenbegrenzung für Request-Bodies bei und validiere IDs, Rollen, Koordinaten und Textlängen.
- Passwörter werden mit `password_hash` gespeichert und mit `password_verify` geprüft.
- Die öffentliche Ersteinrichtung erfordert ein zufälliges `SETUP_TOKEN` mit mindestens 32 Zeichen.
- E-Mails werden über PHP `mail()` oder optional per authentifiziertem SMTP mit STARTTLS versendet. Zugangsdaten bleiben in Umgebungsvariablen oder der nicht versionierten `config.local.php`.
- Workflow-Benachrichtigungen werden erst nach erfolgreichem Speichern versendet. Empfänger ergeben sich serverseitig aus Organisation, Rolle und `user_units`; Fehler werden sichtbar gemeldet und ohne personenbezogene Inhalte protokolliert, dürfen den fachlichen Vorgang aber nicht zurückrollen.
- Direkte E-Mail-Links werden ausschließlich aus `APP_URL` und der internen Einsatz-ID gebildet. Eine Queue, persistenter Versandstatus oder automatische Wiederholung ist derzeit nicht vorgesehen.

## Einsätze und Berichte

- Ein Einsatz kann mehreren Einheiten zugeordnet sein. `(incident_id, unit_id)` ist eindeutig; jede beteiligte Einheit schreibt genau einen Bericht.
- Die Wehrleitung konsolidiert Einzelberichte in `incidents.consolidated_text`.
- Eine manuelle laufende Nummer ist je Einheit und lokalem Kalenderjahr eindeutig.
- Einheitsberichte enthalten Geschädigte und Schädiger mit optionalem Namen, Telefon und Adresse, die optionale Gesamteinsatzleitung sowie die Einsatzleitung der eigenen Einheit mit Dienstgrad und Name.
- Alarmierungszeit und Einsatzende sind erforderlich; Ausrücke- und Eintreffzeit dürfen bei abgebrochenen Einsätzen fehlen. Alle vorhandenen Zeitpunkte müssen chronologisch sein. Die Alarmierungszeit stammt aus dem Einsatz und ist im Bericht unveränderlich; die Dauer wird berechnet.
- Rollen, Dienstgrade, Einsatzarten, Gruppenbezeichnungen und Aufgliederungen liegen zentral in `constants.php`. Die Oberfläche lädt die fachlichen Optionen über `GET /api/options`; dupliziere sie nicht im Frontend.
- Die Aufgliederung entspricht dem Feuerwehrformular und besteht aus den Mehrfachauswahlgruppen `site`, `cause` und `technical`.
- Strukturierte meldende Person, detaillierte Einsatzortfelder, Kostenpflicht, Schadenssumme, Geräte, Löschmittel, Brandwache, Personal am Gerätehaus und Verwaltungsvermerke werden derzeit bewusst nicht erfasst.
- Berichte verwenden `author_draft`, `unit_review` und `wehr_review`. Die Initialstufe folgt der Erstellerrolle; Übergaben und kommentarpflichtige Rückgaben sind atomar, sperren den Datensatz und werden unveränderlich in `report_transitions` protokolliert.
- Frühere Prüfstufen behalten nach einer Rückgabe Leserechte. Bearbeiten darf nur der ursprüngliche Autor in `author_draft` beziehungsweise die zuständige Einheitsführung in `unit_review`; in `wehr_review` ist der Einheitsbericht unveränderlich.
- Eine Rückgabe durch die Wehrführung oder die nachträgliche Zuordnung einer weiteren Einheit leert `incidents.consolidated_at`, erhält den bisherigen Text aber als Arbeitsstand. Wiederholte oder veraltete Statusübergänge liefern HTTP 409.
- Die Wehrführung darf erst konsolidieren, wenn jede alarmierte Einheit einen Bericht in `wehr_review` hat. Führungskräfte sehen nach dem Absenden dessen Zeitpunkt, den aktuellen Status und einen ausdrücklichen Nur-Lese-Hinweis.
- `patient`, `caller`, Geschädigte, Schädiger und Berichtstexte sind sensible, mandantengebundene Einsatzdaten. Protokolliere sie nicht.
- Die erste Statistikansicht ist ausschließlich für Einheitsführungen verfügbar und aggregiert nur deren aktuell zugeordnete Einheit. Alarmierte Fahrzeuge stammen aus `incident_units.vehicles`, tatsächliche Beteiligung aus `report_crew` und zusätzliche Fahrzeuge aus `report_additional_vehicles`; Zeitkategorien werden mit den Grenzen aus `constants.php` in `Europe/Berlin` berechnet.

## Mitglieder, Fahrzeuge und Besatzung

- Mitglieder sind fachliche Personen und keine Anmeldebenutzer.
- Eine Person wird anhand ihrer DIVERA-ID organisationsweit einmal in `members` gespeichert und über `member_units` mehreren Einheiten zugeordnet.
- Qualifikationen sind einheitsspezifisch und werden aus `cluster.qualification` sowie `cluster.consumer[*].qualifications` synchronisiert.
- `vehicles` enthält den aktuellen einheitsspezifischen Fahrzeugstamm aus `cluster.vehicle`; `incident_units.vehicles` bleibt der unveränderliche Einsatz-Snapshot. Zusätzliche eigene Fahrzeuge eines Berichts liegen getrennt in `report_additional_vehicles`.
- Ein vollständiger Stammdatenabgleich setzt nicht mehr gelieferte Mitgliedszuordnungen inaktiv und ersetzt Qualifikations- sowie Fahrzeugzuordnungen der Einheit. Inaktive Mitglieder sind nicht neu als Besatzung auswählbar; historisch in `report_crew` verwendete Mitglieder bleiben unverändert erhalten.
- `report_crew` ist die maßgebliche strukturierte Besatzung. Ein Mitglied kommt pro Bericht höchstens einmal vor.
- Zulässige Funktionen sind `maschinist`, `einheitsfuehrer` und `besatzung`. Pro Fahrzeug gibt es höchstens einen Maschinisten und einen Einheitsführer; die Besatzung ist unbegrenzt.
- Nur eigene Fahrzeuge der berichtenden Einheit oder „Ohne Fahrzeug“ sind Besatzungsziele. Der Server erzwingt diese Regel.
- Bearbeitbare Berichte dürfen weitere Fahrzeuge aus dem aktuellen Stamm der eigenen Einheit aufnehmen. Später nicht mehr gelieferte Fahrzeuge bleiben historisch erhalten, sind aber nicht neu als Besatzungsziel auswählbar.
- Die Ressourcenansicht zeigt standardmäßig nur aktive Mitglieder. „Inaktive Mitglieder anzeigen“ steht hervorgehoben bei der Einheitsauswahl und wird wie der Einsatzstatusfilter benutzer- und rollenbezogen im Browser gespeichert; Mitglieder und eigene Fahrzeuge sind als standardmäßig geöffnete native `<details>` einklappbar.

## DIVERA 24/7

- Jede Einheit besitzt ihren eigenen DIVERA-Access-Key.
- DIVERA ist strikt nur lesend angebunden. Externe DIVERA-Aufrufe verwenden ausschließlich HTTP `GET`.
- Verwende niemals Endpunkte, die Alarme, Rückmeldungen, Status, Besatzungen, Dateien oder andere DIVERA-Daten erstellen, ändern, bestätigen, schließen oder löschen.
- Lies Einsätze über `GET /api/v2/alarms` und Mitglieder, Qualifikationen sowie Fahrzeugstammdaten über `GET /api/v2/pull/all`.
- Rufe `pull/vehicle-status` und DIVERA-Besatzungsendpunkte nicht auf.
- `cluster.vehicle` definiert die eigenen Fahrzeuge einer Einheit. Importiere Alarmfahrzeuge als eigene oder fremde Fahrzeuge; nur eigene Fahrzeuge sind Besatzungsziele.
- Lokale POST-Importe und Synchronisationen schreiben ausschließlich in MySQL.
- Echte Access-Keys werden nie protokolliert, an den Browser ausgegeben oder committed. Ausschließlich die offensichtlich unechten `demo-local-*`-Keys aus `demo/seed.sql` dürfen für den lokalen Fake versioniert werden.
- Ein DIVERA-Einsatz ist innerhalb einer Organisation über `divera_id` eindeutig. Wiederholter Import aktualisiert Einsatz und `incident_units`, statt sie zu duplizieren.
- Führungskräfte dürfen für ihre Einheiten Einsätze erkennen und einzeln importieren. Nur Einheits- und Wehrführung dürfen Access-Keys ändern oder Mitglieder, Qualifikationen und Fahrzeuge synchronisieren.
- „Alles synchronisieren“ ruft `pull/all` und `alarms` je höchstens einmal ab, ersetzt die Stammdaten und importiert beziehungsweise aktualisiert alle gelieferten Einsätze.

## Oberfläche und Barrierefreiheit

- Hauptnavigation: Einsätze, Mitglieder & Fahrzeuge, rollenabhängig Statistik, Verwaltung, System und DIVERA sowie Abmelden.
- „System“ ist nur für die Wehrleitung sichtbar und zeigt ausschließlich kuratierte, nicht geheime Zustandsdaten. Gib niemals DSN, Kennwörter, Einrichtungstoken oder DIVERA-Schlüssel aus.
- Die Oberfläche bleibt ohne Framework responsiv und mit Tastatur, Screenreader und Touch bedienbar.
- Interaktive Ziele sind mindestens 44 Pixel groß, Tastaturfokus ist sichtbar und dynamische Fehler sowie Statusänderungen werden angekündigt.
- Verwende die CSS-Custom-Properties in `public/styles.css` und wiederverwendbare Klassen statt Inline-Styles. Externe Stylesheets, Webfonts und CSS-Frameworks sind nicht vorgesehen.
- Nutze native Eingabetypen, Labels, Fieldsets und mobil bedienbare Kontrollfelder.
- Gruppiere optionale Berichtsbereiche mit nativen `<details>` und `<summary>`. Vorhandene Werte öffnen den jeweiligen Bereich beim Bearbeiten automatisch.
- Halte den Fokus in Bearbeitungsdialogen stabil und gib ihn beim Schließen an das auslösende Element zurück; nur sichtbare Fehlermeldungen erhalten gezielt den Fokus.
- Stelle Alarmierung, Ausrücken, Eintreffen, Einsatzende und Dauer in der Einzelbericht-Übersicht als getrennte semantische Zeilen dar.
- Drag-and-drop ist nur eine optionale Mausbedienung. Auswahlfelder bleiben die gleichwertige Tastatur- und Touchbedienung.
- Externe Kartenlinks verwenden OpenStreetMap, kündigen das neue Fenster an und setzen `rel="noopener"`.
- Hauptbereiche verwenden Query-basierte Deep Links über `view` beziehungsweise `incident`. Refresh und Browser-Historie stellen nur für die aktuelle Rolle erlaubte Ansichten wieder her; Hash-Fragmente bleiben Einladungs- und Wiederherstellungslinks vorbehalten.

## Datenschutz und Geheimnisse

- Gib Passwort-Hashes, Sitzungswerte, Reset-Tokens, Konfigurationsgeheimnisse und DIVERA-Schlüssel niemals über die API aus oder in Logs aus.
- Mandanten-, Rollen- und Einheitsgrenzen gelten auch für Systemübersichten, Exporte und neue Endpunkte.
- Erweitere die Erfassung personenbezogener Daten nur auf ausdrücklichen Auftrag und aktualisiere dafür Datenmodell und Security Review.

## Tests, CI und Deployment

- Verwende die vorhandenen PHP-, MySQL- und Shell-Checks ohne zusätzliches Testframework.
- Ergänze für nicht triviale Änderungen einen fokussierten Check in `test/smoke.sh`, insbesondere für Mandantentrennung, Rollen, Zustandsübergänge, Import-Idempotenz und externe Nur-Lese-Grenzen.
- Jeder neu hinzugefügte oder veränderte Testfall in `test/smoke.sh` erhält unmittelbar davor einen aussagekräftigen Kommentar, der das erwartete Verhalten beschreibt.
- `test/migrations.sh` prüft, dass spätere Migrationen in Dev-Volumes genau einmal ausgeführt werden.
- `test/fake-divera.php` verweist auf die offiziellen OpenAPI-Dokumente. Halte seine GET-Antworten damit konsistent und die `demo-local-*`-Fixtures deckungsgleich mit `demo/seed.sql`; `.github/workflows/divera-api-contract.yml` prüft Pfade und dokumentierte Felder monatlich, während undokumentierte Antwortdetails vor Änderungen manuell mit einer separaten DIVERA-Testeinheit geprüft werden müssen.
- GitHub Actions prüft PHP- und JavaScript-Syntax, Shellskripte, `schema.sql`, den HTTP-End-to-End-Fluss sowie Docker Compose gegen Apache/HTTPS und MySQL.
- Pull Requests erhalten keinen Zugriff auf Deployment-Secrets.
- Nach erfolgreichen Tests eines Pushs auf `main` lädt der Workflow nur `.htaccess`, `api.php`, `constants.php`, `support.php`, `public/index.html`, `public/app.js` und `public/styles.css` per SFTP mit geprüftem Host-Key hoch. Lokale Konfiguration, Schema und Migrationen werden nie automatisch deployt.
- Das produktive GitHub-Environment heißt `hiba`. Jedes weitere Ziel benötigt eigene Secrets, Schutzregeln und eine eigene Concurrency-Gruppe.

## Betrieb und Zurücksetzen

- Es gibt keine Lösch- oder Reset-Funktion in der Oberfläche.
- Ein vollständiger Reset löscht alle MySQL-Tabellen und importiert `schema.sql` neu. Dabei gehen alle Benutzer, Einsätze und Berichte endgültig verloren.
