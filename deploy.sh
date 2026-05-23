#!/usr/bin/env bash
# deploy.sh — Deploy all Blog Post Writer services to Google Cloud Run
set -euo pipefail

PROJECT_ID="project-2227b70e-47ba-4a0b-8d1"
REGION="us-central1"

echo "=== Blog Post Writer — Cloud Run Deployment ==="
echo "Project : $PROJECT_ID"
echo "Region  : $REGION"
echo ""

COMMON_ENV="GOOGLE_CLOUD_PROJECT=$PROJECT_ID,GOOGLE_CLOUD_LOCATION=$REGION,GOOGLE_GENAI_USE_VERTEXAI=true"

# ── 1. Deploy the four ADK sub-agents in parallel ──────────────────────────
echo "[1/3] Deploying sub-agents in parallel (this may take ~5 min)..."

deploy_agent() {
  local name=$1
  local src=$2
  echo "  → deploying $name"
  gcloud run deploy "$name" \
    --source "$src" \
    --region  "$REGION" \
    --project "$PROJECT_ID" \
    --allow-unauthenticated \
    --memory  512Mi \
    --timeout 300 \
    --set-env-vars "$COMMON_ENV" \
    --quiet
  echo "  ✓ $name deployed"
}

deploy_agent researcher agents/researcher &
deploy_agent outliner   agents/outliner  &
deploy_agent writer     agents/writer    &
deploy_agent editor     agents/editor    &
wait
echo "Sub-agents deployed."
echo ""

# ── 2. Capture sub-agent URLs ──────────────────────────────────────────────
url_of() {
  gcloud run services describe "$1" \
    --region "$REGION" --project "$PROJECT_ID" \
    --format "value(status.url)"
}

RESEARCHER_URL=$(url_of researcher)
OUTLINER_URL=$(url_of outliner)
WRITER_URL=$(url_of writer)
EDITOR_URL=$(url_of editor)

echo "Sub-agent URLs:"
echo "  Researcher : $RESEARCHER_URL"
echo "  Outliner   : $OUTLINER_URL"
echo "  Writer     : $WRITER_URL"
echo "  Editor     : $EDITOR_URL"
echo ""

# ── 3. Deploy orchestrator with sub-agent URLs ─────────────────────────────
echo "[2/3] Deploying orchestrator..."
gcloud run deploy orchestrator \
  --source orchestrator/ \
  --region  "$REGION" \
  --project "$PROJECT_ID" \
  --allow-unauthenticated \
  --memory  512Mi \
  --timeout 600 \
  --set-env-vars "$COMMON_ENV,RESEARCHER_URL=$RESEARCHER_URL,OUTLINER_URL=$OUTLINER_URL,WRITER_URL=$WRITER_URL,EDITOR_URL=$EDITOR_URL" \
  --quiet

ORCHESTRATOR_URL=$(url_of orchestrator)
echo "  Orchestrator: $ORCHESTRATOR_URL"
echo ""

# ── 4. Deploy frontend ─────────────────────────────────────────────────────
echo "[3/3] Deploying frontend..."
gcloud run deploy blog-writer-frontend \
  --source frontend/ \
  --region  "$REGION" \
  --project "$PROJECT_ID" \
  --allow-unauthenticated \
  --memory  256Mi \
  --timeout 600 \
  --set-env-vars "ORCHESTRATOR_URL=$ORCHESTRATOR_URL,GOOGLE_CLOUD_PROJECT=$PROJECT_ID" \
  --quiet

FRONTEND_URL=$(url_of blog-writer-frontend)

echo ""
echo "========================================="
echo "  Deployment complete!"
echo "  Frontend : $FRONTEND_URL"
echo "========================================="
