#!/bin/sh
set -eu
YUEQI_REPO_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$YUEQI_REPO_ROOT/小说/client"
"$YUEQI_REPO_ROOT/tool/flutterw" pub get --enforce-lockfile
"$YUEQI_REPO_ROOT/tool/dartw" format --output=none --set-exit-if-changed lib test tool/mac06 tool/mac03 tool/mac16 tool/mac04 tool/mac05 tool/mac07 "$YUEQI_REPO_ROOT/packages/reader_core/lib" "$YUEQI_REPO_ROOT/packages/platform_services/lib" "$YUEQI_REPO_ROOT/packages/reader_storage/lib"
"$YUEQI_REPO_ROOT/tool/dartw" analyze --fatal-infos --fatal-warnings
"$YUEQI_REPO_ROOT/tool/flutterw" test
cd "$YUEQI_REPO_ROOT/packages/reader_core"
"$YUEQI_REPO_ROOT/tool/dartw" pub get
"$YUEQI_REPO_ROOT/tool/dartw" analyze --fatal-infos --fatal-warnings

cd "$YUEQI_REPO_ROOT/packages/platform_services"
"$YUEQI_REPO_ROOT/tool/dartw" pub get
"$YUEQI_REPO_ROOT/tool/dartw" analyze --fatal-infos --fatal-warnings

cd "$YUEQI_REPO_ROOT/packages/reader_storage"
"$YUEQI_REPO_ROOT/tool/dartw" pub get
"$YUEQI_REPO_ROOT/tool/dartw" analyze --fatal-infos --fatal-warnings

cd "$YUEQI_REPO_ROOT"
python3 -m unittest discover -s 小说/client/tool/mac06 -p 'test_*.py'
