#!/bin/sh
# The check of the release on Linux ( release.yml ), as root: syn-mirror-linux.sh installs SYN Mirror, writes every file as it is in
# the folder SynMirror, loads the rules and starts `give` - by systemd when there is one, by itself when not; installing again keeps
# the settings; `remove` takes it all away.
#   sh .github/linux-install.sh <syn-mirror-linux.sh>

set -e
installer=$1
s=$(cd "$(dirname "$0")/.." && pwd)
CONF=/etc/syn-mirror.conf
bad=0
same() { cmp -s "$s/$1" "$2" || { echo "not as in the folder: $2"; bad=1; }; }
systemd() { command -v systemctl >/dev/null && [ -d /run/systemd/system ]; }
give_runs() {
	if systemd; then
		systemctl is-active --quiet syn-mirror
	else
		[ -f /run/syn-mirror.pid ] && kill -0 "$(cat /run/syn-mirror.pid)" 2>/dev/null
	fi
}

sh "$installer"
same OpenWRT/files/rules /usr/libexec/syn-mirror/rules
same Linux/give.pl /usr/libexec/syn-mirror/give.pl
same Linux/syn-mirror /usr/local/sbin/syn-mirror
same OpenWRT/files/syn-mirror.nft /usr/share/syn-mirror/syn-mirror.nft
[ -x /usr/libexec/syn-mirror/rules ] || { echo "not executable: /usr/libexec/syn-mirror/rules"; bad=1; }
[ -x /usr/local/sbin/syn-mirror ] || { echo "not executable: /usr/local/sbin/syn-mirror"; bad=1; }
grep -qE '^PASSWORD=[A-Za-z0-9]{16}$' "$CONF" || { echo "the password made is not 16 characters"; bad=1; }
[ "$(stat -c %a "$CONF")" = 600 ] || { echo "$CONF is not 600"; bad=1; }
! systemd || same Linux/syn-mirror.service /etc/systemd/system/syn-mirror.service
sleep 1
nft list table ip syn_mirror >/dev/null || { echo "the table syn_mirror is not loaded"; bad=1; }
give_runs || { echo "give does not run"; bad=1; }

# again: an update, the settings and the ports given kept
sed -i 's/^PASSWORD=.*/PASSWORD=Keep1234Keep5678/' "$CONF"
nft add element ip syn_mirror given { 41234 }
sh "$installer" >/dev/null
grep -qx 'PASSWORD=Keep1234Keep5678' "$CONF" || { echo "installing again lost the password"; bad=1; }
nft get element ip syn_mirror given { 41234 } >/dev/null 2>&1 || { echo "installing again lost the ports given"; bad=1; }
sleep 1
give_runs || { echo "give does not run after installing again"; bad=1; }

sh "$installer" remove
for f in /usr/libexec/syn-mirror /usr/share/syn-mirror "$CONF" /etc/systemd/system/syn-mirror.service /usr/local/sbin/syn-mirror; do
	[ ! -e "$f" ] || { echo "remove left $f"; bad=1; }
done
! nft list table ip syn_mirror >/dev/null 2>&1 || { echo "remove left the table syn_mirror"; bad=1; }
! pgrep -f /usr/libexec/syn-mirror/give.pl >/dev/null || { echo "remove left give running"; bad=1; }

[ "$bad" = 0 ] && echo "the installer of one file: installed, updated, removed"
exit "$bad"
