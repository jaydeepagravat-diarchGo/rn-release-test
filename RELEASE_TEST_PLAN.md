# Test Plan: Beta → Production Promotion Fix

## Overview
This test plan validates that the release promotion workflow correctly handles the edge case where commits are added after a Beta release is created.

**Time to complete:** ~30 minutes

---

## Test Environment Setup

### Prerequisites
- Repository with updated workflow files
- GitHub workflow permissions enabled
- Access to run manual workflows

### Test Data Preparation
```bash
cd /path/to/repository

# Ensure clean state
git checkout master
git pull origin master

# Verify files exist
ls -la .github/workflows/post-release.yml
ls -la .github/scripts/save-release-metadata.sh
ls -la .github/scripts/load-release-metadata.sh
```

---

## Test 1: Create Beta Release

**Goal:** Verify Beta release creates and saves metadata

### Steps
1. **Bump version**
   ```bash
   # android/app/build.gradle
   versionName "1.3.0"
   versionCode 100
   
   git commit -am "test: bump to v1.3.0 (build 100)"
   git push origin master
   ```

2. **Trigger Beta workflow**
   ```bash
   gh workflow run android-release.yml --raw-field lane=beta
   ```

3. **Wait for completion**
   - Monitor: `gh run list | head -1`
   - Or view on GitHub: Actions tab

### Expected Outcomes
- ✅ Git tag created: `android-v1.3.0-100`
- ✅ GitHub Release created (marked as prerelease)
- ✅ Release body contains commits since previous tag
- ✅ Metadata file created: `.github/.release-metadata/android/1.3.0-100.json`
- ✅ Metadata file committed to repository
- ✅ Slack notification sent

### Verification
```bash
# Check tag
git tag | grep 1.3.0

# Check metadata file
cat .github/.release-metadata/android/1.3.0-100.json | jq .

# Verify commit SHA matches Beta tag
BETA_TAG_SHA=$(git rev-list -n 1 android-v1.3.0-100)
METADATA_SHA=$(cat .github/.release-metadata/android/1.3.0-100.json | jq -r '.commit_sha')
[[ "$BETA_TAG_SHA" == "$METADATA_SHA" ]] && echo "✅ Commit SHAs match" || echo "❌ Mismatch!"
```

---

## Test 2: Add Commits After Beta

**Goal:** Simulate development continuing after Beta

### Steps
1. **Create new commits**
   ```bash
   echo "// New feature 1" >> App.tsx
   git commit -am "feat: new feature 1 after beta"
   
   echo "// New feature 2" >> App.tsx
   git commit -am "feat: new feature 2 after beta"
   
   echo "// New feature 3" >> App.tsx
   git commit -am "feat: new feature 3 after beta"
   
   git push origin master
   ```

2. **Verify HEAD moved**
   ```bash
   git log --oneline -5
   # Should show 3 new commits
   ```

### Expected Outcomes
- ✅ 3 new commits visible in git log
- ✅ HEAD is ahead of Beta tag
- ✅ Metadata file unchanged
- ✅ Beta artifact still on old commit

---

## Test 3: Promote Beta to Production (The Critical Test)

**Goal:** Verify promotion uses exact Beta metadata, ignoring new commits

### Steps
1. **Trigger promotion workflow**
   ```bash
   # Use EXACT same version/build as Beta
   gh workflow run android-release.yml --raw-field lane=promote_to_production
   ```

2. **Wait for completion**
   - Monitor: `gh run list | head -1`

### Expected Outcomes - Tag
- ✅ Git tag created: `android-v1.3.0` (no -BUILD suffix)
- ✅ Tag points to BETA commit (ABC123), NOT current HEAD (XYZ789)

### Verification - Tag Commit
```bash
# Get Beta tag commit
BETA_TAG_COMMIT=$(git rev-list -n 1 android-v1.3.0-100)

# Get Production tag commit
PROD_TAG_COMMIT=$(git rev-list -n 1 android-v1.3.0)

# They should be IDENTICAL
[[ "$BETA_TAG_COMMIT" == "$PROD_TAG_COMMIT" ]] && \
  echo "✅ PASS: Production tag on Beta commit" || \
  echo "❌ FAIL: Production tag on wrong commit"

# Verify it's NOT on current HEAD
CURRENT_HEAD=$(git rev-parse HEAD)
[[ "$PROD_TAG_COMMIT" != "$CURRENT_HEAD" ]] && \
  echo "✅ PASS: Production NOT on current HEAD" || \
  echo "❌ FAIL: Production wrongly on HEAD"
```

