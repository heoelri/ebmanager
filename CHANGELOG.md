# Changelog

Alle relevanten Änderungen werden ab diesem Stand in dieser Datei dokumentiert. Nicht rückwärtskompatible Änderungen stehen zusätzlich unter `Breaking Changes` und enthalten die notwendigen Aktualisierungsschritte.

## Unreleased

### Added

- Führungskräfte sehen Einheit und Verfasser eines bereits vorhandenen fremden Einheitsberichts, ohne dessen Inhalte oder Workflowdaten einsehen zu können.
- Rollenabhängige PDF-Downloads exportieren Einsatzakten, sichtbare Einzelberichte und abgeschlossene Gesamtberichte mit Exportzeitpunkt, Nutzer und Rolle.
- Die Einsatzübersicht zeigt und filtert rollenbezogen fehlende, zu prüfende, zur Konsolidierung bereite und abgeschlossene Einsatzberichte.
- Ein dreistufiger Workflow führt Einheitsberichte vom Autorenentwurf über die Einheitsführung zur Wehrführung, protokolliert alle Übergänge unveränderlich und unterstützt kommentierte Rückgaben mit E-Mail-Benachrichtigung.
- DIVERA-Fahrzeuge werden als aktueller Einheitsstamm synchronisiert; „Alles synchronisieren“ gleicht Mitglieder, Qualifikationen, Fahrzeuge und alle gelieferten Einsätze mit je einem lesenden Abruf pro Quelle ab.
- Der DIVERA-Test-Fake verweist auf die offiziellen OpenAPI-Dokumente; ein monatlicher GitHub-Workflow prüft die verwendeten Pfade und dokumentierten Felder auf Abweichungen.
- Konfigurierbare Dienstgrade aus `constants.php` stehen in beiden Feldern der Einsatzleitung als Drop-down mit Abkürzung und vollständiger Bezeichnung bereit.
- Die Dienstgradliste nach VOFF Nordrhein-Westfalen enthält zusätzlich Gemeinde- und Stadtbrandinspektor; die Auswahl bleibt optional.
- Einheitsführungen werden über neue Einsätze ihrer Einheiten und durch Führungskräfte erstellte Berichte informiert; Wehrführungen erhalten nach Freigaben durch Einheitsführungen eine E-Mail mit Einsatzdetails und direktem Link.
- Berichtsformulare zeigen die DIVERA-Einsatznummer unveränderlich an, trennen Gesamt- und Einheitseinsatzleitung in feste Zeilen und bieten native einklappbare Bereiche.
- Ein lokales Stylesheet vereinheitlicht Layout, Formulare und responsive Darstellung ohne zusätzliche Frontend-Abhängigkeiten.

### Fixed

- Der Hinweis auf bereits vorhandene Einheitsberichte erscheint nur noch für die Wehrführung und Nutzer mit Zugriff auf mehrere Einheiten.
- Der Migrations-Idempotenztest wartet begrenzt auf eine erfolgreiche TCP-Anmeldung am finalen MySQL-Server statt nur auf `mysqladmin ping`, das auch gegen den temporären Initialisierungsserver erfolgreich sein kann.

### Changed

- Wehrführungen benötigen keine Einheitszuordnung, Einheitsführungen gehören exakt einer Einheit an und Führungskräfte dürfen DIVERA-Einsätze ihrer zugeordneten Einheiten selbst erkennen und importieren.
- Nicht mehr von DIVERA gelieferte Stammdatenzuordnungen werden einheitsspezifisch entfernt; historische Einsatz- und Besatzungssnapshots bleiben erhalten.
- Führungskräfte sehen nach dem Absenden den Übergabezeitpunkt und einen eindeutigen Nur-Lese-Hinweis; die Wehrführung sieht vor der Konsolidierung, welche alarmierten Einheiten noch keinen prüfbereiten Bericht geliefert haben.
- Die Einsatzansicht bindet das Konsolidierungsformular nur noch für die Wehrführung; Führungskraft und Einheitsführung können erneut eingereichte Berichte fehlerfrei und nur lesend öffnen.
- Ein optionales Docker-Compose-Profil importiert eine wiederholbare lokale Demofeuerwehr mit allen Rollen, drei Einheiten, Mitgliedern, Fahrzeugen und unterschiedlichen Berichtsständen.
- Fehlgeschlagene Workflow-Benachrichtigungen rollen den gespeicherten Vorgang nicht zurück und werden als sichtbare Warnung sowie datenschutzarm im Serverlog gemeldet.
- Direkte Links mit `?incident=<ID>` öffnen den berechtigten Einsatz auch nach einer erforderlichen Anmeldung.
- Bearbeitungsdialoge halten den Fokus während asynchroner Aktualisierungen stabil und geben ihn beim Schließen kontrolliert zurück; die Zeitwerte der Einzelberichte stehen für bessere Lesbarkeit untereinander.
- Aktivierung und Passwort-Wiederherstellung stellen Passwortmanagern die zum Einmallink gehörende E-Mail-Adresse als Benutzernamen bereit.
- Besatzungswechsel und Wiederholungsversuche bewahren den Tastaturfokus; fehlende Einsatzzeiten erzeugen keine falsche Dauer.

### Breaking Changes

- Bestehende Installationen müssen vor dem neuen Anwendungscode `migrations/001-report-workflow-and-vehicles.sql` importieren. Die Migration ersetzt `draft`/`released` durch die drei Workflowstatus, legt die Übergangshistorie sowie den Fahrzeugstamm an und erzeugt für jeden Bestandsbericht einen initialen Historieneintrag.

## 2026-08-23

### Added

- `constants.php` bündelt Rollen, Einsatzarten, Klassifikationsgruppen und deren UI-Bezeichnungen; die Oberfläche lädt anpassbare Fachoptionen aus derselben Backend-Quelle.
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

### Fixed

- Der Compose-End-to-End-Test behandelt den erfolgreichen Abschluss des einmaligen Migrationsdienstes nicht mehr als Abbruchsignal.
- Die Systemübersicht liefert bei Datenbank- oder Schemafehlern wieder einen kuratierten Status statt eines unstrukturierten Serverfehlers.

### Changed

- Die Einsatzübersicht weist Wehr- und Einheitsleitungen auf neuere, noch nicht importierte DIVERA-Einsätze hin und bietet dort den direkten Import an.
- Einsatz- und Berichtslisten vermeiden N+1-Abfragen und liefern Zuordnungen sowie Besatzungen stabil sortiert; die Besatzungsvalidierung lädt zulässige Mitglieder einmalig.
- Manuelle Einsatzzeitpunkte werden strikt als UTC-ISO-Zeit validiert, fehlende DIVERA-Zeitpunkte werden abgelehnt und SMTP-Nachrichten enthalten einen RFC-konformen `Date`-Header.
- Nur echte MySQL-Duplikatfehler liefern HTTP 409; andere Integritätsfehler werden nicht mehr irreführend als vorhandener Datensatz gemeldet.
- Die Copilot-Instruktionen bündeln dauerhafte Projektregeln ohne wiederholte Sicherheits-, Architektur-, UI- und Testvorgaben.
- Docker Compose führt spätere Datenbankmigrationen vor dem Start des lokalen Webcontainers automatisch und genau einmal aus; ein CI-Test prüft die idempotente Ausführung.
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
