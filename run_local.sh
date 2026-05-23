#!/usr/bin/env bash
# run_local.sh — Start all services locally for development/testing
set -euo pipefail

export GOOGLE_CLOUD_PROJECT="project-2227b70e-47ba-4a0b-8d1"
export GOOGLE_CLOUD_LOCATION="us-central1"
export GOOGLE_GENAI_USE_VERTEXAI="true"

# Ports
R_PORT=8001   # Researcher
O_PORT=8002   # Outliner
W_PORT=8003   # Writer
E_PORT=8004   # Editor
ORCH_PORT=8005
UI_PORT=8080

# ── Cleanup on exit ────────────────────────────────────────────────────────
cleanup() {
  echo ""
  echo "Stopping all services..."
  # Kill child processes
  jobs -p | xargs -r kill 2>/dev/null || true
  wait 2>/dev/null || true
  echo "Done."
}
trap cleanup SIGINT SIGTERM EXIT

# ── Install dependencies ───────────────────────────────────────────────────
echo "Installing dependencies..."
pip install -q -r agents/researcher/requirements.txt
pip install -q -r agents/outliner/requirements.txt
pip install -q -r agents/writer/requirements.txt
pip install -q -r agents/editor/requirements.txt
pip install -q -r orchestrator/requirements.txt
pip install -q -r frontend/requirements.txt
echo "Dependencies installed."
echo ""

# ── Start sub-agents ───────────────────────────────────────────────────────
echo "Starting sub-agents..."
(cd agents/researcher && PORT=$R_PORT python main.py 2>&1 | sed 's/^/[researcher] /') &
(cd agents/outliner   && PORT=$O_PORT python main.py 2>&1 | sed 's/^/[outliner]   /') &
(cd agents/writer     && PORT=$W_PORT python main.py 2>&1 | sed 's/^/[writer]     /') &
(cd agents/editor     && PORT=$E_PORT python main.py 2>&1 | sed 's/^/[editor]     /') &

echo "Waiting for sub-agents to start (5s)..."
sleep 5

# ── Start orchestrator ─────────────────────────────────────────────────────
export RESEARCHER_URL="http://localhost:$R_PORT"
export OUTLINER_URL="http://localhost:$O_PORT"
export WRITER_URL="http://localhost:$W_PORT"
export EDITOR_URL="http://localhost:$E_PORT"

echo "Starting orchestrator..."
(cd orchestrator && PORT=$ORCH_PORT python main.py 2>&1 | sed 's/^/[orchestrator] /') &
sleep 3

# ── Start frontend ─────────────────────────────────────────────────────────
export ORCHESTRATOR_URL="http://localhost:$ORCH_PORT"

echo "Starting frontend..."
(cd frontend && PORT=$UI_PORT python main.py 2>&1 | sed 's/^/[frontend] /') &
sleep 2

echo ""
echo "========================================="
echo "  All services running!"
echo "  Frontend     → http://localhost:$UI_PORT"
echo "  Orchestrator → http://localhost:$ORCH_PORT"
echo "  Researcher   → http://localhost:$R_PORT"
echo "  Outliner     → http://localhost:$O_PORT"
echo "  Writer       → http://localhost:$W_PORT"
echo "  Editor       → http://localhost:$E_PORT"
echo "========================================="
echo "  Press Ctrl+C to stop everything"
echo ""

wait
