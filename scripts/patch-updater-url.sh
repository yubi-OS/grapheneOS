#!/usr/bin/env bash
set -euo pipefail

CONFIG_XML="${1:-/mnt/extended/grapheneos/workspace/packages/apps/Updater/res/values/config.xml}"
OTA_URL="${OTA_URL:-https://ota.yubios.org/}"

if [ ! -f "$CONFIG_XML" ]; then
  echo "ERROR: Updater config.xml not found at $CONFIG_XML" >&2
  exit 1
fi

sed -i -E "s|<string name=\"url\" translatable=\"false\">[^<]+</string>|<string name=\"url\" translatable=\"false\">${OTA_URL}</string>|g" "$CONFIG_XML"

if grep -q "<string name=\"url\" translatable=\"false\">${OTA_URL}</string>" "$CONFIG_XML"; then
  echo "OK: Overrode Updater URL in $CONFIG_XML -> ${OTA_URL}"
else
  echo "ERROR: Failed to override Updater URL in $CONFIG_XML" >&2
  exit 1
fi
