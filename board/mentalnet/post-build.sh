#!/bin/sh
#
# post-build.sh - stamp the Mentalnet root filesystem with a build id
#
# Invoked by Buildroot (BR2_ROOTFS_POST_BUILD_SCRIPT) with the target
# directory as first argument. The same stamp is recorded in
# output/images/.mn-build-stamp so post-image.sh can name the ISO
# after the exact build that is inside it.
#
# The stamp is visible inside the guest:
#   - /etc/os-release  -> BUILD_ID="YYYYMMDD-HHMMSS"
#   - /etc/issue       -> shown above the login prompt

set -e

TARGET_DIR="${1}"
STAMP="$(date +%Y%m%d-%H%M%S)"
IMAGES_DIR="$(dirname "${TARGET_DIR}")/images"

# record the stamp for post-image.sh
mkdir -p "${IMAGES_DIR}"
echo "${STAMP}" > "${IMAGES_DIR}/.mn-build-stamp"

# /etc/os-release (regular file lives at /usr/lib/os-release)
OS_RELEASE="${TARGET_DIR}/usr/lib/os-release"
sed -i '/^BUILD_ID=/d' "${OS_RELEASE}"
echo "BUILD_ID=\"${STAMP}\"" >> "${OS_RELEASE}"

# login banner
ISSUE="${TARGET_DIR}/etc/issue"
sed -i '/^Mentalnet GNU\/Linux build /d' "${ISSUE}"
printf 'Mentalnet GNU/Linux build %s\n' "${STAMP}" >> "${ISSUE}"
