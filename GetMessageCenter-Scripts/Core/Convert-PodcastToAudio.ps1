#Requires -Version 5.1

# ==============================================================================
# Convert-PodcastToAudio.ps1
# Legge lo script podcast .txt generato da Generate-PodcastScript.ps1,
# riconosce le battute ALEX e SARA, applica voci distinte tramite
# Azure OpenAI gpt-4o-mini-tts e salva un unico file .mp3.
# ==============================================================================
# CONFIGURAZIONE
# ==============================================================================

# Endpoint completo del deployment gpt-4o-mini-tts su Azure AI Foundry
$TTSEndpoint = 'ENDPOINT'
$TTSKey      = 'KEY'   # Rigenera la chiave dal portale Azure e inseriscila qui

# Voci OpenAI — scelte per massima distinzione e naturalezza in italiano
# alloy: tono maschile neutro e professionale — perfetto per Alex il conduttore
# nova:  tono femminile caldo e chiaro — perfetto per Sara l'esperta
$VoiceAlex = 'alloy'
$VoiceSara = 'nova'

# Velocità parlato: 1.0 = normale, 1.1 = leggermente più veloce (consigliato per podcast)
# Range supportato: 0.25 - 4.0
$SpeechSpeed = 1.1

# Cartelle
$PodcastFolder = 'C:\Script\GetMessageCenter\Podcast'
$AudioFolder   = 'C:\Script\GetMessageCenter\Audio'

# ==============================================================================
# LETTURA SCRIPT DI OGGI
# ==============================================================================

$ScriptFile = Join-Path $PodcastFolder ("podcast_script_{0}.txt" -f (Get-Date -Format "yyyy-MM-dd"))

if (-not (Test-Path $ScriptFile)) {
    Write-Error "Script podcast non trovato: $ScriptFile — esegui prima Generate-PodcastScript.ps1"
    exit 1
}

$Lines = Get-Content $ScriptFile -Encoding utf8 | Where-Object { $_.Trim() -ne '' }
Write-Host "Lette $($Lines.Count) righe dallo script."

# ==============================================================================
# FUNZIONE: CHIAMATA AZURE OPENAI TTS → restituisce bytes MP3
# ==============================================================================

function Invoke-OpenAITTS {
    param(
        [string]$Text,
        [string]$Voice,
        [string]$Key,
        [string]$Endpoint,
        [double]$Speed
    )

    # gpt-4o-mini-tts accetta JSON semplice — niente SSML
    # "instructions" permette di dare indicazioni stilistiche alla voce
    $Instructions = if ($Voice -eq 'alloy') {
        "Sei Alex, un conduttore radiofonico professionale italiano. Parla in modo diretto, chiaro e con ritmo da briefing mattutino. Tono neutro-autorevole, mai enfatico."
    } else {
        "Sei Sara, un'esperta tecnica italiana. Parla in modo caldo, preciso e conversazionale. Tono competente ma accessibile, come se stessi spiegando a un collega."
    }

    $Body = @{
        model        = 'gpt-4o-mini-tts'
        input        = $Text
        voice        = $Voice
        speed        = $Speed
        instructions = $Instructions
        response_format = 'mp3'
    } | ConvertTo-Json -Depth 3

    $Headers = @{
        'api-key'      = $Key
        'Content-Type' = 'application/json'
    }

    try {
        $Response = Invoke-WebRequest `
            -Uri        $Endpoint `
            -Method     Post `
            -Headers    $Headers `
            -Body       ([System.Text.Encoding]::UTF8.GetBytes($Body)) `
            -TimeoutSec 60

        return $Response.Content
    }
    catch {
        Write-Warning "TTS fallito per: '$($Text.Substring(0, [Math]::Min(60, $Text.Length)))...' — $_"
        return $null
    }
}

# ==============================================================================
# ELABORAZIONE RIGHE — una chiamata TTS per ogni battuta
# ==============================================================================

if (-not (Test-Path $AudioFolder)) {
    New-Item -ItemType Directory -Path $AudioFolder | Out-Null
}

$AudioChunks = [System.Collections.Generic.List[byte[]]]::new()
$TotalLines  = $Lines.Count
$Current     = 0

foreach ($Line in $Lines) {

    $Current++
    Write-Progress -Activity "Generazione audio (gpt-4o-mini-tts)" `
                   -Status "Battuta $Current di $TotalLines" `
                   -PercentComplete (($Current / $TotalLines) * 100)

    if ($Line -match '^ALEX:\s*(.+)$') {
        $Voice     = $VoiceAlex
        $CleanText = $Matches[1].Trim()
    }
    elseif ($Line -match '^SARA:\s*(.+)$') {
        $Voice     = $VoiceSara
        $CleanText = $Matches[1].Trim()
    }
    else {
        Write-Host "  [skip] Riga non riconosciuta: $Line"
        continue
    }

    Write-Host "  [$Voice] $($CleanText.Substring(0, [Math]::Min(70, $CleanText.Length)))..."

    $AudioBytes = Invoke-OpenAITTS `
        -Text     $CleanText `
        -Voice    $Voice `
        -Key      $TTSKey `
        -Endpoint $TTSEndpoint `
        -Speed    $SpeechSpeed

    if ($AudioBytes) {
        $AudioChunks.Add($AudioBytes)
    }

    # Piccola pausa per non saturare il rate limit
    Start-Sleep -Milliseconds 200
}

Write-Progress -Activity "Generazione audio" -Completed

# ==============================================================================
# ASSEMBLAGGIO: concatena tutti i chunk MP3 in un unico file
# ==============================================================================

if ($AudioChunks.Count -eq 0) {
    Write-Error "Nessun chunk audio generato — verifica la chiave e l'endpoint."
    exit 1
}

$OutputFile   = Join-Path $AudioFolder ("podcast_{0}.mp3" -f (Get-Date -Format "yyyy-MM-dd"))
$OutputStream = [System.IO.File]::OpenWrite($OutputFile)

foreach ($Chunk in $AudioChunks) {
    $OutputStream.Write($Chunk, 0, $Chunk.Length)
}

$OutputStream.Close()

$FileSizeMB = [Math]::Round((Get-Item $OutputFile).Length / 1MB, 1)
Write-Host ""
Write-Host "OK — Audio salvato in: $OutputFile ($FileSizeMB MB)"
Write-Host "Battute processate: $($AudioChunks.Count) di $TotalLines righe totali"
