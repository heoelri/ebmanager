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
# ebmanager
