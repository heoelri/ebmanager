# Deployment auf Webspace

Diese Anleitung ist die maßgebliche Betriebsdokumentation für die Erstinstallation und spätere Aktualisierung auf klassischem PHP-/Apache-Webspace mit MySQL. Projektüberblick, Architektur und Datenmodell werden nicht wiederholt, sondern sind in [README](../README.md), [Architektur](ARCHITEKTUR.md) und [Datenmodell](../DATENMODELL.md) beschrieben.

## 1. Voraussetzungen prüfen

Der Webhoster muss folgende Funktionen bereitstellen:

- PHP 8.2 oder neuer mit `pdo_mysql`, `iconv` für PDF-Exporte und für SMTP mit `openssl`
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

### E-Mail-Versand konfigurieren

Die Anwendung versendet Einladungen, Links für vergessene Passwörter und
Workflow-Benachrichtigungen standardmäßig mit der PHP-Standardfunktion
`mail()`. Einheitsführungen erhalten Nachrichten über neue Einsätze ihrer
Einheiten und durch Führungskräfte erstellte Berichte; Wehrführungen werden
über von Einheitsführungen freigegebene Berichte informiert. Ist `mail()` beim
Hoster nicht verfügbar oder unzuverlässig, kann alternativ authentifiziertes
SMTP mit verpflichtendem STARTTLS konfiguriert werden.

1. Beim Hoster eine Absenderadresse unter der eigenen Domain anlegen oder eine dafür freigegebene Adresse auswählen, beispielsweise `ebmanager@feuerwehr-dahlbruch.com`.
2. Diese vollständige Adresse als `mail_from` beziehungsweise `MAIL_FROM` konfigurieren. Eine fremde oder nicht freigegebene Absenderdomain wird von vielen Hostern abgewiesen.
3. `app_url` beziehungsweise `APP_URL` auf die von außen erreichbare HTTPS-Adresse setzen. Dieser Wert erzeugt die Links in den E-Mails und muss bei einer Unterverzeichnisinstallation den Pfad enthalten.
4. In der PHP-Konfiguration oder im Hosting-Kontrollzentrum prüfen, dass `mail()` nicht deaktiviert ist. Falls der Hoster einen festen Envelope-Sender verlangt, muss dieser dort serverseitig eingerichtet werden.
5. SPF, DKIM und gegebenenfalls DMARC für die Absenderdomain im DNS nach den Vorgaben des Mailhosters konfigurieren, damit die Nachrichten nicht unnötig als Spam bewertet werden.
6. Nach der Installation einen Benutzer einladen und zusätzlich „Passwort vergessen“ testen. Spamordner und Mailprotokoll des Hosters prüfen; ein erfolgreicher Aufruf von `mail()` bestätigt nur die Übergabe an das Mailsystem, nicht die spätere Zustellung.

Für STRATO oder vergleichbare Hoster kann `config.local.php` um folgende Werte ergänzt werden:

```php
'smtp_host' => 'smtp.strato.de',
'smtp_port' => 587,
'smtp_username' => 'ebmanager@feuerwehr-dahlbruch.com',
'smtp_password' => 'passwort-des-email-postfachs',
```

`smtp_username` ist bei STRATO die vollständige E-Mail-Adresse; `smtp_password` ist das Passwort dieses Postfachs. Sobald `smtp_host` gesetzt ist, verwendet die Anwendung SMTP statt `mail()`. Alle SMTP-Werte müssen dann vollständig sein. Die entsprechenden Umgebungsvariablen heißen `SMTP_HOST`, `SMTP_PORT`, `SMTP_USERNAME` und `SMTP_PASSWORD`. Das optionale `SMTP_CA_FILE` ist nur für Server mit einer privaten Zertifizierungsstelle vorgesehen; öffentliche Hoster wie STRATO benötigen es nicht.

Kann weder PHP `mail()` noch der konfigurierte SMTP-Server eine Nachricht annehmen, wird ein neu angelegter Benutzer wieder entfernt und die Oberfläche meldet den Versandfehler. Die Passwort-Wiederherstellung bleibt ebenfalls nicht verfügbar.

