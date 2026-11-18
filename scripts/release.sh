#!/usr/bin/env bash
# Builds, signs and publishes a release from this computer, for when you do not want the signing key on
# GitHub. It produces exactly what .github/workflows/release.yml produces, so use one or the other for a
# given version, not both.
#
#   scripts/release.sh 2026.11.18
#
# Needs: Flutter 3.24.5 on PATH, Java 21, the Android SDK, the GitHub CLI (gh, logged in), and a file with
# the signing settings (default ~/.android/ltvl-fork.env) that defines KEYSTORE_FILE, KEYSTORE_PASSWORD,
# KEY_ALIAS and KEY_PASSWORD. Use the same keystore every time, or installed apps will refuse the update.
set -euo pipefail

VERSION="${1:?usage: scripts/release.sh <version>   (for example 2026.11.18)}"
VERSION="${VERSION#v}"
TAG="v$VERSION"
ENV_FILE="${KEYSTORE_ENV:-$HOME/.android/ltvl-fork.env}"

cd "$(dirname "$0")/.."
[ -f "$ENV_FILE" ] || { echo "Missing $ENV_FILE (see the comments at the top of this script)" >&2; exit 1; }
[ -z "$(git status --porcelain)" ] || { echo "The working tree is not clean; commit or stash first." >&2; exit 1; }
git rev-parse "$TAG" >/dev/null 2>&1 && { echo "Tag $TAG already exists." >&2; exit 1; }

set -a; . "$ENV_FILE"; set +a

echo "== tests"
flutter pub get
flutter pub run build_runner build --delete-conflicting-outputs
flutter pub run drift_dev schema generate drift_schemas/ test/generated_migrations/
flutter test --reporter compact || { echo "Tests failed; nothing was published." >&2; exit 1; }

BUILD=$((10000 + $(git rev-list --count HEAD)))
echo "== building $VERSION ($BUILD)"
flutter build apk --release --split-per-abi --target-platform android-arm,android-arm64 --build-name "$VERSION" --build-number "$BUILD"
flutter build apk --release --target-platform android-arm,android-arm64 --build-name "$VERSION" --build-number "$BUILD"

rm -rf dist && mkdir dist
cp build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk dist/LTvLauncher-Enhanced-armeabi-v7a.apk
cp build/app/outputs/flutter-apk/app-arm64-v8a-release.apk dist/LTvLauncher-Enhanced-arm64-v8a.apk
cp build/app/outputs/flutter-apk/app-release.apk dist/LTvLauncher-Enhanced-universal.apk
(cd dist && for f in *.apk; do sha256sum "$f" > "$f.sha256"; done)
ls -la dist

echo "== publishing $TAG"
gh release create "$TAG" dist/* --title "LTvLauncher Enhanced $VERSION" --generate-notes --target "$(git rev-parse --abbrev-ref HEAD)"
echo "Published. Installed launchers will offer it within a day, or right away via Settings, Updates."
