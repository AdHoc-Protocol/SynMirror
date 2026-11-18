# SYN Mirror, the server, on Windows: a service of this computer - Remote Desktop, SSH, VNC, a web server -, or of its network,
# reached by the client through a meeting point, with nothing to forward on the routers. The client uses its own program of that
# service, as with any address: Remote Desktop Connection, ssh, a VNC viewer, a browser. Nothing is installed there.
#
#   syn-mirror-server.cmd                                                     a double click: asks, as a menu; the answers kept
#   powershell -ExecutionPolicy Bypass -File syn-mirror-server.ps1 -Meet Tr7kQ2xZp4Lm9sWd@router.example.org:40000 -Forward 3389
#
# It asks the meeting point for a port of meeting - the password and its id, 8 random bytes of this start -, prints the line for the
# client, the meeting point and that port, and from then on knocks and dials the port every second, from one local port. Each connection
# that meets is joined to the server by .NET, both ways, the bytes as they are; the next one is awaited at once.
# A line with = in place of the @ - Fx2pL8wNq7Rk3mZa=router.example.org:41000 - is of a fixed port: no asking, its key alone
# knocks at it. A meeting point whose address changes has its address kept by others: the line names them, each with a key of
# reading - Tr7kQ2xZp4Lm9sWd@Rk8mP2qLx3Vb7NtY@203.0.113.7:40000,Hx4nT7wAc5Jd2QeL@198.51.100.9:40000 -, and the address is read
# there, again every 30 s. Windows PowerShell 5.1, as Windows has it, or PowerShell 7: nothing to install.

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

# The meeting point as its owner gave it - the page of SYN Mirror copies it so -, one of
#   <password>@<point>[:<port of requests>]                  a port of meeting given at each start
#   <key>=<point>:<port>                                     a fixed port: its key alone opens it
#   <password>@<read>@<keeper>[:<port>][,<read>@<keeper>...]  a point whose address changes: read from its keepers, in turn
#   <key>=<read>@<keeper>[:<port>][,...]                     the same, of a fixed port: the port is read too
# as @{ key; fixed; host; port } or @{ key; fixed; reads = @( @(key of reading, keeper, its port of requests), ... ) }: key $null
# when the line has none. $null - no such line.
function Point([string]$t) {
    $t = $t.Trim()
    $p = @{ key = $null; fixed = $false; reads = $null; host = $null; port = 40000 }
    $rest = $t
    if ($t -match '^([^\s@=]*)([@=])(.*)$') {
        if ($Matches[1]) { $p.key = $Matches[1] }
        $p.fixed = $Matches[2] -eq '='
        $rest = $Matches[3]
    }
    if ($rest.Contains('@')) {
        $reads = @()
        foreach ($r in $rest -split ',') {
            if ($r.Trim() -cnotmatch '^([A-Za-z0-9]{16})@([^\s:@=,]+)(?::(\d+))?$') { return $null }
            $asks = 40000
            if ($Matches[3]) { $asks = [int]$Matches[3] }
            $reads += , @($Matches[1], $Matches[2], $asks)
        }
        $p.reads = $reads
        return $p
    }
    if ($rest -notmatch '^([^\s:@=,]+)(?::(\d+))?$') { return $null }
    if ($p.fixed -and -not $Matches[2]) { return $null }
    $p.host = $Matches[1]
    if ($Matches[2]) { $p.port = [int]$Matches[2] }
    return $p
}

# The line without its key, as the menu keeps it: = first for a fixed port, @ first when the address is read.
function Rest-Of($p) {
    if ($p.reads) { $where = ($p.reads | ForEach-Object { "$($_[0])@$($_[1]):$($_[2])" }) -join ',' } else { $where = "$($p.host):$($p.port)" }
    if ($p.fixed) { return "=$where" }
    if ($p.reads) { return "@$where" }
    return $where
}

# The keys of reading hidden, for the screen.
function Hidden([string]$t) { return $t -creplace '[A-Za-z0-9]{16}@', '****************@' }