Bei Workflow-Benachrichtigungen bleibt der Einsatz, Bericht oder die Freigabe
dagegen gespeichert. Die Oberfläche zeigt eine Warnung; Details ohne
Empfängeradresse, Zugangsdaten oder Einsatzinhalt stehen im PHP-Fehlerlog.
Eine automatische Wiederholung findet nicht statt.

## 6. Dateien hochladen

Folgende Struktur muss im gewählten Zielverzeichnis entstehen:

```text
.htaccess
api.php
constants.php
support.php
config.local.php
public/
  app.js
  index.html
  styles.css
```

1. Das gewählte Zielverzeichnis anlegen und `.htaccess`, `api.php`, `constants.php`, `support.php`, `config.local.php`, `public/index.html`, `public/app.js` sowie `public/styles.css` per SFTP dorthin hochladen.
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
sftp> put constants.php
sftp> put support.php
sftp> put config.local.php
sftp> mkdir public
sftp> put public/index.html public/index.html
sftp> put public/app.js public/app.js
sftp> put public/styles.css public/styles.css
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
2. Auf der Seite „System“ Build-ID, Datenbank- und E-Mail-Status prüfen; dort dürfen keine Kennwörter oder Schlüssel erscheinen.
3. In der Verwaltung einen Testbenutzer anlegen und prüfen, dass die Einladung ankommt, der Link die Anwendung öffnet und der Benutzer sein Passwort selbst setzen kann.
4. Einen manuellen Einsatz und einen Bericht anlegen.
5. Über „Passwort vergessen“ sowie einen neuen Einsatz und Bericht prüfen,
   dass der Webhoster E-Mails mit dem korrekten HTTPS-Link versendet.
6. Optional pro Einheit einen DIVERA-Access-Key hinterlegen und einen lesenden Abruf durchführen.
7. Serverprotokolle auf PHP-, Apache- oder Mailfehler prüfen, ohne Zugangsdaten oder DIVERA-Schlüssel weiterzugeben.

## 9. Automatisches Deployment mit GitHub Actions einrichten

Das Repository deployt nach erfolgreichen Tests eines Pushs auf `main` den exakt getesteten Commit. Der Workflow verwendet das GitHub-Environment `hiba` und kann zum erneuten Deployment des aktuellen `main`-Commits auch manuell gestartet werden.

Der GitHub-Workflow unterstützt SFTP wahlweise mit privatem Schlüssel oder Passwort und prüft den Host-Key verpflichtend.

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
5. Einen Push auf `main` durchführen und zuerst den Workflow `Tests`, danach den Workflow `Deployment` beobachten. Für ein manuelles erneutes Deployment unter **Actions → Deployment → Run workflow** ausschließlich den Branch `main` auswählen.

Der Workflow schreibt den exakt getesteten Commit-SHA in die nicht öffentlich abrufbare Datei `.build-id` und lädt sie zusammen mit `.htaccess`, `api.php`, `constants.php`, `support.php`, `public/index.html`, `public/app.js` und `public/styles.css` hoch. `config.local.php`, Datenbankzugangsdaten, `schema.sql` und Migrationen werden absichtlich nicht automatisiert übertragen.

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

### Von `2026-08-23` auf `2026-09-03` aktualisieren

1. Datenbank und bisherige Anwendungsdateien sichern.
2. `migrations/001-report-workflow-and-vehicles.sql` über die Datenbankverwaltung genau einmal importieren.
3. Danach `migrations/002-inactive-unit-members.sql` genau einmal importieren.
4. Prüfen, dass beide Dateinamen in `schema_migrations` vorhanden sind.
5. Erst dann die Anwendungsdateien des Releases `2026-09-03` hochladen oder das automatische Deployment auslösen.
6. `/api/bootstrap` aufrufen; der Endpunkt darf kein unvollständiges Schema melden.
7. Anmeldung, Benutzerverwaltung, einen vorhandenen Bericht und die DIVERA-Ressourcenansicht prüfen.

