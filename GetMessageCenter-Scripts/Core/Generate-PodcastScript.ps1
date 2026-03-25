#Requires -Version 5.1

# ==============================================================================
# Generate-PodcastScript.ps1
# Legge il JSON prodotto da Get-MessageCenterForAI.ps1, chiama GPT-4o mini
# su Azure AI Foundry e genera uno script podcast a due voci in italiano.
# ==============================================================================
# CONFIGURAZIONE
# ==============================================================================

# Endpoint e chiave del tuo deployment su Azure AI Foundry
# Trovali in AI Foundry → il tuo progetto → Deployments → GPT-4o mini → Endpoint
$AIEndpoint   = 'https://message-center-podcast-resource.cognitiveservices.azure.com'   # es. https://xxx.openai.azure.com
$AIKey        = 'C8yFQexFCD86F9UMLs3QxSPjo9RFLBPie2xcJ5T7xuEiMQtcvLrZJQQJ99CCAC5RqLJXJ3w3AAAAACOG0lXh'
$DeploymentName = 'gpt-4o-mini'           # nome esatto del deployment in Foundry

# Cartelle — devono coincidere con quelle di Get-MessageCenterForAI.ps1
$OutputFolder  = 'C:\Script\GetMessageCenter\Output'
$PodcastFolder = 'C:\Script\GetMessageCenter\Podcast'

# ==============================================================================
# LETTURA JSON DI OGGI
# ==============================================================================

$JsonFile = Join-Path $OutputFolder ("messages_{0}.json" -f (Get-Date -Format "yyyy-MM-dd"))

if (-not (Test-Path $JsonFile)) {
    Write-Error "File JSON non trovato: $JsonFile — assicurati che Get-MessageCenterForAI.ps1 sia già stato eseguito oggi."
    exit 1
}

$Data = Get-Content $JsonFile -Raw | ConvertFrom-Json

if ($Data.messageCount -eq 0) {
    Write-Host "Nessun messaggio oggi — nessun podcast da generare."
    exit 0
}

Write-Host "Trovati $($Data.messageCount) messaggi. Generazione script podcast in corso..."

# ==============================================================================
# COSTRUZIONE DEL PROMPT
# ==============================================================================

# Pre-ordina i messaggi per priorità PRIMA di passarli al modello:
# Gruppo A: Retirement — il modello li troverà già in cima, non può ignorarli
# Gruppo B: azioni admin concrete (tag contiene "Admin impact" ma non Retirement)
# Gruppo C: tutto il resto
$GroupA = $Data.messages | Where-Object { $_.tags -match 'Retirement' }
$GroupB = $Data.messages | Where-Object { $_.tags -notmatch 'Retirement' -and $_.tags -match 'Admin impact' }
$GroupC = $Data.messages | Where-Object { $_.tags -notmatch 'Retirement' -and $_.tags -notmatch 'Admin impact' }
$OrderedMessages = @($GroupA) + @($GroupB) + @($GroupC)

Write-Host "Ordine priorità: $($GroupA.Count) retirement | $($GroupB.Count) admin impact | $($GroupC.Count) altri"

# Serializza i messaggi ordinati con bodyText troncato a 800 caratteri
# I testi originali sono verbosi (800-2000 parole): il modello legge tutto ma "dimentica"
# i messaggi in fondo. 800 caratteri catturano intro + impatto + date senza sprecare token.
$MessagesForPrompt = $OrderedMessages | ForEach-Object {
    $priority = if ($_.tags -match 'Retirement') { "GRUPPO A — RETIREMENT CRITICO" }
                elseif ($_.tags -match 'Admin impact') { "GRUPPO B — AZIONE ADMIN RICHIESTA" }
                else { "GRUPPO C — INFORMATIVO" }
    $actionNote = if ($_.actionRequired) { "SCADENZA AZIONE: $($_.actionRequired)" } else { "" }
    # Tronca il bodyText a 800 caratteri per ridurre i token mantenendo le informazioni chiave
    $shortBody = if ($_.bodyText.Length -gt 1200) { $_.bodyText.Substring(0, 1200) + "..." } else { $_.bodyText }
    @"
---
PRIORITA: $priority
Titolo: $($_.title)
Servizio: $($_.services)
Tag: $($_.tags)
Pubblicato: $($_.published) | Aggiornato: $($_.lastModified)
$actionNote
Contenuto (estratto):
$shortBody
"@
} | Out-String

