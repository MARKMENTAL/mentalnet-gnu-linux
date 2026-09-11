#!/bin/sh
# Copyright (C) 2026 Mark Robillard Jr (MARKMENTAL)
# SPDX-License-Identifier: GPL-3.0-or-later
#
# post-image.sh - publish the Mentalnet ISO under a unique build name
#
# Invoked by Buildroot (BR2_ROOTFS_POST_IMAGE_SCRIPT) with the
# binaries directory as first argument.
#
# The ISO is copied to mentalnet-gnulinux-intel32-<stamp>.iso so that
# uploads to hypervisors (Proxmox in particular) can never be confused
# with a previous build's storage volume, and its SHA256 is printed
# for the build log.

set -e

BINARIES_DIR="${1}"
ISO="${BINARIES_DIR}/rootfs.iso9660"

[ -f "${ISO}" ] || exit 0

# reuse the stamp recorded by post-build.sh so the ISO name matches
# the build id visible inside the guest; fall back to a fresh stamp
STAMP="$(cat "${BINARIES_DIR}/.mn-build-stamp" 2>/dev/null || date +%Y%m%d-%H%M%S)"

OUT="${BINARIES_DIR}/mentalnet-gnulinux-intel32-${STAMP}.iso"
cp "${ISO}" "${OUT}"

echo "Published: ${OUT}"
sha256sum "${OUT}"
