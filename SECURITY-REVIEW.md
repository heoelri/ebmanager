# Security Review

## Einheitsstatistik vom 3. September 2026

`GET /api/statistics` ist ausschließlich für `einheitsleitung` freigegeben
und leitet die auszuwertende Einheit aus der serverseitigen aktuellen
`user_units`-Zuordnung ab. Der Client kann keine Einheits-ID vorgeben. Alle
Einsatzabfragen begrenzen zusätzlich auf `incidents.organization_id`; die
weiteren Aggregationen verwenden nur daraus ermittelte Berichts-IDs und
prüfen Mitglieder nochmals gegen denselben Mandanten.

Die Antwort enthält ausschließlich Namen und aggregierte Häufigkeiten aus
Fahrzeug-Snapshots, zusätzlichen Berichtsfahrzeugen und strukturierter
Besatzung. Berichtstexte, Patient, meldende Person, Geschädigte und Schädiger
werden weder abgefragt noch ausgegeben oder protokolliert. Inaktive
Mitglieder bleiben für historische Häufigkeiten sichtbar, ohne weitere
personenbezogene Angaben offenzulegen. Manipulierte Zeiträume werden strikt
als lokale ISO-Daten validiert.

## Inaktive DIVERA-Mitglieder vom 3. September 2026

Der Aktivstatus wird auf der mandantengebundenen Zuordnung `member_units`
geführt, damit dieselbe Person je Einheit getrennt behandelt wird. Nur aktive
Mitglieder werden für neue Besatzungszuordnungen ausgegeben und serverseitig
akzeptiert. Bereits in einem Bericht gespeicherte inaktive Mitglieder und
historische Fahrzeugzuordnungen dürfen ausschließlich unverändert in diesem
Bericht erhalten oder durch Weglassen entfernt werden; dadurch kann ein
manipulierter Request keine beliebige inaktive Person neu hinzufügen.
Ressourcenlisten bleiben auf berechtigte Einheiten und den aktuellen Mandanten
begrenzt und kennzeichnen inaktive Mitglieder ohne zusätzliche Personendaten.
Migration 002 stellt historische Zuordnungen nur wieder her, wenn Mitglied,
Einheit und Einsatz demselben Mandanten angehören.

## Rollen-, Berichts- und DIVERA-Grenzen

Die API erzwingt die Einheitenanzahl je Rolle: keine Zuordnung für Wehrführungen, exakt eine für Einheitsführungen und mindestens eine für Führungskräfte. Führungskräfte dürfen DIVERA-Einsätze ihrer Einheiten lesen und einzeln importieren, erhalten aber keinen Zugriff auf Access-Key-Konfiguration oder Stammdatensynchronisation. Einheitenlisten, Einsatzzuordnungen, Fahrzeug-Snapshots und PDF-Einsatzakten enthalten für Führungskräfte und Einheitsführungen nur aktuell zugeordnete Einheiten; die Wehrführung behält die Organisationssicht. Alle Wege prüfen weiterhin Mandant und aktuelle Einheitszuordnung serverseitig.

Berichtsübergänge sperren den Datensatz, prüfen Rolle, Einheit und erwarteten Ausgangsstatus erneut und schreiben Status sowie Historie in derselben Transaktion. Rückgaben verlangen einen längenbegrenzten Kommentar; eine Rückgabe an einen nicht mehr zuständigen Autor wird abgelehnt. Die Wehrführung kann fremde Einheitsberichte nicht bearbeiten, und eine Rückgabe macht eine bestehende Konsolidierung sichtbar ungültig, ohne den Arbeitsstand zu löschen.

Zusätzliche Berichtsfahrzeuge werden serverseitig gegen den aktuellen
Fahrzeugstamm und die Organisation der Berichtseinheit geprüft. Fahrzeuge
anderer Einheiten oder Mandanten sind auch mit manipulierten Requests nicht
zulässig. Historische Einträge dürfen nur unverändert erhalten oder entfernt
werden; neue Besatzungszuordnungen zu nicht mehr vorhandenen Fahrzeugen werden
abgelehnt. DIVERA-Neuimporte ändern ausschließlich den getrennten
Einsatz-Snapshot und überschreiben diese Berichtsdaten nicht.

