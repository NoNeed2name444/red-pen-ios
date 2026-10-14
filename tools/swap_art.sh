#!/usr/bin/env bash
# Swap in new launch and icon art in one go, then rebuild everything made
# from it (the launch mark and its chest-piece position, the app icon and
# its layers for IconLayersView):
#   tools/swap_art.sh <folder with 02-white-flat.png, 06-slate-flat-dark.png> \
#                     [<folder with icon-light.png, icon-dark.png, icon-tinted.png>]
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
launch="$1"; icon="${2:-}"
cp "$launch/02-white-flat.png" "$launch/06-slate-flat-dark.png" design/launch-logo/
python3 tools/make_launch_logo.py
if [ -n "$icon" ]; then
  cp "$icon/icon-light.png" "$icon/icon-dark.png" "$icon/icon-tinted.png" design/icon/source/
  python3 tools/make_icon.py
  python3 tools/icon_layers.py
fi
git status --short design ios
