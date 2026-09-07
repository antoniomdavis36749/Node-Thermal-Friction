$ErrorActionPreference = 'Stop'
$vs = 'C:\Users\anton\AppData\Local\BeamNG\BeamNG.drive\current\mods\unpacked\Node-Thermal-Friction-dev\tools'

$b = Get-Content (Join-Path (Join-Path $vs 'fixtures') 'belasco1-from-game.race.json') -Raw | ConvertFrom-Json
Write-Host ("pathnodes=" + $b.pathnodes.Count)
$sumx=0; $sumy=0; $sumz=0
foreach ($n in $b.pathnodes) {
  $sumx += [double]$n.pos[0]
  $sumy += [double]$n.pos[1]
  $sumz += [double]$n.pos[2]
}
$c = [double]$b.pathnodes.Count
Write-Host ("avg={0:n1},{1:n1},{2:n1}" -f ($sumx/$c), ($sumy/$c), ($sumz/$c))
Write-Host ("first={0},{1},{2}" -f $b.pathnodes[0].pos[0], $b.pathnodes[0].pos[1], $b.pathnodes[0].pos[2])

Add-Type -AssemblyName System.IO.Compression.FileSystem
$z = [IO.Compression.ZipFile]::OpenRead('C:\Program Files (x86)\Steam\steamapps\common\BeamNG.drive\content\levels\west_coast_usa.zip')
$e = $z.Entries | Where-Object { $_.FullName -eq 'levels/west_coast_usa/quickrace/race_track.prefab' } | Select-Object -First 1
$sr = New-Object IO.StreamReader($e.Open())
$t = $sr.ReadToEnd()
$sr.Close()
$z.Dispose()
$prefabOut = Join-Path (Join-Path $vs 'fixtures') 'race_track.prefab.txt'
[IO.File]::WriteAllText($prefabOut, $t)
Write-Host ("prefabLen=" + $t.Length)

$names = [regex]::Matches($t, 'name\s*=\s*"(Checkpoint[^"]+)"') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique
Write-Host 'checkpoint names:'
$names

# Sample a few position = "x y z" near Checkpoint
$matches = [regex]::Matches($t, '(?s)new\s+BeamNGWaypoint\([^\)]*\)\s*\{.*?position\s*=\s*"([^"]+)".*?name\s*=\s*"(Checkpoint[^"]+)"')
Write-Host ("waypointBlocks=" + $matches.Count)
foreach ($m in $matches) {
  Write-Host ($m.Groups[2].Value + ' @ ' + $m.Groups[1].Value)
}
