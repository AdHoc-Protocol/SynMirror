# SYN Mirror, the server, on Windows: a service of this computer - Remote Desktop, SSH, VNC, a web server -, or of its network,
# reached by the client through a meeting point, with nothing to forward on the routers. The client uses its own program of that
# service, as with any address: Remote Desktop Connection, ssh, a VNC viewer, a browser. Nothing is installed there.
#
#   syn-mirror-server.cmd                                                     a double click: asks, as a menu; the answers kept
#   powershell -ExecutionPolicy Bypass -File syn-mirror-server.ps1 -Meet Tr7kQ2xZ@router.example.org:40000 -Forward 3389
#
# It asks the meeting point for a port of meeting - the password and its id, 8 random bytes of this start -, prints the line for the
# client, the meeting point and that port, and from then on knocks and dials the port every second, from one local port. Each connection
# that meets is joined to the server by .NET, both ways, the bytes as they are; the next one is awaited at once. Windows PowerShell
# 5.1, as Windows has it, or PowerShell 7: nothing to install.

param([string]$Meet, [string]$Forward)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }

# ── the window: each kind of news with its sign and colour ──

$Tones = @{ good = 'Green'; news = 'Cyan'; wait = 'Yellow'; warn = 'DarkYellow'; bad = 'Red'; quiet = 'DarkGray'; key = 'Yellow'; name = 'White' }
function Say([string]$sign, [string]$tone, [string]$text) {
    Write-Host " $sign " -NoNewline
    Write-Host $text -ForegroundColor $Tones[$tone]
}

# ── what to open: the servers people reach most, and any port ──

$RDP = 3389
$Services = @(
    @('🪟', 'Remote Desktop of Windows', '3389', 'Remote Desktop Connection ( mstsc ): a long, strong password on the account is a must'),
    @('🔐', 'SSH', '22', 'ssh -p <port> <meeting point>'),
    @('🖼️', 'VNC', '5900', 'a VNC viewer'),
    @('🌐', 'A web server', '80', 'a browser: http://<meeting point>:<port>'),
    @('✏️', 'Another port', '', 'of this computer, or address:port of its network: you type which')
)

# ── what the menu keeps beside the script: key = value ──

$KeptFile = Join-Path $PSScriptRoot 'syn-mirror-server.settings'

function Load-Kept {
    $k = @{}
    if (Test-Path $KeptFile) {
        foreach ($l in Get-Content $KeptFile -Encoding UTF8) { if ($l -match '^\s*(\w+)\s*=\s*(\S.*?)\s*$') { $k[$Matches[1]] = $Matches[2] } }
    }
    return $k
}

function Save-Kept($k) {
    $text = "# SYN Mirror, the server: what the menu offers on Enter`r`n"
    foreach ($n in 'service', 'forward', 'meet', 'password') { if ($k[$n]) { $text += "$n = $($k[$n])`r`n" } }
    try { [IO.File]::WriteAllText($KeptFile, $text) } catch { Say '💾' quiet "Not kept for the next start: $($_.Exception.Message)" }
}

# ── the keys and lines typed ──

function Read-Key {
    if ([Console]::IsInputRedirected) {
        $c = [Console]::In.Read()
        if ($c -lt 0) { exit 0 }
        return [string][char]$c
    }
    $k = [Console]::ReadKey($true)
    # Ctrl+C comes as a key here: it ends the script, as anywhere else
    if ($k.Key -eq 'C' -and ($k.Modifiers -band [ConsoleModifiers]::Control)) { exit 0 }
    if ($k.Key -eq 'Enter') { return "`n" }
    return [string]$k.KeyChar
}

function Read-Line([string]$prompt) {
    Write-Host " $prompt " -NoNewline -ForegroundColor Cyan
    $l = [Console]::In.ReadLine()
    if ($null -eq $l) { exit 0 }
    return $l.Trim()
}

# Where the connections go, of what was typed: a port alone - of this computer -, or address:port. $null - neither.
function Target([string]$t) {
    $t = $t.Trim()
    if ($t -match '^\d+$' -and [int]$t -gt 0 -and [int]$t -lt 65536) { return "127.0.0.1:$t" }
    if ($t -match '^([^\s:]+):(\d+)$' -and [int]$Matches[2] -gt 0 -and [int]$Matches[2] -lt 65536) { return $t }
    return $null
}

