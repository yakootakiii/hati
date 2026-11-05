#!/usr/bin/env bash
# Builds the web app into the website at /app/ (DECISIONS D-71).
#
#   tool/build_web.sh && firebase deploy --only hosting
set -euo pipefail
cd "$(dirname "$0")/.."

flutter build web --release --base-href /app/ --dart-define-from-file=.env
rm -rf hosting/public/app
cp -R build/web hosting/public/app
echo "Web app copied to hosting/public/app"
