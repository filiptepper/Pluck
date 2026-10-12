#!/bin/bash

# Exit on error
set -e

# Make sure we are at the repository root
REPO_ROOT=$(git rev-parse --show-toplevel)
cd "$REPO_ROOT"

# Ensure clean working directory (except for untracked files)
if ! git diff-index --quiet HEAD --; then
    echo "❌ Error: You have uncommitted changes. Please stash or commit them before releasing."
    exit 1
fi

INFO_PLIST="Pluck/Info.plist"

# Get current version and build number using PlistBuddy
CURRENT_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFO_PLIST")
CURRENT_BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$INFO_PLIST")

echo "Current version: $CURRENT_VERSION (Build $CURRENT_BUILD)"
read -p "Enter new version number (e.g. 1.1): " NEW_VERSION

if [ -z "$NEW_VERSION" ]; then
    echo "❌ Error: Version cannot be empty."
    exit 1
fi

# Increment build number
NEW_BUILD=$((CURRENT_BUILD + 1))

echo "Bumping version in $INFO_PLIST to $NEW_VERSION (Build $NEW_BUILD)..."
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $NEW_VERSION" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $NEW_BUILD" "$INFO_PLIST"

# Commit and Tag
echo "Staging changes and committing..."
git add "$INFO_PLIST"
git commit -m "chore: bump version to $NEW_VERSION (build $NEW_BUILD)"

TAG_NAME="v$NEW_VERSION"
echo "Creating tag $TAG_NAME..."
git tag "$TAG_NAME"

echo "✅ Success! Version bumped to $NEW_VERSION and tagged with $TAG_NAME."
echo ""
read -p "Would you like to push this branch and tag to GitHub to trigger the release workflow? [y/N]: " PUSH_CONFIRM

if [[ "$PUSH_CONFIRM" =~ ^[yY](es)?$ ]]; then
    CURRENT_BRANCH=$(git branch --show-current)
    echo "Pushing $CURRENT_BRANCH and tag $TAG_NAME to GitHub..."
    git push origin "$CURRENT_BRANCH"
    git push origin "$TAG_NAME"
    echo "🚀 Pushed successfully! Monitor GitHub Actions for the build."
else
    echo "Skipped pushing. You can manually push when ready:"
    echo "  git push origin $(git branch --show-current)"
    echo "  git push origin $TAG_NAME"
fi
