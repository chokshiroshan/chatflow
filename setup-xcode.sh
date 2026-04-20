#!/bin/bash
# Generate Xcode project from Package.swift
cd "$(dirname "$0")"

echo "🔧 Generating Xcode project..."
swift package generate-xcodeproj 2>/dev/null || true

# If generate-xcodeproj isn't available (Swift 6+), use xcodebuild
if [ ! -f "Flow.xcodeproj/project.pbxproj" ]; then
    echo "📦 Using xcodebuild to generate workspace..."
    xcodebuild -scheme Flow -destination 'platform=macOS'
fi

echo ""
echo "✅ Done! Open in Xcode:"
echo "   open Package.swift"
echo ""
echo "Then in Xcode:"
echo "   1. Select Flow scheme → My Mac"
echo "   2. Product → Run (⌘R)"
echo "   3. Grant permissions when prompted"
