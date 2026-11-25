#!/usr/bin/env bash
# Gera dist/pokemon-widget.plasmoid (um .zip com metadata.json + contents/ na raiz).
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p dist
out="dist/pokemon-widget.plasmoid"
rm -f "$out"
python3 -I - "$out" <<'PY'
import os, sys, zipfile
out = sys.argv[1]
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    z.write("metadata.json")
    for root, dirs, files in os.walk("contents"):
        dirs.sort()
        for f in sorted(files):
            z.write(os.path.join(root, f))
PY
echo "$out"
