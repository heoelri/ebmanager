# Deployment auf Webspace

Diese Anleitung ist die maßgebliche Betriebsdokumentation für die Erstinstallation und spätere Aktualisierung auf klassischem PHP-/Apache-Webspace mit MySQL. Projektüberblick, Architektur und Datenmodell werden nicht wiederholt, sondern sind in [README](../README.md), [Architektur](ARCHITEKTUR.md) und [Datenmodell](../DATENMODELL.md) beschrieben.

## 1. Voraussetzungen prüfen

Der Webhoster muss folgende Funktionen bereitstellen:

- PHP 8.2 oder neuer mit `pdo_mysql`
- MySQL 8.0 oder neuer
- Apache mit `mod_rewrite` und erlaubten `.htaccess`-Dateien
- eine Domain oder Subdomain mit dauerhaft aktiviertem HTTPS
- ausgehende HTTPS-Verbindungen und `allow_url_fopen` für DIVERA
- E-Mail-Versand über PHP `mail()` für die Passwort-Wiederherstellung
- SFTP-Zugang zum Webspace
- eine Datenbankverwaltung wie phpMyAdmin zum Import von SQL-Dateien

Die Anwendung benötigt keinen Paketmanager, Build-Schritt, Cronjob oder dauerhaft laufenden Hintergrundprozess.

## 2. Domain und Zielverzeichnis vorbereiten

1. Eine Domain oder Subdomain beim Hoster anlegen und entscheiden, ob die Anwendung direkt im Dokumentenstamm oder in einem Unterverzeichnis wie `ebmanager` betrieben wird.
2. Das Dokumentenstammverzeichnis beziehungsweise das vollständige Zielverzeichnis ermitteln.
3. HTTPS aktivieren und prüfen, dass die Domain ohne Zertifikatswarnung erreichbar ist.
4. Sicherstellen, dass versteckte Dateien wie `.htaccess` hochgeladen werden können.

Beide Varianten werden unterstützt:

| Variante | Öffentliche Adresse | Zielverzeichnis |
|---|---|---|
| Dokumentenstamm | `https://berichte.example.org/` | Dokumentenstamm der Domain |
| Unterverzeichnis | `https://www.example.org/ebmanager/` | Unterverzeichnis `ebmanager` im Dokumentenstamm |

Das Unterverzeichnis benötigt keine besondere `RewriteBase`-Konfiguration. Die Anwendung muss über die Verzeichnisadresse mit abschließendem `/` geöffnet werden, nicht direkt über `public/index.html`.

## 3. MySQL-Datenbank anlegen

1. Eine leere MySQL-Datenbank mit `utf8mb4` anlegen.
2. Einen eigenen Datenbankbenutzer für die Anwendung anlegen.
3. Hostname, Port, Datenbankname, Benutzername und Passwort notieren.
4. `schema.sql` mit einem Administrationskonto über phpMyAdmin oder die Datenbankverwaltung importieren.
5. Prüfen, dass der Import ohne Fehler abgeschlossen wurde.
6. Dem Laufzeitbenutzer anschließend nur `SELECT`, `INSERT`, `UPDATE` und `DELETE` auf der Anwendungsdatenbank gewähren.

Bei einer Erstinstallation ist nur `schema.sql` erforderlich. Die Dateien unter `migrations/` sind ausschließlich für bestehende Installationen bestimmt.

## 4. Einrichtungstoken erzeugen

Das einmalige Einrichtungstoken muss zufällig sein und mindestens 32 Zeichen enthalten. Mit lokal installiertem PHP kann ein geeigneter Wert erzeugt werden:

```powershell
php -r "echo bin2hex(random_bytes(32));"
```

Den ausgegebenen Wert wie ein Passwort behandeln. Er wird einmal bei der Ersteinrichtung der ersten Wehrleitung benötigt.

## 5. Konfiguration erstellen

1. `config.example.php` als `config.local.php` kopieren.
2. Alle Beispielwerte ersetzen.
3. `config.local.php` niemals committen oder öffentlich weitergeben.