### Von `2026-09-03` auf einen Stand mit zusätzlichen Berichtsfahrzeugen aktualisieren

1. Datenbank und bisherige Anwendungsdateien sichern.
2. `migrations/003-report-additional-vehicles.sql` über die Datenbankverwaltung genau einmal importieren.
3. Prüfen, dass `003-report-additional-vehicles.sql` in `schema_migrations` vorhanden ist.
4. Erst danach den neuen Anwendungscode hochladen.
5. `/api/bootstrap` und das Hinzufügen eines eigenen Fahrzeugs in einem bearbeitbaren Einheitsbericht prüfen.

Für andere Ausgangs- oder Zielversionen gelten die jeweils datierten
Upgrade-Hinweise im [Changelog](../CHANGELOG.md).

### Manuelle Einsätze dauerhaft ausblenden (#112)

1. Datenbank und bisherige Anwendungsdateien sichern.
2. Prüfen, dass Migrationen 001 bis 005 angewendet und in
   `schema_migrations` vermerkt sind.
3. `migrations/006-incident-soft-delete.sql` mit einem DDL-berechtigten
   Administrationskonto vollständig ausführen.
4. Prüfen, dass `incidents.deleted_at` und die Tabelle
   `incident_deletions` vorhanden sind. Danach einmalig vermerken:

   ```sql
   INSERT INTO schema_migrations(name,applied_at)
   VALUES('006-incident-soft-delete.sql',UTC_TIMESTAMP());
   ```

   Lokal übernimmt `docker/migrate.sh` den Vermerk automatisch.
5. Erst danach PHP- und Browserdateien gemeinsam bereitstellen. `/api/bootstrap`
   darf keinen Schemafehler melden. Mit einem Testeinsatz die Rollenbegrenzung,
   Revisionsprüfung, dauerhafte Ausblendung und den Audit-Eintrag prüfen.

**Rollback von 006:** Den vorherigen Anwendungscode wiederherstellen. Die
nullable Spalte und die leere beziehungsweise bereits befüllte Audit-Tabelle
können im Schema verbleiben; sie verändern das Verhalten des alten Codes
nicht. Bereits ausgeblendete Einsätze werden vom alten Code wieder sichtbar.
Ist das unerwünscht, Rollback abbrechen und vorwärts korrigieren. Audit-Einträge
oder Einsatzdaten nicht löschen.

### Einsätze als Übung kennzeichnen (#115)

1. Datenbank und bisherige Anwendungsdateien sichern.
2. Prüfen, dass Migrationen 001 bis 006 angewendet und in
   `schema_migrations` vermerkt sind.
3. `migrations/007-incident-exercises.sql` mit einem DDL-berechtigten
   Administrationskonto vollständig ausführen.
4. Prüfen, dass `incidents.is_exercise` und die Tabelle
   `incident_exercise_changes` vorhanden sind. Danach einmalig vermerken:

   ```sql
   INSERT INTO schema_migrations(name,applied_at)
   VALUES('007-incident-exercises.sql',UTC_TIMESTAMP());
   ```

   Lokal übernimmt `docker/migrate.sh` den Vermerk automatisch.
5. Erst danach PHP-, Browser- und Stylesheet-Dateien gemeinsam bereitstellen.
   `/api/bootstrap` darf keinen Schemafehler melden. Mit einem manuellen und
   einem DIVERA-Einsatz Rollen, Revision, Filter, Verlauf, PDF und Statistik
   prüfen.

**Rollback von 007:** Den vorherigen Anwendungscode wiederherstellen. Spalte
und Historientabelle können im Schema verbleiben; alter Code ignoriert beide.
Gesetzte Kennzeichnungen sind im alten Browser nicht sichtbar, bleiben aber
gespeichert. Historieneinträge nicht löschen.

### Sitzungen und Loginhistorie bereinigen (#17, #97)

