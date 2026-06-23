# Release Promotion Architecture

## Visual Flow: Beta → Production (With Fix)

```
┌─────────────────────────────────────────────────────────────────────┐
│                          DAY 1: BETA RELEASE                        │
└─────────────────────────────────────────────────────────────────────┘

  Commits: A, B, C, D, E (HEAD at ABC123)
         ↓
         ├─ Run: gh workflow run android-release.yml --raw-field lane=beta
         ↓
┌────────────────────────────────────────────────────────────┐
│ POST-RELEASE WORKFLOW: BETA LANE                           │
├────────────────────────────────────────────────────────────┤
│ 1. Checkout (full history)                                 │
│ 2. Extract version: v1.2.22, build 70                      │
│ 3. (Skip load metadata - not promotion)                    │
│ 4. Resolve target: HEAD (ABC123)                           │
│ 5. Create tag: android-v1.2.22-70 @ ABC123 ✓             │
│ 6. Find previous tag: android-v1.2.21                      │
│ 7. Generate release notes: android-v1.2.21..HEAD           │
│    ├─ Commit A                                             │
│    ├─ Commit B                                             │
│    ├─ Commit C                                             │
│    ├─ Commit D                                             │
│    └─ Commit E                                             │
│ 8. Create GitHub Release (prerelease) ✓                    │
│ 9. ✅ SAVE METADATA:                                       │
│    └─ .github/.release-metadata/android/1.2.22-70.json    │
│       {                                                     │
│         "commit_sha": "abc123...",                          │
│         "release_notes": "<E-line notes>",                 │
│         ...                                                 │
│       }                                                     │
│ 10. Slack notification ✓                                    │
└────────────────────────────────────────────────────────────┘
         ↓
     ✅ Beta Released
     ├─ Upload to Internal Testing
     └─ QA Begins Testing


┌─────────────────────────────────────────────────────────────────────┐
│                  DAYS 2-4: DEVELOPMENT CONTINUES                     │
└─────────────────────────────────────────────────────────────────────┘

  Commits: A, B, C, D, E, F, G, H, I, J (HEAD at XYZ789)
         ↓
         ├─ Beta artifact UNCHANGED (still v1.2.22-70 @ ABC123)
         ├─ Metadata file UNCHANGED
         └─ HEAD moved far ahead → XYZ789
              ├─ ⚠️ Commits F-J NEVER tested in Beta
              └─ ⚠️ Still 4 commits ahead


┌─────────────────────────────────────────────────────────────────────┐
│                    DAY 5: PROMOTION TO PRODUCTION                    │
└─────────────────────────────────────────────────────────────────────┘

  QA approved Beta ✓
  Release manager promotes to Production

    Run: gh workflow run android-release.yml --raw-field lane=promote_to_production
         ↓
         ├─ Version still v1.2.22, build 70 (must match Beta)
         └─ Current HEAD at XYZ789 (F-J commits)
             ↓
┌────────────────────────────────────────────────────────────┐
│ POST-RELEASE WORKFLOW: PROMOTE LANE                        │
├────────────────────────────────────────────────────────────┤
│ 1. Checkout (full history)                                 │
│ 2. Extract version: v1.2.22, build 70                      │
│ 3. ✅ LOAD METADATA:                                        │
│    └─ .github/.release-metadata/android/1.2.22-70.json    │
│       ├─ commit_sha: abc123... (Beta commit!)              │
│       └─ release_notes: <A-E only>                         │
│ 4. Resolve target: abc123 (NOT XYZ789!) ✓✓✓               │
│ 5. Create tag: android-v1.2.22 @ ABC123 ✓                 │
│    (NOT on current HEAD XYZ789)                            │
│ 6. Find previous tag: android-v1.2.21                      │
│ 7. Generate release notes: (skipped - using stored)        │
│ 8. Create GitHub Release @ ABC123 with STORED notes ✓     │
│    ├─ Release notes: A, B, C, D, E (from Beta) ✓          │
│    ├─ ✓ Commits F, G, H, I, J NOT included                │
│    └─ ✓ Identical to Beta release notes                   │
│ 9. (Skip save metadata - not beta)                         │
│ 10. Slack notification (with stored notes) ✓              │
└────────────────────────────────────────────────────────────┘
         ↓
     ✅ Production Released
     ├─ Tag: android-v1.2.22 @ ABC123 (Beta commit)
     ├─ Release notes: A-E (Beta notes, no F-J)
     ├─ GitHub Release: points to correct artifact
     └─ Slack: Accurate changelog to stakeholders
```

