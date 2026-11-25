#!/bin/sh
# Ground truth for realm-quran, against the three sources it was built from, fetched fresh.
#
#   L1  every view answers BY NAME on its defaults, and is not empty
#   L2  the graph against the sources: every surah's metadata against Tanzil's quran-data.xml; every
#       ayah's Uthmani and Simple Clean Arabic against Tanzil's texts, its English against AlQuran
#       Cloud's Pickthall, and its juz, page and prostration against the same — exactly; the stored
#       reference/ loaded whole
#   L3  views against the sources: a surah, a search, the prostrations, a juz, Meccan and Medinan
#
# No producers and no source calls at query time — the text is stored — so there is no pushdown or
# cost check to make. Keyless: the sources are public downloads.
#
#   APPLIANCE=http://127.0.0.1:11043 AUTH=user:pass sh tests/verify.sh
#
# The last line on success is exactly `ALL CHECKS PASS`; any failure exits non-zero.
set -e
AUTHCFG=$(mktemp); trap 'rm -f "$AUTHCFG"' EXIT
if [ -n "${TOKEN:-}" ]; then printf 'header = "Authorization: Bearer %s"\n' "$TOKEN" > "$AUTHCFG"
else printf 'user = "%s"\n' "${AUTH:?set AUTH (user:pass) or TOKEN}" > "$AUTHCFG"; fi
APPLIANCE="${APPLIANCE:-http://127.0.0.1:11043}"
APPLIANCE="$APPLIANCE" AUTHCFG="$AUTHCFG" python3 - "$(dirname "$0")/.." <<'PY'
import glob, json, os, subprocess, sys, urllib.request, yaml
import xml.etree.ElementTree as ET
base, auth, realm = os.environ["APPLIANCE"], os.environ["AUTHCFG"], sys.argv[1]
TANZIL = ("https://tanzil.net/pub/download/index.php?marks={m}&sajdah={m}&rub=false&tatweel={m}"
          "&quranType={t}&outType=txt-2&agree=true")
fail = 0

def get(url):
    req = urllib.request.Request(url, headers={"User-Agent": "realm-quran tests/verify.sh"})
    return urllib.request.urlopen(req, timeout=180).read().decode("utf-8")
def post(path, body):
    out = subprocess.run(["curl", "-s", "--max-time", "600", "-K", auth, "-X", "POST", base + path,
                          "-H", "Content-Type: application/json", "-d", json.dumps(body)],
                         capture_output=True, text=True).stdout
    try:
        return json.loads(out, strict=False)
    except ValueError:
        return {"error": "not JSON: " + out[:200]}
# A figure is only this realm's figure when the engine says the answer is whole. A source that failed
# or was capped, a hop cut short, a value a step could not work out: each leaves rows that still look
# like an answer, and counting them reports drift that is not the realm's. short() reads the answer's
# own verdict — `error`, `run`, `reason` and the codes `warnings` open with on a query; `status`,
# `outcome` and the warning codes on a view — and is None when whole, else the line that stands in
# for the figure: "REFUSED: <why>" or "PARTIAL <figure>: <the engine's reason>".
SHORT_CODES = ("PARTIAL_RESULT", "PRODUCER_ERROR", "NEEDS_FILTER", "NEEDS_PRODUCER", "FILTER_REJECTED",
               "UNPUSHED_FILTER", "AMBIGUOUS_LABEL", "INCOMPLETE_TRAVERSAL", "INCOMPLETE_RANKING",
               "INCOMPLETE_AGGREGATE", "INCOMPLETE_INPUT", "MATERIALIZATION_FAILED", "REDUCTION_FAILED",
               "UNPARSEABLE_ANSWER", "TERMS_UNAVAILABLE", "COMPUTE_FAILED", "PROPERTY_NOT_STORED",
               "FOLLOW_CAPPED", "UNLINKED_CHILDREN", "RESOLUTION_DROPPED", "AGENTIC_DEGRADED", "SOURCE_UNANSWERED")
SHORT_REASONS = ("UNBOUNDED", "PARTIAL_NOT_MATCHED", "UNPUSHED_FILTER", "DISCONNECTED",
                 "INTERNAL_ERROR", "WRITE_IN_PROGRESS", "KILLED", "TOO_EXPENSIVE")
SHORT_PUBLIC = ("PARTIAL", "REDUCTION_FAILED", "COMPUTE_FAILED", "PROPERTY_NOT_STORED", "AGENTIC_DEGRADED",
                "RATE_LIMITED", "SOURCE_UNAVAILABLE", "SOURCE_REJECTED", "INVALID_FILTER", "UNPUSHED_FILTER",
                "TOO_BROAD", "FETCH_CAPPED", "INDEX_UNAVAILABLE", "ARGUMENT_REFUSED")
