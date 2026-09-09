# Changelog

Alle relevanten Änderungen werden ab diesem Stand in dieser Datei dokumentiert. Nicht rückwärtskompatible Änderungen stehen zusätzlich unter `Breaking Changes` und enthalten die notwendigen Aktualisierungsschritte.

## Unreleased

### Added

- Das Projekt steht unter der PolyForm Noncommercial License 1.0.0. Feuerwehren, öffentliche Sicherheitsorganisationen und Kommunen dürfen die Software unabhängig von ihrer Finanzierung nutzen, ändern und weitergeben; kommerzielle Nutzung benötigt eine gesonderte Zustimmung (#96).
- Eine kompakte [API-Referenz](docs/API.md) beschreibt Endpunkte, Rollen, Eingaben, native Antworttypen, optionale Werte, UTC-Zeitformate und Konfliktvorbedingungen (#92).
- Einheitsführungen erhalten einen eigenen Bereich „Statistik“ mit Zeitraumfilter, Fahrzeug- und Mitgliederhäufigkeiten, zeitlichen Verteilungen sowie der durchschnittlichen Besatzungsstärke ihrer Einheit.
- Bearbeitbare Einheitsberichte können zusätzliche Fahrzeuge aus dem aktuellen Stamm der eigenen Einheit aufnehmen. Die Fahrzeuge stehen als Besatzungsziele bereit, bleiben von DIVERA-Neuimporten unberührt und erscheinen in Ansichten sowie PDF-Exporten.
- Die Ressourcenansicht hebt die weiterhin gespeicherte Auswahl „Inaktive Mitglieder anzeigen“ bei der Einheitsauswahl hervor; Mitglieder, eigene Fahrzeuge und Fahrzeuge anderer Einheiten sind standardmäßig geöffnet und nativ einklappbar.
- Alle Hauptbereiche besitzen Query-basierte Deep Links, die Ansichten nach einem Browser-Refresh sowie bei Vorwärts- und Zurücknavigation wiederherstellen.
- Pull Requests mit Änderungen unter `public/**` erhalten automatisch in `de-DE` und `Europe/Berlin` gerenderte Screenshots aller rollenabhängigen Hauptansichten als Workflow-Artefakt und bei vertrauenswürdigen Repository-Branches zusätzlich direkt eingebettet im PR-Kommentar.
- Die Verwaltung führt alle Einheiten der Organisation in einer eigenen Box auf. Automatisierte Builds erhalten die getestete Commit-ID als Build-ID, die unter „System“ angezeigt wird.
- Die Statistik „Alarmierte Fahrzeuge“ berücksichtigt ausschließlich Fahrzeuge der eigenen Einheit.
- Das produktive Deployment kann zusätzlich zum automatischen Lauf nach erfolgreichen `main`-Tests manuell für den aktuellen `main`-Commit gestartet werden.

### Changed

- Einsatzdaten und bereits vorhandene Einheits-Fahrzeuglisten bleiben ab dem ersten Einheitsbericht historisch erhalten, auch für andere alarmierte Einheiten ohne eigenen Bericht. Abweichende DIVERA-Importe warnen sichtbar, statt Alarmzeit, Berichtsjahr, laufende Nummer oder Freigaben still zu verändern (#89).
- Autor- und Besatzungsnamen werden als Berichtsdaten gespeichert. Konto-/Stammdatenänderungen ändern bestehende Berichte, PDFs, Personalübersichten und Prüfverläufe nicht; neu aufgenommene Personen erhalten den aktuellen Namen. Die Mitgliederstatistik zählt weiterhin je Person und zeigt den letzten historischen Namen im ausgewerteten Einsatzzeitraum (#89).
- Identische oder historisch verworfene Importe erhalten alle fachlichen Revisionen und Abschlüsse. Neue Einheitszuordnungen bleiben möglich und widerrufen nur den Gesamtstand. Der Vollabgleich unterscheidet neu, tatsächlich aktualisiert und unverändert sowie Einsätze mit verworfenen Abweichungen; Import- und Mailwarnungen werden gemeinsam angezeigt (#89).
- Die Besatzungsansicht vermeidet bei großen Mitgliederlisten wiederholte Vollsuchen für historische Namen und nicht mehr im Stamm vorhandene Personen (#89).
- Führungskräfte starten unter „Einsätze“ mit „Bericht erforderlich“. Bisher gespeichertes „Alle Status“ wird einmalig auf diesen Standard umgestellt; andere gespeicherte Filter und eine danach ausdrücklich gewählte Anzeige aller Status bleiben erhalten. Für Einheits- und Wehrführung ändert sich die Voreinstellung nicht.
- Einheitszuordnungen, Fahrzeug-Snapshots und Besatzungen werden als native JSON-Listen geliefert; Kontakt-, Einsatzleitungs- und Klassifikationsangaben als native Objekte. Der Browser verarbeitet diese Werte ohne eine zweite JSON-Dekodierung und meldet falsche Antworttypen sichtbar, statt daraus leere Bearbeitungsformulare zu erzeugen (#92).
- „Einsatz anlegen“ ist auf der Einsatzübersicht standardmäßig eingeklappt und weist auf die ausschließliche Nutzung für nicht über DIVERA alarmierte Einsätze hin.
- Die Box „DIVERA Import“ auf der Einsatzübersicht ist standardmäßig eingeklappt.
- Der UI-Screenshot-Kommentar bettet die 16 erzeugten Ansichten direkt über unveränderliche Dateien in einem separaten Screenshot-Branch je Pull Request ein.
- Fremde Alarmfahrzeuge zeigen bei eindeutigem, bereits synchronisiertem Fahrzeugstamm einer anderen Einheit derselben Wehr Name und Typ statt nur der DIVERA-ID; fehlende oder mehrdeutige Zuordnungen bleiben bei der ID.
- Sichtbare Datums- und Uhrzeitangaben der Browser-Oberfläche verwenden durchgängig das Gebietsschema und das 12-/24-Stunden-Schema des Nutzers; native Datumsfelder behalten die Browserdarstellung.

### Fixed

- Fehlerhafte Text-, ID-, Kontakt-, Klassifikations- und Listenformen werden ausdrücklich abgewiesen statt als Leerwerte oder andere IDs übernommen. Objektfehler benennen den betroffenen Berichtsbereich; fachliche Eindeutigkeitskonflikte erhalten passende Meldungen. Listen und Zusammenfassungen besitzen stabile Tie-Breaker; auch der Demo-Seed-Check verarbeitet native Zuordnungslisten (#92).
- Die Revisionshelfer der API-Regressionen verlangen vor der Payload-Erzeugung genau einen passenden Bericht beziehungsweise Einsatz; fehlende und doppelte Treffer brechen ausdrücklich ab.
- Revisionskonflikte benennen kontextneutral den „geladenen Stand“, sodass der Hinweis zu Einheitsberichten ebenso wie zu Einsatz-/Gesamtstandsrevisionen passt; HTTP 409 und der Erhalt offener Eingaben bleiben unverändert. `public/app.js` ist für GitHub ausdrücklich als handgepflegter, nicht generierter Quelltext markiert.
- Der Parallelitätstest zu #86 identifiziert Sperreigentümer über InnoDB-Transaktions- und Sperr-IDs statt über die Thread-Zuordnung impliziter Insertsperren. Er berücksichtigt gemeinsame Duplikatprüfsperren auf noch nicht bereinigten alten Indexeinträgen und meldet bei Fehlern ausschließlich Metadaten der betroffenen Testtransaktion.
- Die Review-Nacharbeit zu #86 beseitigt einen Deadlock zwischen vollständigem DIVERA-Abgleich und Berichtsspeicherung/-erstellung mit Besatzung. Der Vollabgleich importiert und sperrt alle gelieferten Einsätze in stabiler DIVERA-ID-Reihenfolge, bevor er Mitglieder und Fahrzeuge sperrt. Auch gleichzeitig angelegte Einsätze sind über ihre Upserts geschützt; alle Änderungen bleiben gemeinsam transaktional.
- Geladene Einheitsberichte, Übergaben und Rückgaben sind durch monotone Revisionen vor veralteten Schreibzugriffen geschützt, auch nach Rückkehr zum selben Workflowstatus. Die Konsolidierung prüft zusätzlich den geladenen Gesamtstand und alle Quellberichte. HTTP-409-Konflikte lassen ungespeicherte Texte, Besatzung, Fahrzeugauswahl und Kommentare im Browser geöffnet und erklären die manuelle Wiederherstellung (#86).
- Administrative Passwort- und E-Mail-Änderungen widerrufen ausstehende Einladungs- und Wiederherstellungslinks atomar. Tokenanforderungen und Bestätigungen werden mit Kontoänderungen über dieselbe Sperrreihenfolge koordiniert; fehlgeschlagene Mailversuche löschen keine zwischenzeitlich neu ausgestellten Links (#99).
- Abgelaufene Einmallinks werden vor neuen Wiederherstellungsanforderungen außerhalb der Benutzertransaktion bereinigt; gültige Links bleiben erhalten. Der Parallelitätstest respektiert die konfigurierte PDO-Verbindung einschließlich Port- und Socket-Angaben.
- Die Parallelitätsregression prüft die konkrete MySQL-Wartebeziehung auf den Primärschlüssel der Benutzertabelle statt lediglich einen wartenden `SELECT`.
- Neue Wiederherstellungs-, Einladungs- und Neueinladungstoken speichern ihre Anforderungszeit explizit in UTC, damit die Fünf-Minuten-Sperre nicht von der MySQL-Zeitzone abhängt. Bereits vorhandene Zeitwerte werden nicht pauschal umgerechnet; die weitergehenden Zeitkorrekturen aus #87 bleiben separat.
- Die Einsatzlisten-API liefert konsolidierte Berichtstexte einschließlich zurückbehaltener Arbeitsstände ausschließlich an die Wehrführung. Führungskräfte und Einheitsführungen erhalten weiterhin ihre zulässigen Einsatz- und Statusdaten (#100).

### Breaking Changes

**#89 benötigt Migration 005 und eine neue ausdrückliche Betreiberbestätigung
vor einem Merge nach `main`; frühere Freigaben für 004/#92 gelten nicht dafür.**
Bestehende Namen werden nur aus dem heutigen mandanteneigenen Bestand
übernommen; bereits verlorene Namensstände sind nicht rekonstruierbar.
`personnel` wird aus der strukturierten Besatzung neu aufgebaut; Bestandsberichte
und Einsätze mit Berichten erhalten einmalig eine höhere Revision.
Die beiden Namensspalten sind anschließend `NOT NULL` ohne Default:
Alter Anwendungscode kann keine Berichte/Besatzungen mehr anlegen.
Verbindliche Reihenfolge: unabhängige Schreibsperre und Sicherung, Migration
005 einschließlich Prüfung und Ledger-Vermerk, Betreiberbestätigung,
gemeinsamer PHP-/Browserwechsel, Funktionsprüfung, Freigabe.
Die ausführlichen manuellen Schritte, Grenzen und der schemaabhängige Rollback
stehen ausschließlich unter
[Deployment: Historische Berichtsdaten](docs/WEBSPACE-DEPLOYMENT.md#historische-berichtsdaten-einführen-89).
Die Bedeutung von `incidentsUpdated` ändert sich von „bereits vorhanden“ zu
„fachlich geändert“; unveränderte Einsätze stehen in `incidentsUnchanged`.

Für #92 ändern sich die Typen von `users.unit_ids`, `incidents.assignments`,
`assignments[].vehicles`, `reports.crew`, `reports.damaged_party`,
`reports.damaging_party`, `reports.incident_command` und
`reports.classification`: Sie sind echte JSON-Listen beziehungsweise -Objekte,
keine darin eingebetteten JSON-Strings. API-Clients müssen diese Werte direkt
verwenden. Die strengere Eingabevalidierung lehnt zuvor still umgewandelte
fehlerhafte Formen mit HTTP 400 ab; die zulässigen Leerwerte stehen in der
[API-Referenz](docs/API.md). Es ist keine zusätzliche Datenbankmigration nötig.
PHP und Browser dürfen nur gemeinsam aktualisiert beziehungsweise
zurückgesetzt werden. Die verbindlichen manuellen Schritte stehen unter
[Deployment: API-Vertrag umstellen](docs/WEBSPACE-DEPLOYMENT.md#json-antworttypen-und-eingabevalidierung-umstellen-92).

Die API-Antwort von `GET /api/incidents` enthält für `fuehrungskraft` und `einheitsleitung` kein `consolidated_text` mehr. Der native Browserclient benötigt keine Anpassung. Die Sicherheitskorrekturen für #99 und #100 erfordern keine zusätzliche Migration.

Bestandsinstallationen benötigen die Migrationen 003, 004 und anschließend
005 in dieser Reihenfolge vor dem neuen Code. Neue Installationen verwenden
ausschließlich das aktuelle `schema.sql`. Die kanonische
[Deploymentanleitung](docs/WEBSPACE-DEPLOYMENT.md#10-bestehende-installation-aktualisieren)
beschreibt die jeweiligen manuellen Schritte.

`PUT /api/reports/{id}` und alle Berichtsübergaben/-rückgaben verlangen jetzt die
geladene ganzzahlige `revision`. `PUT /api/incidents/{id}/consolidation` verlangt
die geladene Einsatz-`revision` sowie `reportVersions: [{id, revision}, …]` aller
Quellberichte. Fehlende/ungültige Vorbedingungen liefern HTTP 400, veraltete
Vorbedingungen HTTP 409; Rollen- und Mandantenprüfungen bleiben bestehen.
Seit #89 erhöht ein Neuimport nur bei einer tatsächlich übernommenen Änderung
oder neuen Einheit die Einsatzrevision, nicht die vorhandenen Berichtsrevisionen.
Es gibt keine automatische Übernahme oder Wiederholung veralteter Eingaben.

Die verbindliche Reihenfolge einschließlich Wartungsfenster, SQL-Vermerk,
Prüfung und Rollback steht in
[Deployment: Revisionen einführen](docs/WEBSPACE-DEPLOYMENT.md#revisionen-für-einheits--und-gesamtberichte-einführen-86).

## 2026-09-03

### Added

- Die Wehrleitung kann im Dialog „Benutzer bearbeiten“ einen fremden Zugang zurücksetzen und eine neue sieben Tage gültige Einladung senden.
- DIVERA-Fehler unterscheiden sichere Verbindungs-, HTTP- und Antwortursachen, ohne Access-Keys offenzulegen; der Demo-Start erzeugt einen veralteten Fake-DIVERA-Container zuverlässig neu.
- Das lokale Demo-Profil stellt für alle drei Demo-Einheiten vorkonfigurierte Fake-DIVERA-Stammdaten sowie importierbare Einzel- und Mehrfacheinheiten-Einsätze bereit.
- Die Wehrführung sieht im Gesamtbericht alle alarmierten Einheiten mit Fahrzeug-Snapshots und zugeordneter Besatzung.
- Die Auswahl „Status filtern“ bleibt im Browser pro Benutzer über Seitenaufrufe hinweg erhalten.
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

- Der Bootstrap-Endpunkt erkennt eine fehlende `member_units.active`-Spalte als unvollständiges Schema und antwortet mit HTTP 503.
- Inaktive Mitglieder und ihre historischen Fahrzeugzuordnungen bleiben beim Bearbeiten erhalten, können entfernt, aber nicht neu zugeordnet werden.
- Datums- und Uhrzeitwerte folgen dem Browserformat des Nutzers; Ausrücke- und Eintreffzeit können bei abgebrochenen Einsätzen geleert werden.
- Der Docker-Compose-Smoke-Test nutzt die bereits gesund gestarteten Dienste, statt Abhängigkeiten beim Testlauf erneut zu starten.
- Ungültige JSON-Antworten behalten im Frontend ihren HTTP-Status; kompakte Einheitenauswahlen setzen Validierungsfehler auf alle Kontrollfelder.
- Der Docker-Compose-Smoke-Test wartet explizit auf den Bootstrap-Endpunkt, wenn Compose den Webcontainer vor dem Testlauf neu startet.
- Einheitenlisten, Einsatzzuordnungen, Fahrzeug-Snapshots und PDF-Einsatzakten zeigen Führungskräften und Einheitsführungen nur noch ihre aktuell zugeordneten Einheiten.
- Erfolgreiche Anmeldungen aktualisieren veraltete Passwort-Hashes auf die aktuellen `PASSWORD_DEFAULT`-Parameter.
- Der Hinweis auf bereits vorhandene Einheitsberichte erscheint nur noch für die Wehrführung und Nutzer mit Zugriff auf mehrere Einheiten.
- Der Migrations-Idempotenztest wartet begrenzt auf eine erfolgreiche TCP-Anmeldung am finalen MySQL-Server statt nur auf `mysqladmin ping`, das auch gegen den temporären Initialisierungsserver erfolgreich sein kann.

### Changed

- Nicht mehr von DIVERA gelieferte Mitglieder bleiben einheitsspezifisch als inaktiv sichtbar und in vorhandenen Berichten erhalten, können aber nicht neu als Besatzung ausgewählt werden.
- Die Benutzerverwaltung weist beim Anlegen auf die siebentägige Gültigkeit des Einladungslinks hin und zeigt je Benutzer nur die letzte erfolgreiche Anmeldung.
- Einladungslinks sind sieben Tage gültig und nennen ihren Ablaufzeitpunkt in `Europe/Berlin`; Links für vergessene Passwörter bleiben 30 Minuten gültig.
- Das Frontend lädt JavaScript als separat cachebare Datei ohne Inline-Eventhandler, erzwingt eine restriktivere Content Security Policy und zeigt Benutzerrollen einheitlich auf Deutsch.
- Einzeilige Controls verwenden eine barrierefreundliche Mindesthöhe; gemeinsame Summary-Regeln und semantische Benutzerlisten vereinfachen Styles und Struktur.
- Einsatzanlage und Benutzerverwaltung zeigen Mehrfach-Einheitenauswahlen als kompakte Dropdowns; einzeilige Eingaben, Dropdowns und Buttons verwenden einheitlich 44 Pixel Höhe.
- Mehrfach-Einheitenauswahlen zeigen die Anzahl gewählter Einheiten und verlangen mindestens eine Auswahl; API-, Formular- und Ressourcenabfragen unterscheiden Fehlerzustände und konkurrierende Anfragen zuverlässig.
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

Bestehende Installationen von `2026-08-23` werden in dieser Reihenfolge aktualisiert:

1. Datenbank und bisherige Anwendungsdateien sichern.
2. `migrations/001-report-workflow-and-vehicles.sql` genau einmal importieren. Die Migration ersetzt `draft`/`released` durch die drei Workflowstatus, legt die Übergangshistorie sowie den Fahrzeugstamm an und erzeugt für jeden Bestandsbericht einen initialen Historieneintrag.
3. Danach `migrations/002-inactive-unit-members.sql` genau einmal importieren. Die Migration ergänzt den Aktivstatus bestehender Einheitszuordnungen und setzt alle vorhandenen Mitglieder zunächst aktiv.
4. Prüfen, dass beide Dateinamen in `schema_migrations` vorhanden sind.
5. Erst danach die Anwendungsdateien des Releases `2026-09-03` bereitstellen.
6. `/api/bootstrap`, Anmeldung, Benutzerverwaltung, einen vorhandenen Bericht und die DIVERA-Ressourcenansicht prüfen.

Neue Installationen importieren ausschließlich das aktuelle `schema.sql` und führen die beiden Migrationen nicht zusätzlich aus. Die vollständige Aktualisierungs- und Rollback-Anleitung steht in [`docs/WEBSPACE-DEPLOYMENT.md`](docs/WEBSPACE-DEPLOYMENT.md).

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
