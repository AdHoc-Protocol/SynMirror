#!/bin/sh
# Installs SYN Mirror on this router, from the folder this script is in:
#   sh install.sh
# or from syn-mirror-openwrt.sh, the release of GitHub: this script with the files of the folder in it, one file to copy
# ( ../pack.sh makes it ):
#   sh syn-mirror-openwrt.sh
# The modules of ucode `give` needs come from the packages of OpenWrt when they are not there: ucode-mod-socket, 60 KiB, the
# sockets; ucode-mod-math, which snapshots of OpenWrt do not have. nftables, fw4 and ucode are there already. A password of 8 characters is made when
# /etc/config/syn-mirror has none, and printed. A router with LuCI gets the page Services > SYN Mirror too, with the button
# Uninstall. `sh install.sh remove` does the same: every file installed is erased, the settings too. Installing again over an
# installed SYN Mirror updates it and keeps its settings. The folder, or the file, copied into /tmp, is erased at the end: the files
# are in their places, and the flash keeps them once.

set -e
# the real path: /var of OpenWrt is a link to /tmp
here=$(cd "$(dirname "$0")" && pwd -P)

# src <file of the folder>: its text. The installer of one file has its own src, its files in it, and the path of itself in packed
[ -n "$packed" ] || src() { cat "$here/$1"; }
# put <file of the folder> <its place> [<mode>]: written there at once, no copy anywhere else
put() {
	src "$1" > "$2"
	[ -z "$3" ] || chmod "$3" "$2"
}

if [ "$1" = remove ]; then
	# an argument, not the standard input: the package managers it calls read that
	sh -c "$(src files/uninstall)"
	exit 0
fi

# the modules of ucode `give` and public.uc import, as DEPENDS of the Makefile: socket is not in OpenWrt, math is not in its
# snapshots
modules='socket uci math fs'
need=
for m in $modules; do
	[ -f "/usr/lib/ucode/$m.so" ] || need="$need ucode-mod-$m"
done
if [ -n "$need" ]; then
	# a feed that failed to update leaves the others: the packages may be in them
	if command -v apk >/dev/null; then
		apk update >/dev/null 2>&1 || true
		apk add $need >/dev/null || true
	else
		opkg update >/dev/null 2>&1 || true
		opkg install $need >/dev/null || true
	fi
	for m in $modules; do
		if [ ! -f "/usr/lib/ucode/$m.so" ]; then
			echo "SYN Mirror needs the package ucode-mod-$m, and it did not install: check the internet of the router, and run the installer again" >&2
			exit 1
		fi
	done
fi

mkdir -p /usr/libexec/syn-mirror /usr/share/syn-mirror
put files/rules /usr/libexec/syn-mirror/rules 755
put files/uninstall /usr/libexec/syn-mirror/uninstall 755
put files/give.uc /usr/libexec/syn-mirror/give.uc
put files/public.uc /usr/libexec/syn-mirror/public.uc
put files/syn-mirror.nft /usr/share/syn-mirror/syn-mirror.nft
put files/syn-mirror.init /etc/init.d/syn-mirror 755
[ -f /etc/config/syn-mirror ] || put files/syn-mirror.config /etc/config/syn-mirror

if [ -z "$(uci -q get syn-mirror.main.password)" ]; then
	password=$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 8)
	uci set syn-mirror.main.password="$password"
	uci commit syn-mirror
	echo "the password of this router: $password"
fi

if [ -d /www/luci-static/resources ]; then
	mkdir -p /www/luci-static/resources/view /usr/share/luci/menu.d /usr/share/rpcd/acl.d /usr/libexec/rpcd
	put luci/htdocs/luci-static/resources/view/syn-mirror.js /www/luci-static/resources/view/syn-mirror.js
	put luci/root/usr/share/luci/menu.d/luci-app-syn-mirror.json /usr/share/luci/menu.d/luci-app-syn-mirror.json
	put luci/root/usr/share/rpcd/acl.d/luci-app-syn-mirror.json /usr/share/rpcd/acl.d/luci-app-syn-mirror.json
	put luci/root/usr/libexec/rpcd/syn-mirror /usr/libexec/rpcd/syn-mirror 755
	# LuCI and rpcd see the new page
	rm -f /tmp/luci-indexcache* /tmp/luci-modulecache/* 2>/dev/null || true
	/etc/init.d/rpcd reload 2>/dev/null || true
	echo "LuCI: Services > SYN Mirror"
fi

/etc/init.d/syn-mirror enable
/etc/init.d/syn-mirror restart
first=$(uci -q get syn-mirror.main.first)
echo "SYN Mirror: requests for a port at $first, ports of meeting $((first + 1))-$(uci -q get syn-mirror.main.last)"

# the installer in /tmp is not needed any more and takes the memory: the file of one goes; of the folder, its files go, and the
# folder when nothing else is in it
if [ -n "$packed" ]; then
	case "$packed" in
	/tmp/?*)
		[ ! -f "$packed" ] || { rm -f "$packed"; echo "the installer $packed is erased"; }
		;;
	esac
else
	case "$here" in
	/tmp/?*)
		rm -rf "$here/install.sh" "$here/Makefile" "$here/files" "$here/luci"
		if rmdir "$here" 2>/dev/null; then
			echo "the folder $here is erased"
		else
			echo "the files of SYN Mirror are erased from $here; the rest in it stays"
		fi
		;;
	esac
fi
echo "to remove SYN Mirror: Uninstall on its page, or /usr/libexec/syn-mirror/uninstall"
