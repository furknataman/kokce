#!/usr/bin/env python3
"""Köken kaynak toplayıcı: her kelime için Nişanyan ve TDK kayıtlarını indirir.

Her kelime bir kez çekilir ve scripts/sources/<id>.json olarak saklanır; var
olan dosya --force verilmedikçe yeniden indirilmez. Özet scripts/sources/
_index.json dosyasına yazılır.

Kullanım:
    python3 scripts/fetch_sources.py
    python3 scripts/fetch_sources.py --only kalem,yüz
    python3 scripts/fetch_sources.py --force --limit 20
"""

import argparse
import datetime
import json
import os
import re
import subprocess
import sys
import html as html_module
import time
import unicodedata
import urllib.error
import urllib.parse
import urllib.request

from validate_words import nfc, slugify_id

SCRIPTS_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR = os.path.dirname(SCRIPTS_DIR)
SOURCES_DIR = os.path.join(SCRIPTS_DIR, "sources")
INDEX_PATH = os.path.join(SOURCES_DIR, "_index.json")

NISANYAN_URL = "https://www.nisanyansozluk.com/api/words/%s?session=0"
TDK_URL = "https://sozluk.gov.tr/gts?ara=%s"
# lugatim.com bir SPA; sayfa HTML'i boş gelir. İçerik bu REST uçtan alınır
# (adres JS paketindeki baseURL'den).
KUBBEALTI_URL = "https://eski.lugatim.com/rest/s/%s"
KUBBEALTI_PAGE = "https://lugatim.com/s/%s"
USER_AGENT = "Mozilla/5.0"
REQUEST_TIMEOUT = 20
POLITE_DELAY = 1.0      # istekler arası bekleme
RETRY_DELAY = 1.5       # Nişanyan "Internal Error" sonrası bekleme
RETRIES = 4

# Nişanyan metinlerinde geçen biçim imleri: %b kalın, %i eğik, %u altı çizili.
FORMAT_MARK_RE = re.compile(r"%[a-zA-Z]")
TRAILING_DIGITS_RE = re.compile(r"\d+$")
TAG_RE = re.compile(r"<[^>]+>")
PAREN_RE = re.compile(r"\(([^()]*)\)")
# Kubbealtı köken satırı "(Fars. giristen ...)" biçimindedir.
ORIGIN_RE = re.compile(r"^([A-ZÇĞİÖŞÜ][a-zçğıöşü]{0,6}\.(?:\s*[-–]\s*"
                       r"[A-ZÇĞİÖŞÜ][a-zçğıöşü]{0,6}\.)*)\s")
# Kubbealtı madde başları şapkalı yazılır (TÎR), varyantları tire ile ayırır
# (PÎRÂHEN – PÎREHEN) ve ekleri iki yanı tireli gösterir (–TİR–).
FOLD_MAP = str.maketrans({"â": "a", "î": "i", "û": "u", "ç": "c", "ğ": "g",
                          "ı": "i", "ö": "o", "ş": "s", "ü": "u"})
VARIANT_SPLIT_RE = re.compile(r"\s*[–—/]\s*")
AFFIX_RE = re.compile(r"^[–—-]|[–—-]$")
POS_RE = re.compile(r"^(?:i|sıf|zf|f|e|ünl|zm|bağ|isim|çoğul)\.\s*", re.IGNORECASE)


def clean(text):
    """Biçim imlerini atar, boşlukları toparlar. None → None."""
    if not isinstance(text, str):
        return None
    out = FORMAT_MARK_RE.sub("", text)
    out = re.sub(r"\s+", " ", out).strip()
    return nfc(out) or None


def get_json(url):
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=REQUEST_TIMEOUT) as response:
        raw = response.read().decode("utf-8", "replace")
    return json.loads(raw)


def fetch_nisanyan(word):
    """Nişanyan kaydını döner. Geçici hatada RETRIES kez dener."""
    url = NISANYAN_URL % urllib.parse.quote(word, safe="")
    last_error = None
    for attempt in range(RETRIES):
        try:
            data = get_json(url)
        except (urllib.error.URLError, ValueError, OSError) as exc:
            last_error = str(exc)
            time.sleep(RETRY_DELAY)
            continue
        # Sunucu ara sıra {"message": "Internal Error"} döndürüyor.
        if isinstance(data, dict) and data.get("message") == "Internal Error":
            last_error = "Internal Error"
            time.sleep(RETRY_DELAY)
            continue
        return data, None
    return None, last_error