Die bestätigte Aufbewahrungsfrist für erfolgreiche Anmeldungen beträgt
**90 Tage**, ohne Ausnahme für die letzte Anmeldung eines Benutzers.
Diese Produktentscheidung ist keine Aussage über gesetzliche
Aufbewahrungsfristen fachlicher Berichte. Für Einsatzdaten, Mitglieder,
Einmallinks und Sicherungen werden hier keine neuen Löschregeln eingeführt;
die weiteren Betriebsentscheidungen aus #97 bleiben offen.

1. Datenbank und bisherige Anwendungsdateien sichern. Die Aktivierung entfernt
   später alte Login-Einträge endgültig; die Migration selbst löscht nichts.
2. Prüfen, dass Migrationen 001 bis 007 vollständig ausgeführt und im
   Migrationsledger registriert sind.
3. `migrations/008-auth-retention.sql` mit dem Administrationskonto ausführen.
   Sie ergänzt `login_history_time (logged_in_at, id)` sowie die Tabelle
   `auth_cleanup_state` mit der Steuerzeile `id=1`.
4. Index, Tabellendefinition und Steuerzeile prüfen; initial ist `last_run_at`
   auf `1970-01-01 00:00:00` gesetzt. Erst nach vollständigem Erfolg registrieren:

   ```sql
   INSERT INTO schema_migrations(name,applied_at)
   VALUES('008-auth-retention.sql',UTC_TIMESTAMP());
   ```

   Lokal übernimmt `docker/migrate.sh` die Registrierung. Bei einem
   unterbrochenen DDL-Lauf nicht die gesamte Datei blind wiederholen:
   vorhandenen Index, Tabelle und Steuerzeile mit den Definitionen der
   Migration vergleichen und ausschließlich fehlende Anweisungen nachholen.
   Einen bestehenden Laufzeitpunkt nicht zur vermeintlichen Reparatur
   zurücksetzen.
5. PHP- und Browserdateien gemeinsam ausliefern. `/api/bootstrap` prüft Tabelle
   und Steuerzeile und löst den ersten begrenzten Batch aus. Gültige Anmeldung,
   Benutzerverwaltung und erhaltene laufende Sitzungen prüfen.

**Regelbetrieb:** Öffentliche API-Nutzung wie Bootstrap/Anmeldung und
authentifizierte API-Aufrufe prüfen den Zustand vor der fachlichen
Verarbeitung. Ein Batch läuft installationsweit höchstens einmal pro Stunde
und entfernt je maximal 500 abgelaufene Sitzungen und 500 Login-Einträge
älter als 90 Tage, jeweils die ältesten zuerst. Konkurrenzrequests
überspringen einen gesperrten Batch. Gültige Sitzungen werden nicht verkürzt;
abgelaufene Sitzungen sind auch ohne physische Löschung bereits ungültig.
Die Verwaltung zeigt ältere Login-Einträge auch bei Rückstand nicht mehr an.

Es ist **kein Cronjob erforderlich**. Ohne API-Zugriffe findet keine
Bereinigung statt; der nächste geeignete Zugriff holt genau einen Batch
nach. Größere Altbestände werden über mehrere Stunden mit Zugriffen abgebaut,
nicht in einem langen Request. Die maximale Abbauleistung beträgt bei
stündlichen Zugriffen 12.000 Zeilen je Tabelle und Tag. Übersteigen dauerhaft
mehr Zeilen diese Grenze, muss der Betreiber das Datenbudget neu bewerten.

Zur Kontrolle genügt eine nicht personenbezogene Abfrage über die geschützte
Datenbankverwaltung:

```sql
SELECT last_run_at FROM auth_cleanup_state WHERE id=1;
SELECT COUNT(*) AS expired_sessions
FROM sessions WHERE expires_at<=UTC_TIMESTAMP();
SELECT COUNT(*) AS old_logins
FROM login_history WHERE logged_in_at<UTC_TIMESTAMP()-INTERVAL 90 DAY;
```

