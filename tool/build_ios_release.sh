#!/usr/bin/env bash
# Run from the repository root on the existing signed Codemagic/macOS runner.
set -euo pipefail

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

flutter pub get
(cd ios && pod install)
# Fail before archiving if a stale Pod installation still includes the fallback.
if grep -Eq 'DKImagePickerController|DKPhotoGallery|DKCamera' ios/Podfile.lock; then
  echo 'Unused legacy media Pods are still resolved; check PICKER_LEGACY_MEDIA.' >&2
  exit 1
fi
flutter build ipa --release --build-name="$build_name" --build-number="$build_number"
python3 tool/check_ios_release.py \
  --app-plist build/ios/archive/Runner.xcarchive/Products/Applications/Runner.app/Info.plist
