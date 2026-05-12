#!/usr/bin/env python3
import re
import sys
from pathlib import Path

PBXPROJ = Path(__file__).parent.parent / "FreeDroid.xcodeproj" / "project.pbxproj"

text = PBXPROJ.read_text()

local_refs = {}
for match in re.finditer(
    r"([0-9A-F]{24}) /\* XCLocalSwiftPackageReference \"([^\"]+)\" \*/ = \{\s*isa = XCLocalSwiftPackageReference;\s*relativePath = ([^;]+);\s*\};",
    text,
):
    ref_uuid, label, _path = match.group(1), match.group(2), match.group(3)
    product_name = Path(label).name
    local_refs[product_name] = ref_uuid

def patch_dependency(match):
    block = match.group(0)
    product_name = match.group(2)
    if "package = " in block:
        return block
    ref_uuid = local_refs.get(product_name)
    if not ref_uuid:
        return block
    label = next(
        (key for key, value in local_refs.items() if value == ref_uuid),
        product_name,
    )
    new_block = block.replace(
        f"isa = XCSwiftPackageProductDependency;",
        f"isa = XCSwiftPackageProductDependency;\n\t\t\tpackage = {ref_uuid} /* XCLocalSwiftPackageReference \"Packages/{label}\" or features path */;",
    )
    return new_block

pattern = re.compile(
    r"(([0-9A-F]{24}) /\* (\w+) \*/ = \{\s*isa = XCSwiftPackageProductDependency;\s*productName = \w+;\s*\};)",
)

def replace(match):
    full = match.group(1)
    product = match.group(3)
    if product not in local_refs:
        return full
    if "package = " in full:
        return full
    ref_uuid = local_refs[product]
    ref_label = None
    for line in text.splitlines():
        marker = f"{ref_uuid} /* XCLocalSwiftPackageReference"
        if marker in line:
            ref_label = line.split("XCLocalSwiftPackageReference", 1)[1].strip().strip('"').split("*/")[0].strip().strip('"')
            break
    if ref_label is None:
        ref_label = product
    insertion = (
        f"\n\t\t\tpackage = {ref_uuid} /* XCLocalSwiftPackageReference \"{ref_label}\" */;"
    )
    return full.replace(
        "isa = XCSwiftPackageProductDependency;",
        f"isa = XCSwiftPackageProductDependency;{insertion}",
    )

new_text = pattern.sub(replace, text)

if new_text == text:
    print("No changes — already patched or no local product dependencies found.")
    sys.exit(0)

PBXPROJ.write_text(new_text)
print(f"Patched {len([m for m in pattern.finditer(text)])} dependencies in {PBXPROJ}")
