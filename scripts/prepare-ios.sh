#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
npm ci --cache .cache/npm
npm run ios:sync
npm run ios:check
if xcodebuild -version >/dev/null 2>&1; then
  open ios/App/App.xcodeproj
else
  echo 'Project is prepared. Install Xcode from the Mac App Store, launch it to finish setup, then open ios/App/App.xcodeproj.'
fi
