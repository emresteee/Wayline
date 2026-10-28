#!/bin/bash
set -u
launchctl bootout system/app.wayline.daemon 2>/dev/null || true
pfctl -a com.apple/250.Wayline -F all 2>/dev/null || true
rm -rf /Library/PrivilegedHelperTools/app.wayline /Library/LaunchDaemons/app.wayline.daemon.plist \
	"/Library/Application Support/Wayline" /Library/Logs/Wayline /var/run/app.wayline.daemon.sock