def short(d, figure=None):
    tag = "PARTIAL" if figure is None else "PARTIAL %s" % (figure,)
    if not isinstance(d, dict):
        return "REFUSED: not an engine answer: " + str(d)[:160]
    if "outcome" in d or "status" in d:
        if d.get("status") != "SUCCEEDED":
            e = d.get("error") or {}
            e = (e.get("code", "") + " " + e.get("message", "")).strip() if isinstance(e, dict) else str(e)
            return "REFUSED: %s %s" % (d.get("status"), e[:160])
        ws = [w for w in d.get("warnings") or [] if isinstance(w, dict) and w.get("code") in SHORT_PUBLIC]
        if d.get("outcome") not in ("OK", "EMPTY") or ws:
            return "%s: %s" % (tag, (ws[0]["code"] + ": " + ws[0].get("message", "") if ws else "outcome %s" % d.get("outcome"))[:200])
        return None
    if d.get("error"):
        return "REFUSED: " + str(d["error"])[:160]
    if d.get("run"):
        return "%s: the run had not finished (%s)" % (tag, d["run"])
    ws = [w for w in d.get("warnings") or [] if isinstance(w, str) and w.split(":", 1)[0].strip() in SHORT_CODES]
    if ws:
        return "%s: %s" % (tag, ws[0][:200])
    if d.get("reason") in SHORT_REASONS:
        return "%s: reason %s" % (tag, d["reason"])
    return None
def kg(cypher):
    r = post("/api/v1/admin/kg/execute", {"cypher": cypher})
    if r.get("error"):
        raise SystemExit("  FAIL query REFUSED: %s\n    %s" % (str(r["error"])[:200], cypher))
    # A short count stops the battery as a refusal does: every check after it would read the same gap.
    rows = r.get("rows") or []
    s = short(r, rows[0]["n"] if len(rows) == 1 and "n" in rows[0] else "%d rows" % len(rows))
    if s:
        raise SystemExit("  FAIL query %s\n    %s" % (s, cypher))
    return r.get("rows") or []
def view(name, args=None, whole=True):
    r = post("/api/v1/views/%s/invoke" % name, {"args": args or {}})
    # Rows a view marks short are not its answer, so no check counts them. L1 asks with whole=False
    # because it reports each view's verdict itself and goes on to the next.
    s = whole and short(r, len(r.get("data") or []))
    if s:
        raise SystemExit("  FAIL view %s %s: %s" % (name, json.dumps(args or {}), s))
    return r
def check(what, want, got):
    global fail
    if want == got: print("  ok   %s = %s" % (what, got if len(str(got)) < 80 else str(got)[:77] + "..."))
    else: print("  FAIL %s: expected %s, got %s" % (what, str(want)[:300], str(got)[:300])); fail = 1
def tanzil(text):
    out = {}
    for line in text.splitlines():
        if line.strip() and not line.startswith("#"):
            s, a, words = line.split("|", 2)
            out["%s:%s" % (s, a)] = words
    return out
def records(kind):
    out = []
    for f in sorted(glob.glob(os.path.join(realm, "reference", "*.yml"))):
        out += [r["data"] for r in yaml.safe_load(open(f)) or [] if r.get("type") == kind]
    return out

print("== L1: every view answers by name ==")
for f in sorted(glob.glob(os.path.join(realm, "views", "*.yml"))):
    for v in yaml.safe_load(open(f)):
        r = view(v["name"], whole=False)
        rows = r.get("data") or []
        if r.get("status") != "SUCCEEDED":
            print("  FAIL %s: %s %s" % (v["name"], r.get("status"), str(r.get("error") or r)[:200])); fail = 1
        elif short(r, len(rows)):
            print("  FAIL %s: %s" % (v["name"], short(r, len(rows)))); fail = 1
        elif not rows:
            print("  FAIL %s answered no rows on its defaults" % v["name"]); fail = 1
        else:
            print("  ok   %-18s %d rows" % (v["name"], len(rows)))

print("== L2: the graph against Tanzil and AlQuran Cloud ==")
suras = [s.attrib for s in ET.fromstring(get("https://tanzil.net/res/text/metadata/quran-data.xml")).find("suras")]
want = [{"number": int(s["index"]), "name": s["tname"], "arabicName": s["name"], "meaning": s["ename"],
         "revelation": s["type"], "revelationOrder": int(s["order"]), "ayat": int(s["ayas"]), "rukus": int(s["rukus"])}
        for s in suras]