def parse_nisanyan(data, word):
    """İlgili maddeleri ayıklar. Zincir eskiden yeniye çevrilir."""
    if not isinstance(data, dict):
        return {"found": False, "entries": []}
    words = data.get("words") or []
    target = nfc(word).strip()
    entries = []
    for item in words:
        if not isinstance(item, dict):
            continue
        name = item.get("name")
        if not isinstance(name, str):
            continue
        # "yüz2" → "yüz"; "yüz-" olduğu gibi kalır ve eşleşmez.
        base = TRAILING_DIGITS_RE.sub("", nfc(name).strip())
        if base != target:
            continue

        chain = []
        for step in item.get("etymologies") or []:
            if not isinstance(step, dict):
                continue
            relation = (step.get("relation") or {}).get("name")
            chain.append({
                "relation": clean(relation),
                "languages": [clean(l.get("name")) for l in step.get("languages") or []
                              if isinstance(l, dict) and clean(l.get("name"))],
                "romanizedText": clean(step.get("romanizedText")),
                "originalText": clean(step.get("originalText")),
                "definition": clean(step.get("definition")),
            })
        chain.reverse()  # API yeniden eskiye verir; biz eskiden yeniye saklarız.

        histories = []
        for hist in item.get("histories") or []:
            if not isinstance(hist, dict):
                continue
            source = hist.get("source") or {}
            sortable = hist.get("dateSortable")
            if isinstance(sortable, str):
                try:
                    sortable = int(sortable)
                except ValueError:
                    sortable = None
            if not isinstance(sortable, int) or isinstance(sortable, bool):
                sortable = None
            histories.append({
                "date": clean(hist.get("date")),
                "dateSortable": sortable,
                "source": clean(source.get("name")),
                "book": clean(source.get("book")),
                "definition": clean(hist.get("definition")),
                "quote": clean(hist.get("quote")),
            })
        histories.sort(key=lambda h: (h["dateSortable"] is None, h["dateSortable"] or 0))

        entries.append({
            "name": nfc(name).strip(),
            "note": clean(item.get("note")),
            "chain": chain,
            "histories": histories,
            "url": "https://www.nisanyansozluk.com/kelime/%s"
                   % urllib.parse.quote(nfc(name).strip(), safe=""),
        })
    return {"found": bool(entries), "entries": entries}


def fetch_tdk(word):
    url = TDK_URL % urllib.parse.quote(word, safe="")
    try:
        return get_json(url), None
    except (urllib.error.URLError, ValueError, OSError) as exc:
        return None, str(exc)


def parse_tdk(data):
    """TDK bulunamayınca {'error': ...} nesnesi döner, bulununca dizi."""
    if not isinstance(data, list):
        return {"found": False, "entries": []}
    entries = []
    for item in data:
        if not isinstance(item, dict):
            continue
        meanings = []
        for sense in (item.get("anlamlarListe") or [])[:3]:
            if isinstance(sense, dict):
                text = clean(sense.get("anlam"))
                if text:
                    meanings.append(text)
        entries.append({
            "madde": clean(item.get("madde")),
            "lisan": clean(item.get("lisan")),
            "meanings": meanings,
        })
    return {"found": bool(entries), "entries": entries}


def plain_text(markup):
    """HTML etiketlerini atar, varlıkları çözer, boşlukları toparlar."""
    if not isinstance(markup, str):
        return ""
    text = html_module.unescape(TAG_RE.sub("", markup))
    return re.sub(r"\s+", " ", text).strip()


def parse_kubbealti_entry(item, word):
    """Tek Kubbealtı maddesinden köken satırı ve ilk anlamı çıkarır."""
    headword = nfc((item.get("kelime") or "").strip())
    text = plain_text(item.get("anlam"))
    if not text:
        return None

    origin = None
    rest = text
    for match in PAREN_RE.finditer(text):
        inner = match.group(1).strip()
        if ORIGIN_RE.match(inner):
            origin = clean(inner)
            rest = text[match.end():].strip()
            break
    else:
        # Köken satırı yoksa parantezleri atlayıp gövdeye geç.
        last = None
        for match in PAREN_RE.finditer(text[:120]):
            last = match
        if last:
            rest = text[last.end():].strip()

    rest = POS_RE.sub("", rest).strip()
    rest = re.sub(r"^1\.\s*", "", rest)
    # Anlamdan sonra iki nokta gelir ve örnek cümleler başlar.
    meaning = re.split(r"\s*:\s|\s2\.\s", rest, maxsplit=1)[0]
    language = None
    if origin:
        abbr = ORIGIN_RE.match(origin)
        language = abbr.group(1).strip() if abbr else None

    return {
        "kelime": headword,
        "language": language,
        "origin": origin,
        "meaning": clean(meaning[:400]),
        "url": KUBBEALTI_PAGE % urllib.parse.quote(nfc(word).strip(), safe=""),
    }