$Today = Get-Date -Format "dd MMMM yyyy"

$SystemPrompt = @"
Sei un assistente specializzato nella produzione di podcast tecnici per professionisti IT italiani.
Il tuo compito e trasformare i messaggi del Microsoft 365 Message Center in uno script podcast a due voci,
in italiano, pensato per essere ascoltato in macchina durante il tragitto casa-lavoro (durata target: 10-14 minuti).

LE DUE VOCI:
- ALEX: il conduttore. Tono da radio mattutina, diretto, mai banale. Introduce ogni messaggio con una frase
  secca, poi fa domande reali: chiede implicazioni pratiche, rischi se non si agisce, confronti con il passato.
  VIETATO usare: "Dobbiamo considerare", "Dobbiamo menzionare", "Passiamo a parlare di", "ottimo", "interessante".
  OBBLIGATORIO: ogni sua domanda deve essere specifica al contenuto, non generica.
  Esempio sbagliato: "E quando sara disponibile questa funzione?"
  Esempio corretto: "Quindi chi ha gia configurato le policy MAM esistenti deve modificarle, o si applicano in automatico?"
- SARA: l'esperta tecnica. Risponde con precisione e dettaglio. Per ogni messaggio spiega:
  cosa cambia tecnicamente, chi e impattato, perche Microsoft lo sta facendo, cosa fare in concreto.
  Cita sempre date esatte, nomi di policy, ruoli, URL quando disponibili nel testo del messaggio.
  Non ripete mai quello che Alex ha appena detto. Non usa frasi di riempimento.

STRUTTURA OBBLIGATORIA:
1. INTRO (Alex, max 20 secondi):
   Esempio: "Buongiorno, oggi e il [data], abbiamo [N] aggiornamenti dal Message Center. Si parte."

2. CORPO - ogni messaggio DEVE seguire questo schema:

   SCHEMA BASE (tutti i messaggi, minimo 4 battute):
   Battuta 1 - ALEX: introduce servizio e contenuto in italiano discorsivo. Mai leggere il titolo originale inglese.
               Se e un "Updated" con timeline posticipata, lo dice esplicitamente.
   Battuta 2 - SARA: spiega cosa cambia tecnicamente, chi e impattato, contesto e motivazione Microsoft.
   Battuta 3 - ALEX: domanda specifica e contestuale (non generica) su timeline, impatto, rischi, prerequisiti.
   Battuta 4 - SARA: risponde con date precise, dettagli tecnici, azione concreta.

   SCHEMA ESTESO per Gruppo A e B (6 battute):
   Battuta 5 - ALEX: domanda di follow-up specifica (es. "e chi usa ancora X? deve fare qualcosa prima?")
   Battuta 6 - SARA: risposta con dettaglio aggiuntivo o edge case rilevante.

   REGOLE DI PRIORITA E SPAZIO - ORDINE RIGIDO:
   Gruppo A (tratta per primi): tag "Retirement" o data di fine supporto esplicita - 6 battute minime obbligatorie.
   Gruppo B (tratta secondi): azioni admin concrete richieste - 4-5 battute.
   Gruppo C (tratta ultimi): nuove funzionalita senza impatto immediato - 3-4 battute.
   Messaggi puramente automatici (es. aggiornamento canale apps): massimo 2 battute, poi avanti.

   REGOLA PER VOLUMI ALTI: se i messaggi totali sono piu di 12, i messaggi Gruppo C possono essere ridotti
   a 3 battute minime per garantire che Gruppo A e B mantengano il loro spazio pieno. Mai ridurre A e B.

   TUTTI i messaggi devono comparire. Non omettere nessun messaggio.

3. RIEPILOGO AZIONI (Sara, 90 secondi):
   Sara elenca in modo parlato tutti i messaggi che richiedono un'azione admin concreta.
   Per ogni azione: nome del servizio, azione specifica, data scadenza esatta.
   VIETATO essere generici: no "configurare le policy", si "abilitare la policy CustomSyncRootFolderName
   tramite Group Policy con il valore del nome cartella desiderato, entro il rollout di meta aprile".
   Deve sembrare un promemoria naturale parlato, non una lista letta.

