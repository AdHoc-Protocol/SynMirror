#!/usr/bin/perl
# SYN Mirror, the server, on Linux and macOS: a service of this computer - Remote Desktop, SSH, VNC, a web server -, or of its
# network, reached by the client through a meeting point, with nothing to forward on the routers. The client uses its own program
# of that service, as with any address: Remote Desktop Connection, ssh, a VNC viewer, a browser. Nothing is installed there.
#
#   perl syn-mirror-server.pl                                              asks, as a menu; the answers kept for the next start
#   perl syn-mirror-server.pl --meet Tr7kQ2xZ@router.example.org:40000 --forward 22
#
# It asks the meeting point for a port of meeting - the password and its id, 8 random bytes of this start -, prints the line for the
# client, the meeting point and that port, and from then on knocks and dials the port every second, from one local port. Each connection
# that meets is joined to the server, in a process of its own: the bytes go as they are, both ways. The next one is awaited at once.
# Only perl and its own modules: nothing to install.

use strict;
use warnings;
use utf8;
use IO::Socket::INET;
use IO::Select;
use Socket qw(PF_INET SOCK_STREAM SOL_SOCKET SO_ERROR SO_REUSEADDR IPPROTO_TCP TCP_NODELAY INADDR_ANY inet_aton pack_sockaddr_in unpack_sockaddr_in);
use POSIX qw(EINPROGRESS);
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

# The meeting point as its owner gave it, `password@point:port` - the page of SYN Mirror copies it so -: the password, or undef,
# the point, the port of requests. undef - no such line.
sub point {
    my ($t) = @_;
    $t =~ s/^\s+|\s+$//g;
    my $password = $t =~ s/^([^@]*)@// ? $1 : undef;
    my ($host, $asks) = $t =~ /^([^\s:@]+)(?::(\d+))?$/ or return;
    return ($password, $host, $asks // 40000);
}

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
    my ($password, $meet);
    while (1) {
        my $typed = line($k->{meet} ? "The meeting point - Enter for $k->{meet}:" : 'The meeting point, as its owner gave it, such as Tr7kQ2xZ@router.example.org:40000:');
        $typed = $k->{meet} if $typed eq '' && $k->{meet};
        my ($with, $host, $asks) = point($typed // '');
        if (defined $host) {
            $meet = "$host:$asks";
            $password = $with // ($meet eq ($k->{meet} // '') ? $k->{password} : undef);
            last;
        }
        say('💡', 'warn', 'As its owner gave it - such as Tr7kQ2xZ@router.example.org:40000 - or a name or an address, and :port when its owner gave one');
    }
    until (defined $password && length $password == 8) {
        $password = line('Its password, 8 characters:');
        say('💡', 'warn', 'The password of a meeting point is 8 characters') unless length $password == 8;
    }
    $k->{service} = $service;
    $k->{forward} = $forward if $service == 5;
    $k->{meet} = $meet;
    $k->{password} = $password;
    save_kept($k);
    print "\n";
    return ($forward, "$password\@$meet");
}

# ── the arguments, or the menu ──

my ($forward, $given);
while (my $a = shift @ARGV) {
    if ($a eq '--forward') { $forward = target(shift(@ARGV) // '') or die "--forward <port> or <address:port>, such as 22 or 192.168.1.5:80\n" }
    elsif ($a eq '--meet') { $given = shift @ARGV }
    else {
        print "perl syn-mirror-server.pl [--meet <password>\@<meeting point>[:40000] --forward <port> | <address:port>]\n",
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
my ($password, $host, $asks) = point($given);
die "--meet <password>\@<meeting point>[:<port of requests>], such as Tr7kQ2xZ\@router.example.org:40000\n"
    unless defined $host && defined $password && length $password == 8;
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

sub ipv4 {
    my $ip = inet_aton($host);
    return $ip;
}

# one socket for the request and the knocks: the NAT of this computer keeps one mapping for them
my $udp = IO::Socket::INET->new(Proto => 'udp', LocalAddr => '0.0.0.0') or die "UDP: $!\n";
my $id = '';
if (open my $r, '<:raw', '/dev/urandom') { read $r, $id, 8; close $r }
$id = pack('N2', int(rand(2**32)), int(rand(2**32))) if length $id != 8;
my $knock = $password . $id;
utf8::downgrade($knock);

my $router = ipv4() or die "The meeting point $host: no such address\n";
my $port;
ASK: for (1 .. 10) {
    send($udp, $knock, 0, pack_sockaddr_in($asks, $router));
    my $sel = IO::Select->new($udp);
    my $until = time + 1;
    while ($sel->can_read(1)) {
        my $from = recv($udp, my $got, 16, 0);
        if (defined $from && length $got == 2) { $port = unpack('n', $got); last ASK }
        last if time >= $until;
    }
}
unless ($port) {
    say('❌', 'bad', "No port of meeting from $host:$asks: a wrong password, a wrong first port, this address is blocked for wrong knocks, or SYN Mirror there is older than its ids: update it");
    exit 1;
}

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
say('👀', 'wait', 'Waiting for whoever connects…');

$SIG{CHLD} = 'IGNORE'; # each connection lives in a process of its own, gone with it

# Knocks at the port and dials it until someone comes - from one local port, so the NAT keeps one mapping: the connection.
sub once {
    my ($at) = @_;
    my $from = 0;
    while (1) {
        send($udp, $knock, 0, $at);
        my $started = time;
        # bound by hand: IO::Socket::INET binds no port 0, and then each try would go from another port
        my $tcp = IO::Socket::INET->new;
        socket($tcp, PF_INET, SOCK_STREAM, IPPROTO_TCP) && setsockopt($tcp, SOL_SOCKET, SO_REUSEADDR, 1)
            && bind($tcp, pack_sockaddr_in($from, INADDR_ANY)) or do { say('❌', 'bad', "TCP: $!"); sleep 1; next };
        $from = (unpack_sockaddr_in(getsockname($tcp)))[0];
        $tcp->blocking(0);
        if (connect($tcp, $at) || $! == EINPROGRESS) {
            if (IO::Select->new($tcp)->can_write(1) && !$tcp->getsockopt(SOL_SOCKET, SO_ERROR)) {
                $tcp->blocking(1);
                return $tcp;
            }
        }
        close $tcp;
        # refused at once: the port is not open yet, or the network is down - a pause, not a storm of tries
        select(undef, undef, undef, 1 - (time - $started)) if time - $started < 1;
    }
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

while (1) {
    # a meeting point of a dynamic address: its name looked up for each meeting
    my $ip = ipv4() or do { say('❌', 'bad', "The meeting point $host: no such address"); sleep 5; next };
    my $came = once(pack_sockaddr_in($port, $ip));
    my $pid = fork;
    if (!defined $pid) { say('❌', 'bad', "fork: $!"); close $came; next }
    if ($pid == 0) { close $udp; join_to($came); exit 0 }
    close $came;
}
