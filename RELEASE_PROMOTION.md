# Release Management: Beta → Production Promotion

## Overview

This document describes the release promotion workflow designed to address the critical edge case where existing Beta builds are promoted to Production.

**Problem:** The original workflow always generated release notes from the latest Git tag to `HEAD`, which included commits added after the Beta release was created. This caused inaccurate GitHub Releases and breaking release traceability.

**Solution:** Treat Beta and Production as two stages of the same release artifact, with metadata persistence and commit pinning.

---

## Release Workflow Architecture

### Three Release Lanes

1. **Beta** (`lane: beta`)
   - Creates a new Beta build from current HEAD
   - Generates release notes (`PREV_TAG..HEAD`)
   - **Saves release metadata** for future promotion
   - Tags the current commit

2. **Promote to Production** (`lane: promote_to_production`)
   - Takes an **existing, pre-built Beta artifact**
   - **Loads stored Beta metadata** (commit SHA, release notes)
   - Reuses exact commit and notes from the approved Beta
   - Creates Production tag on **the exact tested commit**
   - Creates GitHub Release from **stored notes** (ignoring any commits added after Beta)
   - **Does NOT rebuild, recalculate release notes, or use HEAD**

3. **Production** (`lane: production`)
   - Direct Production build from current HEAD (rarely used)
   - Generates release notes from PREV_TAG to HEAD
   - For first-time production releases only

---

## How Metadata Persistence Works

### Beta Release (1st time)

```
Commits: A, B, C, D, E (HEAD)
├─ Run: `lane=beta` on commit E
├─ Generates tag: `android-v1.2.22-70`
├─ Generates release notes: A, B, C, D, E
├─ Creates GitHub Release (prerelease)
└─ SAVES metadata file:
   .github/.release-metadata/android/1.2.22-70.json
   {
     "tag": "android-v1.2.22-70",
     "commit_sha": "<SHA of commit E>",
     "release_notes": "<generated notes>",
     ...
   }
```

### Development Continues

```
After Beta is uploaded to internal testing:
├─ Commits: F, G, H, I, J added
├─ HEAD now at commit J
└─ Beta build still at commit E (artifact is unchanged)
```

### Promotion to Production (2nd time)

```
Commits: A, B, C, D, E, F, G, H, I, J (HEAD)
├─ Run: `lane=promote_to_production` on commit J
├─ LOADS metadata for v1.2.22-70:
│  ├─ Retrieves: commit_sha = <SHA of commit E>
│  ├─ Retrieves: stored release notes (A-E only)
│  └─ Ignores: current HEAD, commits F-J
├─ Creates tag: `android-v1.2.22` on commit E (pinned!)
├─ Creates GitHub Release with stored notes (A-E only)
└─ Result: Production accurately reflects Beta artifact
```

---

## Metadata Storage

### Storage Location
Metadata is stored directly in **Git tag annotations** — no separate files.

**Why:**
- No JSON files accumulating in repository
- Metadata is part of Git history (attached to the tag itself)
- Self-cleaning: delete tag = delete metadata
- Fully auditable through `git tag -l`

### How Metadata is Stored
During Beta release:
```bash
git tag -a "android-v1.2.22-70" <commit> -m "android|<commit>
<release notes>"
```

The tag annotation message contains:
- First line: `PLATFORM|COMMIT_SHA` (for parsing)
- Following lines: Full release notes body

### When Metadata is Created
- **Only** during `lane: beta` releases
- Stored in the Git tag annotation automatically
- Committed as part of tag creation

### When Metadata is Used
- **Only** during `lane: promote_to_production` runs
- Read from the Beta tag annotation
- No files to locate or manage

---

## Step-by-Step Workflow

### Post-Release Workflow (`post-release.yml`)

#### Steps 1–2: Setup
1. **Checkout** — full history for git log
2. **Extract version** — from source files (no manual input)

#### Step 3: Load Beta Metadata (Promotion Only)
```bash
if [[ "$LANE" == "promote_to_production" ]]; then
  load-release-metadata.sh
  # Outputs: commit_sha, release_notes
fi
```
- Only runs during promotion
- Loads `.github/.release-metadata/${PLATFORM}/${VERSION}-${BUILD}.json`
- Outputs stored commit SHA and release notes

#### Steps 4–5: Tagging
- **Step 4:** Resolve target commit
  ```bash
  if [[ "$LANE" == "promote_to_production" ]]; then
    TARGET_COMMIT = stored_beta_commit_sha  # ← KEY FIX
  else
    TARGET_COMMIT = HEAD
  fi
  ```
- **Step 5:** Create tag at target commit (not HEAD)
  ```bash
  git tag -a "$TAG" "$TARGET_COMMIT" -m "Release $TAG"
  ```

#### Step 6: Find Previous Tag
- Find the previous platform tag for comparison range
- Used to determine what commits changed

#### Step 7: Generate Release Notes
- For `beta` and `production`: Generate from `PREV_TAG..HEAD`
- For `promote_to_production`: Release notes are skipped (will use stored notes)

#### Step 8: Create GitHub Release
```yaml
body: ${{ inputs.lane == 'promote_to_production' 
       && steps.beta_metadata.outputs.release_notes 
       || steps.notes.outputs.release_body }}
```
- Uses **stored notes** for promotion, **generated notes** otherwise

