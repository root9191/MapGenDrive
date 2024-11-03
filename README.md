# 🚀 Automatische Laufwerkszuordnung

Dieses PowerShell-Skript-System ermöglicht die automatische Zuordnung von Netzwerklaufwerken basierend auf Benutzergruppen und Anmeldeinformationen.

## 📋 Konfigurationsdateien

Das System basiert auf zwei wichtigen CSV-Dateien:

### 🔐 credential.csv

Diese Datei verwaltet die Anmeldeinformationen für die Netzwerkfreigaben.

**Format:** `IP;User;Password`

⚠️ **Wichtige Hinweise:**
- Bei Domänenbenutzern muss die Domäne angegeben werden: `domain\username` oder `username@domain.local`
- Bei lokalen Benutzern muss der Computername angegeben werden: `hostname\username`
- Wenn Hostnames verwendet werden, muss jeder Eintrag doppelt vorhanden sein (IP und Hostname)

**Beispiele:**
```
IP;User;Password
192.168.1.10;DOMAIN\user1;Pass123!
SERVER1;DOMAIN\user1;Pass123!
192.168.1.20;SERVER2\localuser;Pass456!
SERVER2;SERVER2\localuser;Pass456!
```

### 📁 mapdrives.csv

Diese Datei definiert die Laufwerkszuordnungen und Berechtigungen.

**Format:** `Letter;Path;Group`

**Beispiele:**
```
Letter;Path;Group
P;\\SERVER1\Projekte;Projekt-Team,Entwickler
M;\\192.168.1.10\Marketing;Marketing-Team
F;\\SERVER2\Finanzen;Finanz-Team,Buchhalter
```

## 🛠️ Ersteinrichtung

Ein separates FirstStart-Skript übernimmt die initiale Einrichtung:
- 📂 Erstellt erforderliche Verzeichnisstruktur
- 🔑 Setzt NTFS-Berechtigungen
- 📥 Installiert ps2exe-Modul
- ✨ Erstellt erste Beispiel-CSVs

## 📂 Verzeichnisstruktur

```
\\dom-002\NETLOGON\
├── 📂 scripts\
│   ├── 📝 credential.csv
│   └── 📝 mapdrives.csv
└── ⚙️ mapdrives.exe
```


## ⚠️ Häufige Fehler vermeiden

1. **Credential.csv:**
   - ❌ `user1;Pass123!` (Fehlende Server/Domänen-Angabe)
   - ✅ `DOMAIN\user1;Pass123!`
   - ❌ Fehlende Hostname-Einträge bei Verwendung von Namen
   
2. **Mapdrives.csv:**
   - ❌ `P;SERVER1\Projekte;Gruppe` (Fehlende Backslashes)
   - ✅ `P;\\SERVER1\Projekte;Gruppe`
   - ❌ `P;\\SERVER1\Projekte;Gruppe1, Gruppe2` (Leerzeichen nach Komma)
   - ✅ `P;\\SERVER1\Projekte;Gruppe1,Gruppe2`

## 🔍 Überprüfung der Konfiguration

1. Stellen Sie sicher, dass alle Server sowohl mit IP als auch Hostname eingetragen sind
2. Überprüfen Sie die korrekte Schreibweise der Gruppen
3. Testen Sie die Zuordnungen mit verschiedenen Benutzern
4. Prüfen Sie die Protokolle auf Fehler

## 🆘 Troubleshooting

- 🔴 Laufwerk wird nicht verbunden:
  - Überprüfen Sie die Einträge in credential.csv
  - Stellen Sie sicher, dass IP und Hostname-Einträge vorhanden sind
  - Prüfen Sie die Gruppenmitgliedschaft

- 🔴 Authentifizierungsfehler:
  - Kontrollieren Sie das Format der Benutzereinträge
  - Überprüfen Sie die Passwörter
  - Stellen Sie sicher, dass der richtige Domänen/Server-Name verwendet wird

## 📞 Support

Bei Problemen prüfen Sie:
1. 📋 Format der CSV-Dateien
2. 🔑 Benutzer- und Gruppeneinträge
3. 📝 Protokolldateien
4. 🔐 Berechtigungen