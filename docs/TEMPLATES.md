# Scrivere un template

Un template è una cartella che l'app riempie con i dati della partita e salva come PNG. Il formato completo è in
`docs/plan/01-architecture.md` §4 (manifest) e §5 (dati); questa pagina è la versione pratica.

Per l'uso dell'app, cioè come importare o anteprima un template, vedi [USER-GUIDE.md](USER-GUIDE.md#template).

```
mio-template/
├── manifest.json     identificativo, nome, versione, formato, dimensioni, tipo, uso, campi richiesti, limiti
├── template.html     Mustache semplice, un solo elemento radice di esattamente larghezza × altezza px
└── assets/
    ├── club-logo.png        obbligatorio: lo stemma della società, sempre in questo percorso
    └── fonts/               file dei font e la loro licenza (OFL.txt)
```

## Manifest

```jsonc
{
  "id": "mio-template",            // identificativo unico, senza spazi
  "name": "Post · Mio modello",
  "version": "1.0.0",
  "format": "post",                // "post" (1080×1350) oppure "story" (1080×1920)
  "width": 1080, "height": 1350,
  "kind": "single",                // "single": una partita per immagine; "list": più partite per immagine
  "purpose": "prematch",           // "prematch" | "programme" | "halftime" | "fulltime" | "other"
  "pageSize": null,                // solo per "list": righe per immagine (programma = 10)
  "requires": ["time", "venue"],   // campi che devono esserci, altrimenti l'app mostra un avviso
  "limits": { "teamName": 16, "venue": 14, "category": 22 }   // lunghezza massima in caratteri
}
```

Campi che si possono indicare in `requires`: `time`, `venue`, `round`, `competition`, `score`, `halfTime`, `notes`.

## Regole

- **Niente rete.** Nessun URL esterno, nessuna CDN, nessun link a Google Fonts. I font sono file in `assets/fonts/`,
  dichiarati con `@font-face` e percorso relativo (`url('assets/fonts/Barlow-Bold.ttf')`).
- **Solo Mustache semplice**: `{{valore}}`, `{{#sezione}}…{{/sezione}}`, `{{^invertita}}…{{/invertita}}`. Non ci sono funzioni.
  Il maiuscolo si ottiene con il CSS (`text-transform: uppercase`).
- **Il testo arriva già tagliato** ai `limits` del manifest. I limiti sono le stringhe più lunghe che il layout regge,
  scelte guardando un'immagine di prova (il dato `single-long-name`).
- Nelle storie, il contenuto importante sta lontano dai 250 px in alto e in basso (interfaccia di Instagram).
- È permesso uno script `<script>` inline (senza `src`). Se il layout deve finire prima, imposta
  `window.__ready` con una promessa. Il template del programma la usa per rimpicciolire un titolo troppo largo.
- **Testi lunghi**: sui box con nomi, campo e note usa `min-width: 0` e `overflow-wrap: anywhere`; limita le note con
  `-webkit-line-clamp`; metti `flex-shrink: 0` su punteggi e orari; mostra `{{#match.isPostponed}}` / `{{#match.isCancelled}}`
  come etichetta (Rinviata / Annullata).
- **Escape automatico**: `{{x}}` scrive il testo escapato. Usa sempre `{{}}` per ogni testo dell'utente.
- Il template viene importato solo se è valido: il manifest è controllato, la radice ha le dimensioni giuste,
  lo zip non contiene percorsi con `..` né link simbolici, la dimensione è sotto i 20 MB, ci sono al massimo
  200 file e solo di tipi consentiti.

## Dati disponibili

Un template `single` riceve `{club, match}`. Un template `list` riceve
`{club, title, dateLabel, rows[], page, hasPages, pageLabel}`, dove ogni riga è una `match`.

| Campo | Significato |
|---|---|
| `club.name`, `club.shortName`, `club.accent`, `club.season`, `club.handle` | Nome, nome breve, colore, stagione, account social (può essere vuoto). Si impostano in Impostazioni › Società. Esempio: `ASD Esempio`, `Esempio`, `#CF3326`, `2026/27`, `@account` |
| `club.logo` | `assets/club-logo.png` |
| `match.category` | il nome della nostra squadra (nelle righe di una lista: l'etichetta breve) |
| `match.round`, `match.competition` | numero e testo, assenti se non impostati |
| `match.dateLong`, `match.dateShort` | `Domenica 22 novembre`, `Dom 22 nov` |
| `match.time` | `15:30`, assente se non impostato |
| `match.venue` | assente se vuoto |
| `match.isHome`, `match.isAway` | booleani |
| `match.home`, `match.away` | le due squadre, nell'ordine della partita |
| `match.us`, `match.opponent` | le stesse due squadre, per ruolo |
| lato: `name`, `displayName`, `initials`, `logo`, `isUs`, `score`, `halfTimeScore` | `logo` manca se la squadra non ne ha uno |
| `match.hasScore`, `match.hasHalfTime` | entrambe le squadre hanno quel punteggio |
| `match.halfTime`, `match.notes` | risultato del primo tempo e note, testo libero (assenti se vuoti) |
| `match.isPostponed`, `match.isCancelled` | booleani |

I loghi degli avversari sono `_logos/<file>`, lo stemma della società è `assets/club-logo.png`: entrambi vanno
direttamente in `<img src>`.

## Schemi

- **Testo opzionale**: `{{#match.round}}Giornata {{match.round}}{{/match.round}}`.
- **Orario o trattino**: `{{#match.time}}{{match.time}}{{/match.time}}{{^match.time}}—{{/match.time}}`.
- **Campi vuoti = campi assenti.** Il motore di rendering toglie le stringhe vuote o fatte di soli spazi, quindi `{{#match.venue}}` e
  `{{^match.venue}}` funzionano come per un campo mancante.
- **Punteggi: usa sempre `match.hasScore` / `match.hasHalfTime`.** In Mustache i numeri, compreso lo 0, sono sempre
  veri, quindi una sezione sul punteggio non distingue "0" da "nessun punteggio" (e `{{^score}}` non scatta mai).
  `hasScore` dice se il punteggio c'è davvero:
  `{{#match.hasScore}}{{score}}{{/match.hasScore}}{{^match.hasScore}}–{{/match.hasScore}}`.
- **Casa e trasferta**: stampa `match.home` a sinistra e `match.away` a destra (o in prima e seconda riga), poi usa
  `{{#isUs}}…{{/isUs}}` dentro il lato per evidenziare la nostra squadra:
  `{{#match.home}}…{{displayName}}…{{/match.home}}`.
- **Logo o cerchio con le iniziali**:
  `{{#logo}}<img src="{{logo}}" alt="">{{/logo}}{{^logo}}<div class="circle">{{initials}}</div>{{/logo}}`.
- **Indicatore casa/trasferta in una riga di lista**: icona casa (`{{#isHome}}`) o auto (`{{^isHome}}`) in SVG inline.
- **Righe ripetute**: `{{#rows}}…{{/rows}}`; dentro, i campi sono quelli della riga (`{{category}}`,
  `{{opponent.displayName}}`).
- **Numero di pagina solo se le pagine sono più d'una**: `{{#hasPages}}{{pageLabel}}{{/hasPages}}`.

## Provarlo

```bash
swift run ss-tool preview Resources/Templates/<id> Resources/Fixtures/single.context.json
```

Il PNG finisce in `out/preview/`. Guardalo con questi dati di prova: `single`, `single-long-name`, `single-no-logo`,
`single-away`, `single-goalless` (gli zero devono vedersi), `single-no-time`. I template `list` usano `list` e
`list-23`. Il comando `preview` controlla il `manifest.json` e rifiuta quello non valido. È un controllo semplice,
non il renderer di produzione: prima di dire che un modello è pronto, controllalo nell'app con l'anteprima.

## Farsi disegnare un template nuovo

Non serve saper scrivere HTML: si può chiedere a Claude di disegnare un modello che rispetti questo formato.
Il modo più sicuro è dargli tutto il materiale in una sola richiesta:

1. questa pagina (`docs/TEMPLATES.md`), le regole e la tabella dei campi;
2. un file di dati di prova, per esempio `Resources/Fixtures/single-long-name.context.json`;
3. il logo della società e i font che vuoi usare, con la loro licenza OFL;
4. il formato (Post 1080×1350 o Story 1080×1920), il tipo (singolo o elenco) e lo scopo (pre-partita, programma, intervallo, risultato);
5. una foto o un bozzetto dell'idea, se ne hai uno.

Una richiesta di esempio, da adattare:

> Disegna un template Story per il risultato finale, formato 1080×1920, tipo singolo. Segui le regole in
> `docs/TEMPLATES.md`: niente URL esterni, solo Mustache semplice, font in `assets/fonts/`, testo escapato con `{{}}`.
> Usa i campi della tabella e il file `single-long-name.context.json` per controllare i nomi lunghi.
> Il contenuto importante deve stare fra 250 px dall'alto e 250 px dal basso. Restituisci la cartella con
> `manifest.json`, `template.html` e `assets/`, con `requires` e `limits` compilati.

Quando Claude restituisce la cartella:

1. controlla con `swift run ss-tool preview` su tutti i dati di prova, guardando ogni PNG;
2. verifica che non ci siano link esterni: `grep -rnE "https?://" mio-template/` non deve trovare nulla
   (a parte, al massimo, un riferimento nel testo della licenza OFL);
3. importa la cartella o uno zip da **Template › Importa template…** e fai l'anteprima nell'app.

Se un'immagine mostra testo tagliato o sovrapposto, chiedi a Claude di correggere il layout o di abbassare il
limite nel manifest, e poi rigenera l'anteprima.
