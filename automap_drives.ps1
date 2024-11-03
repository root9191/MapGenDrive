# Define paths to the CSV files and output
$credentialFile = "\\dom-002\NETLOGON\scripts\credential.csv"
$mapDrivesFile = "\\dom-002\NETLOGON\scripts\mapdrives.csv"
$lastCredentialFileTimestamp = "\\dom-002\NETLOGON\proalpha\CredentialFileTimestamp.txt"
$lastMapDrivesFileTimestamp = "\\dom-002\NETLOGON\proalpha\MapDrivesFileTimestamp.txt"
$newScriptPath = "\\dom-002\NETLOGON\proalpha\mapdrives.ps1"
$mapdriveEXE = "\\dom-002\NETLOGON\mapdrives.exe"
# Function to log messages
function Write-Log {
    param ([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "$timestamp - $Message"
}


# Function to test file access
function Test-FileAccess {
    param ([string]$Path)
    try {
        $null = Get-Item $Path -ErrorAction Stop
        return $true
    }
    catch {
        Write-Log "Fehler beim Zugriff auf Datei: $Path"
        return $false
    }
}

# Function to check for changes in CSV files
function Test-FileChanges {
    param (
        [string]$File,
        [string]$TimestampFile
    )
    
    $changed = $false
    
    try {
        $currentFileTime = (Get-Item $File).LastWriteTime
        Write-Log "Aktuelle Zeit für $File : $($currentFileTime.ToString('yyyy-MM-dd HH:mm:ss'))"
        
        if (Test-Path $TimestampFile) {
            $lastTime = Get-Content $TimestampFile -Raw
            Write-Log "Gespeicherte Zeit für $File : $lastTime"
            
            if (-not [string]::IsNullOrWhiteSpace($lastTime)) {
                $lastDateTime = [datetime]::ParseExact($lastTime.Trim(), "yyyy-MM-dd HH:mm:ss", $null)
                
                # Vergleiche nur Datum und Zeit, ignoriere Millisekunden
                $currentTimeString = $currentFileTime.ToString("yyyy-MM-dd HH:mm:ss")
                $lastTimeString = $lastDateTime.ToString("yyyy-MM-dd HH:mm:ss")
                
                if ($currentTimeString -ne $lastTimeString) {
                    $changed = $true
                    Write-Log "Änderung erkannt in: $File ($lastTimeString -> $currentTimeString)"
                } else {
                    Write-Log "Keine Änderung in: $File"
                }
            } else {
                $changed = $true
                Write-Log "Leerer Zeitstempel für: $File"
            }
        } else {
            $changed = $true
            Write-Log "Keine Zeitstempel-Datei gefunden für: $File"
        }

        if ($changed -or -not (Test-Path $TimestampFile)) {
            $currentFileTime.ToString("yyyy-MM-dd HH:mm:ss") | 
                Set-Content -Path $TimestampFile -NoNewline -Encoding UTF8
            Write-Log "Zeitstempel aktualisiert für: $File"
        }
    }
    catch {
        Write-Log "Fehler beim Prüfen der Änderungen für $File : $_"
        $changed = $true
    }

    return $changed
}

# Function to generate the new script
function New-MappingScript {
    try {
        $credentialContent = Get-Content $credentialFile -Raw
        $mapDrivesContent = Get-Content $mapDrivesFile -Raw

        $scriptContent = @"
# Function to log messages
function Log-Message {
    param ([string]`$Message)
    Write-Host "`$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - `$Message"
}

# CSV Contents as variables
`$credentialFile = @'
$credentialContent
'@

`$mapDrivesFile = @'
$mapDrivesContent
'@

# Function to add cmdkey entries
function Add-CmdKeyEntries {
    Log-Message "Hinzufügen von cmdkey-Einträgen..."
    `$credentialFile -split "`r?`n" | ForEach-Object {
        if (`$_ -match "IP;User;Password") { return }
        if ([string]::IsNullOrWhiteSpace(`$_)) { return }
        `$parts = `$_ -split ";"
        if (`$parts.Count -eq 3) {
            `$ip = `$parts[0].Trim()
            `$user = `$parts[1].Trim()
            `$password = `$parts[2].Trim()

            try {
                `$cmdKeyOutput = cmdkey /add:`$ip /user:`$user /pass:`$password 2>&1
                if (`$LASTEXITCODE -eq 0) {
                    Log-Message "cmdkey hinzugefügt für IP: `$ip, Benutzer: `$user"
                } else {
                    Log-Message "Fehler beim Hinzufügen von cmdkey für IP: `$ip, Benutzer: `$user. Ausgabe: `$cmdKeyOutput"
                }
            } catch {
                Log-Message "Ausnahme beim Hinzufügen von cmdkey für IP: `$ip, Benutzer: `$user. Fehler: `$_"
            }
        }
    }
}

# Function to check if user is in security group
function IsUserInGroup(`$groupName) {
    `$user = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    `$principal = New-Object System.Security.Principal.WindowsPrincipal(`$user)

    try {
        if (-not [string]::IsNullOrWhiteSpace(`$groupName)) {
            `$groupSID = (New-Object System.Security.Principal.NTAccount(`$groupName)).Translate([System.Security.Principal.SecurityIdentifier])
            return `$principal.IsInRole(`$groupSID)
        }
        return `$false
    } catch {
        Log-Message "Fehler beim Übersetzen der Gruppe: `$groupName. Fehler: `$_"
        return `$false
    }
}

# Function to remove mapped drive
function RemoveMappedDrive(`$driveLetter) {
    if (`$driveLetter) {
        try {
            cmd.exe /c "net use `${driveLetter}: /delete /yes" 2>&1 | Out-Null
            Log-Message "Laufwerk `$driveLetter entfernt."
        } catch {
            Log-Message "Ausnahme beim Entfernen von Laufwerk `$driveLetter. Fehler: `$_"
        }
    }
}

# Function to check group membership with caching
`$cachedGroupMembership = @{}
function CheckGroupMembership(`$groupList) {
    foreach (`$group in `$groupList) {
        `$group = `$group.Trim()
        if (-not [string]::IsNullOrWhiteSpace(`$group)) {
            Log-Message "Überprüfe Mitgliedschaft in Gruppe: `$group"
            if (-not `$cachedGroupMembership.ContainsKey(`$group)) {
                `$cachedGroupMembership[`$group] = IsUserInGroup(`$group)
            }
            if (`$cachedGroupMembership[`$group]) {
                Log-Message "Benutzer ist Mitglied der Gruppe: `$group"
                return `$true
            } else {
                Log-Message "Benutzer ist NICHT Mitglied der Gruppe: `$group"
            }
        }
    }
    return `$false
}

# Function to map drive
function MapDrive(`$driveLetter, `$path, `$securityGroups) {
    RemoveMappedDrive `$driveLetter

    `$checkDrive = net use | Where-Object { `$_ -match "^`${driveLetter}:" }
    if (-not `$checkDrive) {
        if (-not [string]::IsNullOrEmpty(`$securityGroups)) {
            `$groupList = `$securityGroups -split ","
            `$isInGroup = CheckGroupMembership `$groupList
        } else {
            `$isInGroup = `$true
        }

        if (`$isInGroup) {
            try {
                # Bereinige den Pfad
                `$cleanPath = `$path -replace '\\{2,}', '\'
                `$cleanPath = "\\`$(`$cleanPath.TrimStart('\'))"

                # Verwende die korrekte Syntax für den net use Befehl
                cmd.exe /c "net use `${driveLetter}: ```"`$cleanPath```" /persistent:yes" 2>&1 | Out-Null
                if (`$LASTEXITCODE -eq 0) {
                    Log-Message "Laufwerk `$driveLetter erfolgreich auf `$cleanPath gemappt."
                } else {
                    Log-Message "Fehler beim Mappen von Laufwerk `$driveLetter auf `$cleanPath."
                }
            } catch {
                Log-Message "Ausnahme beim Mappen von Laufwerk `$driveLetter auf `$cleanPath. Fehler: `$_"
            }
        } else {
            Log-Message "Laufwerk `$driveLetter (`$path) wird übersprungen, da der Benutzer nicht in den Gruppen ist: `$securityGroups"
        }
    } else {
        Log-Message "Laufwerk `$driveLetter konnte nicht entfernt werden und ist weiterhin vorhanden."
    }
}

# Add cmdkey entries
Add-CmdKeyEntries

# Read and process the map drives content
`$mapDrivesFile -split "`r?`n" | ForEach-Object {
    if (`$_ -match "Letter;Path;Group") { return }
    if ([string]::IsNullOrWhiteSpace(`$_)) { return }
    
    `$parts = `$_ -split ";"
    if (`$parts.Count -ge 2) {
        `$letter = `$parts[0].Trim()
        `$path = `$parts[1].Trim()
        `$securityGroups = if (`$parts.Count -gt 2) { `$parts[2].Trim() } else { "" }

        if (-not [string]::IsNullOrEmpty(`$letter) -and -not [string]::IsNullOrEmpty(`$path)) {
            MapDrive -driveLetter `$letter -path `$path -securityGroups `$securityGroups
        } else {
            Log-Message "Ungültige Einträge: Letter='`$letter', Path='`$path', Group='`$securityGroups'"
        }
    }
}

Log-Message "Skript beendet."
"@

        [System.IO.File]::WriteAllText($newScriptPath, $scriptContent, [System.Text.Encoding]::UTF8)
        Write-Log "Neues Skript erfolgreich generiert"
    }
    catch {
        Write-Log "Fehler beim Generieren des Skripts: $_"
    }
}

# Main execution
try {
    Write-Log "Prüfe auf Änderungen in CSV-Dateien..."
    
    $credentialChanged = Test-FileChanges -File $credentialFile -TimestampFile $lastCredentialFileTimestamp
    $mapDrivesChanged = Test-FileChanges -File $mapDrivesFile -TimestampFile $lastMapDrivesFileTimestamp

    if ($credentialChanged -or $mapDrivesChanged) {
        Write-Log "Änderungen erkannt. Generiere neues Skript..."
        New-MappingScript
        ps2exe $newScriptPath $mapdriveEXE
    }
    else {
        Write-Log "Keine Änderungen erkannt"
    }
}
catch {
    Write-Log "Kritischer Fehler: $_"
}