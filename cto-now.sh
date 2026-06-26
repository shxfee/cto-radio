#!/usr/bin/env bash
# Polls go-librespot and writes now.json into the Icecast webroot, so
# listen.html can show the current track's art, title, artist and progress.
# The file must be writable by the user running this service (pre-create it
# owned by that user; the webroot itself stays root-owned).
set -uo pipefail

OUT="${CTO_NOW_OUT:-/usr/share/icecast/web/now.json}"
API="${CTO_LIBRESPOT_API:-http://127.0.0.1:3678/status}"
INTERVAL="${CTO_NOW_INTERVAL:-2}"

while true; do
  curl -fsS --max-time 2 "$API" 2>/dev/null | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(1)
t = d.get("track") or {}
json.dump({
    "paused":   d.get("paused"),
    "stopped":  d.get("stopped"),
    "name":     t.get("name"),
    "artist":   ", ".join(t.get("artist_names") or []),
    "album":    t.get("album_name"),
    "art":      t.get("album_cover_url"),
    "position": t.get("position"),
    "duration": t.get("duration"),
}, sys.stdout)
' > "$OUT" 2>/dev/null || true
  sleep "$INTERVAL"
done
