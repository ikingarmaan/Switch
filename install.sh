#!/usr/bin/env bash
# ==============================================================================
#  Switch for macOS - Instant One-Click Installer
#  GitHub: https://github.com/ikingarmaan/Switch
# ==============================================================================
set -e

REPO="ikingarmaan/Switch"
APP_NAME="Switch.app"
INSTALL_DIR="/Applications"
TARGET_APP="$INSTALL_DIR/$APP_NAME"
TEMP_DIR="$(mktemp -d)"

cleanup() {
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

# Colors for terminal output
BOLD="\033[1m"
GREEN="\033[0;32m"
BLUE="\033[0;34m"
CYAN="\033[0;36m"
YELLOW="\033[0;33m"
RED="\033[0;31m"
RESET="\033[0m"

echo -e "${CYAN}${BOLD}"
echo "   _____          _ _       _     "
echo "  / ____|        (_) |     | |    "
echo " | (_____      ___| |_ ___| |__  "
echo "  \___ \ \ /\ / / | __/ __| '_ \ "
echo "  ____) \ V  V /| | || (__| | | |"
echo " |_____/ \_/\_/ |_|\__\___|_| |_|"
echo -e "${RESET}"
echo -e "${BOLD}The Ultimate All-In-One macOS Menu Bar Control Center${RESET}"
echo -e "${BLUE}https://github.com/${REPO}${RESET}\n"

# Verify macOS
if [[ "$(uname -s)" != "Darwin" ]]; then
    echo -e "${RED}Error: Switch is only supported on macOS.${RESET}"
    exit 1
fi

echo -e "${BLUE}==>${RESET} Finding latest release of ${BOLD}Switch${RESET}..."
DOWNLOAD_URL="https://github.com/${REPO}/releases/latest/download/Switch.zip"

echo -e "${BLUE}==>${RESET} Downloading ${BOLD}Switch.zip${RESET}..."
ZIP_PATH="$TEMP_DIR/Switch.zip"

if ! curl -fSL --progress-bar "$DOWNLOAD_URL" -o "$ZIP_PATH"; then
    echo -e "${YELLOW}Falling back to direct release asset tag v1.0.0...${RESET}"
    FALLBACK_URL="https://github.com/${REPO}/releases/download/v1.0.0/Switch.zip"
    if ! curl -fSL --progress-bar "$FALLBACK_URL" -o "$ZIP_PATH"; then
        echo -e "${RED}Error: Failed to download Switch.zip from GitHub.${RESET}"
        echo "Please visit https://github.com/${REPO}/releases to download manually."
        exit 1
    fi
fi

# Stop any currently running instance of Switch
if pgrep -x "Switch" >/dev/null 2>&1; then
    echo -e "${YELLOW}==>${RESET} Stopping running instance of Switch..."
    killall Switch 2>/dev/null || true
    sleep 0.5
fi

echo -e "${BLUE}==>${RESET} Installing Switch into ${BOLD}$INSTALL_DIR${RESET}..."
rm -rf "$TARGET_APP"

# Unpack archive preserving permissions
ditto -x -k "$ZIP_PATH" "$INSTALL_DIR/"

# Clear quarantine attribute for smooth launch
if [ -d "$TARGET_APP" ]; then
    echo -e "${BLUE}==>${RESET} Authorizing application bundle..."
    xattr -cr "$TARGET_APP" 2>/dev/null || true
else
    echo -e "${RED}Error: Installation failed. Switch.app was not found in $INSTALL_DIR.${RESET}"
    exit 1
fi

# Register app icon with Finder
touch "$TARGET_APP"

echo -e "${BLUE}==>${RESET} Launching ${BOLD}Switch${RESET}..."
open "$TARGET_APP"

echo -e "\n${GREEN}${BOLD}🎉 Switch for macOS installed successfully!${RESET}"
echo -e "Look for the ${BOLD}Switch${RESET} icon in your menu bar at the top right of your screen."
echo -e "Tip: Press ${BOLD}F9${RESET} to summon the clipboard manager, or double-knock your Mac body for an instant screenshot!"
echo -e "\nEnjoying Switch? Star the repo at: ${CYAN}https://github.com/${REPO}${RESET}\n"
