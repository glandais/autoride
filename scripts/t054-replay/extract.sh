#!/usr/bin/env bash
# Build the replay substrate from a set of exported audit logs (T054).
#
# Only `sv:3` files can be used: the windowed fit (T050) is what is being
# replayed, and a `sv:2` line carries no `asd`/`gav`. A `sv:3` *file* can still
# contain rows written by an older process — the exporter stamps the header with
# the build that ran the export, not the build that wrote each row — so the
# filter below is on the row, not the file.
#
#   ./extract.sh ~/Documents/autoride-audit-*.ndjson.gz
#
# Writes evals3.tsv (start evaluations), win.tsv (the stop path's 1 Hz motion
# window, which is the only continuous record of what happened *during* a
# recording) and tripev.tsv (trip lifecycle) into the working directory.
set -euo pipefail

sv3=()
for f in "$@"; do
  [ "$(gzcat "$f" | head -1 | jq -r .sv)" = "3" ] && sv3+=("$f")
done
[ ${#sv3[@]} -gt 0 ] || { echo "no sv:3 log among the arguments" >&2; exit 1; }
echo "pooling ${#sv3[@]} logs" >&2

# Rows are deduplicated on the whole line: overlapping exports share a database,
# so the same event appears verbatim in each of them.
gzcat "${sv3[@]}" | jq -rc 'select(.e=="start" and .asd!=null)
  |[.t,.c,.n,(if .go then 1 else 0 end),.asd,.gav,.wn,(.spk//-1),
    (if .vt==true then 1 elif .vt==false then 0 else -1 end)]|@tsv' \
  | sort -n -u > evals3.tsv
gzcat "${sv3[@]}" | jq -rc 'select(.e=="win")|[.t,.sd,.gy,.n]|@tsv' | sort -n -u > win.tsv
gzcat "${sv3[@]}" | jq -rc 'select(.e=="trip")
  |[.t,.id,.a,(.why//""),(.dist//0|floor),(.dur//0),(.n//0),(.net//0|floor),
    (.avg//0),(.max//0),(.conf//""),(.pau//0)]|@tsv' | sort -n -u > tripev.tsv
wc -l evals3.tsv win.tsv tripev.tsv >&2