Beispiel:

```php
<?php

return [
    'dsn' => 'mysql:host=mysql.example.net;port=3306;dbname=einsatzberichte;charset=utf8mb4',
    'user' => 'einsatzberichte',
    'password' => 'zufaelliges-datenbankpasswort',
    'setup_token' => 'zufaelliges-einrichtungstoken',
    'app_url' => 'https://berichte.example.org',
    'mail_from' => 'einsatzberichte@example.org',
];
```

`app_url` muss die vollständige öffentliche HTTPS-Adresse der Anwendung ohne abschließenden `/` enthalten, beispielsweise `https://berichte.example.org` für den Dokumentenstamm oder `https://www.example.org/ebmanager` für ein Unterverzeichnis. `mail_from` muss eine beim Hoster zulässige Absenderadresse sein. Alternativ können `DB_DSN`, `DB_USER`, `DB_PASSWORD`, `SETUP_TOKEN`, `APP_URL` und `MAIL_FROM` als Umgebungsvariablen gesetzt werden.

## 6. Dateien hochladen

Folgende Struktur muss im gewählten Zielverzeichnis entstehen:

```text
.htaccess
api.php
config.local.php
public/
  index.html
```

1. `.htaccess`, `api.php`, `config.local.php` und `public/index.html` per SFTP hochladen.
2. Prüfen, dass `.htaccess` tatsächlich vorhanden ist; einige Dateiübertragungsprogramme blenden versteckte Dateien aus.
3. Für Verzeichnisse Berechtigungen wie `755` und für öffentliche Dateien `644` verwenden, sofern der Hoster keine anderen Vorgaben macht.
4. `config.local.php` so restriktiv wie vom Hoster unterstützt auf `600` oder `640` setzen.
5. `schema.sql`, `migrations/`, Tests, Dokumentation und Repository-Metadaten nicht in das öffentliche Zielverzeichnis hochladen.

Unverschlüsseltes FTP darf nicht verwendet werden, weil dabei Zugangsdaten und Anwendungsdateien mitgelesen werden können.

### Upload per SFTP mit Passwort

Ein privater SSH-Schlüssel ist nicht erforderlich, wenn der Hoster ausschließlich Passwortauthentifizierung anbietet. Benötigt werden SFTP-Hostname, Port, Benutzername, Passwort und das Zielverzeichnis.

1. In WinSCP, FileZilla oder einem vergleichbaren Client das Protokoll **SFTP** auswählen; nicht FTP oder FTPS.
2. Hostname und Port des Hosters eintragen, üblicherweise Port `22`, und die Anmeldung mit Benutzername und Passwort wählen.
3. Beim ersten Verbindungsaufbau den angezeigten SSH-Host-Key-Fingerabdruck mit einer vertrauenswürdigen Angabe des Hosters vergleichen. Nur bei Übereinstimmung speichern und fortfahren.
4. Zum Dokumentenstamm wechseln oder dort für die Unterverzeichnisvariante den Ordner `ebmanager` anlegen und öffnen.
5. Die oben gezeigte Dateistruktur vollständig in dieses Zielverzeichnis übertragen.

Mit dem vorhandenen OpenSSH-Client ist derselbe interaktive Upload möglich:

```text
sftp -P 22 benutzer@sftp.example.org
sftp> cd pfad/zum/dokumentenstamm
sftp> mkdir ebmanager
sftp> cd ebmanager
sftp> put .htaccess
sftp> put api.php
sftp> put config.local.php
sftp> mkdir public
sftp> put public/index.html public/index.html
sftp> exit
```

Für eine Installation direkt im Dokumentenstamm entfallen `mkdir ebmanager` und `cd ebmanager`. Eine Ausgabe wie `unsupported KEX method` oder eine reine SSH-Bannerzeile ist kein gültiger Host-Key. Der Schlüssel muss als vollständiger `known_hosts`-Eintrag im Format `hostname schlüsseltyp schlüssel` vorliegen und sein Fingerabdruck muss vor der Verwendung geprüft werden.

