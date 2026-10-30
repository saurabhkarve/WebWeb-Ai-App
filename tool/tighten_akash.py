"""Bake tracking into the app's Akash fonts: every glyph's advance shrinks by 0.03em (Akash has no kerning and sets
loose). Doing it in the font, not with letterSpacing, keeps Hindi, Marathi, Gujarati and Konkani (drawn from the
fallback fonts) at their natural spacing. Run from the app folder: python3 tool/tighten_akash.py. A font already
tightened carries a marker in its version string and is left alone."""
import glob
from fontTools.ttLib import TTFont

TRACK = -0.03  # em
MARK = "tracking -0.03em"

for path in sorted(glob.glob("assets/fonts/Akash-*.ttf")):
    f = TTFont(path)
    names = f["name"]
    version = str(names.getName(5, 3, 1, 0x409) or names.getName(5, 1, 0, 0) or "")
    if MARK in version:
        print(path, "already tightened")
        continue
    delta = round(-TRACK * f["head"].unitsPerEm)
    hmtx = f["hmtx"].metrics
    for g, (adv, lsb) in hmtx.items():
        if adv > 0:
            hmtx[g] = (max(0, adv - delta), lsb)
    for rec in names.names:
        if rec.nameID == 5:
            rec.string = f"{rec.toUnicode()}; {MARK}"
    f.save(path)
    print(path, f"advances -{delta} units")
