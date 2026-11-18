#!/usr/bin/perl
# SYN Mirror, the server, on Linux and macOS: a service of this computer - Remote Desktop, SSH, VNC, a web server -, or of its
# network, reached by the client through a meeting point, with nothing to forward on the routers. The client uses its own program
# of that service, as with any address: Remote Desktop Connection, ssh, a VNC viewer, a browser. Nothing is installed there.
#
#   perl syn-mirror-server.pl                                              asks, as a menu; the answers kept for the next start
#   perl syn-mirror-server.pl --meet Tr7kQ2xZp4Lm9sWd@router.example.org:40000 --forward 22
#
# It asks the meeting point for a port of meeting - the password and its id, 8 random bytes of this start -, prints the line for the
# client, the meeting point and that port, and from then on knocks and dials the port every second, from one local port. Each connection
# that meets is joined to the server, in a process of its own: the bytes go as they are, both ways. The next one is awaited at once.
# A line with = in place of the @ - Fx2pL8wNq7Rk3mZa=router.example.org:41000 - is of a fixed port: no asking, its key alone
# knocks at it. A meeting point whose address changes has its address kept by others: the line names them, each with a key of
# reading - Tr7kQ2xZp4Lm9sWd@Rk8mP2qLx3Vb7NtY@203.0.113.7:40000,Hx4nT7wAc5Jd2QeL@198.51.100.9:40000 -, and the address is read
# there, again every 30 s. Only perl and its own modules: nothing to install.

use strict;
use warnings;
use utf8;
use IO::Socket::INET;
use IO::Select;
use Socket qw(PF_INET SOCK_STREAM SOL_SOCKET SO_ERROR SO_REUSEADDR IPPROTO_TCP TCP_NODELAY INADDR_ANY inet_aton pack_sockaddr_in unpack_sockaddr_in);
use POSIX qw(EINPROGRESS);
use Time::HiRes ();
use File::Basename qw(dirname);
use File::Spec;

binmode STDOUT, ':encoding(UTF-8)';
$| = 1;

# ── the window: each kind of news with its sign and colour; plain in a log or a pipe ──

my $colour = -t STDOUT && !$ENV{NO_COLOR};
my %tone = (good => '1;32', news => '36', wait => '33', warn => '33', bad => '1;31', quiet => '90', key => '1;33', name => '1;37');
sub paint { my ($text, $t) = @_; $colour ? "\e[$tone{$t}m$text\e[0m" : $text }
sub say { my ($sign, $t, $text) = @_; print " $sign ", paint($text, $t), "\n" }

# ── what to open: the servers people reach most, and any port ──

my $RDP = 3389;
my @SERVICES = (
    ['🪟', 'Remote Desktop of Windows', '3389', 'Remote Desktop Connection ( mstsc ); xrdp on Linux: a long, strong password on the account is a must'],
    ['🔐', 'SSH', '22', 'ssh -p <port> <meeting point>'],
    ['🖼️', 'VNC', '5900', 'a VNC viewer'],
    ['🌐', 'A web server', '80', 'a browser: http://<meeting point>:<port>'],
    ['✏️', 'Another port', '', 'of this computer, or address:port of its network: you type which'],
);

# ── what the menu keeps beside the script: key = value ──

my $kept_file = File::Spec->catfile(dirname(File::Spec->rel2abs($0)), 'syn-mirror-server.settings');

sub load_kept {
    my %k;
    if (open my $f, '<:encoding(UTF-8)', $kept_file) {
        while (<$f>) { $k{$1} = $2 if /^\s*(\w+)\s*=\s*(\S.*?)\s*$/ }
        close $f;
    }
    return \%k;
}

sub save_kept {
    my ($k) = @_;
    open my $f, '>:encoding(UTF-8)', $kept_file or return say('💾', 'quiet', "Not kept for the next start: $!");
    print $f "# SYN Mirror, the server: what the menu offers on Enter\n";
    print $f "$_ = $k->{$_}\n" for grep { defined $k->{$_} } qw(service forward meet password);
    close $f;
    chmod 0600, $kept_file; # the password of the meeting point: for this user alone
}

# ── the keys and lines typed ──

