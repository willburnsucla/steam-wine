# shellcheck shell=bash
# Runtime environment shared by steam.sh and wine-run.sh (not the build; see env.sh for that).
# Callers set ROOT first.

# GStreamer for winegstreamer: only our x86_64 plugins, and a registry kept with the prefixes
# so it never mixes with another GStreamer install on this Mac.
export GST_PLUGIN_SYSTEM_PATH_1_0="$ROOT/deps/lib/gstreamer-1.0"
export GST_PLUGIN_PATH_1_0=""
export GST_REGISTRY_1_0="$ROOT/prefixes/gst-registry.bin"
export GST_PLUGIN_SCANNER_1_0="$ROOT/deps/libexec/gstreamer-1.0/gst-plugin-scanner"
unset GST_REGISTRY_UPDATE GST_PLUGIN_LOADING_WHITELIST GST_PLUGIN_SCANNER