DIVERA bleibt ausschließlich lesend angebunden. Einzel- und Gesamtimport verwenden nur `GET`; der Browser liefert beim Einzelimport lediglich die Alarm-ID, die serverseitig erneut verifiziert wird. Die optionale Basisadresse ist eine serverseitige Test- und lokale Demokonfiguration und wird nie aus Requests übernommen. Der Fake-DIVERA-Dienst protokolliert die Methoden und weist schreibende externe Aufrufe zurück. Externe Fehler nennen nur sichere Kategorien oder HTTP-Statuscodes; URL und Access-Key werden weder ausgegeben noch protokolliert.

## Workflow-Benachrichtigungen vom 23. August 2026

Empfänger werden ausschließlich serverseitig über `organization_id`, Rolle
und `user_units` bestimmt und je Benutzer nur einmal angeschrieben. Der
auslösende Benutzer wird aus der Empfängergruppe entfernt. Direkte
Einsatzlinks entstehen aus der konfigurierten HTTPS-`APP_URL` und der
internen Einsatz-ID, niemals aus dem Host-Header oder aus externen
DIVERA-Daten. Nach der Anmeldung öffnet das Frontend den Einsatz nur, wenn er
in der rollenbegrenzten Einsatzliste des Benutzers enthalten ist.

Der Versand erfolgt erst nach erfolgreichem Speichern. Fehler rollen den
fachlichen Vorgang nicht zurück, werden sichtbar an den Browser gemeldet und
ohne Empfängeradresse, Mailzugangsdaten, DIVERA-Schlüssel oder Einsatzinhalt
protokolliert. Es gibt bewusst keine Queue und keine automatische
Wiederholung.

## Login-Historie vom 23. August 2026

Die Historie erfasst ausschließlich die Benutzer-ID und den UTC-Zeitpunkt erfolgreicher Anmeldungen. IP-Adressen, User-Agents, Kennwörter und fehlgeschlagene Versuche werden nicht gespeichert. Die Ausgabe erfolgt nur über die bereits auf `wehrleitung` und den aktuellen Mandanten begrenzte Benutzerverwaltung; pro Benutzer wird nur der neueste Zeitpunkt ausgegeben. Beim Löschen eines Benutzers werden die Einträge kaskadierend entfernt. Nach erfolgreicher Passwortprüfung aktualisiert der Login veraltete Hash-Algorithmen oder Parameter mit `PASSWORD_DEFAULT`; `SELECT ... FOR UPDATE` serialisiert dies mit gleichzeitigen Passwortänderungen und deren Sitzungswiderruf.

## Personenangaben in Einheitsberichten vom 23. August 2026

Geschädigte und Schädiger werden als optionale strukturierte Angaben im jeweiligen Einheitsbericht gespeichert. Sie nutzen keine neuen API-Routen und werden ausschließlich über die bereits mandanten- und rollenbegrenzten Berichtsabfragen ausgegeben. Namen, Telefonnummern und Adressen werden serverseitig längenbegrenzt, nicht protokolliert und nach der Freigabe nicht mehr bearbeitet. Die Angaben erhöhen den Umfang personenbezogener Einsatzdaten; Betreiber müssen sie daher in Aufbewahrungs- und Löschkonzepten wie Patienten-, Anrufer- und Berichtsdaten behandeln.

## API-Hardening vom 23. August 2026

Die im vollständigen API-Review priorisierten Befunde zu Transport, Sitzungen und Zustandsinvarianten wurden umgesetzt. Apache erzwingt HTTPS und sendet HSTS. Der zufällige Sitzungstoken bleibt ausschließlich im `Secure`-Cookie; MySQL speichert nur seinen SHA-256-Hash. Rollenänderungen werden pro Organisation serialisiert und dürfen die letzte Wehrführung nicht entfernen. Berichtsübergänge aktualisieren ausschließlich den jeweils erwarteten Zustand und bewahren den ersten Übergabezeitpunkt an die Wehrführung. Manuelle Einsatzzeitpunkte werden strikt validiert; DIVERA-Importe ohne Alarmzeit werden abgelehnt, statt die Serverzeit einzusetzen.