# The key pressed, alone, no Enter after it: the terminal in raw mode for it. Without a terminal, the next character.
sub key {
    my $c;
    if (-t STDIN) {
        require POSIX;
        my $t = POSIX::Termios->new;
        $t->getattr(0);
        my $was = $t->getlflag;
        $t->setlflag($was & ~(POSIX::ECHO() | POSIX::ICANON()));
        $t->setcc(POSIX::VMIN(), 1);
        $t->setattr(0, POSIX::TCSANOW());
        sysread STDIN, $c, 1;
        $t->setlflag($was);
        $t->setattr(0, POSIX::TCSANOW());
    } else {
        sysread STDIN, $c, 1 or exit 0;
    }
    exit 0 unless defined $c;
    return $c eq "\r" ? "\n" : $c;
}

sub line {
    my ($prompt) = @_;
    print ' ', paint($prompt, 'news'), ' ';
    my $l = <STDIN>;
    exit 0 unless defined $l;
    $l =~ s/^\s+|\s+$//g;
    return $l;
}

# Where the connections go, of what was typed: a port alone - of this computer -, or address:port. undef - neither.
sub target {
    my ($t) = @_;
    $t =~ s/^\s+|\s+$//g;
    return "127.0.0.1:$t" if $t =~ /^\d+$/ && $t > 0 && $t < 65536;
    return $t if $t =~ /^([^\s:]+):(\d+)$/ && $2 > 0 && $2 < 65536;
    return undef;
}

