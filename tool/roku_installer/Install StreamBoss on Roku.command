#!/bin/bash
# Double-click this file (it opens Terminal and runs the installer that sits next to it).
cd "$(dirname "$0")" || exit 1
# The download marks these files as "from the internet"; clear that so macOS does not block the installer.
xattr -dr com.apple.quarantine . 2>/dev/null
chmod +x ./roku-installer
./roku-installer
echo
read -n 1 -s -r -p "Press any key to close this window."
echo