Ein Bereinigungsfehler rollt beide Löschungen und den Laufzeitpunkt zurück
und erscheint als API-Fehler; das PHP-Fehlerlog enthält nur die vorhandenen
neutralen SQL-Fehlercodes, keine Token oder Anmeldedaten. Der nächste Zugriff
kann erneut versuchen. Die Bereinigung ist keine Datensicherung und ersetzt
keinen Wiederherstellungsnachweis.

**Rollback von 008:** PHP- und Browsercode gemeinsam zurücksetzen. Index und
Steuertabelle dürfen unverändert bleiben; alter Code ignoriert sie und
wendet die 90-Tage-Regel nicht mehr an. Bereits gelöschte Login-Einträge werden
dadurch nicht wiederhergestellt. Keine vollständige Datenbanksicherung nur
für diese technischen Altbestände über inzwischen neu geschriebene
Einsatzberichte zurückspielen.

### Revisionen für Einheits- und Gesamtberichte einführen (#86)

1. Ein Wartungsfenster vereinbaren und Schreibzugriffe während Migration und
   Codewechsel unterbinden. Datenbank und bisherige Anwendungsdateien sichern.
   Anwender müssen offene, ungespeicherte Eingaben vor dem Neuladen sichern.
   Die Sperre muss außerhalb der vom SFTP-Workflow überschriebenen Dateien
   liegen, etwa als vorgelagerte Zugriffssperre beim Hoster. Eine temporäre
   Änderung der ausgelieferten `.htaccess` reicht nicht: Der bisherige
   Deployment-Workflow ersetzt sie bereits zu Beginn des Uploads.
2. Prüfen, dass Migrationen 001 bis 003 vollständig angewendet und in
   `schema_migrations` vermerkt sind.
3. `migrations/004-report-revisions.sql` über die Datenbankverwaltung genau
   einmal importieren. Die beiden neuen `INT UNSIGNED NOT NULL DEFAULT 1`-Spalten
   `incidents.revision` und `reports.revision` müssen danach vorhanden sein.
   Fachliche Daten bleiben erhalten. MySQL-DDL ist nicht transaktional:
   Bei einem Teilfehler nicht blind die ganze Datei erneut ausführen, sondern
   den vorhandenen Spaltenstand prüfen und nur die fehlende Anweisung nachholen.
4. Nach erfolgreichem vollständigem Import manuell ausführen:

   ```sql
   INSERT INTO schema_migrations(name,applied_at)
   VALUES('004-report-revisions.sql',UTC_TIMESTAMP());
   ```

   Im lokalen Compose-Betrieb übernimmt ausschließlich `docker/migrate.sh`
   diesen Vermerk automatisch.
5. **Vor dem Merge nach `main`** den erfolgreichen Migrationsstand bestätigen;
   erst danach den neuen PHP- und Browsercode gemeinsam deployen. Der
   SFTP-Workflow führt weiterhin keine Migration aus. Keine Mischversion für
   Schreibzugriffe freigeben: Alter PHP-Code erhöht die Revisionen nicht.
6. `/api/bootstrap` prüfen, Browseransichten neu laden und anschließend in
   zwei Ansichten denselben Bericht öffnen. Nach Speichern der ersten Ansicht
   muss die zweite HTTP 409 melden und ihre Eingaben erhalten. Dasselbe für
   einen Gesamtbericht prüfen; Übergabe/Rückgabe müssen weiterhin funktionieren.
7. Erst danach die Anwendung wieder für Schreibzugriffe freigeben.

Rollback: Im Wartungsfenster PHP- und Browsercode gemeinsam zurücksetzen;
die additiven Revisionsspalten und der Migrationsvermerk dürfen bleiben.
Der alte Code bietet dann keinen Konfliktschutz. Vor erneuter Aktivierung
des neuen Codes nach Schreibzugriffen mit altem Code zunächst im Wartungsfenster
`UPDATE incidents SET revision=revision+1;` und
`UPDATE reports SET revision=revision+1;` ausführen und alle Browseransichten
neu laden lassen. Revisionen niemals auf 1 zurücksetzen und Migration 004
nicht erneut ausführen.

### JSON-Antworttypen und Eingabevalidierung umstellen (#92)