---

## Git Tag Timeline

```
BEFORE (Broken):
════════════════

Current Production:  A----B----C----D----E----F----G----H----I----J (HEAD)
                     ↑    ↑         ↑
                   init   ...    (Beta had A-E)

After Beta release:
                  A----B----C----D----E----F----G----H----I----J (HEAD)
                  ↑                    ↑
              (old tag)         android-v1.2.22-70
                                 (tagged on E)

After promotion (❌ WRONG):
                  A----B----C----D----E----F----G----H----I----J (HEAD)
                  ↑                    ↑                            ↑
              (old tag)     android-v1.2.22-70      android-v1.2.22 ❌
                                                    (tagged on J - current HEAD)
                                                    (includes untested F-J!)


AFTER (Fixed):
══════════════

After Beta release:
                  A----B----C----D----E----F----G----H----I----J (HEAD)
                  ↑                    ↑
              (old tag)         android-v1.2.22-70
                                 (tagged on E, metadata saved)

After development:
                  A----B----C----D----E----F----G----H----I----J (HEAD)
                  ↑                    ↑
              (old tag)         android-v1.2.22-70
                                 (unchanged)

After promotion (✅ CORRECT):
                  A----B----C----D----E----F----G----H----I----J (HEAD)
                  ↑                    ↑↑
              (old tag)      android-v1.2.22-70 ✓ SAME COMMIT
                             android-v1.2.22 ✓  (NOT on J!)
                              (both on Beta commit E)

Release notes:
  Beta:       A, B, C, D, E ✓
  Production: A, B, C, D, E ✓ (same, not F-J)
```

---

## Metadata Flow

```
┌─────────────────┐
│  Beta Release   │
│   lane=beta     │
└────────┬────────┘
         │
         ├─ Generate release notes: A-E
         │
         ├─ Create GitHub Release (prerelease)
         │
         ├─ Create Git tag: android-v1.2.22-70
         │
         └─ ✅ SAVE to .github/.release-metadata/android/1.2.22-70.json
                    {
                      "commit_sha": "abc123...",
                      "release_notes": "## Release...",
                      ...
                    }
                    ↓
                    └─ Committed to Git
                       └─ Tracked in repository history


┌───────────────────────────┐
│  Development Continues    │
│  Commits F-J added        │
│  HEAD moves ahead         │
│  Metadata file UNCHANGED  │
└───────┬───────────────────┘
        │
        └─ Metadata preserved in Git
           (Available for promotion)


┌──────────────────────────────────┐
│  Promotion to Production         │
│  lane=promote_to_production      │
└────────┬─────────────────────────┘
         │
         ├─ ✅ LOAD .github/.release-metadata/android/1.2.22-70.json
         │        {
         │          "commit_sha": "abc123...",
         │          "release_notes": "...",
         │        }
         │
         ├─ Extract: commit_sha = abc123 (Beta commit)
         │
         ├─ Use this commit for tagging (NOT HEAD)
         │
         ├─ Create tag: android-v1.2.22 @ abc123
         │
         ├─ Use stored release notes (A-E, not F-J)
         │
         └─ Create GitHub Release with stored notes ✓
```

---

## Release Notes Generation

```
BEFORE (Broken Logic):
═════════════════════

Beta Release:
  RANGE = PREV_TAG..HEAD (at E)
  Release notes: A, B, C, D, E ✓
  ✓ Saved to Beta GitHub Release

Promotion:
  RANGE = PREV_TAG..HEAD (at J!)  ❌
  Release notes: A, B, C, D, E, F, G, H, I, J ❌
  ✗ Wrong - includes untested commits


AFTER (Fixed Logic):
═════════════════════

Beta Release:
  RANGE = PREV_TAG..HEAD (at E)
  Release notes: A, B, C, D, E ✓
  ✓ Saved to metadata + GitHub Release

Promotion:
  Use stored notes: A, B, C, D, E ✓
  ✗ Do NOT use PREV_TAG..HEAD
  ✓ Reuse Beta notes exactly
```

---

## Step-by-Step: The Critical Fix

