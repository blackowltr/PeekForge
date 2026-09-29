#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h}"
build_dir="$project_dir/../../work/PeekForgeBuild"
xcodebuild -project "$project_dir/PeekForge.xcodeproj" -scheme PeekForge -configuration Release -derivedDataPath "$build_dir" build CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual
python3 -c 'from pathlib import Path; import shutil, sys; p = Path(sys.argv[1]); shutil.rmtree(p) if p.exists() else None' "$project_dir/../PeekForge.app"
cp -R "$build_dir/Build/Products/Release/PeekForge.app" "$project_dir/../PeekForge.app"
codesign --verify --deep --strict "$project_dir/../PeekForge.app"
print "Hazır: $project_dir/../PeekForge.app"
