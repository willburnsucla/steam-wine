#!/bin/bash
# Double-click to start Windows Steam on our self-built Wine. To quit Steam and everything Wine
# started, use Steam's own Exit or run `scripts/steam.sh --quit`.
cd "$(dirname "$0")" && exec scripts/steam.sh "$@"
