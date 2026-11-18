# Installare Sergnanese Social / Installing Sergnanese Social

> Stato: i passaggi del primo avvio (Gatekeeper) non sono ancora stati verificati su macOS 27 con un `.dmg` scaricato dal browser. Vanno controllati e questo file corretto.
> Status: the first-launch (Gatekeeper) steps have not yet been checked on macOS 27 with a browser-downloaded `.dmg`. They must be verified and this file corrected.

## Italiano

### Requisiti

- Mac con chip Apple (M1 o successivi). I Mac Intel non sono supportati.
- macOS 15 o successivo.

### Installazione

1. Apri la pagina **Releases** del repository su GitHub e scarica il file `Sergnanese-Social-<versione>.dmg` dell'ultima versione.
2. Apri il `.dmg` con un doppio clic.
3. Trascina **Sergnanese Social** sulla cartella **Applicazioni** nella stessa finestra.
4. Espelli il disco dal Finder.

### Primo avvio

L'app non e' notarizzata da Apple, quindi macOS la blocca la prima volta. Si approva una volta sola:

1. Apri **Sergnanese Social** dalla cartella Applicazioni. macOS mostra un avviso e non la apre.
2. Vai in **Impostazioni di Sistema > Privacy e sicurezza**, scorri fino alla sezione "Sicurezza".
3. Accanto al nome dell'app clicca **Apri comunque** e conferma con la password o Touch ID.

In alternativa, da Terminale (toglie il blocco del download):

```
xattr -cr "/Applications/Sergnanese Social.app"
```

### Aggiornare

Scarica il `.dmg` della versione piu' recente dalla pagina Releases (o dal menu Aiuto > "Scarica aggiornamenti...") e trascinalo in Applicazioni, sostituendo la versione precedente. I dati non vengono toccati. La prima apertura puo' richiedere di nuovo l'approvazione.

### Dove sono i dati

`~/Library/Application Support/Sergnanese Social/` (database, backup, loghi, modelli). Le immagini generate vanno in `~/Pictures/Sergnanese Social/` salvo diversa scelta nelle Impostazioni. Per aprire la cartella: Finder > Vai > Vai alla cartella...

### Disinstallare

Sposta **Sergnanese Social** dalla cartella Applicazioni nel Cestino. Per cancellare anche i dati, sposta nel Cestino la cartella dei dati indicata sopra (e' irreversibile: fai prima una copia se serve).

## English

### Requirements

- A Mac with Apple silicon (M1 or later). Intel Macs are not supported.
- macOS 15 or later.

### Install

1. Open the repository's **Releases** page on GitHub and download `Sergnanese-Social-<version>.dmg` from the latest release.
2. Double-click the `.dmg`.
3. Drag **Sergnanese Social** onto the **Applications** folder in the same window.
4. Eject the disk in Finder.

### First launch

The app is not notarized by Apple, so macOS blocks it the first time. You approve it once:

1. Open **Sergnanese Social** from Applications. macOS shows a warning and does not open it.
2. Go to **System Settings > Privacy & Security** and scroll to the "Security" section.
3. Next to the app name click **Open Anyway** and confirm with your password or Touch ID.

Alternatively, from Terminal (clears the download quarantine):

```
xattr -cr "/Applications/Sergnanese Social.app"
```

### Update

Download the newest `.dmg` from the Releases page (or Aiuto > "Scarica aggiornamenti...") and drag the app into Applications, replacing the old one. Your data is untouched. The first launch may ask for approval again.

### Where the data lives

`~/Library/Application Support/Sergnanese Social/` (database, backups, logos, templates). Generated images go to `~/Pictures/Sergnanese Social/` unless you pick another folder in Settings. To open it: Finder > Go > Go to Folder...

### Uninstall

Move **Sergnanese Social** from Applications to the Bin. To delete the data as well, move the data folder above to the Bin (irreversible: copy it first if needed).
