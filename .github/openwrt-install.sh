#!/bin/sh
# The check of the release, in OpenWrt booted in Docker as a router ( release.yml ): syn-mirror-openwrt.sh, copied into /tmp,
# installs SYN Mirror with its page of LuCI, writes every file as it is in the folder OpenWRT and erases itself; installing again
# keeps the settings; `remove` takes it all away. The repository is at /src.

set -e
# the LAN of the router is the network of Docker: the first boot made it a bridge of its own
uci set network.lan.device=eth0
uci set network.lan.ipaddr=10.97.0.2/24
uci set network.lan.gateway=10.97.0.1
uci -q delete network.@device[0] || true
uci commit network
/etc/init.d/network reload
sleep 3
echo 'nameserver 1.1.1.1' > /tmp/resolv.conf.d/resolv.conf.auto
if command -v apk >/dev/null; then
	apk update >/dev/null && apk add luci >/dev/null
else
	opkg update >/dev/null && opkg install luci >/dev/null
fi

s=/src/OpenWRT
bad=0
same() { cmp -s "$s/$1" "$2" || { echo "not as in the folder: $2"; bad=1; }; }
runs() { [ -x "$1" ] || { echo "not executable: $1"; bad=1; }; }

cp /src/syn-mirror-openwrt.sh /tmp/
sh /tmp/syn-mirror-openwrt.sh
[ ! -e /tmp/syn-mirror-openwrt.sh ] || { echo "the installer is not erased"; bad=1; }
same files/rules /usr/libexec/syn-mirror/rules
same files/uninstall /usr/libexec/syn-mirror/uninstall
same files/give.uc /usr/libexec/syn-mirror/give.uc
same files/public.uc /usr/libexec/syn-mirror/public.uc
same files/syn-mirror.nft /usr/share/syn-mirror/syn-mirror.nft
same files/syn-mirror.init /etc/init.d/syn-mirror
same luci/htdocs/luci-static/resources/view/syn-mirror.js /www/luci-static/resources/view/syn-mirror.js
same luci/root/usr/share/luci/menu.d/luci-app-syn-mirror.json /usr/share/luci/menu.d/luci-app-syn-mirror.json
same luci/root/usr/share/rpcd/acl.d/luci-app-syn-mirror.json /usr/share/rpcd/acl.d/luci-app-syn-mirror.json
same luci/root/usr/libexec/rpcd/syn-mirror /usr/libexec/rpcd/syn-mirror
runs /usr/libexec/syn-mirror/rules
runs /usr/libexec/syn-mirror/uninstall
runs /etc/init.d/syn-mirror
runs /usr/libexec/rpcd/syn-mirror
nft list table ip syn_mirror >/dev/null || { echo "the table syn_mirror is not loaded"; bad=1; }
ubus call service list '{"name":"syn-mirror"}' | grep -q '"running": true' || { echo "give does not run"; bad=1; }

# again: an update, the settings and the ports given kept
uci set syn-mirror.main.password=Keep1234Keep5678
uci commit syn-mirror
nft add element ip syn_mirror given { 41234 }
cp /src/syn-mirror-openwrt.sh /tmp/
sh /tmp/syn-mirror-openwrt.sh >/dev/null
[ "$(uci -q get syn-mirror.main.password)" = Keep1234Keep5678 ] || { echo "installing again lost the password"; bad=1; }
nft get element ip syn_mirror given { 41234 } >/dev/null 2>&1 || { echo "installing again lost the ports given"; bad=1; }

cp /src/syn-mirror-openwrt.sh /tmp/
sh /tmp/syn-mirror-openwrt.sh remove
for f in /usr/libexec/syn-mirror /usr/share/syn-mirror /etc/init.d/syn-mirror /etc/config/syn-mirror \
	/www/luci-static/resources/view/syn-mirror.js /usr/libexec/rpcd/syn-mirror; do
	[ ! -e "$f" ] || { echo "remove left $f"; bad=1; }
done
! nft list table ip syn_mirror >/dev/null 2>&1 || { echo "remove left the table syn_mirror"; bad=1; }

[ "$bad" = 0 ] && echo "the installer of one file: installed, updated, removed"
exit "$bad"
