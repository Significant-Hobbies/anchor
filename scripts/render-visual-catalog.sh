#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
repo_root=${script_dir:h}
output_dir=${1:-${repo_root}/artifacts/design/visual-catalog}
derived_data=${repo_root}/build/visual-catalog-derived

cd "${repo_root}/Apps"
xcodegen generate

cd "${repo_root}"
npx -y xcodebuildmcp@2.7.0 macos build \
  --project-path Apps/Anchor.xcodeproj \
  --scheme "Anchor Visual Catalog" \
  --configuration DebugLocal \
  --derived-data-path "${derived_data}" \
  --prefer-xcodebuild \
  --output text

"${derived_data}/Build/Products/DebugLocal/Anchor Visual Catalog.app/Contents/MacOS/Anchor Visual Catalog" \
  --output "${output_dir}"