got = kg("""MATCH (s:Surah) RETURN s.chapter AS number, s.name AS name, s.arabicName AS arabicName, s.meaning AS meaning,
                s.revelation AS revelation, s.revelationOrder AS revelationOrder, s.verseCount AS ayat, s.rukus AS rukus
         ORDER BY number""")
check("114 surahs, every field, against quran-data.xml", want, got)
counted = {r["n"]: r["c"] for r in kg("MATCH (s:Surah)<-[:IN]-(a:Ayah) RETURN s.chapter AS n, count(a) AS c")}
check("ayat IN each surah = quran-data.xml", {w["number"]: w["ayat"] for w in want}, counted)
uthmani = tanzil(get(TANZIL.format(m="true", t="uthmani")))
plain = tanzil(get(TANZIL.format(m="false", t="simple-clean")))
english = {"%d:%d" % (s["number"], a["numberInSurah"]): a
           for s in json.loads(get("https://api.alquran.cloud/v1/quran/en.pickthall"))["data"]["surahs"] for a in s["ayahs"]}
check("the three sources number alike", sorted(uthmani), sorted(english))
check("  ...and alike", sorted(plain), sorted(english))
def sajda(v): return None if not v else ("obligatory" if v.get("obligatory") else "recommended")
for lo, hi in ((1, 9), (10, 30), (31, 114)):
    rows = {r["ref"]: r for r in kg("""MATCH (a:Ayah) WHERE a.chapter >= %d AND a.chapter <= %d
                                       RETURN a.ref AS ref, a.text AS text, a.original AS original, a.arabicPlain AS plain,
                                              a.juz AS juz, a.page AS page, a.sajda AS sajda""" % (lo, hi))}
    refs = [k for k in english if lo <= int(k.split(":")[0]) <= hi]
    check("surahs %d–%d: ayat" % (lo, hi), len(refs), len(rows))
    bad = {"english": [], "uthmani": [], "plain": [], "juz/page/sajda": []}
    for k in refs:
        r = rows.get(k) or {}
        if r.get("text") != english[k]["text"]: bad["english"].append(k)
        if r.get("original") != uthmani[k]: bad["uthmani"].append(k)
        if r.get("plain") != plain[k]: bad["plain"].append(k)
        if (r.get("juz"), r.get("page"), r.get("sajda")) != (english[k]["juz"], english[k]["page"], sajda(english[k]["sajda"])):
            bad["juz/page/sajda"].append(k)
    for what, ks in bad.items():
        check("surahs %d–%d: every ayah's %s, exactly" % (lo, hi, what), [], ks[:5])
check("the stored reference/ loaded whole (ayat)", len(records("Ayah")), kg("MATCH (a:Ayah) RETURN count(a) AS n")[0]["n"])

print("== L3: views against the sources ==")
check("ReadSurah 2", 286, len(view("ReadSurah", {"surah": 2}).get("data") or []))
check("SearchQuran 'mercy' = the source's count", sum(1 for a in english.values() if "mercy" in a["text"].lower()),
      len(view("SearchQuran", {"term": "mercy", "limit": 10000}).get("data") or []))
check("SearchArabic 'رحمة' = the source's count", sum(1 for t in plain.values() if "رحمة" in t),
      len(view("SearchArabic", {"term": "رحمة", "limit": 10000}).get("data") or []))
check("Sajdas = the source's prostrations", sorted("Quran " + k for k, a in english.items() if a["sajda"]),
      sorted(r["reference"] for r in view("Sajdas").get("data") or []))
juz30 = {}
for k, a in english.items():
    if a["juz"] == 30: juz30[int(k.split(":")[0])] = juz30.get(int(k.split(":")[0]), 0) + 1
check("ReadJuz 30: surahs and ayat per surah", juz30, {r["number"]: r["ayat"] for r in view("ReadJuz", {"juz": 30}).get("data") or []})
mm = {}
for w in want: mm[w["revelation"]] = [mm.get(w["revelation"], [0, 0])[0] + 1, mm.get(w["revelation"], [0, 0])[1] + w["ayat"]]
check("MeccanAndMedinan = quran-data.xml", mm, {r["revelation"]: [r["surahs"], r["ayat"]] for r in view("MeccanAndMedinan").get("data") or []})

if fail: print("FAILED"); sys.exit(1)
print("ALL CHECKS PASS")
PY