## Systemübersicht vom 23. August 2026

`GET /api/system` wurde auf Rollenprüfung und Konfigurationslecks geprüft. Nur `wehrleitung` erhält die Übersicht. Die API gibt ausschließlich kuratierte Statuswerte, Versionen, Namen, Rollen und boolesche Konfigurationsmerkmale aus; DSN, Datenbank- und SMTP-Kennwörter, Einrichtungstoken sowie DIVERA-Schlüssel bleiben serverseitig. Ein Smoke-Test prüft sowohl die Sperre für andere Rollen als auch das Fehlen geheimnisverdächtiger Schlüsselnamen.

## Deep Links vom 3. September 2026

Query-Parameter wählen ausschließlich bereits vorhandene Browseransichten aus und erweitern keine API-Berechtigung. Nicht erlaubte Rollenansichten und nicht sichtbare Einsatz-IDs fallen auf die Einsatzübersicht zurück; alle fachlichen Daten bleiben zusätzlich serverseitig rollen-, einheits- und mandantengebunden. Einladungs- und Wiederherstellungstoken verbleiben in den bestehenden Hash-Fragmenten und werden nicht in die neue Navigation übernommen.

## UI-Screenshot-Workflow vom 3. September 2026

Der Screenshot-Workflow läuft auf `pull_request` und führt den Code des Pull Requests niemals über `pull_request_target` aus. Er verwendet ausschließlich die versionierten Demo-Daten und offensichtlich unechte lokale Zugangsdaten. Screenshots werden für alle PRs als Artefakt gespeichert; der schreibende Upload zu GitHub User Attachments und der PR-Kommentar laufen nur, wenn der Quell-Branch zum selben Repository gehört. Fork-PRs erhalten dadurch keinen schreibenden Token oder Zugriff auf Deployment-Secrets.

## SMTP-Versand vom 23. August 2026

Der optionale SMTP-Versand verwendet Port 587 mit verpflichtendem STARTTLS, aktiviert Zertifikats- und Hostnamenprüfung und authentifiziert sich erst nach dem TLS-Handshake. SMTP-Passwörter werden ausschließlich aus der nicht versionierten Konfiguration oder aus Umgebungsvariablen gelesen und weder geloggt noch an den Browser übertragen. Unvollständige SMTP-Konfigurationen werden abgelehnt; ohne `smtp_host` bleibt PHP `mail()` der Fallback.

## Benutzereinladungen vom 3. September 2026

Die Benutzeranlage verwendet denselben 256-Bit-Einmaltoken und denselben bestätigten HTTPS-Link wie die Passwort-Wiederherstellung. Bis zur Aktivierung besitzt das Konto nur einen unbekannten zufälligen Passwort-Hash. Schlägt die Übergabe der Einladungs-E-Mail an den konfigurierten Mailtransport fehl, werden Benutzer, Einheitszuordnungen und Token wieder gelöscht. Einladungen laufen nach sieben Tagen ab; Datenbankprüfung und gespeicherter Ablauf verwenden dieselbe UTC-Datenbankzeit, der gespeicherte Zeitpunkt wird in der E-Mail in `Europe/Berlin` genannt. Danach kann der Benutzer über „Passwort vergessen“ einen 30 Minuten gültigen neuen Link anfordern. Das längere Einladungsfenster erhöht die Zeit für einen möglichen Zugriff auf eine weitergeleitete E-Mail, wird aber weiterhin durch einen zufälligen 256-Bit-Token, ausschließliche Hash-Speicherung, HTTPS, Einmalverwendung und das bis zur Aktivierung unbrauchbare Konto begrenzt.

Die Wehrleitung kann ausschließlich fremde Benutzer desselben Mandanten erneut einladen. Passwort-Hash, Sitzungen und vorhandene Einmallinks werden zusammen mit dem neuen Token in einer Transaktion geändert; lehnt der Mailtransport die Einladung ab, wird die Transaktion zurückgerollt und der bisherige Zugang bleibt nutzbar. Die seltene administrative Aktion hält den Benutzerdatensatz während des Mailversands gesperrt, um parallele Änderungen an E-Mail-Adresse oder Zugang zu verhindern.

