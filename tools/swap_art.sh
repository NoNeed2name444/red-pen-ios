#!/usr/bin/env bash
# Swap in new launch or icon art, then rebuild everything made from it (the
# launch mark and its chest-piece position, the app icon, and its layers for
# IconLayersView). The sources are named by mode, not by colour, so a new
# picture is one file copied over the old one:
#   design/launch-logo/light.png, dark.png    the launch mark on its flat ground
#   design/icon/source/icon-light.png, icon-dark.png, icon-tinted.png
# Either copy it there yourself and run this with no arguments, or name it:
#   tools/swap_art.sh launch-dark=PATH icon-dark=PATH
# (keys: launch-light, launch-dark, icon-light, icon-dark, icon-tinted).
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
for pair in "$@"; do
  key="${pair%%=*}"; file="${pair#*=}"
  case "$key" in
    launch-light) dest=design/launch-logo/light.png ;;
    launch-dark)  dest=design/launch-logo/dark.png ;;
    icon-light|icon-dark|icon-tinted) dest="design/icon/source/$key.png" ;;
    *) echo "unknown art '$key' (launch-light, launch-dark, icon-light, icon-dark, icon-tinted)" >&2; exit 2 ;;
  esac
  [ -f "$file" ] || { echo "no such file: $file" >&2; exit 2; }
  cp "$file" "$dest"
done
python3 tools/make_launch_logo.py
python3 tools/make_icon.py
python3 tools/icon_layers.py
git status --short design ios