# The meeting point as its owner gave it - the page of SYN Mirror copies it so -, one of
#   <password>@<point>[:<port of requests>]                  a port of meeting given at each start
#   <key>=<point>:<port>                                     a fixed port: its key alone opens it
#   <password>@<read>@<keeper>[:<port>][,<read>@<keeper>...]  a point whose address changes: read from its keepers, in turn
#   <key>=<read>@<keeper>[:<port>][,...]                     the same, of a fixed port: the port is read too
# as { key, fixed, host, port } or { key, fixed, reads => [ [ key of reading, keeper, its port of requests ], ... ] }: key undef
# when the line has none. undef - no such line.
sub point {
    my ($t) = @_;
    $t =~ s/^\s+|\s+$//g;
    my ($key, $mark, $rest) = $t =~ /^([^\s@=]*)([@=])(.*)$/ ? ($1, $2, $3) : (undef, '@', $t);
    my %p = (key => (defined $key && $key ne '' ? $key : undef), fixed => $mark eq '=');
    if ($rest =~ /@/) {
        for (split /,/, $rest, -1) {
            my ($read, $keeper, $asks) = /^\s*([A-Za-z0-9]{16})@([^\s:@=,]+)(?::(\d+))?\s*$/ or return;
            return if defined $asks && ($asks < 1 || $asks > 65535);
            push @{$p{reads}}, [$read, $keeper, $asks // 40000];
        }
        return \%p;
    }
    my ($host, $port) = $rest =~ /^([^\s:@=,]+)(?::(\d+))?$/ or return;
    return if $p{fixed} && !defined $port;
    return if defined $port && ($port < 1 || $port > 65535);
    @p{qw(host port)} = ($host, $port // 40000);
    return \%p;
}

# The line without its key, as the menu keeps it: = first for a fixed port, @ first when the address is read.
sub rest_of {
    my ($p) = @_;
    my $where = $p->{reads} ? join(',', map { "$_->[0]\@$_->[1]:$_->[2]" } @{$p->{reads}}) : "$p->{host}:$p->{port}";
    return $p->{fixed} ? "=$where" : $p->{reads} ? "\@$where" : $where;
}

# The keys of reading hidden, for the screen.
sub hidden { (my $t = $_[0] // '') =~ s/[A-Za-z0-9]{16}@/****************@/g; return $t }

# A password or a key: 16 letters and digits.
sub key_ok { ($_[0] // '') =~ /^[A-Za-z0-9]{16}\z/ }

# What a whole line is, as docs/lines.tsv writes it - the key, @ or =, where -, or `error`: what every program takes alike.
sub parsed {
    my $p = point($_[0]);
    return 'error' unless $p && key_ok($p->{key});
    my $where = rest_of($p) =~ s/^[@=]//r;
    return "$p->{key} " . ($p->{fixed} ? '=' : '@') . " $where";
}

my $LINES = 'such as Tr7kQ2xZp4Lm9sWd@router.example.org:40000, Fx2pL8wNq7Rk3mZa=router.example.org:41000 - a fixed port -, or Tr7kQ2xZp4Lm9sWd@Rk8mP2qLx3Vb7NtY@203.0.113.7:40000 - its address read there';

# ── the menu, when nothing was given ──

sub menu {
    my $k = load_kept();
    print "\n";
    say('🔌', 'news', 'What should the client reach through the meeting point?');
    print "\n";
    for my $i (0 .. $#SERVICES) {
        my ($sign, $name, $port, $about) = @{$SERVICES[$i]};
        my $what = $port ne '' ? "port $port · $about" : ($k->{forward} && ($k->{service} // 0) == $i + 1 ? "last time $k->{forward}" : $about);
        printf "    %s  %s  %s%s\n", paint($i + 1, 'key'), $sign, paint(sprintf('%-27s', $name), 'name'), paint($what, 'quiet');
    }
    print "\n ", paint($k->{service} ? "Press 1-5 · Enter: $k->{service} as last time ›" : 'Press 1-5 ›', 'news'), ' ';
    my $service;
    while (1) {
        my $c = key();
        if ($c =~ /^[1-5]$/) { $service = $c; last }
        if ($c eq "\n" && $k->{service}) { $service = $k->{service}; last }
    }
    my ($sign, $name, $port) = @{$SERVICES[$service - 1]};
    print paint("$service  $sign $name", 'good'), "\n";
    my $forward;
    if ($port ne '') {
        $forward = "127.0.0.1:$port";
    } else {
        while (1) {
            my $last5 = $k->{forward} && ($k->{service} // 0) == 5;
            my $typed = line($last5
                ? "Which port: of this computer, such as 8080, or address:port of its network - Enter for $k->{forward}:"
                : 'Which port: of this computer, such as 8080, or address:port of its network:');
            $typed = $k->{forward} if $typed eq '' && $last5;
            last if defined($forward = target($typed // ''));
            say('💡', 'warn', 'A port, such as 8080, or an address and a port, such as 192.168.1.5:80');
        }
    }
    my ($p, $meet);
    while (1) {
        my $typed = line($k->{meet} ? 'The meeting point - Enter for ' . hidden($k->{meet}) . ':' : 'The meeting point, as its owner gave it, such as Tr7kQ2xZp4Lm9sWd@router.example.org:40000:');
        $typed = $k->{meet} if $typed eq '' && $k->{meet};
        if ($p = point($typed // '')) {
            $meet = rest_of($p);
            $p->{key} //= $meet eq ($k->{meet} // '') ? $k->{password} : undef;
            last;
        }
        say('💡', 'warn', "As its owner gave it - $LINES - or a name or an address, and :port when its owner gave one");
    }
    my $what = $p->{fixed} ? 'The key of its fixed port' : 'Its password';
    until (key_ok($p->{key})) {
        $p->{key} = line("$what, 16 letters and digits:");
        say('💡', 'warn', $p->{fixed} ? 'The key of a fixed port is 16 letters and digits' : 'The password of a meeting point is 16 letters and digits') unless key_ok($p->{key});
    }
    $k->{service} = $service;
    $k->{forward} = $forward if $service == 5;
    $k->{meet} = $meet;
    $k->{password} = $p->{key};
    save_kept($k);
    print "\n";
    return ($forward, $p->{key} . ($meet =~ /^[@=]/ ? $meet : "\@$meet"));
}

# ── the arguments, or the menu ──

my ($forward, $given);
while (my $a = shift @ARGV) {
    if ($a eq '--forward') { $forward = target(shift(@ARGV) // '') or die "--forward <port> or <address:port>, such as 22 or 192.168.1.5:80\n" }
    elsif ($a eq '--meet') { $given = shift @ARGV }
    elsif ($a eq '--parse') { print parsed(shift(@ARGV) // ''), "\n"; exit 0 } # what it makes of a line: docs/lines.tsv
    else {
        print "perl syn-mirror-server.pl [--meet <the line of the meeting point> --forward <port> | <address:port>]\n",
            "  the line as its owner gave it: <password>\@<meeting point>[:40000], <key>=<meeting point>:<fixed port>, or either\n",
            "  with the address read: <password>\@<key of reading>\@<keeper>:<port>[,...]\n",
            "  with no arguments it asks, and keeps the answers beside it\n";
        exit 2;
    }
}

print "\n ", paint('SYN Mirror', 'name'), paint(' · the server', 'news'), "\n ",
    paint('the client reaches a service of this server through a meeting point: no port forwarded on the routers', 'quiet'), "\n";
if (!defined $forward || !defined $given) {
    die "--meet and --forward go together\n" if defined $forward || defined $given;
    die "no terminal to ask in: give --meet and --forward\n" unless -t STDIN;
    ($forward, $given) = menu();
}
my $p = point($given);
die "--meet <the line of the meeting point>, $LINES\n" unless $p && key_ok($p->{key});
my $fixed = $p->{fixed};
my $rdp = $forward =~ /:$RDP$/;

say('💤', 'warn', 'To connect later, this computer must stay on and awake while this runs: asleep, it lets nobody in, and a minute later the meeting point gives its port to others');
say('💤', 'warn', $^O eq 'darwin' ? 'macOS: System Settings > Energy, or Battery > Options: keep it from sleeping. The screen may go dark'
    : 'Linux: suspend never, in the settings of power; or systemd-inhibit perl syn-mirror-server.pl. The screen may go dark');

# the server: said at once when nothing answers there; the meetings wait for it anyway
if (IO::Socket::INET->new(PeerAddr => $forward, Proto => 'tcp', Timeout => 2)) {
    say('🔌', 'good', "$forward answers: whoever comes is joined to it");
} elsif ($rdp) {
    say('⚠️', 'warn', "Nothing answers at $forward: no Remote Desktop server here. On Linux, xrdp");
} else {
    say('⚠️', 'warn', "Nothing answers at $forward yet: whoever comes waits for it");
}
if ($rdp) {
    say('🔑', 'warn', 'Whoever finds the port will try passwords: programs of the internet guess at every Remote Desktop they find, day and night');
    say('🔑', 'warn', 'The account you log in with needs a long password of its own, 16 characters or more, used nowhere else; not Administrator, admin or user');
}

# ── the meeting ──

# one socket for the request, the knocks and the reads: the NAT of this computer keeps one mapping for them
my $udp = IO::Socket::INET->new(Proto => 'udp', LocalAddr => '0.0.0.0') or die "UDP: $!\n";
my $sel = IO::Select->new($udp);
my $id = '';
if (open my $r, '<:raw', '/dev/urandom') { read $r, $id, 8; close $r }
$id = pack('N2', int(rand(2**32)), int(rand(2**32))) if length $id != 8;
# the knock: the password and the id; at a fixed port its key alone
my $knock = $fixed ? $p->{key} : $p->{key} . $id;
utf8::downgrade($knock);

# The answer of `length` bytes from `to` to what was sent there, within a second; undef - none.
sub answer {
    my ($to, $length) = @_;
    my ($port, $ip) = unpack_sockaddr_in($to);
    my $until = Time::HiRes::time() + 1;
    while ((my $left = $until - Time::HiRes::time()) > 0) {
        last unless $sel->can_read($left);
        my $from = recv($udp, my $got, 64, 0);
        next unless defined $from && length $got == $length;
        my ($fport, $fip) = unpack_sockaddr_in($from);
        return $got if $fport == $port && $fip eq $ip;
    }
    return undef;
}

# Where the meeting point is now: [ its address, packed; the port to ask or knock at; its name in the line for the client ]. Its
# name looked up again; or, of a changing address, read from its keepers in turn - an answer written within 2 minutes taken at
# once, else the freshest. undef - not found.
sub locate {
    unless ($p->{reads}) {
        my $ip = inet_aton($p->{host}) or return undef;
        return [$ip, $p->{port}, $p->{host}];
    }
    my $best;
    for my $r (@{$p->{reads}}) {
        my ($read, $keeper, $asks) = @$r;
        utf8::downgrade($read);
        my $ip = inet_aton($keeper) or next;
        my $to = pack_sockaddr_in($asks, $ip);
        my $got;
        for (1 .. 3) {
            send($udp, $read, 0, $to);
            last if defined($got = answer($to, 7));
        }
        next unless defined $got;
        # the address, the port, the minutes since the meeting point last wrote them
        my ($at, $port, $age) = unpack('a4 n C', $got);
        my $found = [$at, $port, inet_ntoa($at), $age];
        return $found if $age <= 2;
        $best = $found if !$best || $age < $best->[3];
    }
    return $best;
}

# A port of meeting from the meeting point: the password and the id to its port of requests, up to 10 times. The same id gets
# the port it holds again. undef - no answer.
sub ask {
    my ($at) = @_;
    my $to = pack_sockaddr_in($at->[1], $at->[0]);
    for (1 .. 10) {
        send($udp, $knock, 0, $to);
        my $got = answer($to, 2);
        return unpack('n', $got) if defined $got;
    }
    return undef;
}

my $keepers = $p->{reads} ? join(', ', map { "$_->[1]:$_->[2]" } @{$p->{reads}}) : '';
my $at = locate();
until ($at) {
    die "The meeting point $p->{host}: no such address\n" unless $p->{reads};
    say('❌', 'bad', "No address of the meeting point from $keepers: a wrong key of reading, the meeting point has not written its address there yet, or this address is blocked for wrong keys. Again in 5 s");
    sleep 5;
    $at = locate();
}
my $port = $fixed ? $at->[1] : ask($at);
unless ($port) {
    say('❌', 'bad', "No port of meeting from $at->[2]:$at->[1]: a wrong password, a wrong first port, this address is blocked for wrong knocks, or SYN Mirror there is of before the passwords of 16 characters: update it");
    exit 1;
}

# The line for the client, in a box and in the clipboard, and how its program takes it.
sub show {
    my $host = $at->[2];
    my $line = "$host:$port";
    my $bar = '─' x (length($line) + 4);
    print "\n";
    say('📨', 'news', 'Send this line to whoever connects:');
    print '    ', paint("╭$bar╮", 'quiet'), "\n    ", paint('│  ', 'quiet'), paint($line, 'good'), paint('  │', 'quiet'), "\n    ", paint("╰$bar╯", 'quiet'), "\n";
    my $copied;
    for my $tool (['pbcopy'], ['wl-copy'], ['xclip', '-selection', 'clipboard'], ['xsel', '-ib']) {
        next unless grep { -x "$_/$tool->[0]" } split /:/, ($ENV{PATH} // '');
        next if $tool->[0] =~ /^x/ && !$ENV{DISPLAY};
        next if $tool->[0] eq 'wl-copy' && !$ENV{WAYLAND_DISPLAY};
        if (open my $c, '|-', @$tool) { print $c $line; $copied = close $c }
        last if $copied;
    }
    say('📋', 'good', 'It is in your clipboard already: just paste it into a message') if $copied;
    if ($rdp) { say('🖥️', 'news', "Remote Desktop Connection ( mstsc ) of the client: as the computer, $line") }
    elsif ($forward =~ /:22$/) { say('🔐', 'news', "On the client: ssh -p $port <user>\@$host") }
    elsif ($forward =~ /:80$/) { say('🌐', 'news', "A browser of the client: http://$line") }
    else { say('🔗', 'news', "A program of the client reaches $forward at $line") }
    print "\n";
}
show();
say('💡', 'quiet', 'A fixed port answers no knock: if the client gets nothing, check the key with the owner of the meeting point') if $fixed;
say('👀', 'wait', 'Waiting for whoever connects…');

$SIG{CHLD} = 'IGNORE'; # each connection lives in a process of its own, gone with it

# the local port the dialing goes from: kept till someone comes - the meeting point that moves too knows the server by it
my $from = 0;

# Knocks at the port and dials it until someone comes or `until` - from one local port, so the NAT keeps one mapping: the
# connection. undef - nobody came by then.
sub once {
    my ($to, $until) = @_;
    while (time < $until) {
        send($udp, $knock, 0, $to);
        my $started = time;
        # bound by hand: IO::Socket::INET binds no port 0, and then each try would go from another port
        my $tcp = IO::Socket::INET->new;
        socket($tcp, PF_INET, SOCK_STREAM, IPPROTO_TCP) && setsockopt($tcp, SOL_SOCKET, SO_REUSEADDR, 1)
            && bind($tcp, pack_sockaddr_in($from, INADDR_ANY)) or do { say('❌', 'bad', "TCP: $!"); sleep 1; next };
        $from = (unpack_sockaddr_in(getsockname($tcp)))[0];
        $tcp->blocking(0);
        if (connect($tcp, $to) || $! == EINPROGRESS) {
            if (IO::Select->new($tcp)->can_write(1) && !$tcp->getsockopt(SOL_SOCKET, SO_ERROR)) {
                $tcp->blocking(1);
                return $tcp;
            }
        }
        close $tcp;
        # refused at once: the port is not open yet, or the network is down - a pause, not a storm of tries
        select(undef, undef, undef, 1 - (time - $started)) if time - $started < 1;
    }
    return undef;
}

# A connection that met, joined to the service till both sides end: each end told the other.
sub join_to {
    my ($came) = @_;
    my $there = IO::Socket::INET->new(PeerAddr => $forward, Proto => 'tcp', Timeout => 5)
        or return say('❌', 'bad', "Someone came; $forward: $!");
    say('✅', 'good', "Someone came: joined to $forward");
    setsockopt($_, IPPROTO_TCP, TCP_NODELAY, 1) for $came, $there;
    my %other = (fileno($came) => $there, fileno($there) => $came);
    my $sel = IO::Select->new($came, $there);
    while ($sel->count) {
        for my $s ($sel->can_read) {
            my $n = sysread($s, my $buf, 65536);
            if (!$n) {
                $sel->remove($s);
                shutdown($other{fileno $s}, 1);
                next;
            }
            my $out = $other{fileno $s};
            for (my $off = 0; $off < $n;) {
                my $w = syswrite($out, $buf, $n - $off, $off);
                unless (defined $w) { $sel->remove($s); last }
                $off += $w;
            }
        }
    }
    say('👋', 'quiet', 'Gone, the one who came');
}

# the port of meeting is not sure at the address of now: asked again at the next look
my $unsure = 0;
my $look = time + 30;
while (1) {
    my $came = once(pack_sockaddr_in($port, $at->[0]), $look);
    if ($came) {
        $from = 0;
        my $pid = fork;
        if (!defined $pid) { say('❌', 'bad', "fork: $!"); close $came; next }
        if ($pid == 0) { close $udp; join_to($came); exit 0 }
        close $came;
        next;
    }
    # every 30 s: where the meeting point is now - a dynamic address moves; its name looked up again, or its address read again
    $look = time + 30;
    my $now = locate() or do {
        say('⚠️', 'warn', $p->{reads} ? "No address of the meeting point from $keepers now: knocking on at the one of before" : "The meeting point $p->{host}: no such address now: knocking on at the one of before");
        next;
    };
    my $moved = $now->[0] ne $at->[0] || $now->[1] != $at->[1];
    next unless $moved || $unsure;
    my $was = "$at->[2]:$port";
    $at = $now;
    if ($fixed) {
        $port = $at->[1];
    } elsif (my $got = ask($at)) {
        $port = $got;
        $unsure = 0;
    } else {
        $unsure = 1;
        say('⚠️', 'warn', "No port of meeting from $at->[2]:$at->[1] now: knocking at $port there, asking again in 30 s");
    }
    if ("$at->[2]:$port" ne $was) {
        say('🔀', 'news', 'The meeting point moved: the line for the client is new');
        show();
        say('👀', 'wait', 'Waiting for whoever connects…');
    } elsif ($moved) {
        say('🔀', 'quiet', 'The meeting point moved to ' . inet_ntoa($at->[0]) . ': the line for the client stays');
    }
}