Diese Änderung benötigt keine zusätzliche Migration und ändert keine
gespeicherten Berichts- oder Stammdaten. Der
[API-Vertrag](API.md) und der Browserclient ändern sich jedoch gemeinsam.

1. Die bisherigen Anwendungsdateien und die Datenbank sichern. Andere
   API-Clients anhand der Referenz auf native Listen/Objekte und die
   dokumentierten Eingabeformen vorbereiten.
2. Vor dem Codewechsel ein Wartungsfenster mit Schreibsperre sicherstellen.
   Bei automatischem Deployment muss dies vor dem Merge nach `main` geschehen.
   Die Sperre muss den Upload überleben; eine nur in der ausgelieferten
   `.htaccess` eingerichtete Sperre wird vom bisherigen SFTP-Workflow
   überschrieben. Offene, ungespeicherte Formulare vor dem Neuladen sichern.
3. PHP- und Browserdateien desselben Releases vollständig gemeinsam
   ausliefern. Keine Mischung aus altem und neuem API-Vertrag freigeben.
4. `/api/bootstrap` aufrufen und Browser vollständig neu laden. Verwaltung,
   vorhandene Einsatzberichte und deren Bearbeitungsdialoge sowie die
   Fahrzeug-/Besatzungsansichten müssen die vorhandenen Werte unverändert
   darstellen. Erst danach die Schreibsperre aufheben.

Rollback auf den Stand unmittelbar vor #92: PHP- und Browserdateien gemeinsam
im Wartungsfenster zurückspielen und Browser neu laden. Keine Tabellen oder
Migrationsvermerke verändern; der Revisionsschutz aus #86 bleibt erhalten.

### Historische Berichtsdaten einführen (#89)

**Migration 005 braucht eine neue ausdrückliche Betreiberbestätigung.**
Eine bereits erteilte Freigabe für Migration 004 oder #92 ist keine Freigabe
für diesen Eingriff. Vor Bestätigung kein Merge nach `main`: Dessen
SFTP-Deployment läuft nach grünen Tests automatisch.

Die Migration ergänzt `reports.author_name`, `report_crew.member_name` und
`incidents.report_data_frozen`. Altbestände erhalten nur die heute vorhandenen
mandanteneigenen Namen, sonst leere Strings. Bereits verlorene historische
Namensstände sind **nicht rekonstruierbar**. `reports.personnel` wird aus der
strukturierten Besatzung in Mitglieds-ID-Reihenfolge neu berechnet; ein noch
vorhandener älterer Freitext-Namensstand wird dabei ersetzt. Bestehende
Berichtsrevisionen und die Einsatzrevisionen von Einsätzen mit Berichten
steigen einmalig. Status, laufende Nummern, Berichtszeiten, Gesamttexte,
Abschlusszeitpunkte und Prüfverlauf werden nicht umgeschrieben.

1. Wartungsfenster und unabhängige Zugriffssperre beim Hoster einrichten,
   die sämtliche Anwendungsschreibzugriffe während Migration **und**
   Codewechsel verhindert. Sie muss außerhalb der ausgelieferten Dateien
   liegen (z. B. vorgeschaltete Hoster-/Proxy-Sperre), denn der SFTP-Workflow
   überschreibt `.htaccess`. Laufende Requests vollständig abwarten; Benutzer
   müssen offene Eingaben vorher sichern. Datenbank inklusive Schema sowie
   bisherige Anwendungsdateien und `config.local.php` sichern und die
   Wiederherstellbarkeit prüfen.
