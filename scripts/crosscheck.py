#!/usr/bin/env python3
"""Köken programatik çapraz denetim: üretilmiş partiyi scripts/sources/ ile karşılaştırır.

Her madde için Nişanyan ve TDK kayıtlarıyla uyumu denetler ve
scripts/review/NN.auto.json dosyasına karar yazar:

    [{"id": "kalem", "verdict": "ok", "reasons": []}]

"ok" = otomatik denetimden sorunsuz geçti, "check" = insan/LLM incelemesi
gerekiyor. Kaynak kaydı olmayan madde her zaman "check" olur; denetlenemeyen
şey onaylanmış sayılmaz.

Kullanım:
    python3 scripts/crosscheck.py --batch 1
    python3 scripts/crosscheck.py --all
"""

import argparse
import glob
import json
import os
import re
import sys
import urllib.parse

from validate_words import LANGUAGES, nfc, slugify_id

SCRIPTS_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR = os.path.dirname(SCRIPTS_DIR)
BATCHES_DIR = os.path.join(SCRIPTS_DIR, "batches")
SOURCES_DIR = os.path.join(SCRIPTS_DIR, "sources")
REVIEW_DIR = os.path.join(SCRIPTS_DIR, "review")

# Nişanyan ve TDK Türkçe dil adları → schema.md ISO kodları.
# Eşlenmemiş bir ad hata değil, "check" sebebidir; buraya eklenerek kapatılır.
SOURCE_LANG = {
    "türkiye türkçesi": "tr",
    "türkçe": "tr",
    "yeni türkçe": "tr-new",
    "eski türkçe": "otk",
    "orta türkçe": "otk",
    "osmanlıca": "ota",
    "osmanlı türkçesi": "ota",
    "proto-türkçe": "trk",
    "ana türkçe": "trk",
    "tatarca": "tt",
    "kırgızca": "ky",
    "azerice": "az",
    "uygurca": "ug",
    "arapça": "ar",
    "eski güney arapça": "xsa",
    "farsça": "fa",
    "orta farsça": "pal",
    "pehlevice": "pal",
    "eski farsça": "peo",
    "avesta dili": "ae",
    "avestaca": "ae",
    "proto-i̇ranca (ana-i̇ranca)": "ira",
    "proto-iranca (ana-iranca)": "ira",
    "ana i̇ranca": "ira",
    "soğdca": "sog",
    "kürtçe": "ku",
    "fransızca": "fr",
    "eski yunanca": "grc",
    "yunanca": "el",
    "orta yunanca": "el",
    "i̇talyanca": "it",
    "italyanca": "it",
    "i̇ngilizce": "en",
    "ingilizce": "en",
    "latince": "la",
    "almanca": "de",
    "rusça": "ru",
    "moğolca": "mn",
    "ermenice": "hy",
    "i̇spanyolca": "es",
    "ispanyolca": "es",
    "portekizce": "pt",
    "felemenkçe": "nl",
    "hollandaca": "nl",
    "sanskritçe": "sa",
    "i̇branice": "he",
    "ibranice": "he",
    "aramice": "arc",
    "aramice-süryanice": "arc",
    "süryanice": "syc",
    "akatça": "akk",
    "akkadca": "akk",
    "sümerce": "sux",
    "eski mısırca": "egy",
    "macarca": "hu",
    "bulgarca": "bg",
    "sırpça": "sr",
    "rumence": "ro",
    "arnavutça": "sq",
    "hintçe": "hi",
    "urduca": "ur",
    "malayca": "ms",
    "japonca": "ja",
    "çince": "zh",
    "hintavrupa anadili": "ine",
    "hint-avrupa anadili": "ine",
    "slav anadili": "sla",
    "sami anadili": "sem",
}

# Nişanyan'ın belirsizlik bildiren ifadeleri.
COGNATE_RE = re.compile(r"eşköken", re.IGNORECASE)
# Madde metninde akrabalık anlatan ifadeler: bunlar zincir adımı açıklaması olamaz.
# "akraba" tek başına geçerli bir anlam olabilir (aile = akrabalık topluluğu);
# yalnızca biçim/sözcük hakkında konuşan kullanımlar yakalanır.
COGNATE_TEXT_RE = re.compile(
    r"eş ?kökenli|akraba(?:sı)?\s+(?:biçim|sözcük|kelime|kök|form)",
    re.IGNORECASE)
UNCERTAIN_RE = re.compile(
    r"tahmin|tartışmal|belirsiz|muhtemel|şüphe|kesin değil|açıklanamam", re.IGNORECASE)

