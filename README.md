# Einsatzberichte

Einsatzberichte ist eine mandantenfähige Webanwendung für Feuerwehren. Jede
alarmierte Einheit dokumentiert einen Einsatz aus ihrer Sicht mit Zeiten,
Einsatzart, Verlauf, Fahrzeugen und Besatzung. Einheitsführungen prüfen und
veröffentlichen diese Einzelberichte; die Wehrführung sieht alle Berichte und
erstellt daraus den konsolidierten Gesamtbericht.

Die Anwendung ist für klassischen Webspace ausgelegt: PHP und Apache liefern
eine responsive Oberfläche ohne Frontend-Framework, PDO speichert die Daten in
MySQL. DIVERA 24/7 wird pro Einheit ausschließlich lesend angebunden.

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
- mehrere Einheiten und Mehrfachzuordnung von Führungskräften
- ein Einheitsbericht pro Einsatz und Einheit
- Entwurf, Bearbeitung, Freigabe und Konsolidierung
- strukturierte Fahrzeugbesatzung mit Drag-and-Drop
- Mitglieder und Qualifikationen aus DIVERA
- idempotenter, serverseitig verifizierter DIVERA-Einsatzimport
- lokale Docker-Umgebung, GitHub-Tests und SFTP-Deployment

## Rollen

| Rolle | Berechtigung |
|---|---|
| `fuehrungskraft` | Schreibt Berichte für ihre zugeordneten Einheiten und sieht eigene Berichte. |
| `einheitsleitung` | Sieht und bearbeitet Entwürfe ihrer Einheiten und gibt sie frei. |
| `wehrleitung` | Verwaltet Wehr, Einheiten und Benutzer, sieht alle Berichte und konsolidiert sie. |

## Dokumentation

- [Dokumentationsübersicht](docs/README.md)
- [Architektur](docs/ARCHITEKTUR.md)
- [Deployment auf Webspace](docs/WEBSPACE-DEPLOYMENT.md)
- [Datenmodell](DATENMODELL.md)
- [Security Review](SECURITY-REVIEW.md)
- [Changelog und Aktualisierungshinweise](CHANGELOG.md)

## Voraussetzungen

- PHP 8.2 oder neuer mit `pdo_mysql`
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

```text
0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
```

Die Anwendungsdateien sind schreibgeschützt in den Webcontainer eingebunden;
Änderungen an PHP, HTML und `.htaccess` sind ohne neuen Image-Build verfügbar.
Lokale Konfiguration und Repository-Metadaten werden nicht eingebunden. Ein
kompletter lokaler Datenbankreset erfolgt mit:

```powershell
docker compose down --volumes
```

Aktualisierte Basis-Images werden mit `docker compose build --pull` geladen.

Die Docker-Tests verwenden dieselben MySQL- und HTTP-Prüfungen wie CI:

```powershell
docker compose --profile test down --volumes
docker compose --profile test up --build --abort-on-container-exit --exit-code-from test
docker compose --profile test down --volumes
```

## Installation auf Webspace

Die vollständige Erstinstallation mit Hosting-Voraussetzungen, Datenbank, Konfiguration, Dateistruktur, Einrichtung und Funktionsprüfung steht in [Deployment auf Webspace](docs/WEBSPACE-DEPLOYMENT.md).

## DIVERA

DIVERA wird je Einheit unter **DIVERA** mit dem Access-Key aus
**Verwaltung → Einstellungen → Schnittstellen → API** verbunden. Die
Anbindung liest ausschließlich Einsätze, Mitglieder, Qualifikationen und
Fahrzeugstammdaten per HTTPS `GET`; lokale Importe verändern keine Daten in
DIVERA.

## Aktualisierung

Vor jeder Aktualisierung müssen [CHANGELOG.md](CHANGELOG.md) und der Abschnitt [Bestehende Installation aktualisieren](docs/WEBSPACE-DEPLOYMENT.md#10-bestehende-installation-aktualisieren) gelesen werden. Nicht automatisierbare Migrationen und Konfigurationsschritte werden dort in Ausführungsreihenfolge dokumentiert.

## GitHub Actions

`.github/workflows/test.yml` prüft jeden Push und jeden Pull Request. Dabei
werden PHP-Syntax, Shellskripte, das MySQL-Schema und der
Setup-/Anmeldeprozess geprüft. Ein unabhängiger zweiter Job baut außerdem das
Docker-Image und führt denselben End-to-End-Test gegen Apache, HTTPS und MySQL
aus.

Nach einem erfolgreichen Testlauf eines Pushs auf `main` lädt
`.github/workflows/deploy.yml` ausschließlich `.htaccess`, `api.php` und
`public/index.html` per **SFTP** hoch. `config.local.php`, Datenbankdateien und
`schema.sql` werden niemals automatisch übertragen.

Die Einrichtung des Environments `hiba`, alle Secrets und die Trennung zukünftiger Ziele wie `devpreview` sind unter [Automatisches Deployment mit GitHub Actions einrichten](docs/WEBSPACE-DEPLOYMENT.md#9-automatisches-deployment-mit-github-actions-einrichten) dokumentiert.

## Datenbank zurücksetzen

Alle Tabellen in der Hosting-Verwaltung löschen und `schema.sql` erneut
importieren. Danach beginnt die Ersteinrichtung erneut. Dabei werden alle
Benutzer, Einsätze und Berichte endgültig gelöscht.