4. OUTRO (Alex, 10 secondi): chiusura asciutta.
   Esempio: "Questo e tutto per oggi. Buona giornata."

REGOLE STILISTICHE:
- Solo italiano parlato. Zero elenchi, zero markdown, zero titoli nello script.
- Mai leggere gli ID dei messaggi. Usa titolo riformulato in italiano e nome del servizio.
- Transizioni brevi e dirette: "Teams.", "Passiamo a Purview.", "OneDrive."
- Tono: briefing professionale radiofonico. Non uno show televisivo, non un tutorial.
- Dettagli tecnici obbligatori: nomi di policy, ruoli Entra, URL, versioni ? i lettori sono professionisti IT.
- QUALITA COSTANTE: il livello del dialogo non deve calare verso la fine. Se senti che stai accelerando,
  e un segnale che stai comprimendo troppo i messaggi finali. Rallenta e mantieni la qualita.
- Le domande di Alex devono essere diverse tra loro. Vietato ripetere lo stesso schema di domanda
  ("E quando sara disponibile?") su messaggi consecutivi.

FORMATO OUTPUT:
Solo lo script. Nessun titolo, nessuna nota, nessuna spiegazione fuori dallo script.
ALEX: [testo]
SARA: [testo]
"@

# Costruisce lista titoli per il conteggio esplicito nel prompt
$TitleList = ($OrderedMessages | ForEach-Object { "- $($_.title)" }) -join "`n"

$UserPrompt = @"
Oggi è $Today.

Devi coprire ESATTAMENTE questi $($OrderedMessages.Count) messaggi — nessuno escluso.
Ecco la lista completa in ordine di priorità:
$TitleList

I messaggi con dettaglio completo seguono qui sotto.
Inizia a scrivere lo script solo dopo aver letto tutti i messaggi:

$MessagesForPrompt
"@

# ==============================================================================
# CHIAMATA AZURE AI FOUNDRY (Azure OpenAI compatible endpoint)
# ==============================================================================

$ApiUrl = "$AIEndpoint/openai/deployments/$DeploymentName/chat/completions?api-version=2024-02-01"

$RequestBody = @{
    messages = @(
        @{ role = "system"; content = $SystemPrompt },
        @{ role = "user";   content = $UserPrompt   }
    )
    temperature     = 0.7    # un po' di variazione stilistica, ma non troppa
    max_tokens      = 8000   # spazio sufficiente per dialogo ricco su tutti i messaggi
    top_p           = 0.95
} | ConvertTo-Json -Depth 5

$Headers = @{
    'api-key'      = $AIKey
    'Content-Type' = 'application/json'
}

try {
    $Response = Invoke-RestMethod `
        -Uri     $ApiUrl `
        -Method  Post `
        -Headers $Headers `
        -Body    $RequestBody `
        -TimeoutSec 120

    $PodcastScript = $Response.choices[0].message.content

    Write-Host "Script generato — $($PodcastScript.Length) caratteri, ~$([math]::Round($PodcastScript.Length / 900)) minuti di audio stimati."

} catch {
    Write-Error "Chiamata AI Foundry fallita: $_"
    exit 1
}

# ==============================================================================
# SALVATAGGIO SCRIPT TESTO
# ==============================================================================

if (-not (Test-Path $PodcastFolder)) {
    New-Item -ItemType Directory -Path $PodcastFolder | Out-Null
}

$ScriptFile = Join-Path $PodcastFolder ("podcast_script_{0}.txt" -f (Get-Date -Format "yyyy-MM-dd"))
$PodcastScript | Out-File -FilePath $ScriptFile -Encoding utf8

Write-Host "OK — Script salvato in: $ScriptFile"
Write-Host ""
Write-Host "--- ANTEPRIMA (prime 500 battute) ---"
Write-Host ($PodcastScript.Substring(0, [Math]::Min(500, $PodcastScript.Length)))
Write-Host "..."