$Lines = 'such as Tr7kQ2xZp4Lm9sWd@router.example.org:40000, Fx2pL8wNq7Rk3mZa=router.example.org:41000 - a fixed port -, or Tr7kQ2xZp4Lm9sWd@Rk8mP2qLx3Vb7NtY@203.0.113.7:40000 - its address read there'

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
        if ($k.meet) { $typed = Read-Line "The meeting point - Enter for $(Hidden $k.meet):" }
        else { $typed = Read-Line 'The meeting point, as its owner gave it, such as Tr7kQ2xZp4Lm9sWd@router.example.org:40000:' }
        if (-not $typed -and $k.meet) { $typed = $k.meet }
        $p = Point $typed
        if ($p) { break }
        Say '💡' warn "As its owner gave it - $Lines - or a name or an address, and :port when its owner gave one"
    }
    $meet = Rest-Of $p
    $key = $p.key
    if (-not $key -and $meet -eq $k.meet) { $key = $k.password }
    while (-not $key -or $key.Length -ne 16) {
        if ($p.fixed) { $key = Read-Line 'The key of its fixed port, 16 characters:' } else { $key = Read-Line 'Its password, 16 characters:' }
        if ($key.Length -ne 16) {
            if ($p.fixed) { Say '💡' warn 'The key of a fixed port is 16 characters' } else { Say '💡' warn 'The password of a meeting point is 16 characters' }
        }
    }
    $k.service = "$service"
    if ($service -eq 5) { $k.forward = $to }
    $k.meet = $meet
    $k.password = $key
    Save-Kept $k
    Write-Host
    if ($meet -match '^[@=]') { return @($to, "$key$meet") }
    return @($to, "$key@$meet")
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
if (-not $p -or -not $p.key -or $p.key.Length -ne 16) { Fail "-Meet <the line of the meeting point>, $Lines" }
$fixed = $p.fixed
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

function Resolve-IP([string]$name) {
    try { return [Net.Dns]::GetHostAddresses($name) | Where-Object { $_.AddressFamily -eq 'InterNetwork' } | Select-Object -First 1 } catch { return $null }
}