CENTURY_RE = re.compile(r"^\s*(MÖ\s*)?(\d{1,2})\s*\.?\s*(yy|yüzyıl)", re.IGNORECASE)
YEAR_RE = re.compile(r"^\s*(MÖ\s*)?(\d{3,4})\s*$", re.IGNORECASE)
_LOWER_MAP = str.maketrans({"İ": "i", "I": "ı"})


def tr_lower(text):
    return nfc(text or "").translate(_LOWER_MAP).lower()


def lang_code(name):
    """Kaynak dil adını ISO koduna çevirir. Bilinmiyorsa None."""
    key = tr_lower(name).strip()
    if key in SOURCE_LANG:
        return SOURCE_LANG[key]
    # "Arapça ḳalem" gibi biçimlerde ilk sözcük dil adıdır.
    first = key.split(" ")[0] if key else ""
    return SOURCE_LANG.get(first)


def parse_period(text):
    """Dönem metnini (en_erken, en_geç) yıl aralığına çevirir. Çözülemezse None."""
    if not isinstance(text, str) or not text.strip():
        return None
    match = YEAR_RE.match(text)
    if match:
        year = int(match.group(2))
        if match.group(1):
            year = -year
        return (year, year)
    match = CENTURY_RE.match(text)
    if match:
        century = int(match.group(2))
        if match.group(1):
            return (-century * 100, -(century - 1) * 100 - 1)
        return ((century - 1) * 100, century * 100 - 1)
    # "1377'den önce", "y. 1300", "1069 ?" gibi serbest biçimler.
    loose = re.search(r"(\d{3,4})", text)
    if loose:
        year = int(loose.group(1))
        low = tr_lower(text)
        if "önce" in low:
            return (year - 100, year)
        if "sonra" in low:
            return (year, year + 100)
        return (year - 1, year + 1)
    return None


def loose_match(needle, haystack):
    """Kaynak adlarını gevşek karşılaştırır: ortak anlamlı sözcük var mı."""
    a = set(w for w in re.split(r"[^0-9a-zçğıiöşüâîû]+", tr_lower(needle)) if len(w) > 2)
    b = set(w for w in re.split(r"[^0-9a-zçğıiöşüâîû]+", tr_lower(haystack)) if len(w) > 2)
    return bool(a & b)


def load_source(word_id):
    path = os.path.join(SOURCES_DIR, "%s.json" % word_id)
    if not os.path.exists(path):
        return None
    try:
        with open(path, encoding="utf-8") as handle:
            return json.load(handle)
    except (OSError, ValueError):
        return None


def pick_entry(record, word_id):
    """Nişanyan maddelerinden id ile birebir eşleşeni, yoksa ilkini seçer."""
    entries = ((record or {}).get("nisanyan") or {}).get("entries") or []
    for entry in entries:
        if slugify_id(entry.get("name") or "") == word_id:
            return entry
    return entries[0] if entries else None


def check_donor(item, entry, tdk, reasons):
    donor = item.get("donorLanguage")
    nearest_codes, unmapped = set(), set()
    steps = [st for st in (entry or {}).get("chain") or []
             if not COGNATE_RE.search(st.get("relation") or "")]
    if steps:
        for name in steps[-1].get("languages") or []:
            code = lang_code(name)
            (nearest_codes.add(code) if code else unmapped.add(name))
    tdk_code = None
    for tdk_entry in (tdk.get("entries") or [])[:1]:
        tdk_code = lang_code(tdk_entry.get("lisan"))
    all_codes = set()
    for step in steps:
        for name in step.get("languages") or []:
            code = lang_code(name)
            if code:
                all_codes.add(code)

    for name in sorted(unmapped):
        reasons.append("Kaynaktaki dil adı eşlenemedi: %s" % name)

    expected = nearest_codes | ({tdk_code} if tdk_code else set())
    if donor is None:
        nearest_rel = tr_lower(steps[-1].get("relation") if steps else "")
        if "alıntı" in nearest_rel and expected - {"tr", "otk", "ota", "tr-new"}:
            reasons.append("donorLanguage null ama kaynak alıntı diyor: %s"
                           % ", ".join(sorted(expected)))
        return
    if not expected:
        return
    if donor in expected:
        return
    if donor in all_codes:
        reasons.append("donorLanguage %s zincirde var ama en yakın dil değil "
                       "(kaynak: %s)" % (donor, ", ".join(sorted(expected))))
    else:
        reasons.append("donorLanguage %s kaynakla uyuşmuyor (kaynak: %s)"
                       % (donor, ", ".join(sorted(expected))))


def collapse(codes):
    """Ardışık aynı dil kodlarını teke indirir: ar › ar › fa → ar › fa."""
    out = []
    for code in codes:
        if not out or out[-1] != code:
            out.append(code)
    return out


