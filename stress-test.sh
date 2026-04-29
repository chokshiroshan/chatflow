#!/bin/bash
# ═══════════════════════════════════════════════════
# 🧪 ChatFlow Realtime API Stress Test
# ═══════════════════════════════════════════════════
#
# Usage:
#   ./stress-test.sh                    # Run until failure
#   ./stress-test.sh 120                # Run for 120 seconds
#   ./stress-test.sh --token YOUR_TOKEN # Provide token directly
#   ./stress-test.sh --silence          # Use silence instead of tone bursts
#
# Requires: macOS with a signed-in ChatFlow session
# ═══════════════════════════════════════════════════

set -euo pipefail
cd "$(dirname "$0")"

DURATION=0
TOKEN=""
EXTRA_ARGS=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --token)   TOKEN="$2"; shift 2 ;;
        --silence) EXTRA_ARGS="$EXTRA_ARGS --silence"; shift ;;
        --help|-h)
            echo "Usage: $0 [duration_seconds] [--token TOKEN] [--silence]"
            echo ""
            echo "  duration_seconds  How long to run (0 = until failure)"
            echo "  --token TOKEN     OpenAI access token (otherwise reads from keychain/file/env)"
            echo "  --silence         Use silence instead of tone bursts"
            exit 0
            ;;
        *) DURATION="$1"; shift ;;
    esac
done

# Export token if provided
if [ -n "$TOKEN" ]; then
    export OPENAI_TOKEN="$TOKEN"
fi

echo "🧪 ChatFlow Realtime API Stress Test"
echo "====================================="
echo "Duration: $([ $DURATION -gt 0 ] && echo \"${DURATION}s\" || echo 'until failure')"
echo ""

# Run the test
# Option 1: swift test (uses XCTest/Swift Testing)
# Option 2: swift build + direct run
echo "Building..."
swift build 2>&1 | tail -5

echo ""
echo "Running stress test..."
echo "Press Ctrl+C to stop early"
echo ""

# Run via swift test with filter
if [ "$DURATION" -gt 0 ]; then
    echo "⏱️  Running for ${DURATION}s..."
else
    echo "⏱️  Running until failure..."
fi
echo "📝 Logs: ~/.flow/stress-test-*.log"
echo "📊 Results: ~/.flow/stress-test-results.json"
echo ""

swift test --filter RealtimeStressTest 2>&1 || true

echo ""
echo "Done! Check results at ~/.flow/stress-test-results.json"
