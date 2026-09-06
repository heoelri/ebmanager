# Security Review

## API-Vertrag und Eingabevalidierung vom 6. September 2026 (#92)

Der gezielte Integrationsreview umfasst JSON-Eingaben, lokale IDs, optionale
Berichtsdaten, native Antwortstrukturen, bekannte Unique-Konflikte und die
zugehörigen Browseraufrufe. Er ersetzt keinen vollständigen Penetrationstest.
Schema, Rollenmodell und erfasste personenbezogene Daten bleiben unverändert.

Schreibende Anfragen werden vor fachlichen Änderungen als JSON-Objekt
eingelesen. Verschachtelte Objekte bleiben von Listen unterscheidbar;
falsch typisierte Kontakte, Klassifikationen oder Besatzungseinträge werden
nicht mehr in leere Werte oder andere IDs umgewandelt. Die bestehenden
Größen-, Origin-, Rollen- und Mandantengrenzen bleiben erhalten. Die
Revisions- und Sperrreihenfolge aus #86 wird nicht verändert. Auch eine
erst innerhalb der Transaktion erkannte ungültige Besatzung nimmt die
Berichtsanlage und Revisionsänderungen vollständig zurück.

Lokale IDs müssen ohne Rundung als PHP-Integer und JavaScript-Integer
darstellbar sein; Boolesche Werte, Fließkommazahlen, Suffixe, führende Nullen
und Überläufe sind keine IDs. Opake DIVERA-IDs bleiben Texte.
Allgemeine Textskalare behalten die ausdrücklich dokumentierte
Kompatibilitätskonvertierung. Passwörter werden dagegen nur als Strings
angenommen und nicht getrimmt; NUL-Zeichen werden abgewiesen.
Zulässige optionale Leerwerte und bisher unterstützte ein- oder zweistellige
Sekundenbruchteile bleiben erhalten.

Bekannte Eindeutigkeitsverletzungen werden anhand von schreibender Tabelle
und Constraint einer fachlichen HTTP-409-Meldung zugeordnet. Unbekannte
Datenbankfehler bleiben HTTP 500 mit `Interner Fehler`. Allgemeine Fehlerlogs
enthalten nur Fehlerklasse beziehungsweise SQLSTATE und numerischen
Fehlercode, nicht die PDO-Rohmeldung, SQL-Parameter oder sensible Inhalte.

Die Rollenprojektionen ändern sich durch native Listen und Objekte nicht.
PDFs verwenden dieselben sichtbaren Daten weiter. Der Browser prüft die
erwarteten Strukturtypen; alte doppelt kodierte Antworten führen zu einer
sichtbaren Meldung statt zu geleerten Bearbeitungsformularen. Es gibt keine
automatischen Wiederholungen oder zusätzlichen gespeicherten Entwurfskopien.

Die vorhandenen Regressionen decken ungültige Wurzel-/Feldtypen, Grenz-IDs,
unveränderte Daten nach HTTP 400, fachliche und unbekannte Unique-Konflikte,
native Antworttypen, Zeitformate, Sortierungsgleichstände und die bisherigen
fünf echten Parallelitätsszenarien ab. Die vollständigen isolierten
HTTP-/SMTP- und Apache-/MySQL-Suiten bestanden im Implementierungsreview.
Nach der Kompatibilitätsnacharbeit bestand die Apache-/MySQL-Suite erneut
mit frischem Volume und aktivierten PHP-Assertions. PHP-/JavaScript-Syntax
und die erweiterten nativen Browser-Regressionsfälle bestanden ebenfalls.
Produktive oder bestehende Entwicklungsdaten wurden dafür nicht verwendet.