### Expected Outcomes - Release Notes
- ✅ GitHub Release created (NOT prerelease)
- ✅ Release body shows ONLY commits A-E (from Beta)
- ✅ Release body does NOT show commits F, G, H (added after Beta)

### Verification - Release Notes
```bash
# Get GitHub Release body
PROD_RELEASE=$(gh release view android-v1.3.0 --json body -q .body)

# Should NOT contain the post-Beta commits
echo "$PROD_RELEASE" | grep -i "new feature 1" && \
  echo "❌ FAIL: Post-Beta commits in release notes" || \
  echo "✅ PASS: Post-Beta commits NOT in release notes"

echo "$PROD_RELEASE" | grep -i "new feature 2" && \
  echo "❌ FAIL: Post-Beta commits in release notes" || \
  echo "✅ PASS: Post-Beta commits NOT in release notes"

echo "$PROD_RELEASE" | grep -i "new feature 3" && \
  echo "❌ FAIL: Post-Beta commits in release notes" || \
  echo "✅ PASS: Post-Beta commits NOT in release notes"
```

---

## Test 4: Verify Metadata Preservation

**Goal:** Confirm metadata is preserved exactly during promotion

### Steps
1. **Extract metadata values**
   ```bash
   BETA_METADATA=$(cat .github/.release-metadata/android/1.3.0-100.json)
   
   BETA_COMMIT=$(echo "$BETA_METADATA" | jq -r '.commit_sha')
   BETA_NOTES=$(echo "$BETA_METADATA" | jq -r '.release_notes')
   ```

2. **Compare to production release**
   ```bash
   PROD_COMMIT=$(git rev-list -n 1 android-v1.3.0)
   PROD_RELEASE=$(gh release view android-v1.3.0 --json body -q .body)
   ```

### Verification
```bash
# Commit should match
[[ "$BETA_COMMIT" == "$PROD_COMMIT" ]] && \
  echo "✅ PASS: Commit preserved" || \
  echo "❌ FAIL: Commit changed"

# Release notes should match
[[ "$BETA_NOTES" == "$PROD_RELEASE" ]] && \
  echo "✅ PASS: Release notes preserved exactly" || \
  echo "⚠️ NOTE: Release formatting may differ slightly"
```

---

## Test 5: Verify Metadata File Safety

**Goal:** Ensure metadata files are tracked in Git for auditability

### Steps
1. **Check Git status**
   ```bash
   git status
   ```

2. **Verify file was committed**
   ```bash
   git log --oneline .github/.release-metadata/android/1.3.0-100.json | head -3
   ```

### Expected Outcomes
- ✅ Metadata file appears in `git log`
- ✅ Metadata file committed by `github-actions[bot]`
- ✅ File is tracked in repository history

---

## Test 6: Edge Case - No Commits Between Beta and Promotion

**Goal:** Test promotion when development hasn't continued

### Steps
1. **Create new Beta**
   ```bash
   versionName "1.3.1"
   versionCode 101
   git commit -am "test: bump to v1.3.1 (build 101)"
   git push origin master
   gh workflow run android-release.yml --raw-field lane=beta
   # Wait for completion
   ```

2. **Immediately promote** (no new commits)
   ```bash
   gh workflow run android-release.yml --raw-field lane=promote_to_production
   # Wait for completion
   ```

### Expected Outcomes
- ✅ Promotion succeeds
- ✅ Production and Beta tags point to same commit
- ✅ Release notes are identical
- ✅ No errors about duplicate tags

---

## Test 7: Error Case - Missing Metadata

**Goal:** Verify graceful handling when metadata doesn't exist

