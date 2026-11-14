# Itinera

App iOS personale per organizzare i viaggi. Stessa catena di OBD Dash: SwiftUI, progetto generato con XcodeGen, build nel cloud con GitHub Actions, installazione con Sideloadly.

## Stato: v0.1

- **Viaggi:** elenco dei viaggi con date, valuta locale e budget in euro. Al primo avvio c'è già Praga (7-11 dicembre 2026) con i luoghi principali.
- **Giorni:** programma giorno per giorno, tappe con orario, luogo, costo e note; spunta delle tappe fatte, evidenza della prossima, distanza tra una tappa e l'altra con indicazioni a piedi o con i mezzi in Mappe di Apple.
- **Mappa:** tutti i luoghi del viaggio, filtro per categoria, posizione attuale.
- **Luoghi:** ricerca di attrazioni, musei e ristoranti nella città (dati di Mappe di Apple), con prezzo e note.
- **Spese:** spese registrate in valuta locale o in euro, totale contro budget, riepilogo per categoria.
- **Cambio:** convertitore, cambio di riferimento BCE scaricato da frankfurter.dev e salvato per l'uso senza rete.

Ogni prezzo è mostrato in valuta locale e in euro. Tutti i dati restano sul telefono (`trips.json` nei documenti dell'app).

## Non ancora presenti

- Orari, fermate e prezzi dei mezzi dentro l'app (per ora si passa da Mappe di Apple).
- Recensioni e voti dei ristoranti (Mappe di Apple non li fornisce alle app).

## Come ottenere l'app

Come per OBD Dash: ogni push su `main` avvia la build; dalla scheda **Actions** scarica `Itinera-ipa`, estrai `Itinera.ipa` e installala con Sideloadly.

## Struttura

- `project.yml`: definizione del progetto per XcodeGen
- `Sources/Models.swift`: dati (viaggio, luogo, tappa, spesa) e formattazione dei prezzi
- `Sources/AppStore.swift`: salvataggio, cambio valuta, viaggio di esempio
- `Sources/ItineraApp.swift`: avvio, elenco viaggi, schermata del viaggio
- `Sources/ItineraryView.swift`, `PlacesView.swift`, `MoneyViews.swift`: le cinque sezioni
