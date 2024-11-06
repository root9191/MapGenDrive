# Basispfade definieren
$server = "\\dom-002"
$basePath = "\NETLOGON\test"
$fullBasePath = Join-Path $server $basePath

# Benutzerabfrage für Task Scheduler
$domain = $env:USERDOMAIN
Write-Host "Aktuelle Domäne: $domain"
$username = Read-Host "Benutzername für Task (ohne Domäne)"
$taskUser = "$domain\$username"
Write-Host "Verwende Benutzer: $taskUser"
$taskPassword = Read-Host "Passwort für Task" -AsSecureString
$plainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($taskPassword))

# Logging-Funktion
function Write-Log {
    param ([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "$timestamp - $Message"
}

# Funktion zum Erstellen und Setzen von Berechtigungen für Ordner
function New-SecureFolder {
    param (
        [string]$Path,
        [string[]]$AccessIdentities,
        [switch]$IncludeCurrentUser
    )
    
    try {
        # Erstelle Ordner falls nicht vorhanden
        if (-not (Test-Path $Path)) {
            New-Item -ItemType Directory -Path $Path -Force | Out-Null
            Write-Log "Ordner erstellt: $Path"
        }

        # Hole ACL des Ordners
        $acl = Get-Acl $Path
        
        # Deaktiviere Vererbung und entferne alle vererbten Berechtigungen
        $acl.SetAccessRuleProtection($true, $false)
        
        # Entferne alle existierenden Berechtigungen
        foreach ($rule in $acl.Access) {
            $acl.RemoveAccessRule($rule) | Out-Null
        }

        # Füge den aktuellen Benutzer temporär hinzu, wenn gewünscht
        if ($IncludeCurrentUser) {
            $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
            $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                $currentUser,
                "FullControl",
                "ContainerInherit,ObjectInherit",
                "None",
                "Allow"
            )
            $acl.AddAccessRule($rule)
            Write-Log "Aktueller Benutzer temporär hinzugefügt: $currentUser"
        }

        # Füge die übergebenen Berechtigungen hinzu
        foreach ($identity in $AccessIdentities) {
            try {
                $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                    $identity,
                    "FullControl",
                    "ContainerInherit,ObjectInherit",
                    "None",
                    "Allow"
                )
                $acl.AddAccessRule($rule)
                Write-Log "Berechtigung hinzugefügt für: $identity"
            }
            catch {
                Write-Log "Fehler beim Hinzufügen der Berechtigung für $identity`: $_"
            }
        }

        # Setze neue ACL
        Set-Acl -Path $Path -AclObject $acl
        Write-Log "Berechtigungen gesetzt für: $Path"
    }
    catch {
        Write-Log "Fehler beim Erstellen/Konfigurieren von $Path`: $_"
        throw
    }
}

# Funktion zum Erstellen des Scheduled Tasks
function Register-MapDriveTask {
    param (
        [string]$ScriptPath,
        [string]$TaskUser,
        [string]$TaskPassword
    )
    
    try {
        # Definiere Task-Parameter
        $taskName = "GenMapDrive"
        $taskPath = "\proALPHA\"

        Write-Log "Erstelle Task für Benutzer: $TaskUser"

        # Lösche den Task falls er bereits existiert
        if (Get-ScheduledTask -TaskName $taskName -TaskPath $taskPath -ErrorAction SilentlyContinue) {
            Unregister-ScheduledTask -TaskName $taskName -TaskPath $taskPath -Confirm:$false
        }

        # Erstelle die Task-Aktion
        $action = New-ScheduledTaskAction -Execute $ScriptPath

        # Erstelle den Task-Trigger (alle 5 Minuten für einen Tag)
        $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).Date.AddHours(6) `
            -RepetitionInterval (New-TimeSpan -Minutes 5) `
            -RepetitionDuration (New-TimeSpan -Days 1)

        # Erstelle die Task-Einstellungen
        $settings = New-ScheduledTaskSettingsSet `
            -MultipleInstances IgnoreNew `
            -ExecutionTimeLimit (New-TimeSpan -Hours 72) `
            -AllowStartIfOnBatteries `
            -DontStopIfGoingOnBatteries `
            -Priority 7

        # Erstelle den Task
        Register-ScheduledTask -TaskName $taskName `
            -TaskPath $taskPath `
            -Action $action `
            -Trigger $trigger `
            -Settings $settings `
            -User $TaskUser `
            -Password $TaskPassword `
            -RunLevel Highest `
            -Description "Generiert das MapDrives Script" `
            -Force

        Write-Log "Scheduled Task erfolgreich erstellt: $taskPath$taskName"
    }
    catch {
        Write-Log "Fehler beim Erstellen des Scheduled Tasks: $_"
        throw
    }
}

