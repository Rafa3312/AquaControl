#!/usr/bin/env bash
# Aplica las reglas de CI/merge del Plan DevOps (sección 6) como configuración real
# de GitHub, en vez de solo describirlas en el documento.
#
# Requisitos: GitHub CLI autenticado (`gh auth login`) con permisos de admin sobre el repo.
# Uso: ./scripts/setup-branch-protection.sh <owner>/<repo>

set -euo pipefail

REPO="${1:?Uso: ./setup-branch-protection.sh <owner>/<repo>}"

echo "Configurando reglas para main (release) en $REPO..."
gh api \
  --method PUT \
  -H "Accept: application/vnd.github+json" \
  "repos/$REPO/branches/main/protection" \
  -f required_status_checks.strict=true \
  -f 'required_status_checks.contexts[]=build-and-test' \
  -f 'required_status_checks.contexts[]=commitlint' \
  -f 'required_status_checks.contexts[]=pr-title' \
  -f enforce_admins=false \
  -f required_pull_request_reviews.required_approving_review_count=1 \
  -f required_pull_request_reviews.dismiss_stale_reviews=true \
  -f restrictions=null \
  -f allow_force_pushes=false \
  -f allow_deletions=false \
  -f required_linear_history=true

echo "Configurando reglas para develop (integración) en $REPO..."
gh api \
  --method PUT \
  -H "Accept: application/vnd.github+json" \
  "repos/$REPO/branches/develop/protection" \
  -f required_status_checks.strict=true \
  -f 'required_status_checks.contexts[]=build-and-test' \
  -f 'required_status_checks.contexts[]=commitlint' \
  -f enforce_admins=false \
  -f required_pull_request_reviews.required_approving_review_count=0 \
  -f restrictions=null \
  -f allow_force_pushes=false \
  -f allow_deletions=false

echo "Listo. Verifica en Settings > Branches que las reglas quedaron activas."
