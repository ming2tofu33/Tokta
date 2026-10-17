#!/bin/zsh
# 다른 Mac에 배포할 Tokta를 만든다: Developer ID 서명 → Apple 공증 → 공증표 붙이기 → DMG.
# 결과는 dist/Tokta-<버전>.dmg. 빌드 번호는 install.sh와 같이 커밋 수.
#
# 처음 한 번, 공증용 로그인 정보를 키체인에 저장해야 한다(비밀번호는 appleid.apple.com에서 만든 앱 전용 암호):
#   xcrun notarytool store-credentials tokta-notary --apple-id <Apple ID 이메일> --team-id <팀 ID>
set -euo pipefail

cd "$(dirname "$0")/.."
profile=tokta-notary
build=$(git rev-list --count HEAD)
work=build/release
archive="$work/Tokta.xcarchive"
app="$work/export/Tokta.app"

if ! xcrun notarytool history --keychain-profile "$profile" >/dev/null 2>&1; then
  echo "공증용 로그인 정보($profile)가 키체인에 없습니다. 먼저 한 번 실행하세요:"
  echo "  xcrun notarytool store-credentials $profile --apple-id <Apple ID 이메일> --team-id <팀 ID>"
  exit 1
fi

rm -rf "$work"
mkdir -p "$work" dist

echo "▸ 아카이브 (빌드 번호 $build)"
xcodebuild -project Tokta.xcodeproj -scheme Tokta -configuration Release \
  -destination 'generic/platform=macOS' -archivePath "$archive" -allowProvisioningUpdates \
  CURRENT_PROJECT_VERSION="$build" -quiet archive

echo "▸ Developer ID로 서명해서 내보내기"
xcodebuild -exportArchive -archivePath "$archive" -exportOptionsPlist scripts/ExportOptions.plist \
  -exportPath "$work/export" -allowProvisioningUpdates -quiet
codesign --verify --deep --strict "$app"
version=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$app/Contents/Info.plist")

# 앱을 공증하고 공증표를 앱에 붙인다. 그러면 DMG 자체는 서명하지 않아도 인터넷 없이도 열린다.
echo "▸ 공증 (몇 분 걸려요)"
ditto -c -k --keepParent "$app" "$work/Tokta.zip"
xcrun notarytool submit "$work/Tokta.zip" --keychain-profile "$profile" --wait
xcrun stapler staple "$app"
spctl -a -vv "$app"

echo "▸ DMG"
dmg="dist/Tokta-$version.dmg"
staging="$work/dmg"
mkdir -p "$staging"
ditto "$app" "$staging/Tokta.app"
ln -s /Applications "$staging/Applications"
rm -f "$dmg"
hdiutil create -volname "Tokta $version" -srcfolder "$staging" -format UDZO -quiet "$dmg"

echo "▸ 완료: $dmg (버전 $version, 빌드 $build)"
