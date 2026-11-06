# shellcheck shell=bash
# shellcheck disable=SC2034  # variables are used by the scripts that source this file
# Every pinned source in one place: versions, SHA-256 sums and git commits.
# Sourced by env.sh (so every build script), fetch-sources.sh and update-crossover.sh.
# scripts/update-crossover.sh --apply rewrites the two CROSSOVER_ lines.

CROSSOVER_VERSION=26.3.0
CROSSOVER_SHA256=ac99c8ca4b3848f3e81784135f023df266b61c2345726ea55a50b3e030dd6872

NETTLE_VERSION=3.10
NETTLE_SHA256=b4c518adb174e484cb4acea54118f02380c7133771e7e9beb98a0787194ee47c
MPG123_VERSION=1.33.7
MPG123_SHA256=31d0e35a4ca567ec9b5ebda6c3062bb4435d6d3eacd6ef0d95cadd7854dc03ee
SDL2_VERSION=2.32.10
SDL2_SHA256=5f5993c530f084535c65a6879e9b26ad441169b3e25d789d83287040a9ca5165

DXMT_COMMIT=9839e55f98d4aca103957ee4132d6395a325a9ed
LLVM_COMMIT=8dfdcc7b7bf66834a761bd8de445840ef68e4d1a      # llvmorg-15.0.7
MOLTENVK_COMMIT=db66022459ffb663aa2b50f6b018bc2e124f5edf  # v1.4.2
DXVK_MACOS_COMMIT=8f1e28deed3ad30802f7e1bdff428ec14e6e7817

# GLib's subprojects (GLib itself comes from the CrossOver tarball).
LIBFFI_COMMIT=83d0cfd00d7d37af4b4349511d29f1f0512621b3
PROXY_LIBINTL_COMMIT=c03e1a74b17fa7ec467e110130775409e4828a4c
GVDB_COMMIT=0854af0fdb6d527a8d1999835ac2c5059976c210
# What GLib's wraps ask for; update-crossover.sh fails when a new tarball asks for something else.
LIBFFI_WRAP_REVISION=meson
PROXY_LIBINTL_WRAP_REVISION=0.4
PCRE2_VERSION=10.42      # must match GLib's subprojects/pcre2.wrap
PCRE2_WRAP=10.42-2
PCRE2_SHA256=8d36cd8cb6ea2a4c2bb358ff6411b0c788633a2a45dabbf1aeb4b701d1b5e840
PCRE2_PATCH_SHA256=350dc342b81a1611af43e5cc23f1b10453c7df51d5bb60ab9ee247daf03802bc