## 7. Installation prüfen

1. Die öffentliche HTTPS-Adresse im Browser öffnen.
2. Wenn die Datenbank nicht erreichbar, falsch konfiguriert oder unvollständig ist, zeigt die Anwendung eine konkrete Hinweisseite. DSN, Zugangsdaten, Erreichbarkeit, `schema.sql` und ausstehende Migrationen entsprechend prüfen.
3. Bei korrekter Datenbank erscheint die Ersteinrichtung.
4. Wehr, erste Einheit, Name, E-Mail-Adresse, sicheres Passwort und das Einrichtungstoken eingeben.
5. Nach Abschluss mit dem neuen Konto anmelden.

Die Ersteinrichtung ist nach dem ersten Benutzer dauerhaft geschlossen.

## 8. Funktionen nach der Installation prüfen

1. Anmelden und wieder abmelden.
2. In der Verwaltung eine Testeinheit oder einen Testbenutzer anlegen, falls dies fachlich sinnvoll ist.
3. Einen manuellen Einsatz und einen Bericht anlegen.
4. Über „Passwort vergessen“ prüfen, dass der Webhoster E-Mails mit dem korrekten HTTPS-Link versendet.
5. Optional pro Einheit einen DIVERA-Access-Key hinterlegen und einen lesenden Abruf durchführen.
6. Serverprotokolle auf PHP-, Apache- oder Mailfehler prüfen, ohne Zugangsdaten oder DIVERA-Schlüssel weiterzugeben.

## 9. Automatisches Deployment mit GitHub Actions einrichten

Das Repository deployt nach erfolgreichen Tests eines Pushs auf `main` den exakt getesteten Commit. Der Workflow verwendet das GitHub-Environment `hiba`.

Der derzeitige GitHub-Workflow unterstützt explizites FTPS. Bietet der Webspace ausschließlich SFTP an, müssen bis zu einer entsprechenden Workflow-Umstellung die Schritte unter „Upload per SFTP mit Passwort“ verwendet werden.

1. Im GitHub-Repository unter **Settings → Environments** das Environment `hiba` anlegen.
2. Gewünschte Schutzregeln wie erforderliche Freigaben konfigurieren.
3. Folgende Environment-Secrets hinterlegen:

| Secret | Inhalt |
|---|---|
| `SFTP_SERVER` | SFTP-Hostname ohne Protokollpräfix und ohne Port |
| `SFTP_PORT` | Optionaler SSH-Port, Standard `22` |
| `SFTP_USERNAME` | SFTP-Benutzer |
| `SFTP_PRIVATE_KEY` | Privater SSH-Schlüssel im OpenSSH-Format, bevorzugte Anmeldung |
| `SFTP_PASSWORD` | SFTP-Passwort, nur falls kein Schlüssel hinterlegt ist |
| `SFTP_KNOWN_HOSTS` | Pflicht: `known_hosts`-Zeilen des Servers, ermittelt mit `ssh-keyscan -p <Port> <Host>` |
| `SFTP_PATH` | Optionales, bereits vorhandenes Zielverzeichnis relativ zum SFTP-Stamm |

4. Prüfen, dass der Server SFTP über SSH anbietet und der ermittelte Host-Key mit der Angabe des Hosters übereinstimmt.
5. Einen Push auf `main` durchführen und zuerst den Workflow `Tests`, danach den Workflow `Deployment` beobachten.

Der Workflow lädt ausschließlich `.htaccess`, `api.php` und `public/index.html` hoch. `config.local.php`, Datenbankzugangsdaten, `schema.sql` und Migrationen werden absichtlich nicht automatisiert übertragen.

Weitere Ziele wie `devpreview` benötigen ein eigenes GitHub-Environment, eigene Secrets, eigene Schutzregeln und eine eigene Concurrency-Gruppe. Zugangsdaten aus `hiba` dürfen nicht wiederverwendet werden.

## 10. Bestehende Installation aktualisieren

