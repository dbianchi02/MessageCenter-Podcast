#Requires -Modules Microsoft.Graph.Authentication, Microsoft.Graph.Users.Actions

# ==============================================================================
# Get-MessageCenterForAI.ps1
# Recupera i messaggi del Message Center delle ultime 24h e li salva come JSON
# strutturato, pronto per essere passato a un modello AI (es. GPT-4o mini su
# Azure AI Foundry) per generare uno script podcast in italiano.
# ==============================================================================
# CONFIGURAZIONE — sostituisci con i tuoi valori reali
# ==============================================================================

$TenantID             = 'e5e153cb-1ee5-41b4-99ce-0331ea258a0a'
$ClientID             = '8a35cb92-c67c-4473-a8ee-0fc8861a7d0f'
$CertificateThumbprint = 'C2E0E9D5ADF51F1E915D1B6C915E03E9BDD0BCB3'

# Cartella di output — deve esistere o viene creata automaticamente
$OutputFolder = 'C:\Script\GetMessageCenter\Output'
$OutputFile   = Join-Path $OutputFolder ("messages_{0}.json" -f (Get-Date -Format "yyyy-MM-dd"))

# ==============================================================================
# AUTENTICAZIONE
# ==============================================================================

Connect-MgGraph `
    -TenantId            $TenantID `
    -AppId               $ClientID `
    -CertificateThumbprint $CertificateThumbprint `
    -NoWelcome

# ==============================================================================
# RECUPERO MESSAGGI ULTIMI 24H
# ==============================================================================

$Since = (Get-Date).AddDays(-1).ToString('s') + 'Z'
$Uri   = "https://graph.microsoft.com/v1.0/admin/serviceAnnouncement/messages?`$filter=lastModifiedDateTime ge $Since"

$Response = Invoke-MgGraphRequest -Uri $Uri -Method Get

# ==============================================================================
# COSTRUZIONE OUTPUT STRUTTURATO
# ==============================================================================

$Messages = foreach ($msg in $Response.Value) {

    # Estrai il testo pulito dal body HTML (rimuove i tag)
    $BodyText = $msg.body.content -replace '<[^>]+>', '' -replace '&nbsp;', ' ' -replace '\s{2,}', ' '

    [PSCustomObject]@{
        id              = $msg.id
        title           = $msg.title
        services        = $msg.services -join ', '
        tags            = $msg.tags -join ', '
        severity        = $msg.severity
        published       = ([datetime]$msg.startDateTime).ToString('dd/MM/yyyy HH:mm')
        lastModified    = ([datetime]$msg.lastModifiedDateTime).ToString('dd/MM/yyyy HH:mm')
        actionRequired  = $msg.actionRequiredByDateTime
        bodyText        = $BodyText.Trim()
    }
}

# ==============================================================================
# SALVATAGGIO JSON
# ==============================================================================

if (-not (Test-Path $OutputFolder)) {
    New-Item -ItemType Directory -Path $OutputFolder | Out-Null
}

$Output = @{
    generatedAt   = (Get-Date -Format 'dd/MM/yyyy HH:mm')
    messageCount  = ($Messages | Measure-Object).Count
    messages      = $Messages
}

$Output | ConvertTo-Json -Depth 5 | Out-File -FilePath $OutputFile -Encoding utf8

Write-Host "OK — $($Output.messageCount) messaggi salvati in: $OutputFile"

# ==============================================================================
# NOTIFICA TELEGRAM SE NESSUN MESSAGGIO
# ==============================================================================

if ($Output.messageCount -eq 0) {
    Write-Host "Nessun messaggio oggi — invio notifica Telegram."

    $TelegramToken  = '8700705815:AAE3xc5nET3Hz8TV-a-CqoSFkKJqO1Dg2Xg'
    $TelegramChatId = '-5240578577'
    $Uri  = "https://api.telegram.org/bot$TelegramToken/sendMessage"
    $Body = @{
        chat_id    = $TelegramChatId
        text       = "Nessun aggiornamento dal Message Center oggi. Buona giornata!"
        parse_mode = 'HTML'
    } | ConvertTo-Json

    Invoke-RestMethod `
        -Uri         $Uri `
        -Method      Post `
        -ContentType 'application/json; charset=utf-8' `
        -Body        ([System.Text.Encoding]::UTF8.GetBytes($Body)) | Out-Null

    Write-Host "Notifica Telegram inviata."
}