# The meeting point as its owner gave it, `password@point:port` - the page of SYN Mirror copies it so -: the password or $null, the
# point, the port of requests. $null - no such line.
function Point([string]$t) {
    $t = $t.Trim()
    $password = $null
    if ($t -match '^([^@]*)@(.*)$') { $password = $Matches[1]; $t = $Matches[2] }
    if ($t -notmatch '^([^\s:@]+)(?::(\d+))?$') { return $null }
    $asks = 40000
    if ($Matches[2]) { $asks = [int]$Matches[2] }
    return @{ password = $password; host = $Matches[1]; asks = $asks }
}

# ── the menu, when nothing was given ──

function Menu {
    $k = Load-Kept
    Write-Host
    Say '🔌' news 'What should the client reach through the meeting point?'
    Write-Host
    for ($i = 0; $i -lt $Services.Count; $i++) {
        $s = $Services[$i]
        $what = $s[3]
        if ($s[2]) { $what = "port $($s[2]) · $($s[3])" } elseif ($k.forward -and $k.service -eq "$($i + 1)") { $what = "last time $($k.forward)" }
        Write-Host '    ' -NoNewline; Write-Host ($i + 1) -NoNewline -ForegroundColor Yellow
        Write-Host "  $($s[0])  " -NoNewline; Write-Host ('{0,-27}' -f $s[1]) -NoNewline -ForegroundColor White
        Write-Host $what -ForegroundColor DarkGray
    }
    Write-Host
    if ($k.service) { Write-Host " Press 1-5 · Enter: $($k.service) as last time › " -NoNewline -ForegroundColor Cyan }
    else { Write-Host ' Press 1-5 › ' -NoNewline -ForegroundColor Cyan }
    while ($true) {
        $c = Read-Key
        if ($c -match '^[1-5]$') { $service = [int]$c; break }
        if ($c -eq "`n" -and $k.service) { $service = [int]$k.service; break }
    }
    $s = $Services[$service - 1]
    Write-Host "$service  $($s[0]) $($s[1])" -ForegroundColor Green
    if ($s[2]) { $to = "127.0.0.1:$($s[2])" }
    else {
        $last = $k.forward -and $k.service -eq '5'
        while ($true) {
            if ($last) { $typed = Read-Line "Which port: of this computer, such as 8080, or address:port of its network - Enter for $($k.forward):" }
            else { $typed = Read-Line 'Which port: of this computer, such as 8080, or address:port of its network:' }
            if (-not $typed -and $last) { $typed = $k.forward }
            $to = Target $typed
            if ($to) { break }
            Say '💡' warn 'A port, such as 8080, or an address and a port, such as 192.168.1.5:80'
        }
    }
    while ($true) {
        if ($k.meet) { $typed = Read-Line "The meeting point - Enter for $($k.meet):" }
        else { $typed = Read-Line 'The meeting point, as its owner gave it, such as Tr7kQ2xZ@router.example.org:40000:' }
        if (-not $typed -and $k.meet) { $typed = $k.meet }
        $p = Point $typed
        if ($p) { break }
        Say '💡' warn 'As its owner gave it - such as Tr7kQ2xZ@router.example.org:40000 - or a name or an address, and :port when its owner gave one'
    }
    $meet = "$($p.host):$($p.asks)"
    $password = $p.password
    if (-not $password -and $meet -eq $k.meet) { $password = $k.password }
    while (-not $password -or $password.Length -ne 8) {
        $password = Read-Line 'Its password, 8 characters:'
        if ($password.Length -ne 8) { Say '💡' warn 'The password of a meeting point is 8 characters' }
    }
    $k.service = "$service"
    if ($service -eq 5) { $k.forward = $to }
    $k.meet = $meet
    $k.password = $password
    Save-Kept $k
    Write-Host
    return @($to, "$password@$meet")
}

# ── the arguments, or the menu ──

