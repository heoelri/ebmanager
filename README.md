# Einsatzberichte

Einsatzberichte ist eine mandantenfähige Webanwendung für Feuerwehren. Jede
alarmierte Einheit dokumentiert einen Einsatz aus ihrer Sicht mit Zeiten,
Einsatzart, Verlauf, Fahrzeugen und Besatzung. Einheitsführungen prüfen und
veröffentlichen diese Einzelberichte; die Wehrführung sieht alle Berichte und
erstellt daraus den konsolidierten Gesamtbericht.

Die Anwendung ist für klassischen Webspace ausgelegt: PHP und Apache liefern
eine responsive, tastatur- und touchbedienbare Oberfläche ohne
Frontend-Framework, PDO speichert die Daten in MySQL. DIVERA 24/7 wird pro
Einheit ausschließlich lesend angebunden.

## Open Source und Self-Hosting

Das Projekt wird offen entwickelt und ist dafür vorgesehen, von Feuerwehren
selbst betrieben zu werden. Der vollständige Quellcode und alle notwendigen
Dateien für Installation, Docker-Entwicklung und Deployment liegen in diesem
Repository. Es gibt keinen verpflichtenden zentralen Dienst und keine
Herstellerbindung.

Issues, Fehlerberichte, Verbesserungsvorschläge, fachliches Feedback und Pull
Requests sind ausdrücklich willkommen.

**Lizenzhinweis:** Derzeit ist noch keine formale Open-Source-Lizenz
hinterlegt. Bis eine Lizenzdatei ergänzt wurde, ist der Quellcode öffentlich
einsehbar, aber Nutzung, Veränderung und Weitergabe sind rechtlich noch nicht
allgemein freigegeben.

## Funktionsumfang

- mehrere Wehren als strikt getrennte Mandanten
- mehrere Einheiten, genau eine Einheit je Einheitsführung und Mehrfachzuordnung von Führungskräften
- Login-Historie mit den fünf neuesten erfolgreichen Anmeldungen in der Benutzerverwaltung
- ein Einheitsbericht pro Einsatz und Einheit
- manuelle laufende Nummern je Einheit und Jahr sowie strukturierte Angaben zu Geschädigten, Schädigern und Einsatzleitung
- übersichtliche Berichtsformulare mit unveränderlicher DIVERA-Einsatznummer, einklappbaren Bereichen und klar getrennten Einsatzleitungen
- dreistufiger Prüfworkflow mit unveränderlicher Historie, kommentierten Rückgaben und Konsolidierung
- strukturierte Fahrzeugbesatzung mit Drag-and-Drop
- Mitglieder, Qualifikationen und Fahrzeugstammdaten aus DIVERA
- vollständige DIVERA-Synchronisation aller Stammdaten und gelieferten Einsätze
- idempotenter, serverseitig verifizierter DIVERA-Einsatzimport
- Hinweis, Direktimport und letzter Importzeitpunkt für neue DIVERA-Einsätze in der Einsatzübersicht
- E-Mail-Benachrichtigungen an Einheits- und Wehrführungen bei neuen Einsätzen, erstellten Berichten und Freigaben
- lokale Docker-Umgebung, GitHub-Tests und SFTP-Deployment

## Rollen

| Rolle | Berechtigung |
|---|---|
| `fuehrungskraft` | Gehört mindestens einer Einheit an, schreibt und bearbeitet dort eigene Entwürfe, reicht sie ein und darf DIVERA-Einsätze erkennen und importieren. |
| `einheitsleitung` | Gehört exakt einer Einheit an, prüft und bearbeitet eingereichte Berichte, gibt sie kommentiert zurück oder sendet sie an die Wehrführung. |
| `wehrleitung` | Hat wehrweiten Zugriff ohne Einheitszuordnung, verwaltet Wehr, Einheiten und Benutzer, prüft Berichte, gibt sie kommentiert zurück und konsolidiert sie. |

