#!/bin/sh
# Installs SYN Mirror on this Linux computer, from the folder SynMirror ( the rules are in ../OpenWRT/files ):
#   sudo sh Linux/install.sh
# or from syn-mirror-linux.sh, the release of GitHub: this script with the files it installs in it, one file ( ../pack.sh makes it ):
#   sudo sh syn-mirror-linux.sh
# It needs nftables and perl. A password of 8 characters is made when /etc/syn-mirror.conf has none, and printed. Without
# systemd the rules are loaded and `give` started once: do it again after each start of the computer, as printed.
# `sudo sh Linux/install.sh remove` takes it all away, the settings too, and `sudo sh syn-mirror-linux.sh remove` the same.

set -e
here=$(cd "$(dirname "$0")" && pwd)
CONF=/etc/syn-mirror.conf

# src <file of the folder SynMirror>: its text. The installer of one file has its own src, its files in it
[ -n "$packed" ] || src() { cat "$here/../$1"; }
# put <file of the folder SynMirror> <its place> [<mode>]: written there at once
put() {
	src "$1" > "$2"
	[ -z "$3" ] || chmod "$3" "$2"
}
# `give` started without systemd
PID=/run/syn-mirror.pid

systemd() { command -v systemctl >/dev/null && [ -d /run/systemd/system ]; }

give_off() {
	[ -f "$PID" ] && kill "$(cat "$PID")" 2>/dev/null || true
	rm -f "$PID"
}

if [ "$1" = remove ]; then
	if systemd && [ -f /etc/systemd/system/syn-mirror.service ]; then
		systemctl disable --now syn-mirror
		rm -f /etc/systemd/system/syn-mirror.service
		systemctl daemon-reload
	elif [ -x /usr/libexec/syn-mirror/rules ]; then
		give_off
		/usr/libexec/syn-mirror/rules unload
	fi
	rm -rf /usr/libexec/syn-mirror /usr/share/syn-mirror
	rm -f "$CONF"
	echo "SYN Mirror is removed, its settings too"
	exit 0
fi

if ! command -v nft >/dev/null; then
	echo "SYN Mirror needs nftables: apt install nftables, dnf install nftables, pacman -S nftables" >&2
	exit 1
fi
if ! command -v perl >/dev/null; then
	echo "SYN Mirror needs perl: apt install perl-base, dnf install perl, pacman -S perl" >&2
	exit 1
fi

mkdir -p /usr/libexec/syn-mirror /usr/share/syn-mirror
put OpenWRT/files/rules /usr/libexec/syn-mirror/rules 755
put Linux/give.pl /usr/libexec/syn-mirror/give.pl
put OpenWRT/files/syn-mirror.nft /usr/share/syn-mirror/syn-mirror.nft
[ -f "$CONF" ] || put Linux/syn-mirror.conf "$CONF"
chmod 600 "$CONF"
# the settings of an install before the guard against guessing: its lines added, on
if ! grep -q '^GUARD=' "$CONF"; then
	printf '%s\n' '# the guard against guessing passwords: a meeting that ends within SHORT seconds is short; more than GUESSES short' \
		'# meetings of an address at a port, one more back each 10 minutes, and it is blocked at that port. GUARD=0: off' \
		'GUARD=1' 'SHORT=20' 'GUESSES=5' >> "$CONF"
fi

. "$CONF"
if [ -z "$PASSWORD" ]; then
	PASSWORD=$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 8)
	sed -i "s/^PASSWORD=.*/PASSWORD=$PASSWORD/" "$CONF"
	echo "the password of this computer: $PASSWORD"
fi

if systemd; then
	put Linux/syn-mirror.service /etc/systemd/system/syn-mirror.service
	systemctl daemon-reload
	systemctl enable syn-mirror
	# an update: a reload, not a restart - the stop of a restart unloads the table, and the ports given with it. A reload loads the
	# rules keeping the ports given and their addresses, and `give` at SIGHUP starts anew, its new code and the settings
	if systemctl is-active --quiet syn-mirror; then
		systemctl reload syn-mirror
	else
		systemctl restart syn-mirror
	fi
else
	/usr/libexec/syn-mirror/rules load "$PASSWORD" "$FIRST" "$LAST" "$WAIT" "$TRIES" "$BLOCK" "$GUARD" "$SHORT" "$GUESSES"
	give_off
	nohup perl /usr/libexec/syn-mirror/give.pl </dev/null >/dev/null 2>&1 &
	echo $! > "$PID"
	echo "no systemd: after each start of the computer run"
	echo "  . $CONF && /usr/libexec/syn-mirror/rules load \$PASSWORD \$FIRST \$LAST \$WAIT \$TRIES \$BLOCK \$GUARD \$SHORT \$GUESSES && perl /usr/libexec/syn-mirror/give.pl &"
fi
echo "SYN Mirror: requests for a port at $FIRST, ports of meeting $((FIRST + 1))-$LAST"