Write-Host
Write-Host ' SYN Mirror' -NoNewline -ForegroundColor White; Write-Host ' · the server' -ForegroundColor Cyan
Write-Host ' the client reaches a service of this server through a meeting point: no port forwarded on the routers' -ForegroundColor DarkGray

# a failure, said: a window opened by a double click stays to be read
function Fail([string]$text) {
    Say '❌' bad $text
    if (-not [Console]::IsInputRedirected) { Write-Host; Write-Host ' Press Enter to close this window.' -ForegroundColor Cyan; [void][Console]::In.ReadLine() }
    exit 1
}

if ($Forward -or $Meet) {
    if (-not ($Forward -and $Meet)) { Fail '-Meet and -Forward go together' }
    $to = Target $Forward
    if (-not $to) { Fail '-Forward <port> or <address:port>, such as 3389 or 192.168.1.5:80' }
    $given = $Meet
} else {
    $to, $given = Menu
}
$p = Point $given
if (-not $p -or -not $p.password -or $p.password.Length -ne 8) { Fail '-Meet <password>@<meeting point>[:<port of requests>], such as Tr7kQ2xZ@router.example.org:40000' }
$point = $p.host
$isRdp = $to -match ":$RDP$"
$toHost, $toPort = $to -split ':(?=\d+$)'

Say '💤' warn 'To connect later, this computer must stay on and awake while this runs: asleep, it lets nobody in, and a minute later the meeting point gives its port to others'
Say '💤' warn 'Windows: Settings > System > Power, sleep Never. The screen may go dark'

# the server: said at once when nothing answers there; the meetings wait for it anyway
function Dial-Server {
    $c = New-Object Net.Sockets.TcpClient
    try {
        if ($c.ConnectAsync($toHost, [int]$toPort).Wait(5000)) { return $c }
    } catch { }
    $c.Close()
    return $null
}
$probe = Dial-Server
if ($probe) { $probe.Close(); Say '🔌' good "$to answers: whoever comes is joined to it" }
elseif ($isRdp) { Say '⚠️' warn "Nothing answers at ${to}: Remote Desktop is off on this computer. Windows Pro or above: Settings > System > Remote Desktop, on. Windows Home has none" }
else { Say '⚠️' warn "Nothing answers at $to yet: whoever comes waits for it" }
if ($isRdp) {
    Say '🔑' warn 'Whoever finds the port will try passwords: programs of the internet guess at every Remote Desktop they find, day and night'
    Say '🔑' warn 'The account you log in with needs a long password of its own, 16 characters or more, used nowhere else; not Administrator, admin or user'
}

# ── the meeting ──

function Router-IP {
    try { return [Net.Dns]::GetHostAddresses($point) | Where-Object { $_.AddressFamily -eq 'InterNetwork' } | Select-Object -First 1 } catch { return $null }
}