Führungskräfte und Einheitsführungen erhalten Einheitenlisten, Einsatzzuordnungen, importierte Fahrzeug-Snapshots und PDF-Einsatzakten ausschließlich für ihre aktuell zugeordneten Einheiten. Bei gemeinsam alarmierten Einsätzen bleiben die Daten der übrigen Einheiten der Wehrführung vorbehalten.

Die Wehrführung kann einen Gesamtbericht erst speichern, wenn für jede dem Einsatz zugeordnete Einheit ein Einzelbericht im Status „Prüfung durch Wehrführung“ vorliegt. Eine Rückgabe oder eine später ergänzte Einheitenzuordnung macht eine bestehende Konsolidierung wieder ungültig. Führungskräfte sehen nach ihrer Abgabe den Zeitpunkt, den aktuellen Prüfstatus und den ausdrücklichen Hinweis, dass der Bericht für sie nur noch lesbar ist.

In der Einsatzansicht können alle Rollen ihre sichtbare Einsatzakte und jeden sichtbaren Einzelbericht als PDF herunterladen. Die Wehrführung kann zusätzlich einen abgeschlossenen Gesamtbericht exportieren. Die serverseitig erzeugten PDFs verwenden dieselben Leserechte wie die Webansicht und enthalten auf jeder Seite Exportzeitpunkt, Nutzername, Rolle und Seitenzahl. Dafür muss die PHP-Erweiterung `iconv` verfügbar sein; andernfalls antwortet der Export mit HTTP 503.

## Fachliche Anpassung

`constants.php` ist die zentrale Quelle für fachlich anpassbare Listen. Dort können `RANKS`, `INCIDENT_TYPES`, `CLASSIFICATIONS` und die zugehörigen `CLASSIFICATION_LABELS` geändert oder um eigene Einträge und Gruppen ergänzt werden. Dienstgrade ordnen ihre gespeicherte Abkürzung der vollständigen Bezeichnung zu, beispielsweise `'BM' => 'Brandmeister'`. Backend und Oberfläche lesen dieselben Werte; eine doppelte Anpassung im JavaScript ist nicht erforderlich.