2. Migrationen 001–004 und ihre Ledger-Einträge prüfen. Vor dem Import die
   abgeleitete Textlänge und verfügbare Revisionen kontrollieren. Diese Abfragen
   dürfen keine Zeilen liefern (keine Namen oder Einsatzinhalte ausgeben):

   ```sql
   SELECT r.id,
          SUM(OCTET_LENGTH(m.name))+2*(COUNT(*)-1) AS personnel_bytes
   FROM reports r
   JOIN incidents i ON i.id=r.incident_id
   JOIN report_crew rc ON rc.report_id=r.id
   JOIN members m ON m.id=rc.member_id AND m.organization_id=i.organization_id
   GROUP BY r.id
   HAVING personnel_bytes>65535;

   SELECT id FROM reports WHERE revision=4294967295;
   SELECT i.id FROM incidents i
   WHERE i.revision=4294967295
     AND EXISTS(SELECT 1 FROM reports r WHERE r.incident_id=i.id);
   ```

   Bei Treffern anhalten und fachlich/technisch klären; weder Namen abschneiden
   noch Revisionen zurücksetzen. Quellnamen sind auf 200 Zeichen begrenzt.
   Die Migration hebt `group_concat_max_len` für die Sitzung an und erzwingt
   `STRICT_ALL_TABLES`, damit TEXT-Überläufe nicht still gekürzt werden.
   Die betroffenen DML-Schritte laufen gemeinsam in einer Transaktion.
3. `migrations/005-historical-report-snapshots.sql` mit einem DDL-berechtigten
   Administrationskonto über die Datenbankverwaltung vollständig ausführen.
   UTF-8/`utf8mb4` verwenden. Bei Fehlern **abbrechen**, nicht mit `--force`
   oder „bei Fehler fortsetzen“ arbeiten. Ein noch offener Backfill muss in
   derselben Verbindung mit `ROLLBACK` beendet beziehungsweise die Verbindung
   geschlossen werden. Die Schreibsperre bleibt bestehen.
4. Bei einem Teilfehler zuerst den tatsächlichen Spaltenstand prüfen:

   ```sql
   SELECT table_name,column_name,column_type,is_nullable,column_default
   FROM information_schema.columns
   WHERE table_schema=DATABASE()
     AND ((table_name='reports' AND column_name='author_name')
       OR (table_name='report_crew' AND column_name='member_name')
       OR (table_name='incidents' AND column_name='report_data_frozen'))
   ORDER BY table_name,column_name;
   ```

   MySQL-DDL committet implizit. Deshalb niemals die komplette Datei blind
   erneut importieren: Nur fehlende der ersten drei `ADD COLUMN`-Anweisungen
   nachholen. Bereits vorhandene Spalten nicht löschen oder leeren.
   Nach Behebung der Ursache den Rest der Datei **ab
   `SET @previous_sql_mode=...` einschließlich beider abschließender
   `MODIFY COLUMN`-Anweisungen** erneut ausführen. Dieser Teil füllt nur
   noch NULL-Namen, erhöht Berichtsrevisionen nur bei erstmaligem Backfill
   und Einsatzrevisionen nur beim erstmaligen Setzen des Markers. Bereits
   gesicherte Namen und Revisionen bleiben erhalten, auch nach einem Fehler
   im letzten DDL-Schritt. Bei unerwarteten Spaltentypen nicht raten:
   Sicherung wiederherstellen oder den Zustand gezielt prüfen lassen.
5. Der Spaltencheck muss genau drei Zeilen mit `is_nullable='NO'` liefern.
   Beide Namen sind `VARCHAR(200)` ohne Default, der Marker `TINYINT(1)`
   mit Default 0. Zusätzlich müssen folgende Anzahlen jeweils 0 sein:

   ```sql
   SELECT COUNT(*) FROM reports WHERE author_name IS NULL;
   SELECT COUNT(*) FROM report_crew WHERE member_name IS NULL;
   SELECT COUNT(*) FROM incidents i WHERE report_data_frozen<>1
     AND EXISTS(SELECT 1 FROM reports r WHERE r.incident_id=i.id);
   ```

   Erst nach fehlerfreiem vollständigem Abschluss einmalig vermerken:

   ```sql
   INSERT INTO schema_migrations(name,applied_at)
   VALUES('005-historical-report-snapshots.sql',UTC_TIMESTAMP());
   ```

   Bei Wiederaufnahme einen bereits vorhandenen Eintrag nicht erneut anlegen;
   bei einem verfrühten Eintrag den vollständigen Schemazustand trotzdem
   prüfen. Lokal übernimmt `docker/migrate.sh` den Ledger-Vermerk nach Erfolg.
   Einen fehlgeschlagenen automatischen Lauf erst nach der beschriebenen
   manuellen Teil-DDL-Wiederaufnahme und dem Ledger-Eintrag wieder starten.
