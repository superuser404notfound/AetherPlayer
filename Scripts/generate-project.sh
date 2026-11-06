#!/usr/bin/env bash
# Regenerate AetherPlayer.xcodeproj from project.yml, with the package traits project.yml lists.
#
# Use this instead of a bare `xcodegen generate`, locally and in CI: XcodeGen before 2.46 ignores
# package traits, so the `traits:` list under a package in project.yml is written into its package
# reference here, the way Xcode itself stores it. Without this step every opt-in trait of
# AetherEngine (object audio) is silently off. XcodeGen 2.46 writes the list itself; any block it
# wrote is replaced, so every XcodeGen version ends with exactly one (AetherPlayer#16).
set -euo pipefail
cd "$(dirname "$0")/.."

xcodegen generate --spec project.yml

python3 - <<'PY'
import re
pbx_path = "AetherPlayer.xcodeproj/project.pbxproj"
pbx = open(pbx_path).read()
traits, package, inside = {}, None, False
for line in open("project.yml").read().splitlines():
    if line == "packages:":
        inside = True
    elif inside and line and not line.startswith(" "):
        break
    elif inside and (m := re.match(r"^  ([\w-]+):$", line)):
        package = m.group(1)
    elif inside and package and (m := re.match(r"^    traits:\s*\[(.*)\]$", line)):
        traits[package] = [t.strip() for t in m.group(1).split(",") if t.strip()]
for name, names in traits.items():
    block = re.compile(r'(/\* XCRemoteSwiftPackageReference "' + re.escape(name)
                       + r'" \*/ = \{\n(?:\t\t\t.*\n)*?)(\t\t\};)')
    entry = "\t\t\ttraits = (\n" + "".join(f"\t\t\t\t{t},\n" for t in names) + "\t\t\t);\n"
    existing = re.compile(r"\t\t\ttraits = \(\n(?:\t\t\t\t.*\n)*?\t\t\t\);\n")
    pbx, count = block.subn(lambda m: existing.sub("", m.group(1)) + entry + m.group(2), pbx, count=1)
    if count != 1:
        raise SystemExit(f"generate-project.sh: no package reference {name} to give its traits")
    print(f"Package {name}: traits {', '.join(names)}")
open(pbx_path, "w").write(pbx)
PY
