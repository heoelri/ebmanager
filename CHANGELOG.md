# Changelog

Alle relevanten Änderungen werden ab diesem Stand in dieser Datei dokumentiert. Nicht rückwärtskompatible Änderungen stehen zusätzlich unter `Breaking Changes` und enthalten die notwendigen Aktualisierungsschritte.

## Unreleased

### Added

- Benutzer können über einen per E-Mail versendeten Einmallink ein vergessenes Passwort zurücksetzen.
- Passwort-Reset-Tokens werden nur als SHA-256-Hash gespeichert, laufen nach 30 Minuten ab und widerrufen nach Verwendung alle Sitzungen.
- Die Startseite prüft Datenbankkonfiguration, Verbindung und Schema und zeigt bei Problemen eine konkrete Betriebsseite statt eines allgemeinen internen Fehlers.
- Eine zentrale Schritt-für-Schritt-Anleitung dokumentiert Erstinstallation, manuelles und automatisches Deployment, Updates, Rollback und Fehlerbehebung auf Webspace.

### Changed

- Der Docker-Smoke-Test prüft Passwort-Reset, Tokenverbrauch, Sitzungswiderruf und anschließende Anmeldung.
- Interne MySQL-Testverbindungen verwenden explizit UTF-8 und verzichten im isolierten Docker-Netz auf die selbstsignierte MySQL-TLS-Verbindung.
- Das Smoke-Testskript schaltet MySQL-TLS client-kompatibel mit `--ssl-mode=DISABLED` oder `--skip-ssl` ab, damit der CI-Job sowohl mit MySQL- als auch MariaDB-Clients stabil läuft.
- Das produktive GitHub-Deployment verwendet das Environment `hiba` und eine eigene Concurrency-Gruppe; zukünftige Ziele wie `devpreview` bleiben mit separaten Secrets und Schutzregeln isoliert.
- Die Beispielkonfiguration verwendet den einheitlichen Datenbanknamen `einsatzberichte`, fehlende DSN-Konfiguration liefert auf allen API-Routen HTTP 503 und gespeicherte Benutzeradressen werden syntaktisch validiert.

### Breaking Changes

- Bestehende Installationen müssen vor dem neuen Anwendungscode einmal `migrations/001-password-resets.sql` importieren.
- `config.local.php` benötigt `app_url` mit der öffentlichen HTTPS-Adresse und `mail_from` mit einer gültigen Absenderadresse; alternativ werden `APP_URL` und `MAIL_FROM` als Umgebungsvariablen gesetzt.
- Der Webhoster muss E-Mails über PHP `mail()` versenden können. Ohne diese Funktion bleibt die bisherige Anmeldung verfügbar, aber die Passwort-Wiederherstellung ist nicht betriebsbereit.

### Manuelle Aktualisierung

1. Datenbank und `config.local.php` sichern.
2. `migrations/001-password-resets.sql` über die Datenbankverwaltung importieren.
3. `app_url` und `mail_from` in `config.local.php` ergänzen.
4. `.htaccess`, `api.php` und `public/index.html` aktualisieren.
5. Anmeldung und Passwort-Wiederherstellung prüfen.

Die Datenbankmigration kann beim generischen FTPS-Deployment nicht sicher automatisiert werden, weil der Workflow absichtlich keine Datenbankzugangsdaten besitzt und Shared-Hosting-Anbieter unterschiedliche Verwaltungswege bereitstellen.
