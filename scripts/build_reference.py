"""
Build the realm's reference data from its published sources.

The stored graph is Mushaf → Surah → Ayah, with each ayah also IN_PORTION its Juz. Every ayah
carries three texts, all stored because all must be SEARCHABLE:
  original     the Uthmani text, as the Quran is printed and recited;
  arabicPlain  the same text without diacritics, which is what a person types to search Arabic;
  text         Pickthall's English (1930), the meaning in English — the field the scripture
               vocabulary promises is English, so the Quran can be searched beside the Bible.

Sources, downloaded into data/source/ on first run:
  Tanzil Project (tanzil.net) — the Uthmani and Simple Clean texts, and quran-data.xml (surah names,
      Meccan or Medinan, revelation order). Text CC BY 3.0 on Tanzil's terms: verbatim only, the
      source named, a link to tanzil.net, and its copyright block carried in every file that holds a
      substantial part of the text. So the texts are copied into the YAML exactly, and each ayat file
      repeats the block.
  AlQuran Cloud (alquran.cloud) — Pickthall's translation, and per ayah its juz, manzil, ruku, page
      of the Medina mushaf and sajda. Pickthall is public domain: he died in 1936, and the translation
      was published in 1930.

Tanzil prints the basmala at the head of the first ayah of every surah but Al-Fatiha (where it IS
the first ayah) and At-Tawba (which has none); Pickthall does not. Both are kept as published.

Run from the realm root:  python scripts/build_reference.py
"""

import json
import sys
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "data" / "source"
REFERENCE = ROOT / "reference"

TANZIL_TEXT = (
    "https://tanzil.net/pub/download/index.php?marks=true&sajdah=true&rub=false&tatweel=true"
    "&quranType={}&outType=txt-2&agree=true"
)
DOWNLOADS = {
    "tanzil-uthmani.txt": TANZIL_TEXT.format("uthmani"),
    "tanzil-simple-clean.txt": TANZIL_TEXT.format("simple-clean").replace("marks=true", "marks=false")
    .replace("sajdah=true", "sajdah=false").replace("tatweel=true", "tatweel=false"),
    "quran-data.xml": "https://tanzil.net/res/text/metadata/quran-data.xml",
    "pickthall.json": "https://api.alquran.cloud/v1/quran/en.pickthall",
}

SURAHS = 114
AYAT = 6236
JUZ_CYCLE = "thirty parts, one read each night of Ramadan"


def fetch() -> None:
    SOURCE.mkdir(parents=True, exist_ok=True)
    for name, url in DOWNLOADS.items():
        path = SOURCE / name
        if not path.exists():
            print(f"downloading {name}")
            request = urllib.request.Request(url, headers={"User-Agent": "realm-quran build_reference"})
            with urllib.request.urlopen(request) as response:
                path.write_bytes(response.read())


def tanzil(name: str) -> tuple[dict[tuple[int, int], str], str]:
    """The text keyed by (surah, ayah), and Tanzil's copyright block exactly as it ends the file."""
    text, notice = {}, []
    for line in (SOURCE / name).read_text(encoding="utf-8").splitlines():
        if line.startswith("#"):
            notice.append(line)
        elif line.strip():
            surah, ayah, words = line.split("|", 2)
            text[(int(surah), int(ayah))] = words
    if len(text) != AYAT or not notice:
        sys.exit(f"{name}: {len(text)} ayat and {len(notice)} notice lines; refusing to build from it")
    return text, "\n".join(notice)


def surah_metadata() -> list[dict]:
    root = ET.parse(SOURCE / "quran-data.xml").getroot()
    suras = [s.attrib for s in root.find("suras")]
    if len(suras) != SURAHS:
        sys.exit(f"quran-data.xml lists {len(suras)} surahs")
    return suras


def pickthall() -> dict[tuple[int, int], dict]:
    surahs = json.loads((SOURCE / "pickthall.json").read_text(encoding="utf-8"))["data"]["surahs"]
    out = {(s["number"], a["numberInSurah"]): a for s in surahs for a in s["ayahs"]}
    if len(out) != AYAT:
        sys.exit(f"pickthall.json has {len(out)} ayat")
    return out


def header(lines: str, notice: str | None = None) -> str:
    text = "\n".join(f"# {line}" if line else "#" for line in lines.strip().splitlines())
    if notice:
        text += "\n#\n" + notice
    return text + "\n\n"


def write(name: str, comment: str, records: list[dict], notice: str | None = None) -> None:
    body = yaml.dump(records, allow_unicode=True, sort_keys=False, width=100_000)
    (REFERENCE / name).write_text(header(comment, notice) + body, encoding="utf-8")