Die Formatierung alter `DATETIME`-Werte korrigiert keine früheren
Zeitzonenfehler; #87 bleibt offen. Die Umstellung verlangt einen gemeinsamen
PHP-/Browserstand im Wartungsfenster, aber keine neue Migration. Die
verbindlichen Schritte einschließlich Rollback stehen unter
[API-Vertrag umstellen](docs/WEBSPACE-DEPLOYMENT.md#json-antworttypen-und-eingabevalidierung-umstellen-92).

## Revisionsschutz für Berichte vom 6. September 2026 (#86)

Die Änderung schützt sensible Berichtsinhalte vor verlorenen parallelen
Bearbeitungen und vor wiederholten Workflowaktionen nach einem vollständigen
Statuszyklus. Monotone ganzzahlige Revisionen ersetzen dabei keine
Berechtigungsprüfung: Mandant, Rolle, Autor und Einheitszuordnung werden weiter
serverseitig geprüft. Einsatzrevision und Gesamttext werden nur der Wehrführung
ausgegeben; sichtbare Einheitsberichte enthalten ausschließlich ihre eigene
Revision. Geheimnisse und zusätzliche personenbezogene Daten werden nicht
erfasst oder protokolliert.

Bearbeitung, Erstellung, Workflow, Konsolidierung und Import sperren zuerst
den Einsatz und danach Berichte. Die Versionsprüfung erfolgt unter diesen
Sperren vor Text-/Besatzungs-/Fahrzeugänderungen oder Historienschreibzugriffen.
Die Konsolidierung prüft neben dem Gesamtstand die vollständige Menge der
geladenen Quellberichts-IDs und -Revisionen. Rückgaben, erneute Übergaben,
neue Berichte, zusätzliche Einheiten und Neuimporte widerrufen alte Stände.
Konflikte rollen vollständig zurück und lösen keine Workflow-Mail aus.
DIVERA bleibt ausschließlich per GET lesend angebunden.

Die unabhängige Nachprüfung fand einen Deadlock im ersten Revisionsstand:
Der Vollabgleich hielt eine Mitgliedssperre und wartete auf den Einsatz,
während eine Berichtsspeicherung den Einsatz hielt und für ihre Besatzung
auf dasselbe Mitglied wartete. Der Vollabgleich führt deshalb jetzt alle
Alarmimporte in stabiler DIVERA-ID-Reihenfolge **vor** dem Mitglieder- und
Fahrzeugabgleich aus. Die vorhandenen Upserts sperren dabei auch gleichzeitig
neu angelegte Einsätze; die Lösung verlässt sich nicht auf eine ungesicherte
Bestandsliste. Ein Stammdatenfehler rollt weiterhin die gesamte Transaktion
einschließlich Alarmimporten und Revisionserhöhungen zurück. Es werden keine
Deadlocks abgefangen, als Erfolg ausgegeben oder pauschal wiederholt.

Die neue Apache-Regression startet echte parallele API-Anfragen mit Besatzung
und kontrollierter MySQL-Mitgliedssperre. Sie verlangt anhand konkreter
Transaktions-, Sperr- und Datensatz-IDs die Warteketten auf `members.PRIMARY` und
`incidents.PRIMARY`. Startet das Speichern zuerst, gelingen Speicherung und
Vollabgleich; startet der Vollabgleich zuerst, erhält der veraltete Editor
HTTP 409. Beide Reihenfolgen werden zusätzlich mit einer neuen
Berichtserstellung geprüft, die jeweils erfolgreich bleibt. Eine weitere
Warteprobe legt einen noch nicht sichtbaren Alarm parallel an: Während der
Vollabgleich auf dessen eindeutigen Einsatzschlüssel wartet, kann ein Bericht
zu einem anderen Einsatz mit demselben Mitglied erfolgreich entstehen.
Damit deckt der Test auch die Lücke einer bloßen Vorabfrage bestehender
Einsatz-IDs ab. Die Regression läuft im vorhandenen Apache-/HTTPS-Test;
der lokale einzelne PHP-Testserver
kann keine zwei HTTP-Anfragen gleichzeitig bearbeiten.

Die CI-Nachprüfung reproduzierte unter MySQL 8.4.11 eine unzuverlässige
Metadatenannahme im Test, keinen erneuten Laufzeit-Deadlock: Bei der Umwandlung
einer impliziten Insertsperre konnte `BLOCKING_THREAD_ID` auf den wartenden
Thread zeigen, obwohl `BLOCKING_ENGINE_TRANSACTION_ID` weiterhin korrekt den
Einfüger bezeichnete. Ein offener Lese-Snapshot hielt zudem einen alten
Indexeintrag zurück; dann wartete der Upsert auf dessen gemeinsame
Duplikatprüfsperre statt auf eine exklusive Sperre des neuen Indexeintrags.

Der Test bestimmt die eigene Transaktion deshalb über eine explizite
Tabellenabsichtssperre und verfolgt danach die exakten InnoDB-Transaktions-
und Sperr-IDs beider Seiten der Wartebeziehung. Er verlangt weiterhin
wartende Datensatzsperren auf gehaltenen Sperren der bekannten Transaktion
und der richtigen Tabelle/Indizes. Beim parallelen Insert berührt diese
Transaktion nur den ausdrücklich geprüften Test-Einsatzschlüssel; der Test
vergleicht dessen gerenderte zusammengesetzte `LOCK_DATA` nicht mehr mit
einem fest kodierten Text. Die unabhängige Besatzungserstellung muss weiterhin
vor Freigabe der Insertsperre erfolgreich sein. Zeitlimits bleiben unverändert.
Fehlerdiagnosen enthalten nur Sperrmetadaten dieser Transaktion in der isolierten
Testdatenbank, keine SQL-Texte, Zugangsdaten oder Berichtsinhalt.
Die unveränderten fünf Parallelitätsszenarien liefen mit dieser Korrektur sowohl
normal als auch mit einem separat offengehaltenen Lese-Snapshot erfolgreich.
Danach bestand die vollständige Apache-/HTTPS-Smoke-Suite erneut mit einem
frischen isolierten MySQL-8.4.11-Volume; Shellsyntax und `git diff --check`
waren ebenfalls erfolgreich. Die Sperr- und Fachlogik der Anwendung wurde
hierfür nicht geändert. Eine zusätzliche Review-Korrektur formuliert den
HTTP-409-Hinweis kontextneutral für den geladenen Stand; Statuscode,
Versionsprüfung und Erhalt ungespeicherter Eingaben bleiben unverändert.

Der Browser bewahrt Texte, Rückgabekommentare und Ressourcenauswahl bei HTTP 409
im geöffneten Formular; er lädt nicht automatisch nach und versendet keinen
automatischen zweiten Versuch. Die Wiederherstellung ist ausdrücklich manuell.
Sensible Entwürfe werden nicht in Local Storage oder weiteren Inhaltskopien
persistiert.

Die Regressionen prüfen zwei Bearbeiter einschließlich unveränderter
Besatzung/Zusatzfahrzeuge, echte MySQL-Wartebeziehungen auf den primären
Einsatzdatensatz, alle vier Workflowaktionen nach ABA-Zyklen, parallele
Gesamttexte, veraltete Quellen trotz aktueller Einsatzrevision, Pflichtrevisionen,
Import-/Zuordnungsinvalidierung und Bootstrap ohne neue Spalten.
Der vorhandene Migrationscheck prüft Bestandsdaten und den Erhalt bereits
erhöhter Revisionen bei wiederholten Läufen. Browserchecks prüfen die
gesendeten Vorbedingungen und den Erhalt offener Formulare.

Rollout-Voraussetzung ist Migration 004 vor gemeinsamem PHP-/Browserdeployment
im Wartungsfenster; alter PHP-Code pflegt keine Revisionen. Die verbindlichen
Schritte einschließlich Rollback stehen in `docs/WEBSPACE-DEPLOYMENT.md`.

Validierung: PHP-8.2-Syntax, JavaScript-Syntax, `node test/frontend.mjs`,
Shellsyntax und `git diff --check` sind erfolgreich. Der bestehende
Migrationscheck lief in seinem frischen Compose-Projekt erfolgreich.
Die vollständige Smoke-Suite lief sowohl gegen Apache/HTTPS als auch mit
lokalen PHP-/SMTP-Testservern unter PHP 8.5 und MySQL 8.4 erfolgreich, jeweils
mit neu angelegtem isoliertem Datenbankvolume. PHP-Assertions waren aktiviert;
Produktivsysteme und bestehende Entwicklungsdatenbanken wurden nicht verwendet.

Die Sperrreihenfolge-Nacharbeit wurde erneut mit der vollständigen
Apache-/HTTPS-Smoke-Suite auf einem frischen isolierten MySQL-8.4-Volume
erfolgreich geprüft, einschließlich aller fünf neuen Parallelitätsszenarien
und Rücknahme bereits ausgeführter Importe bei einem Stammdatenfehler.
PHP-8.2-Syntax, Shellsyntax und `git diff --check` waren ebenfalls erfolgreich.

## Einmallinks und konsolidierte Texte vom 6. September 2026

Der erneute Vollreview bestätigte zwei vorbestehende Schwachstellen hoher
Schwere: Alte Einladungs-/Wiederherstellungslinks überlebten administrative
Passwort- oder E-Mail-Änderungen (#99), und die Einsatzliste gab
`consolidated_text` auch an niedrigere Rollen aus (#100).

Die Benutzerbearbeitung widerruft ausstehende Einmallinks nun zusammen mit
der Passwort-/E-Mail-Änderung in derselben Transaktion. Passwortänderungen
widerrufen weiterhin alle Sitzungen; reine Profiländerungen erhalten
gültige Links. Tokenausstellung, Bestätigung, Neueinladung und
Benutzerbearbeitung sperren zuerst den Benutzer und anschließend seine
Token. Eine Bestätigung prüft den Token nach dieser Sperre erneut; eine
Anforderung sperrt anhand der zuvor ermittelten Benutzer-ID den
Primärdatensatz und vergleicht die aktuelle Zieladresse erneut mit der
angefragten Adresse. Eine Sperre über den E-Mail-Sekundärindex wird
vermieden, damit parallele Adressänderungen keinen umgekehrten
Index-Sperrpfad erzeugen. Ein nachträglich
fehlgeschlagener Mailversuch entfernt nur seinen eigenen Token-Hash.
Die Neueinladung behält ihr Rollback bei fehlgeschlagener Mailannahme.
Abgelaufene Token werden weiterhin bereinigt. Diese separate
Autocommit-Anweisung läuft vor der Benutzertransaktion, damit keine
Benutzersperre während einer kontenübergreifenden Bereinigung gehalten
wird. Nicht abgelaufene Links werden dabei nicht verändert.
Alle drei Tokenaussteller (Wiederherstellung, Einladung und Neueinladung)
schreiben `requested_at` ausdrücklich mit `UTC_TIMESTAMP()`, ebenso wie
die Ablaufzeit. Die Fünf-Minuten-Sperre verwendet damit für neue Token
dieselbe Zeitbasis unabhängig von der MySQL-Session-Zeitzone. Bestehende
Zeitwerte werden nicht pauschal umgerechnet; die übrigen Zeitfragen aus
#87 bleiben getrennt von diesen Sicherheitskorrekturen.

Die Einsatzliste verwendet eine explizite Spaltenprojektion.
`consolidated_text` wird ausschließlich für `wehrleitung` abgefragt.
Dies gilt sowohl für abgeschlossene Gesamtberichte als auch für nach einer
Rückgabe erhaltene Arbeitsstände; Status und zulässige Einheitsdaten bleiben
für frühere Rollen verfügbar. Die bestehenden PDF- und
Einzelberichtsberechtigungen bleiben unverändert.

Die fokussierten Regressionen in `test/smoke.sh` umfassen Passwort-only-,
E-Mail-only-, kombinierte und reine Profiländerungen, Kontext und Bestätigung
alter Links, auf einer MySQL-Benutzersperre wartende Anforderungen und
Bestätigungen sowie die Sicht beider niedrigeren Rollen auf abgeschlossene
und invalidierte Mehr-Einheiten-Gesamtberichte. Für diese Korrekturen werden
keine weiteren personenbezogenen Daten, Geheimnisprotokolle oder
Abhängigkeiten eingeführt.

Die Review-Nacharbeit ergänzt die Bereinigung abgelaufener Token bei
gleichzeitigem Erhalt gültiger Links. Der Parallelitätstest übernimmt die
explizit konfigurierte `DB_DSN` unverändert; ohne Vorgabe berücksichtigt
der gemeinsame Standard den `TEST_DB_HOST` des Compose-Betriebs.
Die vollständige HTTP-/MySQL-/SMTP-Suite wurde zusätzlich mit expliziter
PDO-Verbindung zu einem isolierten MySQL auf Port 3307 erfolgreich
ausgeführt; die Apache-/HTTPS-Suite verwendet weiterhin den Standard.
Zusätzliche vollständige HTTP-/MySQL-/SMTP-Durchläufe mit den
MySQL-Zeitzonen `+02:00` und `-05:00` prüfen die UTC-Anforderungszeiten
aller drei Tokenaussteller, die Gültigkeitsdauern und den Erhalt eines
gerade ausgestellten Wiederherstellungslinks bei sofortiger Wiederholung.

Die vorhandene HTTP-/MySQL-Suite einschließlich SMTP-Szenarien und die
Apache-/HTTPS-Suite wurden in getrennten, frisch erstellten lokalen
Compose-Umgebungen erfolgreich ausgeführt. Die MySQL-Szenarien beobachten
über `performance_schema` die tatsächliche Wartebeziehung zur eigenen
Testverbindung und verlangen die Tabelle `users` sowie den Index `PRIMARY`
in der konfigurierten Datenbank. Ein beliebiger anderer wartender
`SELECT` genügt nicht. Danach prüfen sie die erneute Adress-/Tokenprüfung
nach dem Commit der parallelen Kontoänderung.

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

Der Screenshot-Workflow läuft auf `pull_request` und führt den Code des Pull Requests niemals über `pull_request_target` aus. Er verwendet ausschließlich die versionierten Demo-Daten und offensichtlich unechte lokale Zugangsdaten. Screenshots werden für alle PRs mit ausschließlich lesenden Rechten als Artefakt gespeichert.

Die direkte Einbettung läuft getrennt über `workflow_run` mit der unveränderlich vom Standardbranch geladenen Workflowdefinition. Nur erfolgreiche Screenshot-Läufe für Quell-Branches desselben Repositorys werden verarbeitet. Dieser zweite Workflow lädt ausschließlich das erzeugte Artefakt, führt keinen PR-Code aus und erhält die für GitHub-Medienanhänge erforderlichen Schreibrechte. GitHub CLI 2.99.0 wird mit fester Version und SHA-256-Prüfsumme geladen; ein persönlicher Zugriffstoken oder Deployment-Secret wird nicht verwendet. Fork-PRs erreichen den schreibenden Job nicht und erhalten weiterhin ausschließlich das Artefakt.

## Wehrweite Fahrzeugnamen vom 4. September 2026

Die Auflösung fremder DIVERA-Fahrzeug-IDs liest ausschließlich bereits synchronisierte Stammdaten von Einheiten mit derselben `organization_id`. Die aktuell abgefragte Einheit bleibt für die Eigentumskennzeichnung maßgeblich; ergänzte Fahrzeuge bleiben `own: false` und damit als Besatzungsziel unzulässig. Treffer anderer Organisationen werden ignoriert, und bei mehreren Treffern innerhalb der Organisation wird kein Klartext übernommen. Ein Smoke-Test prüft Mandantentrennung, Mehrdeutigkeits-Fallback und die Aktualisierung durch erneuten Import.

## Build-ID vom 3. September 2026

Die am 3. September 2026 ergänzte Build-ID enthält ausschließlich den validierten Commit-SHA beziehungsweise den lokalen Fallback „Entwicklung“. Automatische und manuelle Deployments schreiben den jeweils ausgecheckten `main`-Commit in `.build-id`; manuelle Läufe anderer Branches werden abgewiesen. Apache sperrt den direkten HTTP-Zugriff auf diese Datei. Die bereits rollenbeschränkte Systemübersicht gibt nur den validierten Wert aus und erweitert weder Konfigurations- noch Geheimniszugriff.

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
- Das Deployment läuft nach erfolgreichen Tests eines Pushs auf `main` oder
  manuell ausschließlich für `main`, checkt den zugehörigen Commit aus und
  überträgt ausschließlich per SSH gesichertes SFTP mit geprüftem Host-Key.
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
