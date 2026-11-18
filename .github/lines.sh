#!/bin/sh
# Every line of docs/lines.tsv through both scripts of the server - syn-mirror-server.pl and .ps1, `--parse` / `-Parse`: what each makes
# of it is what the file says. RemoteDesk and DeFreez read their copies of the same file in their tests: one form of the lines for all.
#
#   sh .github/lines.sh        ( from the folder of SynMirror; perl and pwsh )
cd "$(dirname "$0")/.." || exit 1
tab=$(printf '\t')
cr=$(printf '\r')
failed=0
cases=0
while IFS="$tab" read -r line want; do
	want=${want%"$cr"} # a checkout of Windows ends its lines in CRLF
	case "$line" in '#'* | '') continue ;; esac
	cases=$((cases + 1))
	got=$(perl Server/syn-mirror-server.pl --parse "$line")
	[ "$got" = "$want" ] || { echo "FAIL  .pl  '$line': '$got', not '$want'"; failed=$((failed + 1)); }
	got=$(pwsh -NoProfile -File Server/syn-mirror-server.ps1 -Parse "$line" | tr -d '\r')
	[ "$got" = "$want" ] || { echo "FAIL  .ps1 '$line': '$got', not '$want'"; failed=$((failed + 1)); }
done < docs/lines.tsv
echo "$cases lines, $failed failed"
[ "$failed" -eq 0 ]
