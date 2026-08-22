# Einsatzberichte

Mandantenfähige Webanwendung für Einsatzberichte von Feuerwehr-Einheiten.

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

Danach ist die Anwendung unter `https://localhost:8443` erreichbar. Das lokal
erzeugte Zertifikat ist selbstsigniert und muss im Browser einmalig bestätigt
werden. Für die Ersteinrichtung gilt ausschließlich lokal dieses Token:

```text
0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
```

Der Projektordner ist in den Webcontainer eingebunden; Änderungen an PHP,
HTML und `.htaccess` sind ohne neuen Image-Build verfügbar. Ein kompletter
lokaler Datenbankreset erfolgt mit:

```powershell
docker compose down --volumes
```

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
3. `config.example.php` als `config.local.php` kopieren und DSN,
   Datenbankbenutzer und Passwort eintragen.
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

Alternativ können `DB_DSN`, `DB_USER`, `DB_PASSWORD` und `SETUP_TOKEN` als
Umgebungsvariablen gesetzt werden. `config.local.php` wird nicht committed und
ist über `.htaccess` gegen HTTP-Zugriff gesperrt.

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

Anwendungsdateien per FTP oder SFTP ersetzen. `config.local.php` dabei nicht
überschreiben. Schemaänderungen werden als gesondertes SQL-Migrationsskript
bereitgestellt und müssen vor dem neuen Anwendungscode importiert werden.

## GitHub Actions

`.github/workflows/test.yml` prüft jeden Push und jeden Pull Request. Dabei
werden PHP-Syntax, Shellskripte, das MySQL-Schema und der
Setup-/Anmeldeprozess geprüft.

Nach einem erfolgreichen Testlauf eines Pushs auf `main` lädt
`.github/workflows/deploy.yml` ausschließlich `.htaccess`, `api.php` und
`public/index.html` per **FTPS** hoch. `config.local.php`, Datenbankdateien und
`schema.sql` werden niemals automatisch übertragen.

Im GitHub-Environment `production` werden diese Secrets benötigt:

| Secret | Inhalt |
|---|---|
| `FTP_SERVER` | FTPS-Hostname, optional mit Port |
| `FTP_USERNAME` | FTP-Benutzer |
| `FTP_PASSWORD` | FTP-Passwort |
| `FTP_PATH` | Optionales Zielverzeichnis relativ zum FTP-Stamm |

Der Server muss explizites FTPS unterstützen. Unverschlüsseltes FTP wird
durch `curl --ssl-reqd` abgelehnt.

## Datenbank zurücksetzen

Alle Tabellen in der Hosting-Verwaltung löschen und `schema.sql` erneut
importieren. Danach beginnt die Ersteinrichtung erneut. Dabei werden alle
Benutzer, Einsätze und Berichte endgültig gelöscht.
