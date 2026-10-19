#!/usr/bin/env python3
"""Line-coverage gate for an .xcresult bundle.

Usage: scripts/check-coverage.py <path.xcresult> <min-percent> <target> [<target> ...]

Reads `xcrun xccov view --report --json`, and for every named target prints its
line coverage plus each file below the threshold. Exits 1 when any target is
under <min-percent>. A target with no executable lines (or absent from the
report because it has none) passes with a notice.

When the bundle holds no coverage archive at all (no test ran), the gate passes only
if every named target's sources under Sources/<target> contain no code — comments and
blank lines only, i.e. a scaffold. Any code without coverage data fails.
"""

import json
import pathlib
import subprocess
import sys


def target_key(name: str) -> str:
    # xccov names SwiftPM targets "Foo", "Foo.o" or "Foo.framework" depending on the build.
    return name.split(".")[0]


def has_code(target: str) -> bool:
    for source in pathlib.Path("Sources", target).rglob("*.swift"):
        for line in source.read_text().splitlines():
            stripped = line.strip()
            if stripped and not stripped.startswith("//"):
                return True
    return False


def main() -> int:
    if len(sys.argv) < 4:
        print(__doc__)
        return 2
    xcresult, minimum, wanted = sys.argv[1], float(sys.argv[2]), sys.argv[3:]
    result = subprocess.run(["xcrun", "xccov", "view", "--report", "--json", xcresult],
                            capture_output=True, text=True)
    if result.returncode != 0:
        with_code = [name for name in wanted if has_code(name)]
        if with_code:
            print(f"❌ No coverage data in {xcresult}, but these targets have code: {', '.join(with_code)}")
            print(result.stderr.strip())
            return 1
        print("ℹ️  No coverage data and no code in the named targets (scaffold) — nothing to cover")
        return 0
    report = json.loads(result.stdout)
    targets = {target_key(t["name"]): t for t in report.get("targets", [])}

    failed = False
    for name in wanted:
        target = targets.get(name)
        if target is None or target["executableLines"] == 0:
            print(f"ℹ️  {name}: no executable lines")
            continue
        percent = 100.0 * target["coveredLines"] / target["executableLines"]
        ok = percent >= minimum
        failed |= not ok
        print(f"{'✅' if ok else '❌'} {name}: {percent:.2f}% "
              f"({target['coveredLines']}/{target['executableLines']} lines, minimum {minimum:g}%)")
        for file in target.get("files", []):
            if file["executableLines"] and file["coveredLines"] < file["executableLines"]:
                file_percent = 100.0 * file["coveredLines"] / file["executableLines"]
                if file_percent < minimum:
                    print(f"    {file['path']}: {file_percent:.2f}% "
                          f"({file['coveredLines']}/{file['executableLines']})")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