```
STEP 4: Resolve Target Commit
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

if [[ "$LANE" == "promote_to_production" ]]; then
  # ✅ Use stored Beta commit from metadata
  TARGET_SHA="${{ steps.beta_metadata.outputs.commit_sha }}"
  echo "📌 Tagging Beta commit: $TARGET_SHA"
else
  # ✅ Use current HEAD for new builds
  TARGET_SHA="${{ github.sha }}"
  echo "🆕 Tagging current HEAD: $TARGET_SHA"
fi


STEP 5: Create Tag
━━━━━━━━━━━━━━━━━

git tag -a "$TAG" "$TARGET_SHA" -m "Release $TAG"
                  ↑
            ✅ This is the KEY FIX
            Now tags the stored commit (Beta)
            instead of current HEAD


Before:    git tag -a "android-v1.2.22" (HEAD at J)  ❌
After:     git tag -a "android-v1.2.22" (ABC123)     ✅


STEP 8: Create GitHub Release
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

body: ${{ inputs.lane == 'promote_to_production' 
       && steps.beta_metadata.outputs.release_notes 
       || steps.notes.outputs.release_body }}
       
       ↑
       ✅ Use stored notes if promotion
       Otherwise use generated notes
```

---

## Platform Support

```
Android
═══════

Beta:        android-v1.2.22-70 @ commit E
             ├─ Release notes: A-E
             ├─ Metadata: .github/.release-metadata/android/1.2.22-70.json
             └─ GitHub Release (prerelease)

Promotion:   android-v1.2.22 @ commit E (same!)
             ├─ Release notes: A-E (from metadata)
             └─ GitHub Release (full release)


iOS
═══

Beta:        ios-v1.2.22-70 @ commit E
             ├─ Release notes: A-E
             ├─ Metadata: .github/.release-metadata/ios/1.2.22-70.json
             └─ GitHub Release (prerelease)

Promotion:   ios-v1.2.22 @ commit E (same!)
             ├─ Release notes: A-E (from metadata)
             └─ GitHub Release (full release)


Independent Schedule:
  ✅ Android v1.2.22 in Production
  ✅ iOS v1.2.21 in Beta
  (Each has its own metadata, tags, and schedule)
```

---

## Error Handling

```
Case 1: Missing Metadata
═══════════════════════

Promotion run with no metadata file:
  ↓
  load-release-metadata.sh
  ↓
  ✓ Check: Does file exist?
  ✗ File NOT found: .github/.release-metadata/android/1.2.22-70.json
  ↓
  ✅ Fail fast with clear error:
     "ERROR: Metadata file not found"
     "This file should have been created during Beta release"
     "Cannot safely promote without verified build information"
  ↓
  ✓ User guidance: "Run Beta release first"


Case 2: Valid Metadata
═══════════════════════

Promotion run with valid metadata:
  ↓
  load-release-metadata.sh
  ↓
  ✓ Check: Does file exist?
  ✓ File found: .github/.release-metadata/android/1.2.22-70.json
  ↓
  ✓ Check: Can read commit_sha?
  ✓ commit_sha: "abc123def456..."
  ↓
  ✓ Check: Can read release_notes?
  ✓ release_notes: "## Release Overview..."
  ↓
  ✅ Proceed with promotion ✓
```

---

## Comparison: Before vs After

```
┌─────────────────────┬──────────────────────┬──────────────────────┐
│ Aspect              │ Before (Broken)      │ After (Fixed)        │
├─────────────────────┼──────────────────────┼──────────────────────┤
│ Production commit   │ HEAD (J) ❌          │ Beta (E) ✅          │
│                     │ Uses untested code   │ Uses tested code     │
├─────────────────────┼──────────────────────┼──────────────────────┤
│ Release notes       │ A-J ❌               │ A-E ✅               │
│                     │ Includes F-J         │ Matches Beta         │
├─────────────────────┼──────────────────────┼──────────────────────┤
│ Artifact integrity  │ Broken ❌            │ Preserved ✅         │
│                     │ Different build      │ Same artifact        │
├─────────────────────┼──────────────────────┼──────────────────────┤
│ Auditability        │ No trace ❌          │ Metadata saved ✅    │
│                     │ No way to track      │ Git history preserved│
├─────────────────────┼──────────────────────┼──────────────────────┤
│ Old Beta promotion  │ N/A                  │ Possible ✅          │
│                     │ Would use HEAD       │ Uses stored metadata │
├─────────────────────┼──────────────────────┼──────────────────────┤
│ Industry standard   │ No ❌                │ Yes ✅               │
│                     │ Non-standard flow    │ Approved pattern     │
└─────────────────────┴──────────────────────┴──────────────────────┘
```

---

**This fix ensures Production releases always represent the exact tested artifact, never including any commits added after Beta.**
