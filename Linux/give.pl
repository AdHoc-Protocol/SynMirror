#!/usr/bin/perl
# SYN Mirror: gives the server a port of meeting. It sends the password and its id, 8 random bytes of its own, to the first port
# of the range; the answer is a port of the others, 2 bytes, high first, given to that id: only knocks with it open the port, from
# whatever address. The rules of the kernel let only the right password through, a few a second from an address; the port is
# taken in the kernel - `nft create`, which fails when the port is taken already - so no two servers get one port, whatever else adds
# there. A server that asks again with the same id - its answer lost - gets the same port. The settings are those of /etc/syn-mirror.conf, read again at SIGHUP, and the addresses of this computer.

use strict;
use warnings;
use IO::Socket::INET;
use IO::Select;
use POSIX ();

my %conf = (FIRST => 40000, LAST => 49999);
open my $file, '<', '/etc/syn-mirror.conf' or die "syn-mirror: /etc/syn-mirror.conf: $!\n";
while (<$file>) { $conf{$1} = $2 if /^\s*([A-Z]+)=(\S*)/ }
close $file;
my ($password, $first, $last) = @conf{qw(PASSWORD FIRST LAST)};

# a socket of the port of requests at the address; SO_REUSEADDR: the one of all the addresses and those of single ones share the
# port
sub at { IO::Socket::INET->new(LocalAddr => $_[0], LocalPort => $first, Proto => 'udp', ReuseAddr => 1) }

# An answer goes from the address its request came to: the kernel picks the address by the way back otherwise - a server in
# the LAN of this computer, asking at its public address, would get the answer from its LAN address, and take none. Perl of the
# system tells no address a request came to, so each IPv4 address of this computer has a socket of its own, and each socket
# answers from itself; the one of all the addresses takes those that come later, until SIGHUP
my $any = at('0.0.0.0') or die "syn-mirror: the port $first: $!\n";
my @single;
my ($ip_cmd) = grep { -x } qw(/usr/sbin/ip /sbin/ip /usr/bin/ip /bin/ip);
if ($ip_cmd && open my $ip, '-|', $ip_cmd, '-4', '-o', 'addr', 'show') {
    while (<$ip>) {
        my $s = m{\binet\s+([\d.]+)/} ? at($1) : undef;
        push @single, $s if $s;
    }
    close $ip;
}
my $select = IO::Select->new($any, @single);
# `nft create` says so when a port is taken: that is no error here
open STDERR, '>', '/dev/null';
$SIG{HUP} = sub { exec $^X, $0 };
# perl blocks SIGHUP while its handler runs, and exec keeps the mask: unblocked, or the next reload would not reach this one
POSIX::sigprocmask(POSIX::SIG_UNBLOCK(), POSIX::SigSet->new(POSIX::SIGHUP()));

# the id of a request, in hex -> [ the port given, when ]: what a request again gets
my %gave;

# a port of meeting nobody holds, given to the id, 16 hex digits; undef when 16 picks found none free
sub give {
    my ($id) = @_;
    for (1 .. 16) {
        my $port = $first + 1 + int rand($last - $first);
        return $port if system('nft', "create element ip syn_mirror given { $port }; add element ip syn_mirror owned { $port . 0x$id }") == 0;
    }
    return undef;
}

while (1) {
    for my $udp ($select->can_read) {
        my $from = $udp->recv(my $got, 64) or next;
        # on a connection conntrack knows already the rules check no password: it is checked here
        next unless length($got) == 16 && substr($got, 0, 8) eq $password;
        my $id = unpack('H*', substr($got, 8));
        my $now = time;
        delete @gave{grep { $now - $gave{$_}[1] > 10 } keys %gave};
        my $port = $gave{$id} ? $gave{$id}[0] : give($id);
        next unless defined $port;
        $gave{$id} = [$port, $now];
        $udp->send(pack('n', $port), 0, $from);
    }
}
