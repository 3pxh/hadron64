"""Writes Hadron64/Localizable.xcstrings and Hadron64/InfoPlist.xcstrings from translations.py.

Usage: python3 scripts/l10n/build_catalogs.py [path/to/exported/en.xliff]
With an xliff from `xcodebuild -exportLocalizations`, also checks that every string the compiler
extracted has translations and that no translation is orphaned.
"""
import json, re, sys
from pathlib import Path
from translations import LANGS, STRINGS, PLURALS, DO_NOT_TRANSLATE, INFO_PLIST

ROOT = Path(__file__).resolve().parents[2]

def unit(value):
    return {"stringUnit": {"state": "translated", "value": value}}

def catalog(entries):
    return {"sourceLanguage": "en", "strings": entries, "version": "1.0"}

def build():
    entries = {}
    for key, values in STRINGS.items():
        assert len(values) == len(LANGS), f"{key!r} has {len(values)} translations"
        entries[key] = {"localizations": {lang: unit(v) for lang, v in zip(LANGS, values)}}
    for key, langs in PLURALS.items():
        assert set(langs) == set(LANGS) | {"en"}, f"{key!r} is missing plural languages"
        entries[key] = {"localizations": {
            lang: {"variations": {"plural": {cat: unit(v) for cat, v in forms.items()}}}
            for lang, forms in langs.items()}}
    for key in DO_NOT_TRANSLATE:
        entries[key] = {"shouldTranslate": False}
    info = {"CFBundleDisplayName": {"shouldTranslate": False}, "CFBundleName": {"shouldTranslate": False}}
    for key, values in INFO_PLIST.items():
        assert len(values) == len(LANGS)
        info[key] = {"localizations": {lang: unit(v) for lang, v in zip(LANGS, values)}}
    return entries, info

def check(entries, xliff):
    text = Path(xliff).read_text()
    body = text.split('original="Hadron64/Localizable.xcstrings"')[1].split("</file>")[0]
    extracted = {re.sub(r"&#10;", "\n", k).replace("&apos;", "'").replace("&amp;", "&")
                 for k in re.findall(r'<trans-unit id="(.*?)"', body, re.S)}
    missing = extracted - set(entries)
    orphaned = set(entries) - extracted
    for k in sorted(missing): print("MISSING translation:", repr(k))
    for k in sorted(orphaned): print("ORPHANED translation:", repr(k))
    return not missing

entries, info = build()
ok = check(entries, sys.argv[1]) if len(sys.argv) > 1 else True
for name, data in [("Localizable.xcstrings", entries), ("InfoPlist.xcstrings", info)]:
    (ROOT / "Hadron64" / name).write_text(json.dumps(catalog(data), ensure_ascii=False, indent=2, sort_keys=True) + "\n")
print(f"wrote {len(entries)} strings in {len(LANGS) + 1} languages")
sys.exit(0 if ok else 1)
