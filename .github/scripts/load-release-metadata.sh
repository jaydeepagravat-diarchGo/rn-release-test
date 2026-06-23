#!/usr/bin/env bash
# .github/scripts/load-release-metadata.sh
#
# Loads saved release metadata from the Git tag annotation to promote an existing Beta build to Production.
# Ensures the Production release references the exact tested Beta artifact,
# not any commits added after the Beta was created.
#
# Metadata is stored as a tag annotation (no JSON files).
#
# Inputs (via env vars):
#   PLATFORM:      "android" or "ios"
#   VERSION:       Version number (e.g., "1.2.22")
#   BUILD:         Build number (e.g., "70")
#
# Outputs (via $GITHUB_OUTPUT):
#   commit_sha     Git commit SHA from the saved Beta tag
#   release_notes  Release notes body from the tag annotation

set -euo pipefail

PLATFORM="${PLATFORM:-}"
VERSION="${VERSION:-}"
BUILD="${BUILD:-}"

if [[ -z "$PLATFORM" || -z "$VERSION" || -z "$BUILD" ]]; then
  echo "ERROR: Missing required env vars (PLATFORM, VERSION, BUILD)" >&2
  exit 1
fi

# Construct the Beta tag name
BETA_TAG="${PLATFORM}-v${VERSION}-${BUILD}"

# Check if the Beta tag exists
if ! git rev-parse "$BETA_TAG" >/dev/null 2>&1; then
  echo "ERROR: Beta tag not found: $BETA_TAG" >&2
  echo "       This tag should have been created during the Beta release." >&2
  echo "       Cannot safely promote without verified build information." >&2
  exit 1
fi

echo "📋 Loading release metadata from tag: $BETA_TAG"

# Get commit SHA from the tag
COMMIT_SHA=$(git rev-list -n 1 "$BETA_TAG")
echo "✅ Loaded commit SHA: $COMMIT_SHA"

# Get the tag annotation message (contains release notes)
TAG_MESSAGE=$(git tag -l "$BETA_TAG" -n 10000 --format='%(contents)')

# Parse the annotation: first line is PLATFORM|COMMIT_SHA, rest is release notes
RELEASE_NOTES=$(echo "$TAG_MESSAGE" | tail -n +2)

if [[ -z "$RELEASE_NOTES" ]]; then
  echo "⚠️ Warning: Could not read release notes from tag annotation"
  RELEASE_NOTES=""
fi

echo "✅ Loaded release notes (${#RELEASE_NOTES} chars)"

{
  echo "commit_sha=$COMMIT_SHA"
  echo "release_notes<<RELEASE_NOTES_EOF"
  printf '%s\n' "$RELEASE_NOTES"
  echo "RELEASE_NOTES_EOF"
} >> "$GITHUB_OUTPUT"

echo "✅ Metadata outputs set for promotion workflow"
