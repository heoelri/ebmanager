# Security Review

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
| Mittel | Sitzungscookies könnten ohne `Secure` über unverschlüsseltes HTTP übertragen werden. | Cookies sind immer `Secure`, `HttpOnly` und `SameSite=Strict`. `.htaccess` leitet HTTP auf HTTPS um und setzt HSTS, sofern `mod_headers` verfügbar ist. |
| Mittel | Eine Passwortänderung ließ bereits bestehende Sitzungen aktiv. | Bei einer Passwortänderung werden alle Sitzungen des Benutzers innerhalb derselben Transaktion gelöscht. |
| Mittel | Der Einsatzimport vertraute den vom Browser gesendeten Einsatzdetails und konnte gemeinsame Einsatzdaten überschreiben. | Der Browser sendet nur die DIVERA-ID. Das Backend lädt den Einsatz mit dem serverseitigen Schlüssel erneut per `GET` und speichert ausschließlich diese verifizierten Daten. |
| Mittel | `SameSite=Strict` allein schützte auf Shared Hosting nicht vor schreibenden Anfragen einer fremden Subdomain derselben Site. | Alle schreibenden Anfragen erfordern `application/json`; vorhandene `Origin`-Header müssen exakt der HTTPS-Anwendungsorigin entsprechen. |
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
  checkt den exakt getesteten Commit aus und erzwingt verschlüsseltes FTPS.
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
- Der Webcontainer bindet nur `api.php`, `.htaccess` und `public/`
  schreibgeschützt ein; eine vorhandene `config.local.php` gelangt nicht in
  den Container.