try {
    # Teste ob das Skript mit Admin-Rechten läuft
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    $isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    
    if (-not $isAdmin) {
        throw "Dieses Skript muss mit Administratorrechten ausgeführt werden!"
    }

    # Hole computerbezogene Informationen
    $computerSystem = Get-WmiObject Win32_ComputerSystem
    $domain = $computerSystem.Domain
    Write-Log "Domäne erkannt: $domain"
    
    # Hole die Administratoren-Gruppe anhand der SID
    $adminSID = "S-1-5-32-544"
    $adminGroupName = (New-Object System.Security.Principal.SecurityIdentifier($adminSID)).Translate([System.Security.Principal.NTAccount]).Value
    Write-Log "Administratoren-Gruppe erkannt: $adminGroupName"
    
    # Erstelle proALPHA Ordner mit Berechtigungen
    $proAlphaPath = Join-Path $fullBasePath "proalpha"
    $proAlphaAccess = @(
        $adminGroupName,
        "NT AUTHORITY\SYSTEM",
        "$env:USERDOMAIN\SG-pA-Cloud"
    )
    New-SecureFolder -Path $proAlphaPath -AccessIdentities $proAlphaAccess -IncludeCurrentUser

    # Erstelle Scripts Ordner mit Berechtigungen
    $scriptsPath = Join-Path $fullBasePath "scripts"
    $scriptsAccess = @(
        "NT AUTHORITY\SYSTEM",
        "$env:USERDOMAIN\SG-pA-Cloud",
        "$env:USERDOMAIN\SG-pA-CustomerAdmin",
        $adminGroupName
    )
    New-SecureFolder -Path $scriptsPath -AccessIdentities $scriptsAccess -IncludeCurrentUser

    # Erstelle CSV-Dateien
    $credentialCsvPath = Join-Path $scriptsPath "credential.csv"
    if (-not (Test-Path $credentialCsvPath)) {
        "IP;User;Password" | Out-File -FilePath $credentialCsvPath -Encoding UTF8 -Force
        Write-Log "credential.csv erstellt"
    }

    $mapdrivesCsvPath = Join-Path $scriptsPath "mapdrives.csv"
    if (-not (Test-Path $mapdrivesCsvPath)) {
        "Letter;Path;Group" | Out-File -FilePath $mapdrivesCsvPath -Encoding UTF8 -Force
        Write-Log "mapdrives.csv erstellt"
    }

    # Generator-Skript herunterladen
    $generatorUrl = "https://raw.githubusercontent.com/root9191/MapGenDrive/main/automap_drives.ps1"
    $generatorPath = Join-Path $proAlphaPath "automap_drives.ps1"
    try {
        # Download mit korrekter Kodierung
        $webClient = New-Object System.Net.WebClient
        $webClient.Encoding = [System.Text.Encoding]::UTF8
        $webClient.DownloadString($generatorUrl) | Out-File -FilePath $generatorPath -Encoding UTF8 -Force
        
        # Prüfe ob die Datei erfolgreich heruntergeladen wurde und valide ist
        if (Test-Path $generatorPath) {
            $content = Get-Content -Path $generatorPath -Raw
            if ($content -match "function Test-FileChanges" -and $content -match "function New-MappingScript") {
                Write-Log "Generator-Skript erfolgreich heruntergeladen und validiert"
            }
            else {
                throw "Das heruntergeladene Skript scheint nicht valide zu sein!"
            }
        }
        else {
            throw "Generator-Skript konnte nicht erstellt werden!"
        }

        # Setze finale Berechtigungen ohne aktuellen Benutzer
        New-SecureFolder -Path $proAlphaPath -AccessIdentities $proAlphaAccess
        New-SecureFolder -Path $scriptsPath -AccessIdentities $scriptsAccess

        # Erstelle Scheduled Task
        Register-MapDriveTask -ScriptPath $generatorPath -TaskUser $taskUser -TaskPassword $plainPassword
    }
    catch {
        Write-Log "Fehler beim Herunterladen des Generator-Skripts: $_"
        throw
    }

    Write-Log "First-Run-Setup abgeschlossen"
}
catch {
    Write-Log "Kritischer Fehler beim First-Run-Setup: $_"
    throw
}