#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

# Qt 6.12 added a QtQuick Color singleton. An unversioned `import QtQuick`
# pulls it in, and it shadows qs.Commons' Color for unqualified access whatever
# the import order, so every Color.<token> reads undefined: the bar and panels
# render black while their click targets still work. A versioned import below
# 6.12 does not export it.
unpinned=()
while IFS= read -r file; do
  grep -qE '^import QtQuick$' "$file" && unpinned+=("${file#"$ROOT"/}")
done < <(grep -rlE '\bColor\.[a-z]' "$ROOT/shell" --include='*.qml')

(( ${#unpinned[@]} == 0 )) ||
  fail "shell QML using Color pins its QtQuick import" "${unpinned[*]}"
pass "shell QML using Color pins its QtQuick import"