def get_json_curl(url):
    """curl ile çeker.

    eski.lugatim.com sertifika zincirinde ara sertifikayı göndermiyor;
    OpenSSL bunu tamamlayamadığı için urllib "unable to get local issuer
    certificate" veriyor. curl (macOS Security çatısı) zinciri tamamlayıp
    doğruluyor, bu yüzden yalnızca bu kaynakta curl kullanılıyor.
    Doğrulama kapatılmıyor.
    """
    result = subprocess.run(
        ["curl", "-sS", "--fail", "--max-time", str(REQUEST_TIMEOUT),
         "-H", "User-Agent: %s" % USER_AGENT, url],
        capture_output=True, text=True)
    if result.returncode != 0:
        raise OSError(result.stderr.strip() or "curl çıkış kodu %d"
                      % result.returncode)
    return json.loads(result.stdout)


def fetch_kubbealti(word):
    url = KUBBEALTI_URL % urllib.parse.quote(word, safe="")
    try:
        return get_json_curl(url), None
    except (OSError, ValueError) as exc:
        return None, str(exc)


def fold(text):
    """Küçük harf + şapkasız biçim: 'TÎR' → 'tir'."""
    return slugify_id(text or "").translate(FOLD_MAP)


def headword_matches(headword, word):
    """Şapka ve varyant farklarını yok sayarak eşleştirir; ekleri eler."""
    headword = nfc((headword or "").strip())
    if not headword or AFFIX_RE.search(headword):
        return False  # –TİR– gibi ek maddeleri madde başı değildir
    target = fold(word)
    return any(fold(v) == target for v in VARIANT_SPLIT_RE.split(headword) if v)


def parse_kubbealti(data, word):
    """Madde başıyla eşleşen kayıtları alır."""
    if not isinstance(data, dict):
        return {"found": False, "entries": []}
    entries = []
    for item in data.get("content") or []:
        if not isinstance(item, dict):
            continue
        if not headword_matches(item.get("kelime"), word):
            continue
        parsed = parse_kubbealti_entry(item, word)
        if parsed:
            entries.append(parsed)
    return {"found": bool(entries), "entries": entries}


def load_words(path):
    with open(path, encoding="utf-8") as handle:
        data = json.load(handle)
    if isinstance(data, dict):
        data = data.get("words")
    if not isinstance(data, list):
        raise SystemExit("%s: kelime dizisi bulunamadı." % path)
    words = []
    for item in data:
        word = item if isinstance(item, str) else (item or {}).get("word")
        if isinstance(word, str) and word.strip():
            words.append(word.strip())
    return words


def fetch_one(word, path):
    nis_raw, nis_error = fetch_nisanyan(word)
    time.sleep(POLITE_DELAY)
    tdk_raw, tdk_error = fetch_tdk(word)

    nisanyan = parse_nisanyan(nis_raw, word)
    if nis_error:
        nisanyan["error"] = nis_error
    tdk = parse_tdk(tdk_raw)
    if tdk_error:
        tdk["error"] = tdk_error

    # Kubbealtı yalnızca ilk iki kaynak boş kaldığında sorulur.
    kubbealti = {"found": False, "entries": []}
    if not nisanyan["found"] and not tdk["found"]:
        time.sleep(POLITE_DELAY)
        kub_raw, kub_error = fetch_kubbealti(word)
        kubbealti = parse_kubbealti(kub_raw, word)
        if kub_error:
            kubbealti["error"] = kub_error

    record = {
        "id": slugify_id(word),
        "word": nfc(word),
        "fetchedAt": datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
        "nisanyan": nisanyan,
        "tdk": tdk,
        "kubbealti": kubbealti,
    }
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(record, handle, ensure_ascii=False, indent=2)
        handle.write("\n")
    return record


def fill_kubbealti(directory, force=False):
    """Var olan kayıtlarda Nişanyan ve TDK boşsa Kubbealtı bölümünü doldurur.

    Nişanyan ve TDK'ye yeniden istek atmaz.
    """
    filled = found = 0
    names = sorted(n for n in os.listdir(directory)
                   if n.endswith(".json") and not n.startswith("_"))
    for name in names:
        path = os.path.join(directory, name)
        with open(path, encoding="utf-8") as handle:
            record = json.load(handle)
        if (record.get("nisanyan") or {}).get("found"):
            continue
        if (record.get("tdk") or {}).get("found"):
            continue
        if record.get("kubbealti") and not force:
            continue
        word = record.get("word") or record.get("id")
        kub_raw, kub_error = fetch_kubbealti(word)
        kubbealti = parse_kubbealti(kub_raw, word)
        if kub_error:
            kubbealti["error"] = kub_error
        record["kubbealti"] = kubbealti
        with open(path, "w", encoding="utf-8") as handle:
            json.dump(record, handle, ensure_ascii=False, indent=2)
            handle.write("\n")
        filled += 1
        if kubbealti["found"]:
            found += 1
        print("%s [%s]" % (word, "K" if kubbealti["found"] else "-"), flush=True)
        time.sleep(POLITE_DELAY)
    print("\nKubbealtı sorulan: %d · bulunan: %d" % (filled, found))
    return filled, found


