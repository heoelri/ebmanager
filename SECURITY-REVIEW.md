# Security Review

## Login-Historie vom 23. August 2026

Die Historie erfasst ausschließlich die Benutzer-ID und den UTC-Zeitpunkt erfolgreicher Anmeldungen. IP-Adressen, User-Agents, Kennwörter und fehlgeschlagene Versuche werden nicht gespeichert. Die Ausgabe erfolgt nur über die bereits auf `wehrleitung` und den aktuellen Mandanten begrenzte Benutzerverwaltung; pro Benutzer werden höchstens fünf Zeitpunkte ausgegeben. Beim Löschen eines Benutzers werden die Einträge kaskadierend entfernt.

## Personenangaben in Einheitsberichten vom 23. August 2026

Geschädigte und Schädiger werden als optionale strukturierte Angaben im jeweiligen Einheitsbericht gespeichert. Sie nutzen keine neuen API-Routen und werden ausschließlich über die bereits mandanten- und rollenbegrenzten Berichtsabfragen ausgegeben. Namen, Telefonnummern und Adressen werden serverseitig längenbegrenzt, nicht protokolliert und nach der Freigabe nicht mehr bearbeitet. Die Angaben erhöhen den Umfang personenbezogener Einsatzdaten; Betreiber müssen sie daher in Aufbewahrungs- und Löschkonzepten wie Patienten-, Anrufer- und Berichtsdaten behandeln.

## API-Hardening vom 23. August 2026

Die im vollständigen API-Review priorisierten Befunde zu Transport, Sitzungen und Zustandsinvarianten wurden umgesetzt. Apache erzwingt HTTPS und sendet HSTS. Der zufällige Sitzungstoken bleibt ausschließlich im `Secure`-Cookie; MySQL speichert nur seinen SHA-256-Hash. Rollenänderungen werden pro Organisation serialisiert und dürfen die letzte Wehrführung nicht entfernen. Berichtsfreigaben aktualisieren ausschließlich Entwürfe und überschreiben einen vorhandenen Freigabezeitpunkt nicht. Manuelle Einsatzzeitpunkte werden strikt validiert; DIVERA-Importe ohne Alarmzeit werden abgelehnt, statt die Serverzeit einzusetzen. Die Migration `002-hash-session-tokens.sql` überführt bestehende Sitzungen ohne Klartextverlust oder Abmeldung.

## Systemübersicht vom 23. August 2026

`GET /api/system` wurde auf Rollenprüfung und Konfigurationslecks geprüft. Nur `wehrleitung` erhält die Übersicht. Die API gibt ausschließlich kuratierte Statuswerte, Versionen, Namen, Rollen und boolesche Konfigurationsmerkmale aus; DSN, Datenbank- und SMTP-Kennwörter, Einrichtungstoken sowie DIVERA-Schlüssel bleiben serverseitig. Ein Smoke-Test prüft sowohl die Sperre für andere Rollen als auch das Fehlen geheimnisverdächtiger Schlüsselnamen.

## SMTP-Versand vom 23. August 2026

Der optionale SMTP-Versand verwendet Port 587 mit verpflichtendem STARTTLS, aktiviert Zertifikats- und Hostnamenprüfung und authentifiziert sich erst nach dem TLS-Handshake. SMTP-Passwörter werden ausschließlich aus der nicht versionierten Konfiguration oder aus Umgebungsvariablen gelesen und weder geloggt noch an den Browser übertragen. Unvollständige SMTP-Konfigurationen werden abgelehnt; ohne `smtp_host` bleibt PHP `mail()` der Fallback.

## Benutzereinladungen vom 23. August 2026

Die Benutzeranlage verwendet denselben 256-Bit-Einmaltoken und denselben bestätigten HTTPS-Link wie die Passwort-Wiederherstellung. Bis zur Aktivierung besitzt das Konto nur einen unbekannten zufälligen Passwort-Hash. Schlägt die Übergabe der Einladungs-E-Mail an den konfigurierten Mailtransport fehl, werden Benutzer, Einheitszuordnungen und Token wieder gelöscht. Einladungen laufen nach 30 Minuten ab; danach kann der Benutzer über „Passwort vergessen“ einen neuen Link anfordern.

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
| Mittel | Eine parallele Bearbeitung konnte zwischen Statusprüfung und Freigabe noch einen bereits freigegebenen Bericht verändern. | Die Bearbeitung sperrt den Berichtsdatensatz mit `SELECT ... FOR UPDATE` und prüft den Entwurfsstatus innerhalb derselben Transaktion erneut. |

## Ohne offenen Befund

- Mandanten- und Einheitsgrenzen werden bei Einsätzen, Berichten, Benutzern,
  Mitgliedern, Konsolidierung und DIVERA-Funktionen serverseitig geprüft.
- PDO verwendet native vorbereitete Statements; ein ausnutzbarer
  SQL-Injection-Pfad wurde nicht gefunden.
- Dynamische Browserausgaben werden maskiert; ein ausnutzbarer XSS-Pfad wurde
  nicht gefunden.
- `SameSite=Strict`, verpflichtendes JSON, Origin-Prüfung und das Fehlen
  zustandsändernder GET-Routen schützen die geprüften CSRF-Szenarien.
- Externe Ziele sind feste HTTPS-Adressen von DIVERA. Alle DIVERA-Aufrufe
  verwenden ausschließlich `GET`; ein SSRF- oder Schreibpfad wurde nicht
  gefunden.
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
- CSP `frame-ancestors 'none'`, HSTS, `nosniff` und `Referrer-Policy:
  no-referrer` werden durch Apache gesetzt.
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
