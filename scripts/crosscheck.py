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
import datetime
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
LOG_DIR = os.path.join(SCRIPTS_DIR, "log")
AUTOFIX_LOG = os.path.join(LOG_DIR, "autofix.log")

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
_FOLD_MAP = str.maketrans({"â": "a", "î": "i", "û": "u", "ç": "c", "ğ": "g",
                           "ı": "i", "ö": "o", "ş": "s", "ü": "u"})

# Nişanyan "Aramice-Süryanice" etiketini ikisi için birden kullanır; denetimde
# arc ve syc aynı halka sayılır.
EQUIVALENT = {"syc": "arc"}


def canon(code):
    """Denetimde eşdeğer sayılan kodları tek kod altında toplar."""
    return EQUIVALENT.get(code, code)


def fold(text):
    """Küçük harf + diacritic'siz biçim: 'Hikâye' → 'hikaye'."""
    return tr_lower(text).translate(_FOLD_MAP)


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
    donor = canon(item.get("donorLanguage"))
    nearest_codes, unmapped = set(), set()
    steps = [st for st in (entry or {}).get("chain") or []
             if not COGNATE_RE.search(st.get("relation") or "")]
    if steps:
        for name in steps[-1].get("languages") or []:
            code = lang_code(name)
            (nearest_codes.add(canon(code)) if code else unmapped.add(name))
    tdk_code = None
    for tdk_entry in (tdk.get("entries") or [])[:1]:
        tdk_code = canon(lang_code(tdk_entry.get("lisan")))
    all_codes = set()
    for step in steps:
        all_codes |= step_codes(step)

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


def step_codes(step):
    """Bir kaynak adımının kabul edilebilir dil kodları kümesi.

    Nişanyan "Farsça / Orta Farsça" gibi bileşik etiket kullanır; bu TEK
    halkadır ve iki koddan biri kabul edilir.
    """
    codes = set()
    for name in step.get("languages") or []:
        code = lang_code(name)
        if code:
            codes.add(canon(code))
    return codes


def transmission_steps(entry):
    """Aktarım halkaları: her halka kabul edilebilir kodlar kümesidir.

    "eşkökenlilik" ilişkili adımlar sözcüğün geçtiği yolu değil, başka
    dillerdeki akrabalarını gösterir; zincire girmezler.
    """
    steps = []
    for step in entry.get("chain") or []:
        if COGNATE_RE.search(step.get("relation") or ""):
            continue
        codes = step_codes(step)
        if codes and (not steps or steps[-1] != codes):
            steps.append(codes)
    return steps


def transmission_chain(entry):
    """Geriye dönük uyumluluk: her halkanın tek temsilci kodu."""
    return [sorted(codes)[0] for codes in transmission_steps(entry)]