# one socket for the request, the knocks and the reads: the NAT of this computer keeps one mapping for them. No error of an ICMP
# that came back for a knock: Windows would end the next receive with it
$udp = New-Object Net.Sockets.UdpClient(0)
try { [void]$udp.Client.IOControl(-1744830452, [byte[]](0, 0, 0, 0), $null) } catch { }
$udp.Client.ReceiveTimeout = 1000
$id = New-Object byte[] 8
[Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($id)
# the knock: the password and the id; at a fixed port its key alone
if ($fixed) { [byte[]]$knock = [Text.Encoding]::ASCII.GetBytes($p.key) }
else { [byte[]]$knock = [Text.Encoding]::ASCII.GetBytes($p.key) + $id }

# The answer of $length bytes from $to to what was sent there, within a second; $null - none.
function Answer($to, [int]$length) {
    $until = [DateTime]::UtcNow.AddSeconds(1)
    while ([DateTime]::UtcNow -lt $until) {
        try {
            $from = New-Object Net.IPEndPoint([Net.IPAddress]::Any, 0)
            $got = $udp.Receive([ref]$from)
            if ($got.Length -eq $length -and $from.Equals($to)) { return , $got }
        } catch { return $null }
    }
    return $null
}

# Where the meeting point is now: @{ ip; port - to ask or knock at -; name - in the line for the client }. Its name looked up
# again; or, of a changing address, read from its keepers in turn - an answer written within 2 minutes taken at once, else the
# freshest. $null - not found.
function Locate {
    if (-not $p.reads) {
        $ip = Resolve-IP $p.host
        if (-not $ip) { return $null }
        return @{ ip = $ip; port = $p.port; name = $p.host }
    }
    $best = $null
    foreach ($r in $p.reads) {
        $ip = Resolve-IP $r[1]
        if (-not $ip) { continue }
        $to = New-Object Net.IPEndPoint($ip, [int]$r[2])
        [byte[]]$read = [Text.Encoding]::ASCII.GetBytes($r[0])
        $got = $null
        for ($i = 0; $i -lt 3 -and -not $got; $i++) {
            [void]$udp.Send($read, $read.Length, $to)
            $got = Answer $to 7
        }
        if (-not $got) { continue }
        # the address, the port, the minutes since the meeting point last wrote them
        $at = [Net.IPAddress]::new([byte[]]$got[0..3])
        $found = @{ ip = $at; port = $got[4] * 256 + $got[5]; name = "$at"; age = [int]$got[6] }
        if ($found.age -le 2) { return $found }
        if (-not $best -or $found.age -lt $best.age) { $best = $found }
    }
    return $best
}

# A port of meeting from the meeting point: the password and the id to its port of requests, up to 10 times. The same id gets
# the port it holds again. 0 - no answer.
function Ask($at) {
    $to = New-Object Net.IPEndPoint($at.ip, [int]$at.port)
    for ($i = 0; $i -lt 10; $i++) {
        [void]$udp.Send($knock, $knock.Length, $to)
        $got = Answer $to 2
        if ($got) { return $got[0] * 256 + $got[1] }
    }
    return 0
}

$keepers = ''
if ($p.reads) { $keepers = ($p.reads | ForEach-Object { "$($_[1]):$($_[2])" }) -join ', ' }
$at = Locate
while (-not $at) {
    if (-not $p.reads) { Fail "The meeting point $($p.host): no such address" }
    Say '❌' bad "No address of the meeting point from ${keepers}: a wrong key of reading, the meeting point has not written its address there yet, or this address is blocked for wrong keys. Again in 5 s"
    Start-Sleep 5
    $at = Locate
}
if ($fixed) { $port = $at.port } else { $port = Ask $at }
if (-not $port) { Fail "No port of meeting from $($at.name):$($at.port): a wrong password, a wrong first port, this address is blocked for wrong knocks, or SYN Mirror there is of before the passwords of 16 characters: update it" }

# The line for the client, in a box and in the clipboard, and how its program takes it.
function Show {
    $line = "$($at.name):$port"
    $bar = '─' * ($line.Length + 4)
    Write-Host
    Say '📨' news 'Send this line to whoever connects:'
    Write-Host "    ╭$bar╮" -ForegroundColor DarkGray
    Write-Host '    │  ' -NoNewline -ForegroundColor DarkGray; Write-Host $line -NoNewline -ForegroundColor Green; Write-Host '  │' -ForegroundColor DarkGray
    Write-Host "    ╰$bar╯" -ForegroundColor DarkGray
    try { Set-Clipboard -Value $line; Say '📋' good 'It is in your clipboard already: just paste it into a message' } catch { }
    if ($isRdp) { Say '🖥️' news "Remote Desktop Connection ( mstsc ) of the client: as the computer, $line" }
    elseif ($toPort -eq '22') { Say '🔐' news "On the client: ssh -p $port <user>@$($at.name)" }
    elseif ($toPort -eq '80') { Say '🌐' news "A browser of the client: http://$line" }
    else { Say '🔗' news "A program of the client reaches $to at $line" }
    Write-Host
}
Show
if ($fixed) { Say '💡' quiet 'A fixed port answers no knock: if the client gets nothing, check the key with the owner of the meeting point' }
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

# the local port the dialing goes from: kept till someone comes - the meeting point that moves too knows the server by it
$from = 0
# the port of meeting is not sure at the address of now: asked again at the next look
$unsure = $false
$look = [DateTime]::UtcNow.AddSeconds(30)
while ($true) {
    $dial = New-Object Net.IPEndPoint($at.ip, [int]$port)
    # knocks and dials till someone comes, from one local port: the NAT keeps one mapping; the next one from a new local port
    $met = $false
    while (-not $met -and [DateTime]::UtcNow -lt $look) {
        Tend
        [void]$udp.Send($knock, $knock.Length, $dial)
        $started = [DateTime]::UtcNow
        $tcp = New-Object Net.Sockets.Socket('InterNetwork', 'Stream', 'Tcp')
        $tcp.SetSocketOption('Socket', 'ReuseAddress', $true)
        $tcp.Bind((New-Object Net.IPEndPoint([Net.IPAddress]::Any, $from)))
        $from = $tcp.LocalEndPoint.Port
        $try = $tcp.BeginConnect($dial, $null, $null)
        if ($try.AsyncWaitHandle.WaitOne(1000)) { try { $tcp.EndConnect($try); $met = $true } catch { } }
        if ($met) { Join-To $tcp; $from = 0; break }
        $tcp.Close()
        # refused at once: the port is not open yet, or the network is down - a pause, not a storm of tries
        $rest = 1000 - ([DateTime]::UtcNow - $started).TotalMilliseconds
        if ($rest -gt 0) { Start-Sleep -Milliseconds ([int]$rest) }
    }
    if ($met) { continue }
    # every 30 s: where the meeting point is now - a dynamic address moves; its name looked up again, or its address read again
    $look = [DateTime]::UtcNow.AddSeconds(30)
    $now = Locate
    if (-not $now) {
        if ($p.reads) { Say '⚠️' warn "No address of the meeting point from $keepers now: knocking on at the one of before" }
        else { Say '⚠️' warn "The meeting point $($p.host): no such address now: knocking on at the one of before" }
        continue
    }
    $moved = -not $now.ip.Equals($at.ip) -or $now.port -ne $at.port
    if (-not $moved -and -not $unsure) { continue }
    $was = "$($at.name):$port"
    $at = $now
    if ($fixed) { $port = $at.port }
    else {
        $got = Ask $at
        if ($got) { $port = $got; $unsure = $false }
        else { $unsure = $true; Say '⚠️' warn "No port of meeting from $($at.name):$($at.port) now: knocking at $port there, asking again in 30 s" }
    }
    if ("$($at.name):$port" -ne $was) {
        Say '🔀' news 'The meeting point moved: the line for the client is new'
        Show
        Say '👀' wait 'Waiting for whoever connects…'
    } elseif ($moved) {
        Say '🔀' quiet "The meeting point moved to $($at.ip): the line for the client stays"
    }
}
