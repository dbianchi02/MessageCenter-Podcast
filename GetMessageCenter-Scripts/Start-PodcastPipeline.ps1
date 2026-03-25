#Requires -Version 5.1

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$ScriptRoot    = 'C:\Script\GetMessageCenter'
$LogFolder     = "$ScriptRoot\Logs"
$LogFile       = "$LogFolder\pipeline_$(Get-Date -Format 'yyyy-MM-dd').log"

function Write-PipelineLog {
    param([string]$Message, [string]$Level = 'INFO')
    $timestamp = Get-Date -Format 'HH:mm:ss'
    $line = "[$timestamp][$Level] $Message"
    Write-Host $line
    $line | Out-File $LogFile -Append -Encoding utf8
}

function Send-TeamsAlert {
    param([string]$Message)
    if ($TeamsWebhook -eq 'YOUR_TEAMS_WEBHOOK_URL') { return }
    try {
        $body = @{ text = $Message } | ConvertTo-Json
        Invoke-RestMethod -Uri $TeamsWebhook -Method Post -Body $body -ContentType 'application/json'
    } catch {
        Write-PipelineLog "Impossibile inviare alert Teams: $_" 'WARN'
    }
}

function Invoke-PipelineStep {
    param([string]$Name, [string]$ScriptPath)
    Write-PipelineLog "INIZIO: $Name"
    $start = Get-Date
    try {
        & pwsh.exe -NonInteractive -ExecutionPolicy Bypass -File $ScriptPath
        $exitCode = $LASTEXITCODE
        if ($exitCode -ne 0) { throw "Exit code: $exitCode" }
        $elapsed = [math]::Round(((Get-Date) - $start).TotalSeconds)
        Write-PipelineLog "COMPLETATO: $Name ($elapsed sec)"
        return $true
    }
    catch {
        $elapsed = [math]::Round(((Get-Date) - $start).TotalSeconds)
        Write-PipelineLog "FALLITO: $Name dopo ${elapsed}sec - $_" 'ERROR'
        return $false
    }
}

if (-not (Test-Path $LogFolder)) { New-Item -ItemType Directory -Path $LogFolder | Out-Null }

Write-PipelineLog "=== AVVIO PIPELINE PODCAST $(Get-Date -Format 'dd/MM/yyyy') ==="

$ok = Invoke-PipelineStep -Name "Raccolta messaggi Message Center" -ScriptPath "$ScriptRoot\Core\Get-MessageCenterForAI.ps1"
if (-not $ok) { Write-PipelineLog "Pipeline interrotta allo step 1." 'ERROR'; exit 1 }

Start-Sleep -Seconds 5

$ok = Invoke-PipelineStep -Name "Generazione script podcast (AI Foundry)" -ScriptPath "$ScriptRoot\Core\Generate-PodcastScript.ps1"
if (-not $ok) { Write-PipelineLog "Pipeline interrotta allo step 2." 'ERROR'; exit 1 }

Start-Sleep -Seconds 5

$ok = Invoke-PipelineStep -Name "Conversione audio (gpt-4o-mini-tts)" -ScriptPath "$ScriptRoot\Core\Convert-PodcastToAudio.ps1"
if (-not $ok) { Write-PipelineLog "Pipeline interrotta allo step 3." 'ERROR'; exit 1 }

Start-Sleep -Seconds 5

$ok = Invoke-PipelineStep `
    -Name       "Invio podcast su Telegram" `
    -ScriptPath "$ScriptRoot\Core\Send-PodcastTelegram.ps1"

if (-not $ok) {
    Write-PipelineLog "Invio Telegram fallito — il podcast e stato generato ma non consegnato." 'ERROR'
}

Write-PipelineLog "=== PIPELINE COMPLETATA ==="
exit 0
