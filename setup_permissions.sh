#!/usr/bin/env bash
# setup_permissions.sh — Grant IAM roles needed for `gcloud run deploy --source`
# Run this ONCE before deploy.sh
set -euo pipefail

PROJECT_ID="project-2227b70e-47ba-4a0b-8d1"
PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format="value(projectNumber)")
REGION="us-central1"

echo "=== Cloud Run Deploy — Permission Setup ==="
echo "Project        : $PROJECT_ID"
echo "Project Number : $PROJECT_NUMBER"
echo ""

# Service accounts involved
CLOUDBUILD_SA="${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com"
COMPUTE_SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"

echo "[1/4] Enabling required APIs..."
gcloud services enable \
  cloudbuild.googleapis.com \
  run.googleapis.com \
  artifactregistry.googleapis.com \
  storage.googleapis.com \
  --project "$PROJECT_ID"
echo "  ✓ APIs enabled"
echo ""

echo "[2/4] Granting Cloud Build SA permissions..."
for ROLE in \
  roles/storage.admin \
  roles/artifactregistry.admin \
  roles/logging.logWriter \
  roles/run.admin \
  roles/iam.serviceAccountUser; do
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:${CLOUDBUILD_SA}" \
    --role="$ROLE" \
    --condition=None \
    --quiet 2>/dev/null || true
  echo "  ✓ $ROLE → Cloud Build SA"
done
echo ""

echo "[3/4] Granting Compute Engine SA permissions..."
for ROLE in \
  roles/storage.objectAdmin \
  roles/artifactregistry.writer \
  roles/logging.logWriter; do
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:${COMPUTE_SA}" \
    --role="$ROLE" \
    --condition=None \
    --quiet 2>/dev/null || true
  echo "  ✓ $ROLE → Compute Engine SA"
done
echo ""

echo "[4/4] Creating Artifact Registry repository (if missing)..."
gcloud artifacts repositories create cloud-run-source-deploy \
  --repository-format=docker \
  --location="$REGION" \
  --project="$PROJECT_ID" \
  --quiet 2>/dev/null \
  && echo "  ✓ Repository created" \
  || echo "  ✓ Repository already exists"
echo ""

echo "========================================="
echo "  Setup complete — now run: bash deploy.sh"
echo "========================================="
