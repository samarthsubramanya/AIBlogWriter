#!/usr/bin/env bash
# test_local.sh — Verify all services are healthy and test blog post generation
set -euo pipefail

ORCH_URL="${ORCHESTRATOR_URL:-http://localhost:8005}"
UI_URL="${FRONTEND_URL:-http://localhost:8080}"
R_URL="http://localhost:8001"
O_URL="http://localhost:8002"
W_URL="http://localhost:8003"
E_URL="http://localhost:8004"

PASS=0; FAIL=0

check() {
  local label=$1 url=$2
  if curl -sf --max-time 5 "$url" > /dev/null 2>&1; then
    echo "  ✓  $label"
    ((PASS++))
  else
    echo "  ✗  $label  ($url)"
    ((FAIL++))
  fi
}

echo "=== Health Checks ==="
check "Frontend"     "$UI_URL/health"
check "Orchestrator" "$ORCH_URL/health"
check "Researcher"   "$R_URL/health"
check "Outliner"     "$O_URL/health"
check "Writer"       "$W_URL/health"
check "Editor"       "$E_URL/health"
echo ""

if [[ $FAIL -gt 0 ]]; then
  echo "WARN: $FAIL service(s) not reachable — make sure run_local.sh is running."
  echo ""
fi

# ── Functional test ────────────────────────────────────────────────────────
echo "=== Functional Test (calls all 4 agents — expect 2-4 min) ==="
echo "Topic: 'The benefits of daily journaling'"
echo ""

RESULT=$(curl -sf --max-time 360 -X POST "$ORCH_URL/generate" \
  -H "Content-Type: application/json" \
  -d '{"topic":"The benefits of daily journaling","tone":"conversational"}')

if [[ -z "$RESULT" ]]; then
  echo "FAIL: Empty response from orchestrator."
  exit 1
fi

POST=$(echo "$RESULT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('blog_post',''))")
CHARS=${#POST}

if [[ $CHARS -lt 200 ]]; then
  echo "FAIL: Blog post too short ($CHARS chars). Something went wrong."
  echo "Raw response: $RESULT"
  exit 1
fi

echo "SUCCESS — generated $CHARS characters."
echo ""
echo "--- Preview (first 600 chars) ---"
echo "$POST" | head -c 600
echo ""
echo "---"
echo ""
echo "Results: $PASS health checks passed, $FAIL failed."
