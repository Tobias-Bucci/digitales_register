#!/usr/bin/env bash
# Run from the repository root on the existing signed Codemagic/macOS runner.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != Darwin ]]; then
  echo 'This release script requires macOS/Xcode.' >&2
  exit 1
fi
echo "Release source commit: $(git rev-parse HEAD)"
echo "Codemagic counter (not used as CFBundleVersion): ${BUILD_NUMBER:-unset}"
flutter --version
pod --version
python3 tool/prepare_ios_firebase.py
python3 tool/check_ios_release.py

# Explicit arguments take precedence over Codemagic's BUILD_NUMBER counter.
read -r build_name build_number < <(python3 - <<'PY'
from pathlib import Path
import re
version = re.search(r'^version: (\d+\.\d+\.\d+)\+([1-9]\d*)$',
                    Path('pubspec.yaml').read_text(encoding='utf-8'), re.M)
if version is None:
    raise SystemExit('Invalid Flutter release version')
print(version[1], version[2])
PY
)

# Remove generated app/SPM output and the local CocoaPods sandbox, not signing
# files, the lockfile or global caches. Never restore caches after this point.
flutter clean
rm -rf -- ios/Pods ios/.symlinks ios/Flutter/ephemeral
flutter pub get
python3 tool/check_ios_release.py
python3 - <<'PY'
import json
from pathlib import Path
metadata = json.loads(Path('.flutter-plugins-dependencies').read_text())
picker = next(p for p in metadata['plugins']['ios'] if p['name'] == 'file_picker')
actual = Path(picker['path']).resolve()
expected = Path('packages/file_picker').resolve()
if actual != expected:
    raise SystemExit(f'Wrong file_picker source: {actual}; expected {expected}')
print('Verified file_picker source:', actual)
print('SPM configuration:', metadata.get('swift_package_manager_enabled'))
PY
flutter build ios --config-only --release --no-codesign \
  --build-name="$build_name" --build-number="$build_number"
(cd ios && pod install --repo-update)
# Fail before archiving if a stale Pod installation still includes the fallback.
if grep -Eq 'DKImagePickerController|DKPhotoGallery|DKCamera' ios/Podfile.lock; then
  echo 'Unused legacy media Pods are still resolved; check plugin source and dependency caches.' >&2
  exit 1
fi
mkdir -p build/ios/diagnostics
cp ios/Podfile.lock build/ios/diagnostics/Podfile.lock
build_args=(--release "--build-name=$build_name" "--build-number=$build_number")
if [[ -n "${IOS_EXPORT_OPTIONS_PLIST:-}" ]]; then
  [[ -f "$IOS_EXPORT_OPTIONS_PLIST" ]] || { echo 'Export options plist missing.' >&2; exit 1; }
  build_args+=("--export-options-plist=$IOS_EXPORT_OPTIONS_PLIST")
fi
flutter build ipa "${build_args[@]}"
python3 tool/check_ios_release.py \
  --app-plist build/ios/archive/Runner.xcarchive/Products/Applications/Runner.app/Info.plist
python3 tool/inspect_ios_artifact.py \
  build/ios/archive/Runner.xcarchive/Products/Applications/Runner.app \
  --report build/ios/diagnostics/archive.json
# Inspect the export too: publishing uploads the IPA, not the xcarchive.
ipa_path=$(python3 - <<'PY'
from pathlib import Path
ipas = list(Path('build/ios/ipa').glob('*.ipa'))
if len(ipas) != 1:
    raise SystemExit(f'Expected exactly one fresh IPA, found {len(ipas)}')
print(ipas[0])
PY
)
python3 tool/inspect_ios_artifact.py "$ipa_path" --report build/ios/diagnostics/ipa.json
echo "Verified IPA for publication: $ipa_path ($build_name+$build_number)"
