# Einsatzberichte

Kleine mandantenfähige Webanwendung für Einsatzberichte von Feuerwehr-Einheiten.

## Start

Voraussetzung: Node.js 22.5 oder neuer.

```powershell
npm start
```

Danach `http://localhost:3000` öffnen. Beim ersten Aufruf werden Wehr, erste
Einheit und Wehrführung angelegt. Die SQLite-Datenbank liegt unter
`data\app.db`.

```powershell
npm test
```

DIVERA wird je Einheit unter **DIVERA** mit dem Access-Key aus
**Verwaltung → Einstellungen → Schnittstellen → API** verbunden.
Die Anbindung liest ausschließlich Einsätze und Fahrzeuge per HTTP `GET`;
der Import speichert Daten nur lokal und verändert nichts in DIVERA.
Mitglieder werden je Einheit aus `pull/all` synchronisiert. Personen mit
derselben DIVERA-ID werden über mehrere Einheiten gemeinsam geführt und im
Einsatzbericht einem importierten Fahrzeug oder „ohne Fahrzeug“ zugeordnet.
Qualifikationen werden dabei aus dem Qualifikationskatalog der Einheit
aktualisiert.

## Datenbank einmalig zurücksetzen

Server beenden und anschließend im Projektverzeichnis ausführen:

```powershell
Remove-Item .\data\app.db
```

Beim nächsten `npm start` beginnt die Ersteinrichtung mit einer neuen
Datenbank. Diese Aktion löscht alle Benutzer, Einsätze und Berichte endgültig.
# ebmanager
