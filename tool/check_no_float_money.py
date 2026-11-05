"""Structural check that money code never touches floating point (spec §14).

Run through tool/check_no_float_money.sh, which documents the rule.

Scanning source text naively produces false positives — a '/' inside a URL, a
'double' inside a comment — so string literals and comments are blanked out
before the patterns are applied.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# Directories whose every line must be free of floating point.
SCAN_ROOTS = [Path("lib/core/money"), Path("lib/core/split")]
FEATURE_LAYERS = ("domain", "data")

# Generated files are not hand-written; the declarations that drive them are
# what this check governs.
GENERATED = (".g.dart", ".freezed.dart")

# Converting a JSON number to an int yields an int and never does float
# arithmetic. json_serializable emits exactly this, and hand-written fromJson
# bodies mirror it.
SAFE_IDIOMS = [re.compile(r"as num\??\)\??\.toInt\(\)")]

PATTERNS = [
    (re.compile(r"\bdouble\b"), "double"),
    (re.compile(r"\bnum\b"), "num"),
    (re.compile(r"\.toDouble\b"), "toDouble()"),
    # Division that is not truncating (~/). Money divides with ~/ and hands the
    # remainder to the split engine's largest-remainder rule (spec §6.2).
    (re.compile(r"(?<![~/])/(?![/=])"), "inexact division (/)"),
]

STRING_LITERAL = re.compile(
    r"""r?'''.*?'''|r?\"\"\".*?\"\"\"|r?'(?:\\.|[^'\\])*'|r?"(?:\\.|[^"\\])*\"""",
    re.S,
)


def scan_dirs() -> list[Path]:
    dirs = [d for d in SCAN_ROOTS if (ROOT / d).is_dir()]
    features = ROOT / "lib" / "features"
    if features.is_dir():
        for feature in sorted(features.iterdir()):
            for layer in FEATURE_LAYERS:
                path = feature / layer
                if path.is_dir():
                    dirs.append(path.relative_to(ROOT))
    return dirs


def blank_noise(source: str) -> str:
    """Replaces string literals and comments with spaces, preserving offsets."""
    source = STRING_LITERAL.sub(lambda m: " " * len(m.group(0)), source)
    out = []
    for line in source.split("\n"):
        stripped = line.lstrip()
        if stripped.startswith(("//", "///", "*", "/*")):
            out.append(" " * len(line))
        else:
            comment = line.find("//")
            out.append(line[:comment] + " " * (len(line) - comment) if comment != -1 else line)
    return "\n".join(out)


def main() -> int:
    dirs = scan_dirs()
    if not dirs:
        print("check_no_float_money: nothing to scan yet")
        return 0

    violations: list[str] = []

    for directory in dirs:
        for path in sorted((ROOT / directory).rglob("*.dart")):
            if path.name.endswith(GENERATED):
                continue

            raw_lines = path.read_text().split("\n")
            cleaned = blank_noise(path.read_text()).split("\n")

            for number, (raw, line) in enumerate(zip(raw_lines, cleaned), start=1):
                if "money-ok:" in raw:
                    continue
                for idiom in SAFE_IDIOMS:
                    line = idiom.sub("", line)
                for pattern, label in PATTERNS:
                    if pattern.search(line):
                        rel = path.relative_to(ROOT)
                        violations.append(f"  {rel}:{number}: {label} — {raw.strip()}")
                        break

    if violations:
        print("✗ Floating-point or inexact division in money code (spec §4.1, §14):")
        print("\n".join(violations))
        print()
        print("Use int centavos and ~/. If a line is genuinely safe, append")
        print("  // money-ok: <why>")
        return 1

    print(f"✓ no floating-point money in {len(dirs)} scanned directories")
    return 0


if __name__ == "__main__":
    sys.exit(main())
