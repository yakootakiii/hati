#!/usr/bin/env bash
# Spec §14: "No floating-point arithmetic is used for money anywhere in the
# codebase (lint or grep check in CI)."
#
# Dart has no lint for this, so we enforce it structurally: the directories
# that handle money — the Money type, the split engine, and every feature's
# domain and data layers — may not mention double/num, may not call toDouble,
# and must use truncating division (~/) rather than /.
#
# Presentation code is deliberately not scanned: doubles are unavoidable there
# (padding, opacity, animation) and money never reaches it as anything but a
# formatted string or a Money.
#
# A line that genuinely needs one of these — the final format-for-display step
# is the only known case — opts out with a trailing `// money-ok: <reason>`.

set -euo pipefail
cd "$(dirname "$0")/.."

exec python3 tool/check_no_float_money.py "$@"
