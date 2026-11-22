#!/usr/bin/env python3
"""fix_imports.py — sets Godot import options for every generated texture:
mipmaps on (textures are applied from code, so Godot's "detect 3D" never fires and would leave them
off, which makes fabrics shimmer), normal maps flagged as normal maps, and roughness maps linked to
their normal map for specular anti-aliasing. Run after generate_textures.py, then reimport:
    python fix_imports.py ../assets/textures && godot --headless --path .. --import
Writes a .import file next to each PNG if Godot hasn't created one yet."""
import os
import sys

root = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "..", "assets", "textures")
TEMPLATE = """[remap]

importer="texture"
type="CompressedTexture2D"

[deps]

source_file="{res}"

[params]

compress/mode=0
compress/high_quality=false
compress/lossy_quality=0.7
compress/normal_map={nm}
compress/channel_pack=0
mipmaps/generate=true
mipmaps/limit=-1
roughness/mode=0
roughness/src_normal=""
process/fix_alpha_border=true
process/premult_alpha=false
process/normal_map_invert_y=false
process/size_limit=0
detect_3d/compress_to=0
"""
n = 0
for d, _, files in os.walk(root):
    for f in files:
        if not f.endswith(".png") or f.startswith("_"):
            continue
        path = os.path.join(d, f)
        imp = path + ".import"
        is_normal = f.endswith("_normal.png")
        if os.path.exists(imp):
            lines = open(imp, encoding="utf-8").read().splitlines()
            out = []
            for ln in lines:
                if ln.startswith("mipmaps/generate="):
                    ln = "mipmaps/generate=true"
                elif ln.startswith("compress/normal_map="):
                    ln = "compress/normal_map=%d" % (1 if is_normal else 0)
                elif ln.startswith("detect_3d/compress_to="):
                    ln = "detect_3d/compress_to=0"
                out.append(ln)
            open(imp, "w", encoding="utf-8").write("\n".join(out) + "\n")
        else:
            rel = os.path.relpath(path, os.path.join(root, "..", "..")).replace(os.sep, "/")
            open(imp, "w", encoding="utf-8").write(TEMPLATE.format(res="res://" + rel, nm=1 if is_normal else 0))
        n += 1
print("patched", n, "import files")