6. Den erfolgreichen Migrations-/Sperrstand ausdrücklich für **005**
   bestätigen. Erst danach Merge/Deployment freigeben beziehungsweise den
   zugehörigen PHP- und Browsercode gemeinsam hochladen. Alter Code kann
   wegen `NOT NULL` ohne Default keine Berichte oder Besatzungen mehr
   anlegen; eine Mischversion niemals für Schreibzugriffe öffnen.
7. Unter weiter aktiver öffentlicher Sperre über einen kontrollierten
   Betreiberzugang `/api/bootstrap` (kein 503), Anmeldung, Bestandsbericht,
   historische Namen und PDF prüfen. Mit einer autorisierten Testeinheit
   identischen/abweichenden Reimport, erste Berichtsanlage und Bearbeitung
   prüfen: Identisch bleibt fachlich unverändert; Abweichungen warnen ohne
   Überschreiben; eine neue Einheit widerruft den Gesamtabschluss.
   Browser vollständig neu laden lassen. Erst dann die Sperre aufheben.

**Rollback von 005:** Schreibsperre wieder beziehungsweise weiterhin aktiv
halten. Der sichere Rückweg ist die Wiederherstellung der vollständigen
Datenbank-/Schemasicherung **von vor 005** zusammen mit dem dazugehörigen
PHP- und Browserstand; anschließend Browser neu laden und prüfen.
Die beiden zusätzlichen Pflichtspalten dürfen nicht unverändert bleiben,
während nur alter PHP-Code zurückkopiert wird. Kein improvisierter Default
für fehlende Namen und kein erneuter Import der Migration über den Bestand.
Nach zwischenzeitlichen produktiven Schreibzugriffen würde die Sicherung
diese neuen Daten verlieren: Verlust ausdrücklich bewerten/freigeben oder
stattdessen unter Sperre eine vorwärtsgerichtete Korrektur wählen.
Migrationsvermerke müssen zum wiederhergestellten Schema passen.

## 11. Rollback

Für einen Stand mit Migration 005 gelten zwingend die oben beschriebenen
releasebezogenen Schritte; bloßes Zurückkopieren älterer PHP-Dateien reicht
wegen der zusätzlichen Pflichtspalten nicht aus.

1. Vor jeder Aktualisierung eine Datenbanksicherung und eine Kopie der bisherigen Anwendungsdateien erstellen.
2. Bei einem reinen Anwendungsfehler die vorherigen Versionen von `.htaccess`, `api.php`, `constants.php`, `support.php`, `public/index.html`, `public/app.js` und `public/styles.css` wiederherstellen.
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
| PDF-Export liefert HTTP 503 | Prüfen, ob die PHP-Erweiterung `iconv` aktiviert ist |
| Passwort-E-Mail kommt nicht an | `app_url`, `mail_from`, PHP `mail()`, Spamordner und Mailprotokoll des Hosters prüfen |
| GitHub-Deployment findet Secrets nicht | Environment-Name `hiba`, Secret-Namen und Environment-Freigabe prüfen |
| SFTP-Deployment schlägt fehl | Hostname, `SFTP_PORT`, Benutzer, Schlüssel oder Passwort, aktuellen `SFTP_KNOWN_HOSTS`-Eintrag und ein vorhandenes `SFTP_PATH` prüfen |

Zugangsdaten, Einrichtungstoken, Sitzungstoken und DIVERA-Schlüssel dürfen bei der Fehlersuche nicht in Issues oder Protokollauszüge kopiert werden.

## Weiterführende Dokumentation

- [Architektur](ARCHITEKTUR.md)
- [Datenmodell](../DATENMODELL.md)
- [Security Review](../SECURITY-REVIEW.md)
- [Changelog](../CHANGELOG.md)