def sajda(value) -> str | None:
    """AlQuran Cloud gives `false`, or an object saying whether the prostration is obligatory."""
    if not value:
        return None
    return "obligatory" if value.get("obligatory") else "recommended"


def main() -> None:
    fetch()
    uthmani, notice = tanzil("tanzil-uthmani.txt")
    plain, plain_notice = tanzil("tanzil-simple-clean.txt")
    suras = surah_metadata()
    english = pickthall()
    for ref in uthmani:
        if ref not in plain or ref not in english:
            sys.exit(f"ayah {ref} is missing from a source: the three do not number alike")

    REFERENCE.mkdir(exist_ok=True)
    for old in REFERENCE.glob("quran-*.yml"):
        old.unlink()

    write("quran-01-mushaf.yml", """
The Quran as one holy book. Generated by scripts/build_reference.py — do not edit by hand.
""", [{
        "type": "Mushaf",
        "data": {
            "scripture": "quran",
            "name": "The Quran",
            "tradition": "Islam",
            "originalLanguage": "Arabic",
            "translation": "Pickthall (1930)",
            "chapterCount": SURAHS,
            "verseCount": AYAT,
            "textSource": "Tanzil Project, https://tanzil.net — Uthmani and Simple Clean, version 1.1",
        },
    }])

    write("quran-02-surahs.yml", """
The 114 surahs, in the order of the mushaf. Names, Meccan or Medinan, and revelation order from
Tanzil's quran-data.xml (CC BY 3.0, https://tanzil.net). Generated by scripts/build_reference.py —
do not edit by hand.
""", [{
        "type": "Surah",
        "data": {
            "ref": s["index"],
            "scripture": "quran",
            "name": s["tname"],
            "chapter": int(s["index"]),
            "arabicName": s["name"],
            "meaning": s["ename"],
            "revelation": s["type"],
            "revelationOrder": int(s["order"]),
            "verseCount": int(s["ayas"]),
            "rukus": int(s["rukus"]),
            "documentUri": f"quran://pickthall/{s['index']}",
        },
        "relations": [{"predicate": "IN", "to": {"type": "Mushaf", "scripture": "quran"}}],
    } for s in suras])

    starts: dict[int, tuple[int, int]] = {}
    for ref in sorted(english, key=lambda r: english[r]["number"]):
        starts.setdefault(english[ref]["juz"], ref)
    write("quran-03-juz.yml", """
The thirty ajza, each with the ayah it begins at (AlQuran Cloud's division, which follows the Medina
mushaf). Generated by scripts/build_reference.py — do not edit by hand.
""", [{
        "type": "Juz",
        "data": {
            "key": f"juz-{n}",
            "scripture": "quran",
            "name": f"Juz {n}",
            "number": n,
            "cycle": JUZ_CYCLE,
            "startsAt": f"Quran {starts[n][0]}:{starts[n][1]}",
        },
    } for n in sorted(starts)])

    for s in suras:
        number, name = int(s["index"]), s["tname"]
        ayat = []
        for ayah in range(1, int(s["ayas"]) + 1):
            e = english[(number, ayah)]
            data = {
                "ref": f"{number}:{ayah}",
                "scripture": "quran",
                "name": f"Quran {number}:{ayah}",
                "chapter": number,
                "verse": ayah,
                "ordinal": e["number"],
                "text": e["text"],
                "translation": "Pickthall",
                "original": uthmani[(number, ayah)],
                "arabicPlain": plain[(number, ayah)],
                "surahName": name,
                "juz": e["juz"],
                "manzil": e["manzil"],
                "ruku": e["ruku"],
                "page": e["page"],
            }
            if sajda(e["sajda"]):
                data["sajda"] = sajda(e["sajda"])
            ayat.append({
                "type": "Ayah",
                "data": data,
                "relations": [
                    {"predicate": "IN", "to": {"type": "Surah", "ref": str(number)}},
                    {"predicate": "IN_PORTION", "to": {"type": "Juz", "key": f"juz-{e['juz']}"}},
                ],
            })
        write(f"quran-04-ayat-{number:03d}.yml", f"""
Every ayah of Surah {name} ({s['ename']}): the Uthmani text as `original`, the same without
diacritics as `arabicPlain`, and Pickthall's English as `text`. The two Arabic texts are Tanzil's,
copied verbatim under the notice below; the English is public domain, from alquran.cloud. Generated
by scripts/build_reference.py — do not edit by hand.
""", ayat, notice + ("" if plain_notice == notice else "\n#\n" + plain_notice))

    print(f"{SURAHS} surahs, {len(starts)} ajza, {AYAT} ayat written to {REFERENCE}")


if __name__ == "__main__":
    main()
