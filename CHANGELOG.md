# Changelog

Alle relevanten Änderungen werden ab diesem Stand in dieser Datei dokumentiert. Nicht rückwärtskompatible Änderungen stehen zusätzlich unter `Breaking Changes` und enthalten die notwendigen Aktualisierungsschritte.

## Unreleased

### Added

- Erfolgreiche DIVERA-Importe werden mit Einheit, Einsatz, Benutzer und UTC-Zeitpunkt protokolliert; die Einsatzübersicht zeigt den letzten Import je Einheit.
- Erfolgreiche Anmeldungen werden pro Benutzer gespeichert; die Wehrleitung sieht in der Verwaltung die fünf neuesten Anmeldezeitpunkte.
- Einheitsberichte erfassen eine manuelle, je Einheit und Kalenderjahr eindeutige laufende Nummer, Geschädigte und Schädiger mit Name, Telefon und Adresse sowie die Einsatzleitung und eine optionale weitere Führungskraft.
- Die nur für die Wehrführung sichtbare Seite „System“ zeigt den Zustand von Anwendung, Datenbank und E-Mail sowie angelegte Einheiten und Benutzer, ohne Kennwörter oder Schlüssel auszugeben.
- Optionaler SMTP-Versand mit Authentifizierung und STARTTLS unterstützt Hoster, bei denen PHP `mail()` nicht verfügbar oder unzuverlässig ist.
- Neue Benutzer erhalten eine Einladungs-E-Mail und aktivieren ihr Konto über einen einmaligen Link, statt ein von der Wehrführung vergebenes Startpasswort zu verwenden.
- Benutzer können über einen per E-Mail versendeten Einmallink ein vergessenes Passwort zurücksetzen.
- Passwort-Reset-Tokens werden nur als SHA-256-Hash gespeichert, laufen nach 30 Minuten ab und widerrufen nach Verwendung alle Sitzungen.
- Die Startseite prüft Datenbankkonfiguration, Verbindung und Schema und zeigt bei Problemen eine konkrete Betriebsseite statt eines allgemeinen internen Fehlers.
- Eine zentrale Schritt-für-Schritt-Anleitung dokumentiert Erstinstallation, manuelles und automatisches Deployment, Updates, Rollback und Fehlerbehebung auf Webspace.

### Changed

- Die Einsatzübersicht weist Wehr- und Einheitsleitungen auf neuere, noch nicht importierte DIVERA-Einsätze hin und bietet dort den direkten Import an.
- Einsatz- und Berichtslisten vermeiden N+1-Abfragen, die Besatzungsvalidierung lädt zulässige Mitglieder einmalig und die Systemübersicht wiederholt keine vollständige Schemaprüfung.
- Manuelle Einsatzzeitpunkte werden strikt als UTC-ISO-Zeit validiert, fehlende DIVERA-Zeitpunkte werden abgelehnt und SMTP-Nachrichten enthalten einen RFC-konformen `Date`-Header.
- Nur echte MySQL-Duplikatfehler liefern HTTP 409; andere Integritätsfehler werden nicht mehr irreführend als vorhandener Datensatz gemeldet.
- Die Copilot-Instruktionen bündeln dauerhafte Projektregeln ohne wiederholte Sicherheits-, Architektur-, UI- und Testvorgaben.
- Docker Compose führt ausstehende Datenbankmigrationen vor dem Start des lokalen Webcontainers automatisch und genau einmal aus; ein CI-Test simuliert dafür ein bestehendes Dev-Volume.
- Die Oberfläche verwendet mindestens 44 Pixel große Touch-Ziele, sichtbare Tastaturfokusse, Screenreader-Livebereiche, Fokusführung bei Seitenwechseln, mobil bedienbare Kontrollfelder statt Mehrfach-Selects sowie bildschirmfüllende Dialoge auf kleinen Geräten.
- Einheiten mit demselben Namen können innerhalb einer Wehr nicht mehrfach angelegt werden; die Datenbank-Eindeutigkeit ist durch einen Smoke-Test abgesichert.
- In der Verwaltung werden beim Anlegen und Bearbeiten von Benutzern eine oder mehrere Einheiten über eindeutige Kontrollfelder ausgewählt.
- HTTP wird wieder dauerhaft auf HTTPS umgeleitet und HSTS ist aktiv.
- Sitzungstoken werden nur noch als SHA-256-Hash gespeichert und verglichen.
- Eine Rollenänderung wird abgelehnt, wenn sie den Mandanten ohne Wehrführung zurücklassen würde.
- Bereits freigegebene Berichte können nicht erneut freigegeben werden; der ursprüngliche Freigabezeitpunkt bleibt erhalten.
- Wiederverwendbare HTTP-, Datenbank-, Validierungs- und Mailfunktionen liegen in `support.php`; `api.php` enthält nur noch fachliche Logik und Routing.
- Die Webspace-Anleitung beschreibt die Konfiguration und betrieblichen Voraussetzungen des E-Mail-Versands über PHP `mail()`.
- Die Anwendung kann unverändert im Dokumentenstamm oder in einem Unterverzeichnis betrieben werden; Frontend und Backend leiten den jeweiligen Basispfad automatisch aus der aufgerufenen Adresse ab.
- Die Webspace-Anleitung dokumentiert den manuellen SFTP-Upload mit Passwort und die verpflichtende Host-Key-Prüfung.
- Der Docker-Smoke-Test prüft Passwort-Reset, Tokenverbrauch, Sitzungswiderruf und anschließende Anmeldung.
- Datenbankverbindungen initialisieren UTF-8 ohne die unter PHP 8.5 veraltete PDO-Konstante, damit API-Statuscodes nicht durch Deprecation-Ausgaben verfälscht werden.
- Interne MySQL-Testverbindungen verwenden explizit UTF-8 und verzichten im isolierten Docker-Netz auf die selbstsignierte MySQL-TLS-Verbindung.
- Das Smoke-Testskript schaltet MySQL-TLS client-kompatibel mit `--ssl-mode=DISABLED` oder `--skip-ssl` ab, damit der CI-Job sowohl mit MySQL- als auch MariaDB-Clients stabil läuft.
- Das produktive GitHub-Deployment verwendet das Environment `hiba` und eine eigene Concurrency-Gruppe; zukünftige Ziele wie `devpreview` bleiben mit separaten Secrets und Schutzregeln isoliert.
- Das automatische Deployment lädt die Anwendungsdateien per SFTP statt per FTPS hoch, weil der Zielwebspace keinen FTP-Zugang mehr anbietet. Der Host-Key wird dabei verpflichtend gegen `SFTP_KNOWN_HOSTS` geprüft.
- Die Beispielkonfiguration verwendet den einheitlichen Datenbanknamen `einsatzberichte`, fehlende DSN-Konfiguration liefert auf allen API-Routen HTTP 503 und gespeicherte Benutzeradressen werden syntaktisch validiert.