def check_chain(item, entry, reasons):
    if not entry or not entry.get("chain"):
        return
    source_steps = transmission_steps(entry)
    item_codes = collapse([canon(s.get("language")) for s in item.get("chain") or []
                           if isinstance(s, dict)])
    if item_codes and item_codes[-1] == "tr":
        item_codes = item_codes[:-1]
    if not source_steps:
        return

    present = set(item_codes)
    missing = [" veya ".join(sorted(codes)) for codes in source_steps
               if not (codes & present)]
    if missing:
        reasons.append("Kaynak zincirinde olup maddede olmayan halka: %s"
                       % ", ".join(missing))
    allowed = set().union(*source_steps)
    extra = [c for c in item_codes if c not in allowed]
    if extra:
        reasons.append("Maddede olup kaynak zincirinde olmayan halka: %s"
                       % ", ".join(extra))

    # Ortak halkaların göreli sırası korunmuş mu.
    positions = []
    for code in item_codes:
        for i, codes in enumerate(source_steps):
            if code in codes:
                positions.append((code, i))
                break
    order = [i for _c, i in positions]
    if order and order != sorted(order):
        reasons.append("Zincir sırası kaynaktan farklı: madde %s, kaynak %s"
                       % (" › ".join(c for c, _i in positions),
                          " › ".join(c for c, _i in sorted(positions,
                                                           key=lambda x: x[1]))))

    # Bileşik etiket tek halkadır, ikiye bölünemez.
    for codes in source_steps:
        if len(codes) < 2:
            continue
        for i in range(len(item_codes) - 1):
            first, second = item_codes[i], item_codes[i + 1]
            if first != second and first in codes and second in codes:
                reasons.append("Kaynaktaki bileşik dil etiketi (%s) iki ayrı "
                               "halkaya bölünmüş: %s › %s"
                               % (" / ".join(sorted(codes)), first, second))
                break


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
        year = oldest["dateSortable"]
        if high < year:
            # Madde kaynaktan daha eski bir tanıklık iddia ediyor: her zaman bak.
            reasons.append("firstAttestation.period %s kaynaktaki en eski "
                           "tanıklıktan (%s) eski" % (att.get("period"), year))
        elif low > year:
            # Madde daha geç bir tarih veriyor. Kaynağın en eski kaydı çoğu kez
            # başka bir sözcüğe ait (Codex Cumanicus 1303 gibi); yalnızca o kayıt
            # gerçekten madde başını içeriyorsa itiraz sayılır.
            stem = fold(item.get("word") or "")[:4]
            text = fold(" ".join(x for x in (oldest.get("quote"),
                                             oldest.get("definition")) if x))
            if stem and stem in text:
                reasons.append("firstAttestation.period %s, kaynaktaki en eski "
                               "tanıklık %s ve o kayıt madde başını içeriyor"
                               % (att.get("period"), year))

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
    transmission = set().union(*transmission_steps(entry)) \
        if transmission_steps(entry) else set()
    cognate_codes = set()
    for step in entry.get("chain") or []:
        if COGNATE_RE.search(step.get("relation") or ""):
            cognate_codes |= step_codes(step)
    cognate_only = cognate_codes - transmission
    item_codes = {canon(st.get("language")) for st in item.get("chain") or []
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


def source_has_uncertainty(entry):
    """Nişanyan aktarım ilişkilerinde tartışma/tahmin kaydı var mı."""
    if not entry:
        return None  # bilinmiyor
    for step in entry.get("chain") or []:
        relation = step.get("relation") or ""
        if COGNATE_RE.search(relation):
            continue
        if UNCERTAIN_RE.search(relation):
            return True
    return False


def autofix_items(items):
    """Yalnızca deterministik tek durumu düzeltir: yanlış kullanılmış tartışmalı.

    Koşullar: formationType tartışmalı, Nişanyan aktarım ilişkisinde tartışma
    kaydı yok ve donorLanguage dolu. Bu üçü birden sağlanınca oluşum türü
    bellidir ve "alıntı" yazılır. donorLanguage boşsa öz/türeme kararı
    verilmez, madde check olarak bırakılır. alternatives'e dokunulmaz.
    """
    fixed = []
    for item in items:
        if not isinstance(item, dict):
            continue
        if item.get("formationType") != "tartışmalı":
            continue
        donor = canon(item.get("donorLanguage"))
        if not isinstance(donor, str) or not donor.strip():
            continue
        word_id = slugify_id(item.get("word") or item.get("id") or "")
        entry = pick_entry(load_source(word_id), word_id)
        if source_has_uncertainty(entry) is not False:
            continue  # kaynak yok ya da kaynakta tartışma var: dokunma
        item["formationType"] = "alıntı"
        fixed.append(word_id)
    return fixed


def write_autofix_log(tag, fixed):
    os.makedirs(LOG_DIR, exist_ok=True)
    stamp = datetime.datetime.now().astimezone().isoformat(timespec="seconds")
    with open(AUTOFIX_LOG, "a", encoding="utf-8") as handle:
        for word_id in fixed:
            handle.write("%s\t%s\t%s\t%s\n"
                         % (stamp, tag, word_id,
                            "formationType: tartışmalı → alıntı"))


def crosscheck_batch(tag, batches_dir, review_dir, autofix=False):
    path = os.path.join(batches_dir, "%s.json" % tag)
    if not os.path.exists(path):
        print("Parti yok: %s" % path, file=sys.stderr)
        return None
    with open(path, encoding="utf-8") as handle:
        items = json.load(handle)
    if not isinstance(items, list):
        print("%s: JSON dizi bekleniyordu." % path, file=sys.stderr)
        return None

    if autofix:
        fixed = autofix_items(items)
        if fixed:
            with open(path, "w", encoding="utf-8") as handle:
                json.dump(items, handle, ensure_ascii=False, indent=2)
                handle.write("\n")
            write_autofix_log(tag, fixed)
            print("Parti %s: %d madde düzeltildi (tartışmalı → alıntı): %s"
                  % (tag, len(fixed), ", ".join(fixed)))

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
    parser.add_argument("--autofix", action="store_true",
                        help="Yanlış kullanılmış formationType tartışmalı "
                             "değerlerini parti dosyasında yerinde düzeltir.")
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
        results = crosscheck_batch(tag, args.batches_dir, args.review_dir,
                                   autofix=args.autofix)
        if results is None:
            return 1
        total_ok += sum(1 for r in results if r["verdict"] == "ok")
        total_check += sum(1 for r in results if r["verdict"] == "check")
    print("\nToplam: ok %d · check %d" % (total_ok, total_check))
    return 0


if __name__ == "__main__":
    sys.exit(main())
