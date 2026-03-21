#!/bin/zsh

set -euo pipefail

VERSION="${1:?Usage: $0 <version>}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

CUEPANE_VERSION="$VERSION" "$REPO_ROOT/scripts/build_dmg.sh"

echo ""
echo "로컬 릴리즈 산출물 준비 완료"
echo "  DMG: $REPO_ROOT/dist/CuePane.dmg"
echo ""
echo "원격 릴리즈 업로드는 일부러 자동화하지 않았습니다."
echo "현재 작업 규칙상 push를 하지 않기 때문입니다."