def write_index(directory):
    """sources/ içindeki tüm kayıtlardan özet üretir."""
    entries = {}
    for name in sorted(os.listdir(directory)):
        if not name.endswith(".json") or name.startswith("_"):
            continue
        with open(os.path.join(directory, name), encoding="utf-8") as handle:
            record = json.load(handle)
        entries[record["id"]] = {
            "word": record.get("word"),
            "nisanyan": bool((record.get("nisanyan") or {}).get("found")),
            "tdk": bool((record.get("tdk") or {}).get("found")),
            "kubbealti": bool((record.get("kubbealti") or {}).get("found")),
        }
    both = sum(1 for e in entries.values() if e["nisanyan"] and e["tdk"])
    neither = sum(1 for e in entries.values()
                  if not e["nisanyan"] and not e["tdk"] and not e.get("kubbealti"))
    index = {
        "generatedAt": datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
        "total": len(entries),
        "nisanyanFound": sum(1 for e in entries.values() if e["nisanyan"]),
        "tdkFound": sum(1 for e in entries.values() if e["tdk"]),
        "kubbealtiFound": sum(1 for e in entries.values() if e.get("kubbealti")),
        "bothFound": both,
        "neitherFound": neither,
        "words": entries,
    }
    with open(INDEX_PATH, "w", encoding="utf-8") as handle:
        json.dump(index, handle, ensure_ascii=False, indent=2)
        handle.write("\n")
    return index


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Nişanyan ve TDK kayıtlarını indirir.")
    parser.add_argument("--wordlist",
                        default=os.path.join(SCRIPTS_DIR, "wordlist.json"))
    parser.add_argument("--only", help="Virgülle ayrılmış kelimeler.")
    parser.add_argument("--limit", type=int, help="En fazla kaç kelime çekilsin.")
    parser.add_argument("--force", action="store_true",
                        help="Var olan kayıtları yeniden indirir.")
    parser.add_argument("--index-only", action="store_true",
                        help="İndirme yapmaz, yalnızca _index.json üretir.")
    parser.add_argument("--kubbealti-only", action="store_true",
                        help="Yalnızca Nişanyan ve TDK boş olan kayıtlarda "
                             "Kubbealtı bölümünü doldurur.")
    args = parser.parse_args(argv)

    os.makedirs(SOURCES_DIR, exist_ok=True)
    if args.kubbealti_only:
        fill_kubbealti(SOURCES_DIR, force=args.force)
        index = write_index(SOURCES_DIR)
        print("Nişanyan: %d · TDK: %d · Kubbealtı: %d · hiçbiri: %d"
              % (index["nisanyanFound"], index["tdkFound"],
                 index["kubbealtiFound"], index["neitherFound"]))
        return 0
    if args.index_only:
        index = write_index(SOURCES_DIR)
        print("Özet: %d kayıt · Nişanyan %d · TDK %d · Kubbealtı %d · "
              "hiçbiri %d"
              % (index["total"], index["nisanyanFound"], index["tdkFound"],
                 index["kubbealtiFound"], index["neitherFound"]))
        return 0

    if args.only:
        words = [w.strip() for w in args.only.split(",") if w.strip()]
    else:
        words = load_words(args.wordlist)
    if args.limit:
        words = words[:args.limit]
    if not words:
        raise SystemExit("Çekilecek kelime yok.")

    total = len(words)
    fetched = skipped = 0
    for i, word in enumerate(words, 1):
        path = os.path.join(SOURCES_DIR, "%s.json" % slugify_id(word))
        if os.path.exists(path) and not args.force:
            skipped += 1
            continue
        try:
            record = fetch_one(word, path)
        except Exception as exc:  # ağ kesintisi tek kelimeyi düşürsün, hattı değil
            print("%d/%d %s: HATA %s" % (i, total, word, exc), file=sys.stderr)
            time.sleep(POLITE_DELAY)
            continue
        fetched += 1
        marks = ("N" if record["nisanyan"]["found"] else "-") + \
                ("T" if record["tdk"]["found"] else "-") + \
                ("K" if record["kubbealti"]["found"] else "-")
        print("%d/%d %s [%s]" % (i, total, word, marks), flush=True)
        time.sleep(POLITE_DELAY)

    index = write_index(SOURCES_DIR)
    print("\nİndirilen: %d · atlanan: %d · toplam kayıt: %d"
          % (fetched, skipped, index["total"]))
    print("Nişanyan: %d · TDK: %d · Kubbealtı: %d · ilk ikisi de: %d · hiçbiri: %d"
          % (index["nisanyanFound"], index["tdkFound"], index["kubbealtiFound"],
             index["bothFound"], index["neitherFound"]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