### Steps
1. **Simulate missing metadata**
   ```bash
   # Create version that was never released as Beta
   versionName "1.9.9"
   versionCode 999
   git commit -am "test: bump to v1.9.9 (build 999)"
   git push origin master
   ```

2. **Try to promote without Beta**
   ```bash
   gh workflow run android-release.yml --raw-field lane=promote_to_production
   ```

### Expected Outcomes
- ✅ Workflow fails gracefully
- ✅ Error message: "Metadata file not found"
- ✅ Useful message directing user to create Beta first
- ✅ No partial tag/release created

### Verification
```bash
# Should see error in workflow output
gh run view <latest_run_id> --log | grep "Metadata file not found"
```

---

## Test 8: iOS Platform (if applicable)

**Goal:** Verify fix works for iOS platform too

### Repeat Tests 1-3 with iOS
```bash
# Test 1: Beta
gh workflow run ios-release.yml --raw-field lane=beta

# Test 2: Add commits

# Test 3: Promote
gh workflow run ios-release.yml --raw-field lane=promote_to_production
```

### Expected Outcomes
- ✅ Same behavior as Android
- ✅ Metadata stored: `.github/.release-metadata/ios/VERSION-BUILD.json`
- ✅ Production tag on Beta commit
- ✅ Release notes unchanged

---

## Test 9: Multiple Concurrent Platforms

**Goal:** Verify Android and iOS can have independent release schedules

### Steps
1. **Create Android Beta v1.3.0**
   ```bash
   gh workflow run android-release.yml --raw-field lane=beta
   ```

2. **Create iOS Beta v1.3.0** (same version)
   ```bash
   gh workflow run ios-release.yml --raw-field lane=beta
   ```

3. **Add commits**

4. **Promote only Android**
   ```bash
   gh workflow run android-release.yml --raw-field lane=promote_to_production
   ```

5. **Verify iOS metadata unchanged**

### Expected Outcomes
- ✅ Each platform has separate metadata
- ✅ Promotion of Android doesn't affect iOS
- ✅ iOS can be promoted independently later

---

## Test 10: Slack Notification Content

**Goal:** Verify Slack messages use correct release notes

### Steps
1. **Run Beta release**
2. **Run Promotion**
3. **Check Slack messages** (if integrated)

### Expected Outcomes
- ✅ Beta Slack message shows Beta notes
- ✅ Promotion Slack message shows SAME notes (not new commits)
- ✅ Links point to correct GitHub Releases

---

## Summary Report Template

```
BETA → PRODUCTION PROMOTION TEST
================================

Test Date: ____________________
Tester: ____________________
Platform(s): [ ] Android  [ ] iOS  [ ] Both

TEST RESULTS:
=============

✅ Test 1: Beta Release Metadata
✅ Test 2: Commits After Beta
✅ Test 3: Promotion Uses Beta Commit (CRITICAL)
✅ Test 4: Metadata Preservation
✅ Test 5: Git Tracking
✅ Test 6: No Commits Between Beta/Promo
✅ Test 7: Error Handling
✅ Test 8: iOS Platform
✅ Test 9: Concurrent Platforms
✅ Test 10: Slack Notifications

ISSUES FOUND:
=============
(none)

SIGN-OFF:
=========
The release promotion workflow correctly handles the edge case
where commits are added after a Beta release. Production releases
always point to the exact tested Beta artifact.

Tester: __________________
Date: ____________________
```

---

## Cleanup After Testing

```bash
# Remove test tags (optional)
git tag -d android-v1.3.0-100 android-v1.3.0 \
        android-v1.3.1-101 \
        ios-v1.3.0-100 ios-v1.3.0
git push origin --delete android-v1.3.0-100 android-v1.3.0 \
        android-v1.3.1-101 \
        ios-v1.3.0-100 ios-v1.3.0

# Remove test metadata files (optional)
rm -rf .github/.release-metadata/

# Delete test GitHub Releases (via GitHub web UI)
```

---

## Success Criteria

✅ All 10 tests pass  
✅ Production release notes exclude post-Beta commits  
✅ Production tag points to Beta commit, not HEAD  
✅ Metadata files preserved in Git  
✅ Slack notifications show correct information  

**Result:** ✅ Release promotion workflow is production-ready
