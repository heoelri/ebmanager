# Changelog

Alle relevanten Änderungen werden ab diesem Stand in dieser Datei dokumentiert. Nicht rückwärtskompatible Änderungen stehen zusätzlich unter `Breaking Changes` und enthalten die notwendigen Aktualisierungsschritte.

## Unreleased

### Added

- Optionaler SMTP-Versand mit Authentifizierung und STARTTLS unterstützt Hoster, bei denen PHP `mail()` nicht verfügbar oder unzuverlässig ist.
- Neue Benutzer erhalten eine Einladungs-E-Mail und aktivieren ihr Konto über einen einmaligen Link, statt ein von der Wehrführung vergebenes Startpasswort zu verwenden.
- Benutzer können über einen per E-Mail versendeten Einmallink ein vergessenes Passwort zurücksetzen.
- Passwort-Reset-Tokens werden nur als SHA-256-Hash gespeichert, laufen nach 30 Minuten ab und widerrufen nach Verwendung alle Sitzungen.
- Die Startseite prüft Datenbankkonfiguration, Verbindung und Schema und zeigt bei Problemen eine konkrete Betriebsseite statt eines allgemeinen internen Fehlers.
- Eine zentrale Schritt-für-Schritt-Anleitung dokumentiert Erstinstallation, manuelles und automatisches Deployment, Updates, Rollback und Fehlerbehebung auf Webspace.

### Changed

- Die Webspace-Anleitung beschreibt die Konfiguration und betrieblichen Voraussetzungen des E-Mail-Versands über PHP `mail()`.
- Die Anwendung kann unverändert im Dokumentenstamm oder in einem Unterverzeichnis betrieben werden; Frontend und Backend leiten den jeweiligen Basispfad automatisch aus der aufgerufenen Adresse ab.
- Die Webspace-Anleitung dokumentiert den manuellen SFTP-Upload mit Passwort, die verpflichtende Host-Key-Prüfung und die Abgrenzung zum derzeit FTPS-basierten GitHub-Workflow.
- Origin-Prüfung und Sitzungscookie richten sich vorübergehend nach dem tatsächlich verwendeten HTTP- oder HTTPS-Schema; HTTPS verwendet weiterhin ein `Secure`-Cookie mit `__Host-`-Präfix.
- Der Docker-Smoke-Test prüft Passwort-Reset, Tokenverbrauch, Sitzungswiderruf und anschließende Anmeldung.
- Datenbankverbindungen initialisieren UTF-8 ohne die unter PHP 8.5 veraltete PDO-Konstante, damit API-Statuscodes nicht durch Deprecation-Ausgaben verfälscht werden.
- Interne MySQL-Testverbindungen verwenden explizit UTF-8 und verzichten im isolierten Docker-Netz auf die selbstsignierte MySQL-TLS-Verbindung.
- Das Smoke-Testskript schaltet MySQL-TLS client-kompatibel mit `--ssl-mode=DISABLED` oder `--skip-ssl` ab, damit der CI-Job sowohl mit MySQL- als auch MariaDB-Clients stabil läuft.
- Das produktive GitHub-Deployment verwendet das Environment `hiba` und eine eigene Concurrency-Gruppe; zukünftige Ziele wie `devpreview` bleiben mit separaten Secrets und Schutzregeln isoliert.
- Das automatische Deployment lädt die Anwendungsdateien per SFTP statt per FTPS hoch, weil der Zielwebspace keinen FTP-Zugang mehr anbietet. Der Host-Key wird dabei verpflichtend gegen `SFTP_KNOWN_HOSTS` geprüft.
- Die Beispielkonfiguration verwendet den einheitlichen Datenbanknamen `einsatzberichte`, fehlende DSN-Konfiguration liefert auf allen API-Routen HTTP 503 und gespeicherte Benutzeradressen werden syntaktisch validiert.

### Breaking Changes

- Bestehende Installationen müssen vor dem neuen Anwendungscode einmal `migrations/001-password-resets.sql` importieren.
- `config.local.php` benötigt `app_url` mit der öffentlichen HTTPS-Adresse und `mail_from` mit einer gültigen Absenderadresse; alternativ werden `APP_URL` und `MAIL_FROM` als Umgebungsvariablen gesetzt.
- Das GitHub-Environment `hiba` benötigt die neuen Secrets `SFTP_SERVER`, `SFTP_USERNAME`, `SFTP_KNOWN_HOSTS` sowie `SFTP_PRIVATE_KEY` oder `SFTP_PASSWORD`; optional `SFTP_PORT` und `SFTP_PATH`. Die bisherigen Secrets `FTP_SERVER`, `FTP_USERNAME`, `FTP_PASSWORD` und `FTP_PATH` werden nicht mehr verwendet und sollten entfernt werden. Ohne die neuen Secrets bricht der Deployment-Workflow ab.
- Der Webhoster muss E-Mails über PHP `mail()` versenden können. Ohne diese Funktion bleibt die bisherige Anmeldung verfügbar, aber die Passwort-Wiederherstellung ist nicht betriebsbereit.

### Manuelle Aktualisierung

1. Datenbank und `config.local.php` sichern.
2. `migrations/001-password-resets.sql` über die Datenbankverwaltung importieren.
3. `app_url` und `mail_from` in `config.local.php` ergänzen.
4. `.htaccess`, `api.php` und `public/index.html` aktualisieren.
5. Anmeldung und Passwort-Wiederherstellung prüfen.
6. Für das automatische Deployment im Environment `hiba` die neuen `SFTP_*`-Secrets hinterlegen und die alten `FTP_*`-Secrets löschen. `SFTP_KNOWN_HOSTS` wird mit `ssh-keyscan -p <Port> <Host>` ermittelt.

Die Datenbankmigration kann beim generischen SFTP-Deployment nicht sicher automatisiert werden, weil der Workflow absichtlich keine Datenbankzugangsdaten besitzt und Shared-Hosting-Anbieter unterschiedliche Verwaltungswege bereitstellen.
