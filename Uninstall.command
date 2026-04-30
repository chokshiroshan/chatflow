#!/bin/bash
# ChatFlow Uninstaller
# Double-click this file to completely remove ChatFlow from your Mac.

echo "🗑️ ChatFlow Uninstaller"
echo "━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Check if installed
if [ ! -d "/Applications/ChatFlow.app" ]; then
    echo "ℹ️ ChatFlow is not in /Applications. Nothing to uninstall."
    read -p "Press Enter to close..."
    exit 0
fi

echo "This will remove:"
echo "  • /Applications/ChatFlow.app"
echo "  • ~/Library/Application Support/ChatFlow (config, logs, vocabulary)"
echo "  • ~/Library/Caches/ChatFlow"
echo ""

# Ask for confirmation
read -p "Continue? (y/N): " confirm
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "Cancelled."
    read -p "Press Enter to close..."
    exit 0
fi

echo ""

# Quit the app if running
if pgrep -f "ChatFlow" > /dev/null 2>&1; then
    echo "⏹ Stopping ChatFlow..."
    pkill -f "ChatFlow" 2>/dev/null
    sleep 1
fi

# Remove the app
echo "🗑️ Removing ChatFlow.app..."
rm -rf /Applications/ChatFlow.app 2>/dev/null

if [ -d "/Applications/ChatFlow.app" ]; then
    echo "🔐 Need admin access..."
    osascript -e 'do shell script "rm -rf /Applications/ChatFlow.app" with administrator privileges'
fi

# Remove app data
echo "🗑️ Removing config and logs..."
rm -rf ~/Library/Application\ Support/ChatFlow 2>/dev/null
rm -rf ~/Library/Caches/ChatFlow 2>/dev/null

# Remove login item if set
osascript -e 'tell application "System Events" to delete login item "ChatFlow"' 2>/dev/null

echo ""
echo "✅ ChatFlow has been completely removed."
echo ""
read -p "Press Enter to close..."