def transmission_chain(entry):
    """Nişanyan zincirinden aktarım halkalarını çıkarır.

    "eşkökenlilik" ilişkili adımlar sözcüğün geçtiği yolu değil, başka
    dillerdeki akrabalarını gösterir; zincire girmezler.
    """
    codes = []
    for step in entry.get("chain") or []:
        if COGNATE_RE.search(step.get("relation") or ""):
            continue
        names = [lang_code(n) for n in step.get("languages") or []]
        names = [c for c in names if c]
        if names:
            codes.append(names[0])
    return collapse(codes)


def check_chain(item, entry, reasons):
    if not entry or not entry.get("chain"):
        return
    source_codes = transmission_chain(entry)
    item_codes = collapse([s.get("language") for s in item.get("chain") or []
                           if isinstance(s, dict)])
    if item_codes and item_codes[-1] == "tr":
        item_codes = item_codes[:-1]
    if not source_codes:
        return

    missing = [c for c in source_codes if c not in item_codes]
    if missing:
        reasons.append("Kaynak zincirinde olup maddede olmayan halka: %s"
                       % ", ".join(missing))
    extra = [c for c in item_codes if c not in source_codes]
    if extra:
        reasons.append("Maddede olup kaynak zincirinde olmayan halka: %s"
                       % ", ".join(extra))
    # Ortak halkaların göreli sırası korunmuş mu.
    common = [c for c in item_codes if c in source_codes]
    expected_order = [c for c in source_codes if c in item_codes]
    if common and common != expected_order:
        reasons.append("Zincir sırası kaynaktan farklı: madde %s, kaynak %s"
                       % (" › ".join(common), " › ".join(expected_order)))


def check_attestation(item, entry, reasons):
    att = item.get("firstAttestation")
    histories = [h for h in ((entry or {}).get("histories") or [])
                 if h.get("dateSortable") is not None]
    if att is None:
        return
    if not isinstance(att, dict):
        return
    if not histories:
        reasons.append("Kaynakta tanıklık yok ama firstAttestation dolu")
        return

    oldest = min(histories, key=lambda h: h["dateSortable"])
    parsed = parse_period(att.get("period"))
    if parsed is None:
        reasons.append("firstAttestation.period çözümlenemedi: %r"
                       % (att.get("period"),))
    else:
        low, high = parsed
        if not low <= oldest["dateSortable"] <= high:
            reasons.append("firstAttestation.period %s, kaynaktaki en eski "
                           "tanıklık %s" % (att.get("period"), oldest["dateSortable"]))

    named = att.get("source")
    if isinstance(named, str) and named.strip():
        candidates = [x for h in histories for x in (h.get("source"), h.get("book")) if x]
        if candidates and not any(loose_match(named, c) for c in candidates):
            reasons.append("firstAttestation.source %r kaynaktaki eserlerle "
                           "eşleşmiyor (%s)" % (named, ", ".join(candidates[:4])))


def check_cognates(item, entry, reasons):
    """Eş kökenli halkaların aktarım zincirine sızmadığını denetler."""
    for i, step in enumerate(item.get("chain") or []):
        if not isinstance(step, dict):
            continue
        meaning = step.get("meaning")
        if isinstance(meaning, str) and COGNATE_TEXT_RE.search(meaning):
            reasons.append("chain[%d].meaning akrabalık anlatıyor (%r); eş "
                           "kökenli biçim zincire girmez" % (i, meaning))
    if not entry:
        return
    transmission = set(transmission_chain(entry))
    cognate_codes = set()
    for step in entry.get("chain") or []:
        if not COGNATE_RE.search(step.get("relation") or ""):
            continue
        for name in step.get("languages") or []:
            code = lang_code(name)
            if code:
                cognate_codes.add(code)
    cognate_only = cognate_codes - transmission
    item_codes = {st.get("language") for st in item.get("chain") or []
                  if isinstance(st, dict)}
    intruders = sorted(cognate_only & item_codes)
    if intruders:
        reasons.append("Kaynakta yalnızca eş kökenli olarak geçen dil zincire "
                       "aktarım halkası olarak konmuş: %s" % ", ".join(intruders))


def check_uncertainty(item, entry, reasons):
    if not entry:
        return
    texts = [s.get("relation") or "" for s in entry.get("chain") or []
             if not COGNATE_RE.search(s.get("relation") or "")]
    hits = sorted({t for t in texts if UNCERTAIN_RE.search(t)})
    formation = item.get("formationType")

    # tartışmalı yalnızca kaynaklar oluşum türünde ayrışınca kullanılır.
    if formation == "tartışmalı" and not hits:
        reasons.append("formationType tartışmalı ama Nişanyan ilişkisinde "
                       "tartışma kaydı yok; veren dil belirsizse alıntı + "
                       "alternatives kullanılmalı")
    if formation == "tartışmalı" and not item.get("alternatives"):
        reasons.append("formationType tartışmalı ama alternatives boş")
    # Kaynak belirsizlik bildiriyorsa bu bir yerde kayıtlı olmalı.
    if hits and formation != "tartışmalı" and not item.get("alternatives"):
        reasons.append("Kaynak belirsizlik bildiriyor (%s) ama ne formationType "
                       "tartışmalı ne alternatives dolu" % ", ".join(hits))


