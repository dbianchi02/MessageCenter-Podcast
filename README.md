# M365 Message Center Podcast

Automazione completa che ogni mattina feriale raccoglie i messaggi del Microsoft 365 Message Center, genera uno script podcast a due voci tramite Azure AI Foundry, lo converte in audio e lo consegna su Telegram.

<img width="1365" height="858" alt="image" src="https://github.com/user-attachments/assets/cab9fc74-9dc4-40fd-a031-54d4683942c4" />

---

## Indice

- [Idea e contesto](#idea-e-contesto)
- [Architettura](#architettura)
- [Prerequisiti](#prerequisiti)
- [Struttura del repository](#struttura-del-repository)
- [Setup passo-passo](#setup-passo-passo)
  - [1. App Registration su Entra ID](#1-app-registration-su-entra-id)
  - [2. Azure AI Foundry](#2-azure-ai-foundry)
  - [3. Azure Speech TTS](#3-azure-speech-tts)
  - [4. Bot Telegram](#4-bot-telegram)
  - [5. VM Azure e Task Scheduler](#5-vm-azure-e-task-scheduler)
  - [6. Azure Automation per start/stop VM](#6-azure-automation-per-startstop-vm)
  - [7. Configurazione variabili](#7-configurazione-variabili)
- [Punti insidiosi](#punti-insidiosi)
- [Personalizzazione del prompt](#personalizzazione-del-prompt)
- [Costi](#costi)
- [Replicare su un nuovo cliente](#replicare-su-un-nuovo-cliente)
- [Sviluppi futuri](#sviluppi-futuri)

---

## Idea e contesto

Il Message Center di Microsoft 365 genera ogni giorno annunci, aggiornamenti pianificati e retirement. Tenersi aggiornati richiede tempo e concentrazione. L'idea nasce da **Audio Overview** di Microsoft 365 Copilot: la funzione genera una sintesi audio a due voci da un documento, ma non e automabile via Power Automate.

La soluzione replica quel comportamento in modo completamente automatizzato usando Azure AI Foundry, con consegna su Telegram per ascoltarla in macchina durante il tragitto casa-lavoro.

---

## Architettura

```
Azure Automation (06:50)
        |
        v
  VM Azure avviata
        |
        v
Task Scheduler (07:00) --> Start-PodcastPipeline.ps1
        |
        |-- Step 1: Get-MessageCenterForAI.ps1
        |          Microsoft Graph API --> messages_YYYY-MM-DD.json
        |
        |-- Step 2: Generate-PodcastScript.ps1
        |          Azure AI Foundry (GPT-4o mini) --> podcast_script_YYYY-MM-DD.txt
        |
        |-- Step 3: Convert-PodcastToAudio.ps1
        |          Azure AI Foundry (gpt-4o-mini-tts) --> podcast_YYYY-MM-DD.mp3
        |
        |-- Step 4: Send-PodcastTelegram.ps1
                   Telegram Bot API --> gruppo Telegram
        |
        v
Azure Automation (08:10) --> VM spenta
```

---

## Prerequisiti

| Componente | Dettaglio |
|---|---|
| Microsoft 365 | Qualsiasi piano Business/Enterprise con Message Center |
| Azure Subscription | Attiva, con permessi per creare risorse |
| Azure AI Foundry | Progetto creato, deployment GPT-4o mini e gpt-4o-mini-tts |
| Entra ID App Registration | Con certificato e permesso `ServiceMessage.Read.All` |
| VM Azure | Windows Server 2019+ con PowerShell 7 installato |
| Azure Automation Account | Con System-assigned Managed Identity abilitata |
| Telegram | Account personale per creare il bot tramite @BotFather |

---

## Struttura del repository

```
m365-podcast/
|-- Start-PodcastPipeline.ps1     # Script master di orchestrazione
|-- Core/
|   |-- config.ps1                # Variabili di configurazione (NON versionare con credenziali reali)
|   |-- Get-MessageCenterForAI.ps1
|   |-- Generate-PodcastScript.ps1
|   |-- Convert-PodcastToAudio.ps1
|   |-- Send-PodcastTelegram.ps1
|   |-- system_prompt.txt         # System prompt per GPT-4o mini
|-- Output/                       # JSON giornalieri (ignorati da .gitignore)
|-- Podcast/                      # Script .txt giornalieri (ignorati da .gitignore)
|-- Audio/                        # File .mp3 giornalieri (ignorati da .gitignore)
|-- Logs/                         # Log pipeline giornalieri (ignorati da .gitignore)
|-- docs/
|   |-- architecture.svg          # Diagramma architettura
|-- .gitignore
|-- LICENSE
|-- README.md
```

---

## Setup passo-passo

### 1. App Registration su Entra ID

1. Vai su **portal.azure.com** > Entra ID > App Registrations > New registration
2. Dai un nome (es. `MessageCenterPodcast`)
3. In **Certificates & secrets** > **Certificates**: carica un certificato `.cer`
   - Per generarlo localmente: `New-SelfSignedCertificate` in PowerShell, poi esporta
4. In **API Permissions** > Add permission > Microsoft Graph > Application:
   - `ServiceMessage.Read.All`
   - `Mail.Send` (opzionale, solo se vuoi notifiche via mail)
5. Clicca **Grant admin consent**
6. Annota: **Tenant ID**, **Client ID**, **Certificate Thumbprint**

> **Nota**: usa l'autenticazione con certificato (non Client Secret) per i task schedulati. Il certificato non scade ogni anno come il secret e non richiede rotazione frequente.

---

### 2. Azure AI Foundry

**Deployment GPT-4o mini (generazione script):**

1. Vai su **ai.azure.com** > crea o apri un progetto
2. Models + endpoints > Deploy model > cerca `gpt-4o-mini`
3. Deployment type: **Global Standard** (pay per use, rate limit alto)
4. Region: **West Europe** o quella piu vicina
5. Annota: **Target URI** (solo la base, es. `https://xxx.cognitiveservices.azure.com`) e **API Key**

**Deployment gpt-4o-mini-tts (sintesi vocale):**

1. Models + endpoints > Deploy model > cerca `tts`
2. Seleziona `gpt-4o-mini-tts`
3. Region: **East US 2** (attenzione: in West Europe potrebbe non avere quota disponibile)
4. Annota: **Target URI completo** (incluso il path `/openai/deployments/gpt-4o-mini-tts/audio/speech?api-version=...`) e **API Key**

> **Punto insidioso**: le due risorse TTS e LLM possono stare in region diverse. Lo script le chiama con endpoint separati, quindi non e un problema. Verifica la disponibilita della quota per region prima di scegliere.

---

### 3. Azure Speech TTS (alternativa, non usata in questa implementazione)

Inizialmente era previsto Azure Speech Service con voci neurali italiane (`it-IT-GiuseppeNeural`, `it-IT-IsabellaNeural`). La qualita e inferiore a `gpt-4o-mini-tts`, ma il piano F0 e gratuito fino a 500.000 caratteri/mese. Se vuoi usarlo come fallback, crea la risorsa Speech in **West Europe** dal portale Azure.

---

### 4. Bot Telegram

1. Apri Telegram e cerca **@BotFather**
2. Manda `/newbot` e segui le istruzioni
3. Annota il **token** (formato: `1234567890:AAF...`)
4. Crea un gruppo Telegram e aggiungi il bot come membro
5. Manda un messaggio nel gruppo, poi apri nel browser:
   ```
   https://api.telegram.org/bot<TOKEN>/getUpdates
   ```
6. Cerca `"chat":{"id":` nel JSON - per i gruppi il valore e **negativo** (es. `-987654321`)
7. Annota il **Chat ID** del gruppo

---

### 5. VM Azure e Task Scheduler

**Requisiti VM:**
- Windows Server 2019 o superiore
- PowerShell 7 installato (`winget install Microsoft.PowerShell`)
- Modulo Microsoft Graph: `Install-Module Microsoft.Graph -Scope AllUsers`
- Certificato dell'App Registration installato nel cert store della macchina

**Struttura cartelle sulla VM:**
```
C:\Script\GetMessageCenter\
|-- Start-PodcastPipeline.ps1
|-- Core\
|   |-- (tutti gli script + config.ps1 + system_prompt.txt)
|-- Output\
|-- Podcast\
|-- Audio\
|-- Logs\
```

**Creazione Task Scheduler (da PowerShell amministratore):**

Apri Task Scheduler dalla GUI (cercare "Task Scheduler" nel menu Start) e crea il task manualmente:

- **General tab**: nome `PodcastPipeline`, spunta "Run whether user is logged on or not" e "Run with highest privileges"
- **Triggers tab**: Weekly, lun-ven, ore 07:00, spunta "Enabled"
- **Actions tab**: Program = `pwsh.exe`, Arguments = `-NonInteractive -ExecutionPolicy Bypass -File "C:\Script\GetMessageCenter\Start-PodcastPipeline.ps1"`
- **Conditions tab**: deseleziona "Start only if on AC power"
- **Settings tab**: spunta "Run task as soon as possible after a scheduled start is missed", imposta execution time limit a 1 ora

> **Punto insidioso critico**: usa `pwsh.exe` (PowerShell 7) e NON `powershell.exe` (PowerShell 5). PS5 in modalita `-NonInteractive` usa encoding Windows-1252 invece di UTF-8, corrompendo i caratteri italiani e causando errori 400 nelle chiamate API. PS7 usa UTF-8 come default in tutte le modalita.

---

### 6. Azure Automation per start/stop VM

1. Crea un **Automation Account** nel portale Azure (stesso Resource Group della VM)
2. Abilita **System-assigned Managed Identity**: Automation Account > Identity > Status: On
3. Assegna il ruolo **Virtual Machine Contributor** alla Managed Identity sulla VM:
   - VM > Access Control (IAM) > Add role assignment > Virtual Machine Contributor > seleziona la Managed Identity
4. Crea il runbook:
   - Automation Account > Runbooks > Create a runbook
   - Nome: `Start-StopPodcastVM`
   - Runbook type: `PowerShell`
   - **Runtime version: 7.2** (fondamentale - non lasciare 5.1)
   - Incolla il codice del runbook, pubblica
5. Crea due schedule dal runbook > Schedules > Add a schedule:
   - `StartVM`: ricorrente lun-ven ore **06:50**, parametro `Action` = `Start`
   - `StopVM`: ricorrente lun-ven ore **08:10**, parametro `Action` = `Stop`

> **Punto insidioso**: quando inserisci il parametro nello schedule, nel campo "Action" scrivi solo il valore (`Start` o `Stop`), mai `Action = Start`. Il portale sa gia che stai compilando il parametro Action.

> **Punto insidioso**: il runtime version 5.1 non e modificabile dopo la pubblicazione del runbook. Se hai pubblicato con 5.1, devi eliminare il runbook e ricrearlo con 7.2.

---

### 7. Configurazione variabili

Copia `Core/config.ps1.example` in `Core/config.ps1` e compila tutti i valori:

```powershell
# config.ps1 - NON caricare su GitHub con valori reali

# App Registration
$TenantID              = 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'
$ClientID              = 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'
$CertificateThumbprint = 'XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX'

# Azure AI Foundry - GPT-4o mini (generazione script)
$AIEndpoint      = 'https://xxx.cognitiveservices.azure.com'
$AIKey           = 'YOUR_AI_KEY'
$AIDeploymentName = 'gpt-4o-mini'

# Azure AI Foundry - gpt-4o-mini-tts (sintesi vocale)
$TTSEndpoint  = 'https://xxx.eastus2.cognitiveservices.azure.com/openai/deployments/gpt-4o-mini-tts/audio/speech?api-version=2025-03-01-preview'
$TTSKey       = 'YOUR_TTS_KEY'
$SpeechSpeed  = 1.1

# Telegram
$TelegramToken  = 'YOUR_BOT_TOKEN'
$TelegramChatId = '-987654321'
```

---

## Punti insidiosi

Questa sezione raccoglie i problemi reali incontrati durante l'implementazione.

### Encoding PowerShell 5 vs 7

Il problema piu frequente e piu difficile da diagnosticare. Sintomi: gli script funzionano perfettamente in VS Code ma falliscono quando lanciati dallo script master o dal Task Scheduler con errori 400 dalle API o caratteri corrotti.

**Causa**: PowerShell 5 in modalita non interattiva usa Windows-1252. I caratteri italiani (e, a, u ecc.) vengono corrotti nel JSON, Azure restituisce 400 Bad Request.

**Soluzione**: usare sempre `pwsh.exe` (PS7) sia nel Task Scheduler che nello script master. PS7 usa UTF-8 come default ovunque.

### Here-string con caratteri speciali

I blocchi `@" ... "@` in PowerShell non tollerano caratteri tipografici come virgolette curve (`"` `"`), trattini em (`-`), o apostrofi tipografici. Se copi testo da Word, browser o editor con autocorrect, questi caratteri entrano negli script causando errori di parsing.

**Soluzione**: scrivere i file con contenuto critico (system prompt, script con testo lungo) direttamente da console PowerShell usando `@' ... '@` (virgolette singole, che non interpretano nulla) e salvare con `Out-File -Encoding utf8`. In alternativa, usare file `.txt` separati per i testi lunghi (come il system prompt) e leggerli a runtime con `Get-Content`.

### Runtime version del Runbook non modificabile

Una volta pubblicato un runbook con Runtime version 5.1, non e possibile cambiarlo. Il pulsante non e cliccabile.

**Soluzione**: eliminare il runbook e ricrearlo scegliendo 7.2 al momento della creazione, prima della pubblicazione.

### Quota TTS per region

`gpt-4o-mini-tts` non e disponibile in tutte le region con quota. West Europe spesso mostra "no quota" per questo modello.

**Soluzione**: deployare il modello TTS in **East US 2** (o verificare la disponibilita nella propria region). Lo script usa endpoint separati per LLM e TTS, quindi le due risorse possono stare in region diverse senza problemi.

### Parametri nei runbook schedule

Quando si configura lo schedule di un runbook con parametri, il portale Azure mostra i campi gia nominati. Nel campo "Action" va inserito solo il valore (`Start` o `Stop`), non `Action = Start`.

### Modello che omette messaggi con volumi alti

Con piu di 12-15 messaggi giornalieri, GPT-4o mini tende ad abbreviare o omettere i messaggi in fondo alla lista per stare nei token di output.

**Soluzioni applicate**:
1. Pre-ordinare i messaggi per priorita gia nel codice PowerShell (Retirement > Admin impact > Informativo) prima di passarli al modello
2. Includere nel prompt utente la lista completa dei titoli con la dicitura "Devi coprire ESATTAMENTE questi N messaggi"
3. Troncare il bodyText a 1200 caratteri per ridurre i token di input e lasciare piu spazio all'output
4. Impostare `max_tokens = 8000`

---

## Personalizzazione del prompt

Il file `Core/system_prompt.txt` controlla tutto il comportamento del podcast. E il file piu importante da personalizzare.

**Parametri chiave da modificare:**

| Parametro | Dove | Effetto |
|---|---|---|
| Durata target | Prima riga del prompt | Influenza la lunghezza complessiva |
| Nomi delle voci | Sezione "LE DUE VOCI" | Cambia il carattere dei personaggi |
| Soglia messaggi Gruppo C | Regola volumi alti | Controlla la compressione con molti messaggi |
| Tono del riepilogo | Sezione "RIEPILOGO AZIONI" | Da generico a molto dettagliato |

**Iterazione consigliata**: modifica una cosa sola per volta e confronta due transcript consecutivi. Il prompt engineering su testi lunghi ha effetti non lineari.

**Velocita audio**: modifica `$SpeechSpeed` in `config.ps1`. Il range e 0.25-4.0; 1.1 e il punto ottimale per un ritmo naturale da briefing.

**Voci disponibili** (parametri `echo` e `nova` in `Convert-PodcastToAudio.ps1`):
- Maschili: `alloy`, `echo`, `onyx`, `fable`
- Femminili: `nova`, `shimmer`

---

## Costi

Stimati su 22 esecuzioni/mese (5 giorni/settimana), media 12 messaggi/giorno:

| Componente | Piano | Costo stimato |
|---|---|---|
| GPT-4o mini (script) | Pay per use | < 0,10 EUR/mese |
| gpt-4o-mini-tts (audio) | Pay per use | < 0,50 EUR/mese |
| VM Azure (B2s o simile) | 1h20m/giorno lun-ven | ~ 2-4 EUR/mese |
| Azure Automation | Piano free (500 min/mese) | 0 EUR |
| Telegram Bot API | Gratuito | 0 EUR |

**Totale stimato: 3-5 EUR/mese**, dominato dalla VM.

---

## Replicare su un nuovo cliente

1. **Crea una nuova App Registration** nel tenant del cliente con `ServiceMessage.Read.All`
2. **Crea un nuovo progetto Azure AI Foundry** nella subscription del cliente (o riusa uno esistente)
3. **Deploya i modelli** `gpt-4o-mini` e `gpt-4o-mini-tts`
4. **Copia la struttura delle cartelle** sulla VM del cliente
5. **Compila `config.ps1`** con le credenziali del nuovo tenant
6. **Crea un nuovo bot Telegram** (o riusa lo stesso con un gruppo diverso)
7. **Configura Task Scheduler e Azure Automation** come da setup

> I soli file da modificare per un nuovo cliente sono `config.ps1` e, se necessario, `system_prompt.txt` per adattare il tono o aggiungere istruzioni specifiche (es. focus su determinati servizi).

---

## Sviluppi futuri

- [ ] **Bot Telegram interattivo**: Azure Function con webhook per rispondere a comandi (`/oggi`, `/cerca`, `/scadenze`)
- [ ] **Alert urgenti**: notifica immediata per messaggi con severity `high` o tag `Major change`, senza aspettare il podcast mattutino
- [ ] **Riepilogo settimanale**: podcast speciale ogni venerdi con tutti i messaggi della settimana
- [ ] **Upgrade modello**: valutare GPT-4.1 per giornate con molti messaggi (>15), qualita del dialogo significativamente migliore
- [ ] **Storico su SharePoint**: archiviare JSON e MP3 su SharePoint per consultazione storica e ricerca per keyword
- [ ] **Gestione multi-tenant**: un'unica pipeline che genera podcast separati per piu tenant, consegnati su gruppi Telegram distinti

---

## License

MIT License - vedi [LICENSE](LICENSE)