## Passwort-Wiederherstellung vom 22. August 2026

Der neue öffentliche Wiederherstellungsfluss wurde auf Kontoermittlung, Token-Leaks, Token-Wiederverwendung, Sitzungsfortbestand, CSRF und manipulierte Links geprüft. Die API antwortet unabhängig vom Vorhandensein eines Kontos gleich, speichert nur den SHA-256-Hash eines zufälligen 256-Bit-Tokens, begrenzt Anforderungen pro Benutzer auf eine Nachricht in fünf Minuten und lässt Tokens nach 30 Minuten ablaufen. `APP_URL` muss eine konfigurierte HTTPS-URL sein und wird nicht aus dem manipulierbaren Host-Header erzeugt. Ein erfolgreicher Reset löscht Token und sämtliche Sitzungen in derselben Transaktion. Eine fehlgeschlagene Übergabe an PHP `mail()` oder SMTP wird ohne Adresse oder Token protokolliert und der unzustellbare Token gelöscht. Als verbleibende Betriebsanforderung sollte der Webhoster zusätzlich allgemeines HTTP-Rate-Limiting aktivieren, falls automatisierter Missbrauch beobachtet wird.

## Vollreview vom 22. August 2026

Geprüft wurden das PHP/PDO-MySQL-Backend, die Browseroberfläche, das
MySQL-Schema, die Apache-Konfiguration, lokale Konfiguration, Tests und GitHub
Actions. Schwerpunkte waren Authentifizierung, Sitzungen, Rollen,
Mandantentrennung, IDOR, XSS, CSRF, SQL-Injection, SSRF, sensible Einsatzdaten,
Secrets, HTTPS und externe DIVERA-Aufrufe.

## Behobene Befunde

| Schweregrad | Befund | Umsetzung |
|---|---|---|
| Hoch | Eine ungeschützte Ersteinrichtung könnte vom ersten externen Aufrufer übernommen werden. | `/api/setup` verlangt ein zufälliges `SETUP_TOKEN` mit mindestens 32 Zeichen und vergleicht es mit `hash_equals`. Nach dem ersten Benutzer ist die Route dauerhaft geschlossen. |
| Hoch | Sitzungscookies und Anmeldedaten könnten über unverschlüsseltes HTTP mitgelesen werden. | `.htaccess` leitet HTTP dauerhaft auf HTTPS um und setzt HSTS; Cookies sind `Secure`, `HttpOnly` und `SameSite=Strict`. |
| Mittel | Eine Passwortänderung ließ bereits bestehende Sitzungen aktiv. | Bei einer Passwortänderung werden alle Sitzungen des Benutzers innerhalb derselben Transaktion gelöscht. |
| Mittel | Der Einsatzimport vertraute den vom Browser gesendeten Einsatzdetails und konnte gemeinsame Einsatzdaten überschreiben. | Der Browser sendet nur die DIVERA-ID. Das Backend lädt den Einsatz mit dem serverseitigen Schlüssel erneut per `GET` und speichert ausschließlich diese verifizierten Daten. |
| Mittel | `SameSite=Strict` allein schützte auf Shared Hosting nicht vor schreibenden Anfragen einer fremden Subdomain derselben Site. | Alle schreibenden Anfragen erfordern `application/json`; vorhandene `Origin`-Header müssen exakt der Anwendungsorigin einschließlich des tatsächlich verwendeten Schemas entsprechen. |
| Mittel | Eine parallele Bearbeitung konnte zwischen Statusprüfung und Übergabe noch einen bereits weitergeleiteten Bericht verändern. | Bearbeitung und Übergang sperren den Berichtsdatensatz mit `SELECT ... FOR UPDATE` und prüfen Status sowie Berechtigung innerhalb derselben Transaktion erneut. |

## Ohne offenen Befund