def check_source_url(item, entry, reasons):
    if not entry or not entry.get("url"):
        return
    for src in item.get("sources") or []:
        if not isinstance(src, dict):
            continue
        if "nişanyan" not in tr_lower(src.get("name")):
            continue
        url = src.get("url")
        # Yüzde kodlu ve düz Unicode yazım aynı adrestir.
        if url and urllib.parse.unquote(url).rstrip("/") != \
                urllib.parse.unquote(entry["url"]).rstrip("/"):
            reasons.append("Nişanyan bağlantısı kaynakla farklı: %s (beklenen %s)"
                           % (url, entry["url"]))
        return


def crosscheck_item(item):
    word_id = slugify_id(item.get("word") or item.get("id") or "")
    record = load_source(word_id)
    reasons = []
    if record is None:
        return {"id": word_id, "verdict": "check",
                "reasons": ["Kaynak dosyası yok: scripts/sources/%s.json" % word_id]}
    nis = record.get("nisanyan") or {}
    tdk = record.get("tdk") or {}
    if not nis.get("found") and not tdk.get("found"):
        return {"id": word_id, "verdict": "check",
                "reasons": ["Nişanyan ve TDK kaydı bulunamadı, doğrulanamıyor"]}

    entry = pick_entry(record, word_id)
    if entry is None and nis.get("found"):
        reasons.append("Nişanyan maddesi id ile eşleşmedi")
    check_donor(item, entry, tdk, reasons)
    check_chain(item, entry, reasons)
    check_attestation(item, entry, reasons)
    check_cognates(item, entry, reasons)
    check_uncertainty(item, entry, reasons)
    check_source_url(item, entry, reasons)

    return {"id": word_id, "verdict": "check" if reasons else "ok",
            "reasons": reasons}


def crosscheck_batch(tag, batches_dir, review_dir):
    path = os.path.join(batches_dir, "%s.json" % tag)
    if not os.path.exists(path):
        print("Parti yok: %s" % path, file=sys.stderr)
        return None
    with open(path, encoding="utf-8") as handle:
        items = json.load(handle)
    if not isinstance(items, list):
        print("%s: JSON dizi bekleniyordu." % path, file=sys.stderr)
        return None

    results = [crosscheck_item(item) for item in items if isinstance(item, dict)]
    os.makedirs(review_dir, exist_ok=True)
    out_path = os.path.join(review_dir, "%s.auto.json" % tag)
    with open(out_path, "w", encoding="utf-8") as handle:
        json.dump(results, handle, ensure_ascii=False, indent=2)
        handle.write("\n")

    ok = sum(1 for r in results if r["verdict"] == "ok")
    check = len(results) - ok
    print("Parti %s: %d madde · ok %d · check %d → %s"
          % (tag, len(results), ok, check, os.path.relpath(out_path, ROOT_DIR)))
    for result in results:
        if result["verdict"] == "check":
            print("  %s: %s" % (result["id"], " | ".join(result["reasons"])))
    return results


def main(argv=None):
    global SOURCES_DIR
    parser = argparse.ArgumentParser(
        description="Üretilmiş partiyi kaynaklarla karşılaştırır.")
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--batch", type=int, metavar="N", help="Parti numarası.")
    group.add_argument("--all", action="store_true", help="Tüm partiler.")
    parser.add_argument("--batches-dir", default=BATCHES_DIR)
    parser.add_argument("--review-dir", default=REVIEW_DIR)
    parser.add_argument("--sources-dir", default=SOURCES_DIR)
    args = parser.parse_args(argv)
    SOURCES_DIR = args.sources_dir

    if args.all:
        tags = sorted(os.path.basename(p)[:-5]
                      for p in glob.glob(os.path.join(args.batches_dir, "*.json")))
    else:
        tags = ["%02d" % args.batch]
    if not tags:
        raise SystemExit("Denetlenecek parti yok.")

    total_ok = total_check = 0
    for tag in tags:
        results = crosscheck_batch(tag, args.batches_dir, args.review_dir)
        if results is None:
            return 1
        total_ok += sum(1 for r in results if r["verdict"] == "ok")
        total_check += sum(1 for r in results if r["verdict"] == "check")
    print("\nToplam: ok %d · check %d" % (total_ok, total_check))
    return 0


if __name__ == "__main__":
    sys.exit(main())
