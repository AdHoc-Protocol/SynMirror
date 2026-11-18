#!/bin/sh
# Makes an installer of one file: the install.sh of a folder, and before it every file it installs, each a here-document of the
# function src. install.sh writes each straight to its place through put: nothing is unpacked anywhere first. The release workflow
# of GitHub runs it:
#   sh pack.sh openwrt syn-mirror-openwrt.sh   OpenWRT/install.sh, the files of OpenWRT/files and OpenWRT/luci but the Makefiles;
#                                              the router holds in /tmp only this file, erased at the end
#   sh pack.sh linux syn-mirror-linux.sh       Linux/install.sh, the files of Linux - the command syn-mirror among them - and the
#                                              rules of OpenWRT/files
# The lines end in LF there: a CR of a checkout on Windows is dropped.

set -e
here=$(cd "$(dirname "$0")" && pwd)
out=$2
# base: the folder the names of src are in, as its install.sh takes them
case "$1" in
openwrt)
	base=$here/OpenWRT
	installer=$base/install.sh
	list=$(cd "$base" && find files luci -type f ! -name Makefile | LC_ALL=C sort)
	about='# SYN Mirror for OpenWrt in one file: copy it to the router, into /tmp, and run
#   sh syn-mirror-openwrt.sh
# It erases itself from /tmp at the end.'
	;;
linux)
	base=$here
	installer=$base/Linux/install.sh
	list='Linux/give.pl Linux/syn-mirror Linux/syn-mirror.conf Linux/syn-mirror.service OpenWRT/files/rules OpenWRT/files/syn-mirror.nft'
	about='# SYN Mirror for a Linux computer in one file:
#   sudo sh syn-mirror-linux.sh
# and to remove it, with the settings:
#   sudo sh syn-mirror-linux.sh remove'
	;;
*)
	echo "usage: sh pack.sh openwrt|linux <file to make>" >&2
	exit 1
	;;
esac
[ -n "$out" ] || { echo "usage: sh pack.sh openwrt|linux <file to make>" >&2; exit 1; }
# the end of every here-document: no file may have this line
END=SYN_MIRROR_EOF

for f in $list; do
	if tr -d '\r' < "$base/$f" | grep -qx "$END"; then
		echo "pack.sh: $f has the line $END" >&2
		exit 1
	fi
	# a here-document ends its text with a line break: a file without one would get it
	if [ -n "$(tail -c 1 "$base/$f")" ]; then
		echo "pack.sh: $f does not end with a line break" >&2
		exit 1
	fi
done

trap 'rm -f "$out"' EXIT
{
	echo '#!/bin/sh'
	echo "$about"
	echo '# Below: the files it installs, then the install.sh of the folder, which writes each of them to its place.'
	echo
	echo '# the path of this installer'
	echo 'packed=$(cd "$(dirname "$0")" && pwd -P)/$(basename "$0")'
	echo
	echo 'src() {'
	echo '	case "$1" in'
	for f in $list; do
		echo "	$f)"
		echo "		cat <<'$END'"
		tr -d '\r' < "$base/$f"
		echo "$END"
		echo '		;;'
	done
	echo '	*)'
	echo '		echo "SYN Mirror: no $1 in this installer" >&2'
	echo '		return 1'
	echo '		;;'
	echo '	esac'
	echo '}'
	echo
	tr -d '\r' < "$installer"
} > "$out"
trap - EXIT
echo "$out: $(wc -c < "$out") bytes, $(echo $list | wc -w) files"