- Mandanten- und Einheitsgrenzen werden bei Einsätzen, Berichten, Benutzern,
  Mitgliedern, Konsolidierung und DIVERA-Funktionen serverseitig geprüft.
- PDO verwendet native vorbereitete Statements; ein ausnutzbarer
  SQL-Injection-Pfad wurde nicht gefunden.
- Dynamische Browserausgaben werden maskiert; ein ausnutzbarer XSS-Pfad wurde
  nicht gefunden.
- `SameSite=Strict`, verpflichtendes JSON, Origin-Prüfung und das Fehlen
  zustandsändernder GET-Routen schützen die geprüften CSRF-Szenarien.
- Das produktive externe Ziel ist die feste HTTPS-Adresse von DIVERA; nur Tests und das lokale Demo-Profil dürfen sie serverseitig überschreiben. Alle DIVERA-Aufrufe verwenden ausschließlich `GET`; ein durch Benutzer steuerbarer SSRF- oder Schreibpfad wurde nicht gefunden.
- Passwort-Hashes, Sitzungswerte, Datenbankzugangsdaten und DIVERA-Schlüssel
  werden nicht über die API ausgegeben.
- Patienten- und Anruferdaten bleiben an authentifizierte,
  mandantengebundene Abfragen gebunden.
- `.htaccess` sperrt HTTP-Zugriffe auf Konfigurations- und Schemadateien und
  deaktiviert Verzeichnisauflistungen.
- Der dokumentierte MySQL-Laufzeitbenutzer benötigt keine DDL- oder
  Administrationsrechte.
- GitHub Actions besitzt nur Leserechte und verwendet keine
  Deployment-Zugangsdaten in Pull-Request-Workflows.
- CI prüft Anwendung und Schema direkt sowie unabhängig davon das gebaute
  Docker-/Apache-System; veraltete Läufe derselben Referenz werden abgebrochen.
- Das Deployment läuft nur nach erfolgreichen Tests eines Pushs auf `main`,
  checkt den exakt getesteten Commit aus und überträgt ausschließlich per SSH
  gesichertes SFTP mit geprüftem Host-Key.
  Datenbankkonfiguration und SQL-Schema werden nicht übertragen.

## Defense in Depth

- Das Cookie-Präfix `__Host-` verhindert, dass andere Subdomains ein
  gleichnamiges Sitzungscookie setzen.
- Die CSP beschränkt Skripte, Styles, API-Verbindungen, Formulare und sonstige Ressourcen auf die eigene Origin, verbietet Plugins, fremde Basispfade und Framing; HSTS, `nosniff` und `Referrer-Policy: no-referrer` werden ebenfalls durch Apache gesetzt.
- Zusätzliche mandantenübergreifende Verbundschlüssel in MySQL wären eine
  weitere Schutzschicht gegen zukünftige Programmierfehler. Die aktuelle
  Mandantentrennung wird vollständig in den geprüften API-Abfragen erzwungen.

## Betriebsanforderungen

- Die Domain muss ausschließlich über HTTPS betrieben werden.
- Apache muss `.htaccess`, `mod_rewrite` und PHP-Dateien korrekt verarbeiten.
- `config.local.php` darf nicht in die Versionsverwaltung oder in
  Sicherungen mit öffentlichem Zugriff gelangen.
- Der MySQL-Benutzer erhält nur `SELECT`, `INSERT`, `UPDATE` und `DELETE`.
- Nach Änderungen an Authentifizierung, Berechtigungen, Datenmodell,
  DIVERA-Import oder Hosting-Konfiguration ist ein neuer Security Review
  erforderlich.
- Die festen Docker-Zugangsdaten und das selbstsignierte Zertifikat sind
  ausschließlich für die lokale, nicht öffentlich erreichbare
  Entwicklungsumgebung bestimmt.
- Die Docker-Webports sind ausdrücklich an `127.0.0.1` gebunden; MySQL wird
  nicht auf dem Host veröffentlicht.
- Der Webcontainer bindet nur `api.php`, `constants.php`, `support.php`,
  `.htaccess` und `public/` schreibgeschützt ein; eine vorhandene
  `config.local.php` gelangt nicht in den Container.
