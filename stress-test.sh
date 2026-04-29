#!/bin/bash
# ═══════════════════════════════════════════════════
# 🧪 ChatFlow Realtime API Stress Test
# ═══════════════════════════════════════════════════
#
# Usage:
#   ./stress-test.sh [duration] [--tier free|plus] [--aggressive] [--parallel N] [--token TOKEN] [--silence]
#
# Examples:
#   ./stress-test.sh 600 --tier free --aggressive
#   ./stress-test.sh 600 --tier plus --aggressive --parallel 2
#   ./stress-test.sh --token sk-... --tier plus
#
# Output (per worker):
#   ~/.flow/stress-test-results-<tier>[-wN].json
#   ~/.flow/stress-test-<tier>[-wN]-<timestamp>.log
# ═══════════════════════════════════════════════════

set -euo pipefail
cd "$(dirname "$0")"

DURATION=0
TOKEN=""
TIER=""
AGGRESSIVE=0
PARALLEL=1

while [[ $# -gt 0 ]]; do
    case $1 in
        --token)      TOKEN="$2"; shift 2 ;;
        --tier)       TIER="$2"; shift 2 ;;
        --aggressive) AGGRESSIVE=1; shift ;;
        --parallel)   PARALLEL="$2"; shift 2 ;;
        --silence)    shift ;;  # legacy no-op (aggressive controls cadence now)
        --help|-h)
            cat <<EOF
Usage: $0 [duration_seconds] [options]

  duration_seconds       How long to run (0 = until failure)
  --token TOKEN          OpenAI/Codex OAuth token (else reads from keychain/file/env)
  --tier free|plus       Tags output filenames so back-to-back runs don't overwrite
  --aggressive           Hammer mode: 15s utterances, 0s gap (for finding ceiling)
  --parallel N           Run N workers concurrently against the same token
  --help, -h             Show this help

EOF
            exit 0
            ;;
        *) DURATION="$1"; shift ;;
    esac
done

# Validate tier
if [ -n "$TIER" ] && [ "$TIER" != "free" ] && [ "$TIER" != "plus" ]; then
    echo "❌ --tier must be 'free' or 'plus' (got: $TIER)"
    exit 1
fi

if [ -n "$TOKEN" ]; then
    export OPENAI_TOKEN="$TOKEN"
fi

export FLOW_STRESS_TIER="$TIER"
export FLOW_STRESS_AGGRESSIVE="$AGGRESSIVE"
export FLOW_STRESS_DURATION="$DURATION"
export FLOW_STRESS_PARALLEL="$PARALLEL"

echo "🧪 ChatFlow Realtime API Stress Test"
echo "====================================="
echo "Tier:       ${TIER:-(untagged)}"
echo "Aggressive: $([ "$AGGRESSIVE" = "1" ] && echo YES || echo NO)"
echo "Parallel:   $PARALLEL worker(s)"
echo "Duration:   $([ "$DURATION" -gt 0 ] && echo "${DURATION}s" || echo 'until failure')"
echo ""

if [ "$PARALLEL" -le 1 ]; then
    echo "📝 Logs:    ~/.flow/stress-test${TIER:+-$TIER}-*.log"
    echo "📊 Results: ~/.flow/stress-test-results${TIER:+-$TIER}.json"
else
    echo "📝 Logs:    ~/.flow/stress-test${TIER:+-$TIER}-w*-*.log"
    echo "📊 Results: ~/.flow/stress-test-results${TIER:+-$TIER}-w*.json"
fi
echo ""

# Single swift test invocation; parallelism happens inside via TaskGroup.
swift test --filter "RealtimeStressTest/testUntilFailure" 2>&1 || true

echo ""
echo "Done. Results:"
ls -1 ~/.flow/stress-test-results${TIER:+-$TIER}*.json 2>/dev/null || echo "  (no results files found)"