1. Datenbank und `config.local.php` sichern.
2. [CHANGELOG.md](../CHANGELOG.md) vollständig lesen.
3. Alle Einträge unter `Breaking Changes` und `Manuelle Aktualisierung` in der angegebenen Reihenfolge berücksichtigen.
4. Neue SQL-Dateien aus `migrations/` in numerischer Reihenfolge vor dem neuen Anwendungscode über die Datenbankverwaltung importieren.
5. Neue Konfigurationswerte in `config.local.php` ergänzen, ohne bestehende Werte zu überschreiben.
6. Erst danach den neuen Anwendungscode manuell hochladen oder den für `main` vorgesehenen GitHub-Workflow auslösen.
7. Anmeldung, Passwort-Wiederherstellung und die im Changelog genannten Funktionen prüfen.

Wenn das automatische Deployment verwendet wird, müssen erforderliche Migrationen vor dem Merge beziehungsweise Push nach `main` eingespielt werden. Der SFTP-Workflow kann SQL-Migrationen nicht sicher automatisieren, weil er absichtlich keine Datenbankzugangsdaten besitzt und Shared-Hosting-Anbieter unterschiedliche Verwaltungswege bereitstellen.

## 11. Rollback

1. Vor jeder Aktualisierung eine Datenbanksicherung und eine Kopie der bisherigen Anwendungsdateien erstellen.
2. Bei einem reinen Anwendungsfehler die vorherigen Versionen von `.htaccess`, `api.php` und `public/index.html` wiederherstellen.
3. Bei einer inkompatiblen Datenbankänderung die zum Release dokumentierten Rollback-Schritte verwenden oder die vorherige Datenbanksicherung einspielen.
4. Nach einem Rollback Anmeldung und zentrale Funktionen erneut prüfen.

Migrationen dürfen nicht auf Verdacht rückgängig gemacht werden. Maßgeblich sind die releasebezogenen Hinweise im Changelog.

## 12. Fehlerbehebung

| Anzeige oder Fehler | Prüfung |
|---|---|
| „Datenbankzugang ist nicht konfiguriert“ | `config.local.php`, `DB_DSN` und Speicherort der Datei prüfen |
| „Datenbankverbindung fehlgeschlagen“ | Hostname, Port, Datenbankname, Benutzer, Passwort und externe MySQL-Freigabe prüfen |
| „Datenbankschema ist unvollständig“ | `schema.sql` beziehungsweise ausstehende Dateien aus `migrations/` importieren |
| API-Aufrufe liefern 404 | `.htaccess`, `mod_rewrite` und `AllowOverride` beim Hoster prüfen |
| Unterverzeichnis öffnet, API-Aufrufe gehen aber an die Domainwurzel | Aktuelle Version von `public/index.html` hochladen und die Anwendung über die Verzeichnisadresse mit abschließendem `/` öffnen |
| HTTPS-Weiterleitung funktioniert nicht | Zertifikat, Domainzuordnung und Apache-Unterstützung prüfen |
| Passwort-E-Mail kommt nicht an | `app_url`, `mail_from`, PHP `mail()`, Spamordner und Mailprotokoll des Hosters prüfen |
| GitHub-Deployment findet Secrets nicht | Environment-Name `hiba`, Secret-Namen und Environment-Freigabe prüfen |
| SFTP-Deployment schlägt fehl | Hostname, `SFTP_PORT`, Benutzer, Schlüssel oder Passwort, aktuellen `SFTP_KNOWN_HOSTS`-Eintrag und ein vorhandenes `SFTP_PATH` prüfen |

Zugangsdaten, Einrichtungstoken, Sitzungstoken und DIVERA-Schlüssel dürfen bei der Fehlersuche nicht in Issues oder Protokollauszüge kopiert werden.

## Weiterführende Dokumentation

- [Architektur](ARCHITEKTUR.md)
- [Datenmodell](../DATENMODELL.md)
- [Security Review](../SECURITY-REVIEW.md)
- [Changelog](../CHANGELOG.md)
