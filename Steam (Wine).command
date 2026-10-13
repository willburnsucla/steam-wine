#!/bin/bash
# Double-click to start Windows Steam on our self-built Wine. Close this window or press
# Ctrl-C to leave Steam running; run `scripts/steam.sh --stop` to quit everything.
cd "$(dirname "$0")" && exec scripts/steam.sh "$@"