#### Step 9: Save Metadata (Beta Only)
```bash
if [[ "$LANE" == "beta" ]]; then
  save-release-metadata.sh
  # Creates .github/.release-metadata/...
fi
```

#### Step 10: Slack Notification
- Uses the appropriate release notes (stored or generated)

---

## Key Scripts

### `save-release-metadata.sh`
- Called during Beta releases only
- Saves commit SHA and release notes to JSON file
- Commits file to repository for auditability

### `load-release-metadata.sh`
- Called during promotions only
- Loads and validates metadata file
- Outputs: `commit_sha`, `release_notes`

### `generate-release-notes.sh`
- Updated to accept `TARGET_SHA` parameter
- Generates from `PREV_TAG..HEAD` for new builds
- (Promotion skips this; uses stored notes instead)

---

## Correctness Guarantees

### ✅ Accurate Release Notes
- Beta release notes contain exactly what was tested
- Production promotion preserves those exact notes
- Commits added after Beta are never included in Production release notes

### ✅ Artifact Integrity
- Production always points to the exact Beta commit
- Tagging is done against stored commit SHA, not HEAD
- Rebuilding not required (same artifact throughout)

### ✅ Auditability
- Metadata files committed to repository
- Full history of which commits were in each release
- GitHub Release history matches Git history

### ✅ Industry-Standard Promotion
- Treats Beta and Production as stages, not independent builds
- Reuses previously generated and approved metadata
- No recalculation, no HEAD references during promotion

---

## Examples

### Example 1: Beta Release (Day 1)

```bash
# Version bump in source files
versionName "1.2.22"
versionCode 70

# Run workflow
gh workflow run android-release.yml --raw-field lane=beta

# Workflow creates:
- Tag: android-v1.2.22-70 (on HEAD commit ABC123)
- GitHub Release (prerelease): "🧪 Android Release v1.2.22 (70)"
- Metadata file: .github/.release-metadata/android/1.2.22-70.json
- Slack notification: "Beta uploaded to Internal Testing"
```

### Example 2: Development Continues (Day 2–4)

```bash
# More commits merged
commit F
commit G
commit H
commit I
commit J  # HEAD now at DEF789

# Version not bumped yet
# Artifact is still v1.2.22-70 (at ABC123)
```

### Example 3: Promote to Production (Day 5)

```bash
# Beta was approved by QA
# Same version and build number

# Run workflow
gh workflow run android-release.yml --raw-field lane=promote_to_production

# Workflow:
# 1. Loads metadata: .github/.release-metadata/android/1.2.22-70.json
# 2. Retrieves stored commit SHA: ABC123 (Day 1 commit, not current HEAD)
# 3. Creates tag: android-v1.2.22 on commit ABC123 (NOT DEF789)
# 4. Creates GitHub Release with stored notes (A-E, NOT F-J)
# 5. Slack notification uses stored notes
```

### Example 4: Next Beta (Day 6+)

```bash
# New version bump
versionName "1.2.23"
versionCode 71

# Run workflow (on current HEAD at commit XYZ789)
gh workflow run android-release.yml --raw-field lane=beta

# Workflow creates new metadata
- .github/.release-metadata/android/1.2.23-71.json
# Future promotions will use THIS metadata
```

---

## Troubleshooting

### Problem: Metadata file not found during promotion
```
ERROR: Metadata file not found: .github/.release-metadata/android/1.2.22-70.json
```

**Solution:** 
- Ensure the Beta release was run first with `lane=beta`
- Verify metadata file was saved to repository
- Check that version/build numbers match between Beta and promotion

### Problem: Wrong commit tagged during promotion
```
❌ Tag created on current HEAD instead of Beta commit
```

**Solution:**
- Verify `steps.beta_metadata.outputs.commit_sha` is populated
- Check that `load-release-metadata.sh` completed successfully
- Ensure JSON metadata file has valid `commit_sha` field

### Problem: Release notes include commits after Beta
```
❌ Production release notes show commits F-J (added after Beta)
```

**Solution:**
- Verify promotion is using `lane=promote_to_production` (not `lane=production`)
- Check that GitHub Release body uses `steps.beta_metadata.outputs.release_notes`
- Metadata must be saved before any new commits are added

---

## Migration Guide (For Existing Repos)

### Prerequisites
- All three scripts installed in `.github/scripts/`
- `post-release.yml` updated with new logic
- Metadata directory `.github/.release-metadata/` will be auto-created

### First Time Setup
1. Ensure latest version of scripts are deployed
2. Next Beta release will create first metadata file
3. Future promotions will automatically use metadata

### Existing Releases
- If promoting an old Beta without metadata:
  - Can still do direct `lane=production` (generates notes from HEAD)
  - After migration, always use `lane=promote_to_production` with metadata
  - Create retroactive metadata files if needed

---

## References

- [Post-Release Workflow](.github/workflows/post-release.yml)
- [Save Metadata Script](.github/scripts/save-release-metadata.sh)
- [Load Metadata Script](.github/scripts/load-release-metadata.sh)
- [Release Notes Generator](.github/scripts/generate-release-notes.sh)
