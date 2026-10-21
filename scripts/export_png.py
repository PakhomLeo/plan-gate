"""Exports light and dark PNG previews of each SVG with rsvg-convert.

Usage: python3 scripts/export_png.py docs/assets /tmp/png   (previews are not committed)
"""
import os, re, subprocess, sys, tempfile
src, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)
for name in sorted(os.listdir(src)):
    if not name.endswith(".svg"): continue
    svg = open(os.path.join(src, name), encoding="utf-8").read()
    m = re.search(r"@media \(prefers-color-scheme: dark\)\{(.*?)\n  \}", svg, re.S)
    assert m, name
    light = re.sub(r"@media \(prefers-color-scheme: dark\)\{.*?\n  \}", "", svg, flags=re.S)
    # Dark: the media-query rules become plain rules that come last and win.
    dark = light.replace("</style>", m.group(1) + "\n</style>")
    for variant, text, bg in (("light", light, "#ffffff"), ("dark", dark, "#0d1117")):
        with tempfile.NamedTemporaryFile("w", suffix=".svg", delete=False, encoding="utf-8") as f:
            f.write(text)
        png = os.path.join(out, name[:-4] + f"-{variant}.png")
        subprocess.run(["rsvg-convert", "-z", "1.5", "-b", bg, "-o", png, f.name], check=True)
        os.unlink(f.name)
        print(png)
