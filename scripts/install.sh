#!/bin/zsh
# Tokta를 Release로 빌드해 /Applications에 설치하고 실행한다.
# 빌드 번호는 커밋 수 + 100(scripts/build-number.sh). 설정 → 일반의 버전에서 100을 빼면 커밋 수.
set -euo pipefail

cd "$(dirname "$0")/.."
build_dir=build/install
app="$build_dir/Build/Products/Release/Tokta.app"
target=/Applications/Tokta.app

build=$(scripts/build-number.sh)
echo "▸ 빌드 (빌드 번호 $build)"
xcodebuild -project Tokta.xcodeproj -scheme Tokta -configuration Release \
  -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath "$build_dir" -allowProvisioningUpdates \
  CURRENT_PROJECT_VERSION="$build" \
  -quiet build

codesign --verify --strict "$app"

if pgrep -x Tokta >/dev/null; then
  echo "▸ 실행 중인 Tokta 종료"
  osascript -e 'tell application "Tokta" to quit' || true
  for _ in {1..20}; do pgrep -x Tokta >/dev/null || break; sleep 0.25; done
  pkill -x Tokta || true
fi

echo "▸ $target 에 설치"
rm -rf "$target"
ditto "$app" "$target"

echo "▸ 실행"
# 방금 끈 Tokta를 LaunchServices가 정리하기 전에 열면 실패할 수 있어 몇 번 다시 시도한다.
for attempt in {1..5}; do
  open "$target" 2>/dev/null && exit 0
  sleep 1
done
echo "Tokta를 열지 못했습니다. 응용 프로그램 폴더에서 직접 여세요." >&2
exit 1