Die Dienstgradliste entspricht § 14 und Anlage 1 der [VOFF Nordrhein-Westfalen](https://recht.nrw.de/lrgv/rechtsverordnung/27052017-verordnung-ueber-das-ehrenamt-den-freiwilligen-feuerwehren-im-land), geprüft am 23. August 2026. Gemeinde- und Stadtbrandinspektor werden in der Anwendung getrennt als `GBI` und `SBI` geführt. Beide Einsatzleitungsfelder dürfen mit „Keine Angabe“ leer bleiben.

Die Schlüssel in `CLASSIFICATIONS` und `CLASSIFICATION_LABELS` müssen
übereinstimmen und dauerhaft stabil bleiben, weil Berichte sie im
Klassifikations-JSON speichern. Entfernte Einsatzarten und Klassifikationen
bleiben in bestehenden Berichten lesbar, können beim nächsten Bearbeiten aber
nicht erneut ausgewählt werden. `ROLES` liegt ebenfalls in `constants.php`,
ist jedoch mit Datenbankschema und Berechtigungslogik gekoppelt und darf nicht
ohne entsprechende Code- und Schemaänderung angepasst werden.
Bereits gespeicherte Dienstgradwerte bleiben beim Bearbeiten auswählbar, auch wenn sie später aus `RANKS` entfernt werden.

## Dokumentation

- [Dokumentationsübersicht](docs/README.md)
- [Architektur](docs/ARCHITEKTUR.md)
- [Deployment auf Webspace](docs/WEBSPACE-DEPLOYMENT.md)
- [Datenmodell](DATENMODELL.md)
- [Security Review](SECURITY-REVIEW.md)
- [Changelog und Aktualisierungshinweise](CHANGELOG.md)

## Voraussetzungen

- PHP 8.2 oder neuer mit `pdo_mysql` und `iconv`
- MySQL 8.0 oder neuer
- Apache mit `mod_rewrite` und erlaubten `.htaccess`-Dateien
- HTTPS
- Für DIVERA: ausgehende HTTPS-Verbindungen und aktiviertes
  `allow_url_fopen`

Die Anwendung benötigt keinen Paketmanager, Build-Schritt oder dauerhaft
laufenden Prozess.

## Lokale Entwicklung mit Docker

Voraussetzung ist Docker mit Compose-Unterstützung.

```powershell
docker compose up --build
```

Danach ist die nur an `127.0.0.1` gebundene Anwendung unter
`https://localhost:8443` erreichbar. Das lokal erzeugte Zertifikat ist
selbstsigniert und muss im Browser einmalig bestätigt werden. Für die
Ersteinrichtung gilt ausschließlich lokal dieses Token:

Falls die Standardports belegt sind, können sie vor dem Start beispielsweise
mit `HTTP_PORT=18080` und `HTTPS_PORT=18443` überschrieben werden.

```text
0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
```

Die Anwendungsdateien sind schreibgeschützt in den Webcontainer eingebunden;
Änderungen an PHP, HTML und `.htaccess` sind ohne neuen Image-Build verfügbar.
Lokale Konfiguration und Repository-Metadaten werden nicht eingebunden. Beim
Start führt der einmalige Dienst `migrate` alle noch nicht vermerkten Dateien
aus `migrations/` vor dem Webcontainer aus. Frische Datenbanken werden
vollständig aus `schema.sql` initialisiert. Ein kompletter lokaler
Datenbankreset erfolgt mit:

```powershell
docker compose down --volumes
```

Aktualisierte Basis-Images werden mit `docker compose build --pull` geladen.

### Lokale Demofeuerwehr

Eine ausschließlich lokale Demofeuerwehr mit drei Einheiten, allen Rollen, Mitgliedern, Fahrzeugen und zahlreichen Einsätzen wird auf Wunsch in die laufende Compose-Datenbank importiert:

```powershell
$env:DIVERA_API_BASE_URL='http://divera:8090'
docker compose --profile demo up --build --detach --wait divera web
docker compose --profile demo run --rm demo-seed
```

Der Seed erkennt seine Organisation ausschließlich über das reservierte Konto `wehrleitung@demo.local`, setzt nur diese auf ihren definierten Demo-Stand zurück und verändert keine anderen Organisationen. Wiederholtes Ausführen erzeugt daher keine Duplikate. Die drei Demo-Einheiten sind mit offensichtlich unechten lokalen Access-Keys vorkonfiguriert. Das Demo-Profil startet `test/fake-divera.php`, sodass Stammdaten synchronisiert und zusätzliche Einzel- sowie Mehrfacheinheiten-Einsätze importiert werden können, ohne die echte DIVERA-API aufzurufen. Ein kompletter Neustart ist mit `docker compose --profile demo down --volumes` möglich.

Alle Demo-Konten verwenden ausschließlich lokal das Kennwort `Demo-Feuerwehr-2026!`:

| Rolle | E-Mail |
|---|---|
| Wehrführung | `wehrleitung@demo.local` |
| Einheitsführung Mitte | `leitung.mitte@demo.local` |
| Einheitsführung Nord | `leitung.nord@demo.local` |
| Einheitsführung Süd | `leitung.sued@demo.local` |
| Führungskraft Mitte | `fuehrung.mitte@demo.local` |
| Führungskraft Nord | `fuehrung.nord@demo.local` |
| Führungskraft Süd | `fuehrung.sued@demo.local` |
| Führungskraft Mitte und Nord | `fuehrung.springer@demo.local` |

Demodaten, Demo-Zugangsdaten und die reservierten `demo-local-*`-Keys dürfen nicht außerhalb der lokalen Docker-Compose-Umgebung verwendet werden. Der normale Aufruf `docker compose up` importiert keine Demodaten; Produktionsschema, Migrationen, CI und Deploymentpfade enthalten den Seed nicht.

Die Docker-Tests verwenden dieselben MySQL- und HTTP-Prüfungen wie CI:

```powershell
docker compose --profile test down --volumes
$env:DIVERA_API_BASE_URL='http://divera:8090'
docker compose --profile test up --build --detach --wait divera web
docker compose --profile test run --rm --no-deps test
docker compose --profile test down --volumes
```

## Installation auf Webspace

Die vollständige Erstinstallation mit Hosting-Voraussetzungen, Datenbank, Konfiguration, Dateistruktur, Einrichtung und Funktionsprüfung steht in [Deployment auf Webspace](docs/WEBSPACE-DEPLOYMENT.md).

## DIVERA

DIVERA wird je Einheit unter **DIVERA** mit dem Access-Key aus **Verwaltung → Einstellungen → Schnittstellen → API** verbunden. Die Anbindung liest ausschließlich Einsätze, Mitglieder, Qualifikationen und Fahrzeugstammdaten per HTTPS `GET`; lokale Importe verändern keine Daten in DIVERA. Führungskräfte können Einsätze ihrer Einheiten abrufen und importieren, während Konfiguration und Stammdatensynchronisation der Einheits- und Wehrführung vorbehalten bleiben.

Der lokale Fake in `test/fake-divera.php` verweist direkt auf die offiziellen OpenAPI-Dokumente. `.github/workflows/divera-api-contract.yml` vergleicht die verwendeten Endpunkte und dokumentierten Felder monatlich sowie bei manueller Auslösung mit [DIVERA Swagger](https://api.divera247.com/). Der nicht eindeutig dokumentierte Fahrzeugbezug eines Einsatzes muss bei Änderungen zusätzlich mit einer separaten DIVERA-Testeinheit geprüft werden.

## Benachrichtigungen

Einheitsführungen werden über neue Einsätze ihrer Einheiten und eingereichte Berichte informiert. Rückgaben informieren den ursprünglichen Autor beziehungsweise die zuständige Einheitsführung einschließlich Kommentar; Übergaben an die Wehrführung informieren alle Wehrführungen der Organisation. Die Nachrichten enthalten die Eckdaten und einen direkten, aus `APP_URL` gebildeten Link zum Einsatz. Versandfehler ändern den gespeicherten Vorgang nicht und werden in der Oberfläche als Warnung angezeigt.

## Aktualisierung

Vor jeder Aktualisierung müssen [CHANGELOG.md](CHANGELOG.md) und der Abschnitt [Bestehende Installation aktualisieren](docs/WEBSPACE-DEPLOYMENT.md#10-bestehende-installation-aktualisieren) gelesen werden. Nicht automatisierbare Migrationen und Konfigurationsschritte werden dort in Ausführungsreihenfolge dokumentiert.

## GitHub Actions

`.github/workflows/test.yml` prüft jeden Push und jeden Pull Request. Dabei
werden PHP- und JavaScript-Syntax, Shellskripte, das MySQL-Schema und der
Setup-/Anmeldeprozess geprüft. Ein unabhängiger zweiter Job baut außerdem das
Docker-Image und führt denselben End-to-End-Test gegen Apache, HTTPS und MySQL
aus.

Nach einem erfolgreichen Testlauf eines Pushs auf `main` lädt `.github/workflows/deploy.yml` ausschließlich `.htaccess`, `api.php`, `constants.php`, `support.php`, `public/index.html`, `public/app.js` und `public/styles.css` per **SFTP** hoch. `config.local.php`, Datenbankdateien und `schema.sql` werden niemals automatisch übertragen.

Die Einrichtung des Environments `hiba`, alle Secrets und die Trennung zukünftiger Ziele wie `devpreview` sind unter [Automatisches Deployment mit GitHub Actions einrichten](docs/WEBSPACE-DEPLOYMENT.md#9-automatisches-deployment-mit-github-actions-einrichten) dokumentiert.

## Datenbank zurücksetzen

Alle Tabellen in der Hosting-Verwaltung löschen und `schema.sql` erneut
importieren. Danach beginnt die Ersteinrichtung erneut. Dabei werden alle
Benutzer, Einsätze und Berichte endgültig gelöscht.
