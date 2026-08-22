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
- lokale Docker-Umgebung, GitHub-Tests und FTPS-Deployment

## Rollen

| Rolle | Berechtigung |
|---|---|
| `fuehrungskraft` | Schreibt Berichte für ihre zugeordneten Einheiten und sieht eigene Berichte. |
| `einheitsleitung` | Sieht und bearbeitet Entwürfe ihrer Einheiten und gibt sie frei. |
| `wehrleitung` | Verwaltet Wehr, Einheiten und Benutzer, sieht alle Berichte und konsolidiert sie. |

## Dokumentation

- [Dokumentationsübersicht](docs/README.md)
- [Architektur](docs/ARCHITEKTUR.md)
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

1. Eine leere MySQL-Datenbank und einen Datenbankbenutzer anlegen.
2. `schema.sql` einmalig über phpMyAdmin oder die Verwaltungsoberfläche des
   Hosters importieren.
3. `config.example.php` als `config.local.php` kopieren und DSN, Datenbankbenutzer, Passwort, öffentliche HTTPS-URL `app_url` und Absenderadresse `mail_from` eintragen. Der Webhoster muss den E-Mail-Versand über die PHP-Funktion `mail()` unterstützen.
4. Ein Einrichtungstoken mit mindestens 32 zufälligen Zeichen erzeugen, zum
   Beispiel lokal mit:

   ```powershell
   php -r "echo bin2hex(random_bytes(32));"
   ```

5. Das Token in `config.local.php` als `setup_token` eintragen.
6. `.htaccess`, `api.php`, `config.local.php` und den Ordner `public` per FTP
   oder SFTP in das Stammverzeichnis der Domain hochladen.
7. Die HTTPS-Adresse öffnen und bei der einmaligen Ersteinrichtung das Token
   eingeben.

Alternativ können `DB_DSN`, `DB_USER`, `DB_PASSWORD`, `SETUP_TOKEN`, `APP_URL` und `MAIL_FROM` als Umgebungsvariablen gesetzt werden. `config.local.php` wird nicht committed und ist über `.htaccess` gegen HTTP-Zugriff gesperrt.

Beispiel-DSN:

```text
mysql:host=mysql.example.net;port=3306;dbname=einsatzberichte;charset=utf8mb4
```

Nach dem Schemaimport benötigt der Laufzeitbenutzer nur `SELECT`, `INSERT`,
`UPDATE` und `DELETE` auf der Anwendungsdatenbank.

## DIVERA

DIVERA wird je Einheit unter **DIVERA** mit dem Access-Key aus
**Verwaltung → Einstellungen → Schnittstellen → API** verbunden. Die
Anbindung liest ausschließlich Einsätze, Mitglieder, Qualifikationen und
Fahrzeugstammdaten per HTTPS `GET`; lokale Importe verändern keine Daten in
DIVERA.

## Aktualisierung

1. Datenbank und `config.local.php` sichern.
2. `CHANGELOG.md` vollständig lesen und alle Einträge unter `Breaking Changes` sowie `Manuelle Aktualisierung` befolgen.
3. Neue SQL-Dateien aus `migrations/` in numerischer Reihenfolge vor dem neuen Anwendungscode über die Datenbankverwaltung des Hosters importieren.
4. Neue Konfigurationswerte in `config.local.php` ergänzen, ohne bestehende Werte zu überschreiben.
5. Anwendungsdateien per FTP oder SFTP ersetzen und anschließend Anmeldung sowie zentrale Funktionen prüfen.

Für die Passwort-Wiederherstellung muss bei bestehenden Installationen vor dem Anwendungscode einmal `migrations/001-password-resets.sql` importiert werden. Das generische FTPS-Deployment automatisiert Datenbankmigrationen absichtlich nicht, weil es keine Datenbankzugangsdaten erhält und Shared-Hosting-Anbieter unterschiedliche Verwaltungswege bereitstellen.

## GitHub Actions

`.github/workflows/test.yml` prüft jeden Push und jeden Pull Request. Dabei
werden PHP-Syntax, Shellskripte, das MySQL-Schema und der
Setup-/Anmeldeprozess geprüft. Ein unabhängiger zweiter Job baut außerdem das
Docker-Image und führt denselben End-to-End-Test gegen Apache, HTTPS und MySQL
aus.

Nach einem erfolgreichen Testlauf eines Pushs auf `main` lädt
`.github/workflows/deploy.yml` ausschließlich `.htaccess`, `api.php` und
`public/index.html` per **FTPS** hoch. `config.local.php`, Datenbankdateien und
`schema.sql` werden niemals automatisch übertragen.

Im GitHub-Environment `hiba` werden diese Secrets benötigt:

| Secret | Inhalt |
|---|---|
| `FTP_SERVER` | FTPS-Hostname, optional mit Port |
| `FTP_USERNAME` | FTP-Benutzer |
| `FTP_PASSWORD` | FTP-Passwort |
| `FTP_PATH` | Optionales Zielverzeichnis relativ zum FTP-Stamm |

Der Server muss explizites FTPS unterstützen. Unverschlüsseltes FTP wird
durch `curl --ssl-reqd` abgelehnt.

Weitere Ziele wie `devpreview` erhalten ein eigenes GitHub-Environment mit eigenen Secrets, Schutzregeln und einer eigenen Concurrency-Gruppe. Produktionszugangsdaten aus `hiba` werden nicht wiederverwendet.

## Datenbank zurücksetzen

Alle Tabellen in der Hosting-Verwaltung löschen und `schema.sql` erneut
importieren. Danach beginnt die Ersteinrichtung erneut. Dabei werden alle
Benutzer, Einsätze und Berichte endgültig gelöscht.
