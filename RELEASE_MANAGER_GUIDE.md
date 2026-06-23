# Release Manager Quick Reference

## Three Release Lanes

### 🧪 Beta Release
**When:** To release a new beta for testing  
**Command:** `gh workflow run android-release.yml --raw-field lane=beta`  
**What happens:**
- Creates tag: `platform-vX.Y.Z-BUILD`
- Generates release notes from previous tag
- Creates GitHub Release (prerelease)
- **Saves metadata for later promotion**
- Sends Slack notification to testing channel

**Time to Production:** ✋ Wait for QA approval (can be days)

---

### 🚀 Promote Beta to Production
**When:** QA approved the Beta build → promote to Production  
**Command:** `gh workflow run android-release.yml --raw-field lane=promote_to_production`  
**What happens:**
- **Uses exact Beta commit** (not current HEAD)
- **Uses Beta release notes** (no new commits)
- Creates tag: `platform-vX.Y.Z` on Beta commit
- Creates GitHub Release (full release)
- Sends Slack notification to shipping channel

**Prerequisites:**
- Must match version/build from approved Beta
- Beta was released with `lane=beta` first

**Important:** This is the safe way to promote tested builds

---

### 🏭 Direct Production Build
**When:** Emergency or direct production bypass (rare)  
**Command:** `gh workflow run android-release.yml --raw-field lane=production`  
**What happens:**
- Creates tag: `platform-vX.Y.Z-BUILD`
- Generates release notes from current HEAD
- Creates GitHub Release (full release)
- Does NOT save metadata for reuse
- Sends Slack notification

**Use case:** Direct to production without beta testing (not recommended)

---

## Workflow: Beta → Production (Recommended)

### Day 1: Create Beta
```bash
# Bump version in source files
# android/app/build.gradle:
#   versionName "1.2.22"
#   versionCode 70

git commit -am "chore: bump to v1.2.22"
git push origin master

# Trigger Beta release
gh workflow run android-release.yml --raw-field lane=beta
# Wait for workflow to complete
# Check GitHub Release page
# Share TestFlight/Internal Testing link on Slack
```

**Metadata saved:** `.github/.release-metadata/android/1.2.22-70.json`

---

### Days 2-N: Development Continues
```bash
# QA tests the Beta build
# New feature commits are merged
git commit -am "feat: new feature"
git push origin master
# More commits added...
# HEAD is now WAY ahead of Beta commit
# But Beta artifact is still unchanged
```

**Important:** Beta build remains unchanged. Version not bumped yet.

---

### Day N+1: Beta Approved ✓

```bash
# QA approves Beta ✓
# Release manager promotes to Production

gh workflow run android-release.yml --raw-field lane=promote_to_production

# Workflow automatically:
# 1. Loads Beta metadata from .github/.release-metadata/android/1.2.22-70.json
# 2. Uses Beta's exact commit (NOT current HEAD)
# 3. Uses Beta's exact release notes (NOT commits F-J)
# 4. Creates Production tag on Beta commit
# 5. Creates GitHub Release with Beta notes
# 6. Notifies Slack shipping channel
```

**Result:**
- Production release shows: A, B, C, D, E (exactly what was tested)
- Commits F-J (added after Beta) are NOT in Production release notes
- GitHub Release URL points to Production build
- Play Store / App Store link in Slack

---

## Metadata Management

### Where Metadata is Stored
```
.github/.release-metadata/
├── android/
│   ├── 1.2.22-70.json      ← From Beta (2024-06-23)
│   ├── 1.2.23-71.json      ← From Beta (2024-06-24)
│   └── 1.2.24-72.json      ← From Beta (2024-06-25)
├── ios/
│   ├── 1.2.22-70.json
│   └── ...
```

### What's in Each File
```json
{
  "platform": "android",
  "tag": "android-v1.2.22-70",
  "version": "1.2.22",
  "build": "70",
  "commit_sha": "abc123def456...",
  "created_at": "2024-06-23T15:30:45Z",
  "release_notes": "## Release Overview\n... (full notes)"
}
```

### How Promotion Uses It
1. Promotion run with `lane=promote_to_production`
2. Workflow loads metadata for version/build
3. Extracts stored commit SHA
4. Tags THAT commit (not current HEAD)
5. Extracts stored release notes
6. Creates GitHub Release with those notes

### Manual Promotion (No Metadata)
If you need to promote an OLD Beta without metadata:
```bash
# Last resort only
gh workflow run android-release.yml --raw-field lane=production
# This generates release notes from current HEAD
# Not recommended after commits have been added
```

---

## Checklist: Before Promoting to Production

- [ ] Beta was released with `lane=beta`
- [ ] Version and build number match approved Beta
- [ ] QA sign-off received
- [ ] Metadata file exists: `.github/.release-metadata/PLATFORM/VERSION-BUILD.json`
- [ ] GitHub Release (prerelease) shows correct Beta notes
- [ ] Slack message confirms Beta link

---

## Checklist: After Promoting to Production

- [ ] Workflow completed successfully
- [ ] GitHub Release (full, not prerelease) created
- [ ] Release notes match Beta release notes
- [ ] Tag created: `platform-vX.Y.Z` (no -BUILD suffix)
- [ ] Slack notification includes Play Store / App Store link
- [ ] QA + Marketing confirmed link is correct

---

## Common Questions

**Q: Can I promote an old Beta that's weeks old?**  
A: Yes! As long as metadata file exists. The workflow will use the exact commit and notes from that old Beta.

**Q: What if I add commits between Beta and promotion?**  
A: They won't appear in release notes. Production will show only what was in the approved Beta.

**Q: Can I skip Beta and go straight to Production?**  
A: Yes, use `lane=production`. But you won't get the safety of tested metadata.

**Q: What if I promote the wrong version by accident?**  
A: The tag won't be created if it already exists. You can manually clean up and retry.

**Q: Can multiple platforms (Android/iOS) have different release schedules?**  
A: Yes! Each platform has separate metadata files and separate tags. Android v1.2.22 can be in production while iOS is still on v1.2.21 in beta.

**Q: How do I promote if I don't have the metadata file?**  
A: Use `lane=production` instead (not recommended). It will generate notes from current HEAD.

---

## Emergency Recovery

### Tag Already Exists
```bash
# If you see: "Tag android-v1.2.22 already exists"
# Delete the tag locally and remotely:
git tag -d android-v1.2.22
git push origin --delete android-v1.2.22
# Then re-run the workflow
gh workflow run android-release.yml --raw-field lane=promote_to_production
```

### Wrong Release Notes
```bash
# If GitHub Release has wrong notes:
# 1. Delete the GitHub Release (keep the tag)
# 2. Delete the release on GitHub's web UI
# 3. Re-run the workflow
# The workflow will recreate the release with correct notes
```

### Metadata File Corrupted
```bash
# If workflow says "Could not read commit_sha from metadata"
# Check the JSON file:
cat .github/.release-metadata/android/1.2.22-70.json | jq .
# Fix or recreate if corrupted
git add .github/.release-metadata/...
git commit -m "fix: repair metadata"
git push origin master
# Retry promotion
```

---

## Reference Links

- [Full Documentation](./RELEASE_PROMOTION.md)
- [Change Summary](./RELEASE_FIX_SUMMARY.md)
- [Post-Release Workflow](.github/workflows/post-release.yml)
- [Save Metadata Script](.github/scripts/save-release-metadata.sh)
- [Load Metadata Script](.github/scripts/load-release-metadata.sh)
