#!/usr/bin/env bash
# grant_clamshell.sh — One-time passwordless grant for pmset disablesleep
# This allows Switch to keep your Mac awake even when the lid is closed
# without asking for password every time.

set -euo pipefail

TARGET_USER="${SUDO_USER:-$(id -un)}"
if [ -z "$TARGET_USER" ] || [ "$TARGET_USER" = "root" ]; then
  TARGET_USER="$(stat -f%Su /dev/console 2>/dev/null || true)"
fi

if [ -z "$TARGET_USER" ] || [ "$TARGET_USER" = "root" ]; then
  echo "Error: could not resolve non-root console user." >&2
  exit 1
fi

SUDOERS_FILE="/etc/sudoers.d/switch-disablesleep"
TEMP_FILE="/tmp/switch-disablesleep.$$"

echo "==> Configuring passwordless pmset disablesleep for user: $TARGET_USER"

echo "$TARGET_USER ALL=(ALL) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1" > "$TEMP_FILE"
chmod 0440 "$TEMP_FILE"

if sudo /usr/sbin/visudo -c -f "$TEMP_FILE" >/dev/null 2>&1; then
    sudo mv -f "$TEMP_FILE" "$SUDOERS_FILE"
    sudo chown root:wheel "$SUDOERS_FILE"
    sudo chmod 0440 "$SUDOERS_FILE"
    echo "==> SUCCESS! Passwordless grant installed at $SUDOERS_FILE"
else
    rm -f "$TEMP_FILE"
    echo "==> ERROR: visudo validation failed." >&2
    exit 1
fi
