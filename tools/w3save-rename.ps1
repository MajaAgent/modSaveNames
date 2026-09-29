<#
  w3save-rename.ps1 - nadaj customową nazwę zapisowi Wiedźmina 3 (5.0 / next-gen)

  Nazwa zapisu w menu gry żyje w nazwie pliku, więc ten skrypt przemianowuje całą
  trójkę plików jednego zapisu: <name>.sav + <name>.json + <name>.png, wstawiając
  etykietę w nawiasach:  ManualSave_[Bez i agrest]_53db9_7ea47000_5c98d32

  Mod modSaveNames czyta tę etykietę i pokazuje w menu samą nazwę, bez daty.

  Użycie (gra ZAMKNIĘTA - inaczej gra nadpisze pliki):
    .\w3save-rename.ps1 -List
    .\w3save-rename.ps1 -Save manualsave_53db9 -Label "Bez i agrest"
    .\w3save-rename.ps1 -Save manualsave_53db9 -Label "Test" -DryRun
    .\w3save-rename.ps1 -Save manualsave_53db9 -Label "Test" -Dir "D:\...\gamesaves"

  Po nadpisaniu zapisu w grze (nowy plik, nowa nazwa) etykietę nadaje się ponownie
  tą samą komendą.

  Nie dotyka zawartości zapisów - tylko nazwy plików. Rób kopię zapasową folderu.
#>
param(
    [string]$Save,
    [string]$Label,
    [switch]$List,
    [switch]$DryRun,
    [string]$Dir = "$env:USERPROFILE\Documents\The Witcher 3\gamesaves"
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $Dir)) {
    Write-Error "nie ma folderu: $Dir  (podaj -Dir albo ustaw zmienną W3_SAVES)"
    exit 2
}

function Get-W3Saves {
    Get-ChildItem -LiteralPath $Dir -Filter *.sav -File | Sort-Object LastWriteTime -Descending
}

if ($List -or (-not $Save)) {
    $saves = @(Get-W3Saves)
    if ($saves.Count -eq 0) { Write-Host "brak zapisów w $Dir"; exit 1 }
    Write-Host "$($saves.Count) zapis(ów) w $Dir"
    $saves | ForEach-Object {
        $custom = if ($_.BaseName -match '\[([^\]]*)\]') { $matches[1] } else { '' }
        [pscustomobject]@{
            Nazwa  = $_.BaseName
            Custom = $custom
            Data   = $_.LastWriteTime.ToString('yyyy-MM-dd HH:mm')
        }
    } | Format-Table -AutoSize
    exit 0
}

if (-not $Label) {
    Write-Error 'podaj -Label "nazwa" (albo -List, żeby zobaczyć zapisy)'
    exit 2
}

# nazwa musi być poprawna dla Windows i nie może rozbić schematu silnika
$clean = ($Label -replace '[<>:"/\\|?*]', '-' -replace '\s+', ' ').Trim(' ', '.', '-')
if (-not $clean) { Write-Error 'etykieta pusta po oczyszczeniu'; exit 2 }
if ($clean -ne $Label) { Write-Host "etykieta oczyszczona: '$Label' -> '$clean'" }

$hits = @(Get-W3Saves | Where-Object { $_.BaseName -like "$Save*" })
if ($hits.Count -eq 0) { Write-Error "nie znalazłem zapisu zaczynającego się od '$Save'"; exit 2 }
if ($hits.Count -gt 1) {
    Write-Error "pasuje $($hits.Count) zapisów - podaj więcej znaków:"
    $hits | ForEach-Object { Write-Host "  $($_.BaseName)" }
    exit 2
}

$old = $hits[0].BaseName
# <typ>_[stara etykieta]_<reszta>  albo  <typ>_<reszta>   ->   <typ>_[nowa]_<reszta>
if ($old -match '^(?<prefix>[A-Za-z]+)_(?:\[[^\]]*\]_)?(?<rest>.+)$') {
    $new = "$($matches['prefix'])_[$clean]_$($matches['rest'])"
} else {
    Write-Error "'$old' nie ma schematu silnika (<typ>_<id>) - użyj w3save_renamer.py (-Save oraz --mode free/tag)"
    exit 2
}

foreach ($ext in @('.sav', '.json', '.png')) {
    $src = Join-Path $Dir "$old$ext"
    if (-not (Test-Path -LiteralPath $src)) { continue }
    if (Test-Path -LiteralPath (Join-Path $Dir "$new$ext")) {
        Write-Error "istnieje już plik $new$ext - przerwa, nic nie zmieniam"
        exit 3
    }
    if ($DryRun) {
        Write-Host "[dry-run] $old$ext  ->  $new$ext"
    } else {
        Rename-Item -LiteralPath $src -NewName "$new$ext"
        Write-Host "  $old$ext  ->  $new$ext"
    }
}

if ($DryRun) {
    Write-Host "(dry-run - nic nie zmieniono)"
} else {
    Write-Host "gotowe: $new"
    Write-Host 'odpal grę i sprawdź zakładkę Wczytaj grę'
}
