# realm-quran

> **Experimental.** Its types are children of
> [realm-scripture-vocabulary](https://github.com/embabel-worlds/realm-scripture-vocabulary), which must be installed first — a
> child whose parent's realm is missing is refused at load. It also needs a host that writes a child
> type's inherited properties (Embabel hosts from October 2026): an `Ayah` declares almost nothing of its own.

The Quran as a queryable graph: read an ayah or a surah in Arabic and English, search in either
language, list the surahs in the order of the mushaf or of revelation, and see what each of the
thirty ajza holds. Because an `Ayah` is a `Verse`, a question asked of every scripture — which verses
speak of mercy — is answered here and in the Bible alike.

## Shape

```
Mushaf ◀─IN─ Surah ◀─IN─ Ayah ─IN_PORTION─▶ Juz
(HolyBook)   (ScriptureChapter)  (Verse)      (ReadingPortion)
```

The Quran has no books, so a surah is `IN` the holy book directly. Every type is stored, seeded from
`reference/`, and never changes.

| | Count | Source |
|---|---|---|
| Mushaf | 1 | — |
| Surah | 114 | names, Meccan/Medinan, revelation order: Tanzil `quran-data.xml` |
| Juz | 30 | AlQuran Cloud's division (the Medina mushaf) |
| Ayah | 6,236 | Arabic: Tanzil; English: Pickthall, via AlQuran Cloud |

## Three texts on every ayah

| Property | What it is | Why it is stored |
|---|---|---|
| `original` | the Uthmani text, as printed and recited — the Quran | to read and show |
| `arabicPlain` | the same text without diacritics (Tanzil Simple Clean) | what a person types to search Arabic |
| `text` | Pickthall's English (1930) | the vocabulary's promise: `text` is English, so every scripture can be searched together |

Pickthall called his work *The Meaning of the Glorious Koran*, and that is what `text` is: a
translation of the meaning. Every reading view returns the Arabic beside it.

Tanzil prints the basmala at the head of the first ayah of every surah but Al-Fatiha (where it IS the
first ayah) and At-Tawba (which has none); Pickthall does not. Both are kept as published, so those
ayat's `original` and `text` differ by it.

## Views

| View | Answers |
|---|---|
| `ReadAyah` | one ayah by `2:255`, Arabic and English, with surah, juz, page and any prostration |
| `ReadSurah` | a whole surah by number |
| `Surahs` | the 114, in mushaf or revelation order, optionally only Meccan or Medinan |
| `SearchQuran` | ayat whose English contains a word |
| `SearchArabic` | ayat whose Arabic contains a word typed without diacritics |
| `SurahsMentioning` | surahs ranked by how many ayat mention a word |
| `ReadJuz` | the surahs one juz spans |
| `Sajdas` | the fifteen ayat of prostration |
| `MeccanAndMedinan` | how the two groups differ in size |

Searching across scriptures is in realm-scripture-vocabulary, not here: those views read only parent
labels, and answer from whatever is installed.

`sources.yml` also declares the Quran as searchable documents, one per surah in Pickthall's English
(`quran://pickthall/<surah>`), embedded on install.

## Rebuilding the reference data

```
python scripts/build_reference.py
```

Downloads into `data/source/` (ignored by git) and rewrites `reference/`. It refuses to build if the
three sources do not all number 6,236 ayat alike.

## Licences

- **Arabic text**: Tanzil Quran Text (Uthmani and Simple Clean, version 1.1), © Tanzil Project,
  [tanzil.net](https://tanzil.net), Creative Commons Attribution 3.0, on Tanzil's terms: copied
  verbatim, never changed, with its copyright notice — which every `reference/quran-04-ayat-*.yml`
  carries in its header. Check [tanzil.net/updates](http://tanzil.net/updates/) for corrections.
- **Surah metadata**: Tanzil `quran-data.xml`, Creative Commons Attribution.
- **English**: Mohammed Marmaduke Pickthall, *The Meaning of the Glorious Koran* (1930). Public
  domain: Pickthall died in 1936, and the work was published in 1930. Text from
  [alquran.cloud](https://alquran.cloud).
- **Code**: GPL-3.0, as realm-bible.
