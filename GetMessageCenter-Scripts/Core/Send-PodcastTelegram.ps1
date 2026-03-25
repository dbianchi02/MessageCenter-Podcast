#Requires -Version 5.1

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$TelegramToken  = '8700705815:AAE3xc5nET3Hz8TV-a-CqoSFkKJqO1Dg2Xg'
$TelegramChatId = '-5240578577'
$AudioFolder    = 'C:\Script\GetMessageCenter\Audio'

$AudioFile = Join-Path $AudioFolder ("podcast_{0}.mp3" -f (Get-Date -Format "yyyy-MM-dd"))

if (-not (Test-Path $AudioFile)) {
    Write-Error "File audio non trovato: $AudioFile"
    exit 1
}

Write-Host "Invio podcast su Telegram..."

$Uri      = "https://api.telegram.org/bot$TelegramToken/sendAudio"
$Boundary = [System.Guid]::NewGuid().ToString()
$FileBytes = [System.IO.File]::ReadAllBytes($AudioFile)
$FileName  = [System.IO.Path]::GetFileName($AudioFile)
$Caption   = "Podcast Message Center - $(Get-Date -Format 'dd/MM/yyyy')"

$BodyLines = [System.Collections.Generic.List[byte]]::new()

function Add-FormField {
    param([string]$Name, [string]$Value)
    $part = "--$Boundary`r`nContent-Disposition: form-data; name=`"$Name`"`r`n`r`n$Value`r`n"
    $BodyLines.AddRange([System.Text.Encoding]::UTF8.GetBytes($part))
}

function Add-FormFile {
    param([string]$Name, [string]$FileName, [byte[]]$FileBytes)
    $header = "--$Boundary`r`nContent-Disposition: form-data; name=`"$Name`"; filename=`"$FileName`"`r`nContent-Type: audio/mpeg`r`n`r`n"
    $BodyLines.AddRange([System.Text.Encoding]::UTF8.GetBytes($header))
    $BodyLines.AddRange($FileBytes)
    $BodyLines.AddRange([System.Text.Encoding]::UTF8.GetBytes("`r`n"))
}

Add-FormField -Name 'chat_id'   -Value $TelegramChatId
Add-FormField -Name 'caption'   -Value $Caption
Add-FormField -Name 'performer' -Value 'Message Center Bot'
Add-FormField -Name 'title'     -Value "M365 Update - $(Get-Date -Format 'dd MMMM yyyy')"
Add-FormFile  -Name 'audio'     -FileName $FileName -FileBytes $FileBytes

$closing = [System.Text.Encoding]::UTF8.GetBytes("--$Boundary--`r`n")
$BodyLines.AddRange($closing)

try {
    $Response = Invoke-RestMethod `
        -Uri         $Uri `
        -Method      Post `
        -ContentType "multipart/form-data; boundary=$Boundary" `
        -Body        $BodyLines.ToArray() `
        -TimeoutSec  120

    if ($Response.ok) {
        Write-Host "OK - Podcast inviato su Telegram."
    } else {
        Write-Error "Telegram errore: $($Response.description)"
        exit 1
    }
}
catch {
    Write-Error "Invio Telegram fallito: $_"
    exit 1
}
