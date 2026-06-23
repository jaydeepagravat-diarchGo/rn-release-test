#!/usr/bin/env bash
# .github/scripts/save-release-metadata.sh
#
# Saves release metadata to the Git tag annotation during a Beta release.
# This metadata is then retrieved during promotion to Production.
#
# Used to ensure that Production releases reference the exact tested Beta artifact,
# not any commits added after the Beta was created.
#
# Inputs (via env vars):
#   PLATFORM:      "android" or "ios"
#   TAG:           Release tag (e.g., "android-v1.2.22-70")
#   COMMIT_SHA:    Git commit SHA used for this build
#   RELEASE_NOTES: Multiline release notes body
#
# Outputs:
#   Annotates the Git tag with metadata (no files created)

set -euo pipefail

PLATFORM="${PLATFORM:-}"
TAG="${TAG:-}"
COMMIT_SHA="${COMMIT_SHA:-}"
RELEASE_NOTES="${RELEASE_NOTES:-}"

if [[ -z "$PLATFORM" || -z "$TAG" || -z "$COMMIT_SHA" ]]; then
  echo "ERROR: Missing required env vars (PLATFORM, TAG, COMMIT_SHA)" >&2
  exit 1
fi

# Create tag annotation with embedded metadata
# Format: PLATFORM|COMMIT_SHA followed by release notes
TAG_ANNOTATION="${PLATFORM}|${COMMIT_SHA}"$'\n'"${RELEASE_NOTES}"

# Update the existing tag with annotation (idempotent)
git config user.name  "github-actions[bot]"
git config user.email "github-actions[bot]@users.noreply.github.com"

# Delete and recreate tag to add annotation if it's lightweight
if git rev-parse "$TAG" >/dev/null 2>&1; then
  # Check if it's a lightweight tag (no annotation)
  if ! git cat-file -t "$TAG" | grep -q tag; then
    echo "ℹ️ Converting lightweight tag to annotated tag with metadata..."
    git tag -d "$TAG"
    git tag -a "$TAG" "$COMMIT_SHA" -m "$TAG_ANNOTATION"
    git push origin "$TAG" --force || true
  else
    echo "ℹ️ Tag already annotated, skipping"
  fi
fi

echo "✅ Release metadata stored in tag annotation for: $TAG"
