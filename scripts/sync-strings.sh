#!/bin/zsh
# 코드에서 번역할 문구를 모아 번역표(Localizable.xcstrings)에 넣고, 영어 번역이 빠진 문구를 알려준다.
# Xcode에서 빌드하면 저절로 되지만, 커맨드라인 빌드는 번역표를 고치지 않아서 이 스크립트를 쓴다.
# 새 문구는 Text("…")처럼 SwiftUI에 바로 넣거나, 그 밖에서는 String(localized: "…")로 쓴다.
set -euo pipefail

cd "$(dirname "$0")/.."
build_dir=$(mktemp -d)
trap 'rm -rf "$build_dir"' EXIT

echo "▸ 문구 모으기 (깨끗한 빌드)"
xcodebuild -project Tokta.xcodeproj -scheme Tokta -destination "platform=macOS,arch=$(uname -m)" \
  -derivedDataPath "$build_dir" CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= \
  SWIFT_EMIT_LOC_STRINGS=YES -quiet build

# iPhone 앱도 문구를 모은다(시뮬레이터용 빌드).
xcodebuild -project Tokta.xcodeproj -target ToktaPhone -sdk iphonesimulator -configuration Debug \
  SYMROOT="$build_dir/phone" OBJROOT="$build_dir/phone-obj" CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= \
  SWIFT_EMIT_LOC_STRINGS=YES -quiet build

objects="$build_dir/Build/Intermediates.noindex/Tokta.build/Debug"
phone="$build_dir/phone-obj/Tokta.build/Debug-iphonesimulator"
xcrun xcstringstool sync Tokta/Localizable.xcstrings --stringsdata "$objects"/Tokta.build/Objects-normal/*/*.stringsdata
xcrun xcstringstool sync ToktaWidget/Localizable.xcstrings --stringsdata "$objects"/ToktaWidget.build/Objects-normal/*/*.stringsdata
xcrun xcstringstool sync ToktaPhone/Localizable.xcstrings --stringsdata "$phone"/ToktaPhone.build/Objects-normal/*/*.stringsdata

echo "▸ 영어 번역이 빠진 문구"
python3 -I - <<'PY'
import json
missing = 0
for path in ("Tokta/Localizable.xcstrings", "ToktaWidget/Localizable.xcstrings", "ToktaPhone/Localizable.xcstrings"):
    strings = json.load(open(path))["strings"]
    for key, value in sorted(strings.items()):
        if value.get("extractionState") == "stale":
            continue
        if "en" not in value.get("localizations", {}):
            print(f"  {path}: {key!r}")
            missing += 1
print("  없음" if missing == 0 else f"  {missing}개 — 번역표에 영어를 채우세요")
PY