# one socket for the request and the knocks: the NAT of this computer keeps one mapping for them. No error of an ICMP that came
# back for a knock: Windows would end the next receive with it
$udp = New-Object Net.Sockets.UdpClient(0)
try { [void]$udp.Client.IOControl(-1744830452, [byte[]](0, 0, 0, 0), $null) } catch { }
$id = New-Object byte[] 8
[Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($id)
[byte[]]$knock = [Text.Encoding]::ASCII.GetBytes($p.password) + $id

$router = Router-IP
if (-not $router) { Fail "The meeting point ${point}: no such address" }
$asks = New-Object Net.IPEndPoint($router, $p.asks)
$udp.Client.ReceiveTimeout = 1000
$port = 0
for ($i = 0; $i -lt 10 -and -not $port; $i++) {
    [void]$udp.Send($knock, $knock.Length, $asks)
    $until = [DateTime]::UtcNow.AddSeconds(1)
    while (-not $port -and [DateTime]::UtcNow -lt $until) {
        try {
            $from = New-Object Net.IPEndPoint([Net.IPAddress]::Any, 0)
            $got = $udp.Receive([ref]$from)
            if ($got.Length -eq 2 -and $from.Equals($asks)) { $port = $got[0] * 256 + $got[1] }
        } catch { break }
    }
}
if (-not $port) { Fail "No port of meeting from ${point}:$($p.asks): a wrong password, a wrong first port, this address is blocked for wrong knocks, or SYN Mirror there is older than its ids: update it" }

$line = "${point}:$port"
$bar = '─' * ($line.Length + 4)
Write-Host
Say '📨' news 'Send this line to whoever connects:'
Write-Host "    ╭$bar╮" -ForegroundColor DarkGray
Write-Host '    │  ' -NoNewline -ForegroundColor DarkGray; Write-Host $line -NoNewline -ForegroundColor Green; Write-Host '  │' -ForegroundColor DarkGray
Write-Host "    ╰$bar╯" -ForegroundColor DarkGray
try { Set-Clipboard -Value $line; Say '📋' good 'It is in your clipboard already: just paste it into a message' } catch { }
if ($isRdp) { Say '🖥️' news "Remote Desktop Connection ( mstsc ) of the client: as the computer, $line" }
elseif ($toPort -eq '22') { Say '🔐' news "On the client: ssh -p $port <user>@$point" }
elseif ($toPort -eq '80') { Say '🌐' news "A browser of the client: http://$line" }
else { Say '🔗' news "A program of the client reaches $to at $line" }
Write-Host
Say '👀' wait 'Waiting for whoever connects…'

# the connections joined now: each way a copy of .NET, on its own; a way that ended tells the other side, a pair that ended goes
$pairs = New-Object Collections.ArrayList
function Tend {
    foreach ($q in @($pairs)) {
        if ($q.up.IsCompleted -and -not $q.upShut) { try { $q.there.Client.Shutdown('Send') } catch { }; $q.upShut = $true }
        if ($q.down.IsCompleted -and -not $q.downShut) { try { $q.came.Shutdown('Send') } catch { }; $q.downShut = $true }
        if ($q.upShut -and $q.downShut) {
            $q.came.Close(); $q.there.Close()
            $pairs.Remove($q)
            Say '👋' quiet 'Gone, the one who came'
        }
    }
}

function Join-To($came) {
    $there = Dial-Server
    if (-not $there) { $came.Close(); Say '❌' bad "Someone came; nothing answers at $to"; return }
    Say '✅' good "Someone came: joined to $to"
    $came.NoDelay = $true
    $there.NoDelay = $true
    $a = New-Object Net.Sockets.NetworkStream($came, $false)
    $b = $there.GetStream()
    [void]$pairs.Add(@{ came = $came; there = $there; up = $a.CopyToAsync($b, 65536); down = $b.CopyToAsync($a, 65536); upShut = $false; downShut = $false })
}

while ($true) {
    # a meeting point of a dynamic address: its name looked up for each meeting
    $router = Router-IP
    if (-not $router) { Say '❌' bad "The meeting point ${point}: no such address"; Start-Sleep 5; continue }
    $at = New-Object Net.IPEndPoint($router, $port)
    # knocks and dials till someone comes, from one local port: the NAT keeps one mapping; the next one from a new local port
    $from = 0
    while ($true) {
        Tend
        [void]$udp.Send($knock, $knock.Length, $at)
        $started = [DateTime]::UtcNow
        $tcp = New-Object Net.Sockets.Socket('InterNetwork', 'Stream', 'Tcp')
        $tcp.SetSocketOption('Socket', 'ReuseAddress', $true)
        $tcp.Bind((New-Object Net.IPEndPoint([Net.IPAddress]::Any, $from)))
        $from = $tcp.LocalEndPoint.Port
        $try = $tcp.BeginConnect($at, $null, $null)
        $met = $false
        if ($try.AsyncWaitHandle.WaitOne(1000)) { try { $tcp.EndConnect($try); $met = $true } catch { } }
        if ($met) { Join-To $tcp; break }
        $tcp.Close()
        # refused at once: the port is not open yet, or the network is down - a pause, not a storm of tries
        $rest = 1000 - ([DateTime]::UtcNow - $started).TotalMilliseconds
        if ($rest -gt 0) { Start-Sleep -Milliseconds ([int]$rest) }
    }
}