### Breaking Changes

- Bestehende Installationen müssen vor dem neuen Anwendungscode einmal `migrations/005-divera-imports.sql` importieren. Die Historie beginnt mit dem ersten DIVERA-Import nach dem Update.
- Bestehende Installationen müssen vor dem neuen Anwendungscode einmal `migrations/004-login-history.sql` importieren. Die Historie beginnt mit der ersten erfolgreichen Anmeldung nach dem Update.
- Bestehende Installationen müssen vor dem neuen Anwendungscode einmal `migrations/003-report-details.sql` importieren. Bestehende Berichte bleiben lesbar und erhalten laufende Nummer und Zusatzangaben bei der nächsten Bearbeitung.
- Bestehende Installationen müssen vor dem neuen Anwendungscode einmal `migrations/002-hash-session-tokens.sql` importieren. Die Migration hasht bestehende Sitzungstoken in-place und erhält dadurch aktive Anmeldungen.
- Deployments müssen `support.php` zusammen mit `api.php` hochladen. Ohne die neue Datei startet die API nicht.
- Bestehende Installationen müssen vor dem neuen Anwendungscode einmal `migrations/001-password-resets.sql` importieren.
- `config.local.php` benötigt `app_url` mit der öffentlichen HTTPS-Adresse und `mail_from` mit einer gültigen Absenderadresse; alternativ werden `APP_URL` und `MAIL_FROM` als Umgebungsvariablen gesetzt.
- Das GitHub-Environment `hiba` benötigt die neuen Secrets `SFTP_SERVER`, `SFTP_USERNAME`, `SFTP_KNOWN_HOSTS` sowie `SFTP_PRIVATE_KEY` oder `SFTP_PASSWORD`; optional `SFTP_PORT` und `SFTP_PATH`. Die bisherigen Secrets `FTP_SERVER`, `FTP_USERNAME`, `FTP_PASSWORD` und `FTP_PATH` werden nicht mehr verwendet und sollten entfernt werden. Ohne die neuen Secrets bricht der Deployment-Workflow ab.
- Der Webhoster muss E-Mails über PHP `mail()` oder die dokumentierte SMTP-Konfiguration versenden können. Ohne E-Mail-Versand bleibt die bisherige Anmeldung verfügbar, aber Einladungen und Passwort-Wiederherstellung sind nicht betriebsbereit.

### Manuelle Aktualisierung

1. Datenbank und `config.local.php` sichern.
2. `migrations/001-password-resets.sql` über die Datenbankverwaltung importieren.
3. `migrations/002-hash-session-tokens.sql` genau einmal importieren.
4. `migrations/003-report-details.sql` genau einmal importieren.
5. `migrations/004-login-history.sql` genau einmal importieren.
6. `migrations/005-divera-imports.sql` genau einmal importieren.
7. `app_url` und `mail_from` in `config.local.php` ergänzen.
8. `.htaccess`, `api.php`, `support.php` und `public/index.html` aktualisieren.
9. Anmeldung, Benutzerverwaltung, Passwort-Wiederherstellung und Einheitsberichte prüfen.
10. Für das automatische Deployment im Environment `hiba` die neuen `SFTP_*`-Secrets hinterlegen und die alten `FTP_*`-Secrets löschen. `SFTP_KNOWN_HOSTS` wird mit `ssh-keyscan -p <Port> <Host>` ermittelt.

Die Datenbankmigration kann beim generischen SFTP-Deployment nicht sicher automatisiert werden, weil der Workflow absichtlich keine Datenbankzugangsdaten besitzt und Shared-Hosting-Anbieter unterschiedliche Verwaltungswege bereitstellen.
