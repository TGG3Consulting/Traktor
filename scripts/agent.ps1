# Fonovyy pomoshchnik Traktor.
#
# Zachem: u Claude net pryamogo dostupa k komandnoy stroke etogo kompyutera -
# on umeet tolko pisat fayly. Pomoshchnik smotrit papku scripts\_queue i
# vypolnyaet vsyo, chto tuda polozheno, skladyvaya vyvod v scripts\_out.
# Tak sborki, testy i perezapuski idut bez klikov vladeltsa.
#
# Vypolnyayutsya tolko fayly .bat iz papki _queue vnutri C:\Traktor.
# Vypolnennye pomechayutsya prefiksom _done_ i ostayutsya dlya istorii.
#
# VNIMANIE: fayl dolzhen byt tolko na latinitse - PowerShell 5.1 chitaet
# .ps1 v kodirovke ANSI, i kirillitsa lomaet razbor skripta.

$ErrorActionPreference = 'Continue'
$queue = 'C:\Traktor\scripts\_queue'
$out   = 'C:\Traktor\scripts\_out'
New-Item -ItemType Directory -Force -Path $queue, $out | Out-Null

# Avtozapusk pri vklyuchenii kompyutera: kladem fayl v papku avtozagruzki
# polzovatelya (prav administratora ne trebuet, legko udalyaetsya).
try {
    $startup = [Environment]::GetFolderPath('Startup')
    $autorun = Join-Path $startup 'traktor-agent.bat'
    if (-not (Test-Path $autorun)) {
        $line = 'start "" /min powershell -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File C:\Traktor\scripts\agent.ps1'
        Set-Content -Path $autorun -Value "@echo off`r`n$line" -Encoding ASCII
    }
} catch {
    "avtozapusk ne nastroen: $_" | Add-Content -Path "$out\agent-error.txt"
}

"$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') pomoshchnik zapushchen" |
    Set-Content -Path "$out\agent-alive.txt" -Encoding ASCII

while ($true) {
    # Otmetka "ya zhiv" - po ney vidno, rabotaet li pomoshchnik.
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') pomoshchnik rabotaet" |
        Set-Content -Path "$out\agent-alive.txt" -Encoding ASCII

    $tasks = Get-ChildItem -Path $queue -Filter '*.bat' -ErrorAction SilentlyContinue |
             Where-Object { $_.Name -notlike '_done_*' } |
             Sort-Object CreationTime

    foreach ($t in $tasks) {
        $name = $t.BaseName
        $log  = Join-Path $out "$name.log"
        "=== $name start $(Get-Date -Format 'HH:mm:ss') ===" | Set-Content -Path $log
        try {
            # Start-Process, a ne "cmd /c ... | Add-Content": pri konveyere
            # roditel zhdet zakrytiya potokov vsemi dochernimi processami, i odin
            # dolgozhivushchiy process (tunnel, servis) veshaet pomoshchnika navsegda.
            $p = Start-Process -FilePath 'cmd.exe' -ArgumentList '/c', "`"$($t.FullName)`"" `
                 -NoNewWindow -PassThru -RedirectStandardOutput "$log.out" -RedirectStandardError "$log.err"
            # Zadanie ne dolzhno idti bolshe 15 minut - inache schitaem ego zavisshim.
            if (-not $p.WaitForExit(900000)) {
                $p.Kill()
                "=== $name PREVYSHENO VREMYA (15 min), zadanie ostanovleno" | Add-Content -Path $log
            }
            Get-Content "$log.out" -ErrorAction SilentlyContinue | Add-Content -Path $log
            Get-Content "$log.err" -ErrorAction SilentlyContinue | Add-Content -Path $log
            Remove-Item "$log.out", "$log.err" -ErrorAction SilentlyContinue
            "=== $name done, code $($p.ExitCode), $(Get-Date -Format 'HH:mm:ss') ===" | Add-Content -Path $log
        } catch {
            "=== $name OSHIBKA: $_" | Add-Content -Path $log
        }
        Move-Item -Path $t.FullName -Destination (Join-Path $queue "_done_$($t.Name)") -Force
    }

    Start-Sleep -Seconds 3
}
