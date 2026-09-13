#!/usr/bin/env python3
"""Köken içerik doğrulayıcı.

Hem tek bir parti dosyasını (çıplak JSON dizi) hem de birleşik
Resources/Content/words.json dosyasını (kök nesne) doğrular.

Kullanım:
    python3 scripts/validate_words.py                      # words.json
    python3 scripts/validate_words.py --batch scripts/batches/01.json
    python3 scripts/validate_words.py --batch a.json --batch b.json
    python3 scripts/validate_words.py --words yol/words.json

Hata biçimi: dosya:id:alan: mesaj — en az bir hata varsa çıkış kodu 1.
Şema belgesi: scripts/schema.md
"""

import argparse
import json
import os
import re
import sys
import unicodedata

SCHEMA_VERSION = 1

# scripts/schema.md "Dil kodları" tablosunun birebir karşılığı.
# Yeni kod önce schema.md'ye, sonra buraya eklenir.
LANGUAGES = {
    "tr": "Türkçe",
    "otk": "Eski Türkçe",
    "ota": "Osmanlı Türkçesi",
    "tr-new": "Dil Devrimi türetmesi",
    "trk": "Ana Türkçe",
    "tt": "Tatarca",
    "ky": "Kırgızca",
    "az": "Azerbaycan Türkçesi",
    "ug": "Uygurca",
    "ar": "Arapça",
    "fa": "Farsça",
    "pal": "Pehlevice",
    "peo": "Eski Farsça",
    "ae": "Avestaca",
    "sog": "Soğdca",
    "ku": "Kürtçe",
    "fr": "Fransızca",
    "grc": "Eski Yunanca",
    "el": "Yunanca",
    "it": "İtalyanca",
    "en": "İngilizce",
    "la": "Latince",
    "de": "Almanca",
    "ru": "Rusça",
    "mn": "Moğolca",
    "hy": "Ermenice",
    "es": "İspanyolca",
    "pt": "Portekizce",
    "nl": "Felemenkçe",
    "sa": "Sanskritçe",
    "he": "İbranice",
    "arc": "Aramice",
    "syc": "Süryanice",
    "akk": "Akkadca",
    "sux": "Sümerce",
    "egy": "Eski Mısırca",
    "hu": "Macarca",
    "bg": "Bulgarca",
    "sr": "Sırpça",
    "ro": "Rumence",
    "sq": "Arnavutça",
    "hi": "Hintçe",
    "ur": "Urduca",
    "ms": "Malayca",
    "ja": "Japonca",
    "zh": "Çince",
    "ine": "Hint-Avrupa ana dili",
    "sla": "Slav ana dili",
    "sem": "Sami ana dili",
}

FORMATION_TYPES = {
    "alıntı", "türeme", "birleşik", "öz", "yansıma", "kısaltma", "tartışmalı",
}
RELATIONS = {"türev", "birleşik", "akraba", "eş köken"}
CONFIDENCE = {"yüksek", "orta"}
PARTS_OF_SPEECH = {
    "isim", "sıfat", "fiil", "zarf", "zamir", "edat", "bağlaç", "ünlem", "deyim",
}

WORD_FIELDS = [
    "id", "word", "partOfSpeech", "formationType", "donorLanguage",
    "ultimateOrigin", "chain", "shortMeaning", "currentMeaning", "story",
    "firstAttestation", "relatives", "alternatives", "funFact", "sources",
    "confidence", "reviewed",
]
CHAIN_FIELDS = ["language", "form", "meaning", "period", "reconstructed"]
ATTESTATION_FIELDS = ["source", "period", "form"]
SOURCE_FIELDS = ["name", "ref", "url"]

# null yazılabilen alanların açık listesi. Burada olmayan bir alanda null hatadır.
NULLABLE = {
    "donorLanguage", "ultimateOrigin", "firstAttestation", "relatives",
    "alternatives", "funFact", "chain[].period", "sources[].url",
}

SHORT_MEANING_MAX = 80
STORY_MIN_SENTENCES = 2
STORY_MAX_SENTENCES = 6
DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
ID_RE = re.compile(r"^[0-9a-zçğıiöşü\-]+$")

# Türkçeye duyarlı küçük harf: Python'un .lower() metodu İ için birleşik nokta
# bırakır, I için ı yerine i verir.
_LOWER_MAP = str.maketrans({"İ": "i", "I": "ı"})


def nfc(text):
    return unicodedata.normalize("NFC", text)


def slugify_id(word):
    """word alanından id üretir. schema.md "id kuralı" bölümünün karşılığı."""
    slug = nfc(word).strip().translate(_LOWER_MAP).lower()
    slug = re.sub(r"[\s_]+", "-", slug)
    return nfc(slug)


def count_sentences(text):
    """Cümle sayar. '13. yy' gibi sıra sayılarındaki nokta cümle sonu sayılmaz."""
    parts = re.split(r"(?<![0-9])[.!?]+(?:\s|$)", text.strip())
    return len([p for p in parts if p.strip()])


class Reporter:
    def __init__(self, path):
        self.path = os.path.basename(path)
        self.errors = []

    def add(self, item_id, field, message):
        self.errors.append("%s:%s:%s: %s" % (self.path, item_id, field, message))


def _check_str(rep, wid, field, value, *, max_len=None):
    """Dolu, NFC normalize bir string bekler. Sorun varsa False döner."""
    if not isinstance(value, str):
        rep.add(wid, field, "metin bekleniyordu, %s geldi" % type(value).__name__)
        return False
    if not value.strip():
        rep.add(wid, field, "boş bırakılamaz")
        return False
    if value != nfc(value):
        rep.add(wid, field, "NFC normalize değil")
        return False
    if value != value.strip():
        rep.add(wid, field, "başında veya sonunda boşluk var")
        return False
    if max_len is not None and len(value) > max_len:
        rep.add(wid, field, "en fazla %d karakter olmalı, %d karakter"
                % (max_len, len(value)))
        return False
    return True


def _check_lang(rep, wid, field, value):
    if not isinstance(value, str) or value not in LANGUAGES:
        rep.add(wid, field, "bilinmeyen dil kodu: %r" % (value,))
        return False
    return True


def _check_bool(rep, wid, field, value):
    if not isinstance(value, bool):
        rep.add(wid, field, "true/false bekleniyordu, %r geldi" % (value,))
        return False
    return True


def validate_word(item, rep, index):
    """Tek bir kelime nesnesini doğrular, id'sini (varsa) döner."""
    if not isinstance(item, dict):
        rep.add("#%d" % index, "-", "nesne bekleniyordu, %s geldi"
                % type(item).__name__)
        return None

    raw_id = item.get("id")
    wid = raw_id if isinstance(raw_id, str) and raw_id.strip() else "#%d" % index

    missing = [f for f in WORD_FIELDS if f not in item]
    for field in missing:
        rep.add(wid, field, "alan eksik")
    extra = [k for k in item if k not in WORD_FIELDS]
    for key in sorted(extra):
        rep.add(wid, key, "şemada tanımsız alan")

    # id ve word
    word_ok = _check_str(rep, wid, "word", item.get("word"))
    if _check_str(rep, wid, "id", raw_id):
        if not ID_RE.match(raw_id):
            rep.add(wid, "id", "yalnızca küçük Türkçe harf, rakam ve - içerebilir")
        if word_ok:
            expected = slugify_id(item["word"])
            if raw_id != expected:
                rep.add(wid, "id", "word alanından üretilen id %r olmalı" % expected)

    # sınırlı değerler
    pos = item.get("partOfSpeech")
    if pos not in PARTS_OF_SPEECH:
        rep.add(wid, "partOfSpeech", "izinli değil: %r" % (pos,))
    ftype = item.get("formationType")
    if ftype not in FORMATION_TYPES:
        rep.add(wid, "formationType", "izinli değil: %r" % (ftype,))
    conf = item.get("confidence")
    if conf not in CONFIDENCE:
        rep.add(wid, "confidence", "yüksek veya orta olmalı, %r geldi" % (conf,))
    if "reviewed" in item:
        _check_bool(rep, wid, "reviewed", item["reviewed"])

    for field in ("donorLanguage", "ultimateOrigin"):
        value = item.get(field)
        if value is not None:
            _check_lang(rep, wid, field, value)

    # chain
    chain = item.get("chain")
    used_langs = set()
    if not isinstance(chain, list) or not chain:
        if "chain" in item:
            rep.add(wid, "chain", "en az 1 adımlık dizi olmalı")
    else:
        for i, step in enumerate(chain):
            prefix = "chain[%d]" % i
            if not isinstance(step, dict):
                rep.add(wid, prefix, "nesne bekleniyordu")
                continue
            for field in CHAIN_FIELDS:
                if field not in step:
                    rep.add(wid, prefix + "." + field, "alan eksik")
            for key in sorted(k for k in step if k not in CHAIN_FIELDS):
                rep.add(wid, prefix + "." + key, "şemada tanımsız alan")
            if _check_lang(rep, wid, prefix + ".language", step.get("language")):
                used_langs.add(step["language"])
            _check_str(rep, wid, prefix + ".form", step.get("form"))
            _check_str(rep, wid, prefix + ".meaning", step.get("meaning"))
            if step.get("period") is not None:
                _check_str(rep, wid, prefix + ".period", step.get("period"))
            if "reconstructed" in step:
                _check_bool(rep, wid, prefix + ".reconstructed", step["reconstructed"])
        last = chain[-1]
        if isinstance(last, dict):
            if last.get("language") != "tr":
                rep.add(wid, "chain[%d].language" % (len(chain) - 1),
                        "zincirin son adımı tr olmalı, %r geldi"
                        % (last.get("language"),))
            if word_ok and isinstance(last.get("form"), str) \
                    and nfc(last["form"]) != nfc(item["word"]):
                rep.add(wid, "chain[%d].form" % (len(chain) - 1),
                        "son adımın biçimi madde başıyla aynı olmalı (%r bekleniyordu)"
                        % (item["word"],))

    # metinler
    _check_str(rep, wid, "shortMeaning", item.get("shortMeaning"),
               max_len=SHORT_MEANING_MAX)
    _check_str(rep, wid, "currentMeaning", item.get("currentMeaning"))
    if _check_str(rep, wid, "story", item.get("story")):
        n = count_sentences(item["story"])
        if not STORY_MIN_SENTENCES <= n <= STORY_MAX_SENTENCES:
            rep.add(wid, "story", "%d-%d cümle olmalı, %d cümle sayıldı"
                    % (STORY_MIN_SENTENCES, STORY_MAX_SENTENCES, n))

    # firstAttestation
    att = item.get("firstAttestation")
    if att is not None:
        if not isinstance(att, dict):
            rep.add(wid, "firstAttestation", "nesne veya null olmalı")
        else:
            for field in ATTESTATION_FIELDS:
                if field not in att:
                    rep.add(wid, "firstAttestation." + field, "alan eksik")
                else:
                    _check_str(rep, wid, "firstAttestation." + field, att[field])
            for key in sorted(k for k in att if k not in ATTESTATION_FIELDS):
                rep.add(wid, "firstAttestation." + key, "şemada tanımsız alan")

    # relatives — hedef kelimenin madde başı olması gerekmez, yalnızca biçim.
    rels = item.get("relatives")
    if rels is not None:
        if not isinstance(rels, list):
            rep.add(wid, "relatives", "dizi veya null olmalı")
        else:
            for i, rel in enumerate(rels):
                prefix = "relatives[%d]" % i
                if not isinstance(rel, dict):
                    rep.add(wid, prefix, "nesne bekleniyordu")
                    continue
                _check_str(rep, wid, prefix + ".word", rel.get("word"))
                if rel.get("relation") not in RELATIONS:
                    rep.add(wid, prefix + ".relation",
                            "izinli değil: %r" % (rel.get("relation"),))
                for key in sorted(k for k in rel if k not in ("word", "relation")):
                    rep.add(wid, prefix + "." + key, "şemada tanımsız alan")

    # alternatives
    alts = item.get("alternatives")
    if alts is not None:
        if not isinstance(alts, list) or not alts:
            rep.add(wid, "alternatives", "dolu dizi veya null olmalı")
        else:
            for i, alt in enumerate(alts):
                _check_str(rep, wid, "alternatives[%d]" % i, alt)

    if item.get("funFact") is not None:
        _check_str(rep, wid, "funFact", item.get("funFact"))

    # sources
    sources = item.get("sources")
    if not isinstance(sources, list) or not sources:
        if "sources" in item:
            rep.add(wid, "sources", "en az 1 kaynak gerekli")
    else:
        for i, src in enumerate(sources):
            prefix = "sources[%d]" % i
            if not isinstance(src, dict):
                rep.add(wid, prefix, "nesne bekleniyordu")
                continue
            for field in SOURCE_FIELDS:
                if field not in src:
                    rep.add(wid, prefix + "." + field, "alan eksik")
            for key in sorted(k for k in src if k not in SOURCE_FIELDS):
                rep.add(wid, prefix + "." + key, "şemada tanımsız alan")
            _check_str(rep, wid, prefix + ".name", src.get("name"))
            _check_str(rep, wid, prefix + ".ref", src.get("ref"))
            url = src.get("url")
            if url is not None:
                if _check_str(rep, wid, prefix + ".url", url):
                    if not url.startswith(("http://", "https://")):
                        rep.add(wid, prefix + ".url",
                                "http:// veya https:// ile başlamalı")

    if isinstance(raw_id, str) and raw_id.strip():
        return nfc(raw_id)
    return None


def collect_languages(words):
    """Kelimelerde geçen tüm dil kodları."""
    used = set()
    for item in words:
        if not isinstance(item, dict):
            continue
        for field in ("donorLanguage", "ultimateOrigin"):
            value = item.get(field)
            if isinstance(value, str):
                used.add(value)
        chain = item.get("chain")
        if isinstance(chain, list):
            for step in chain:
                if isinstance(step, dict) and isinstance(step.get("language"), str):
                    used.add(step["language"])
    return used


def _validate_word_list(words, rep):
    seen = {}
    for index, item in enumerate(words):
        wid = validate_word(item, rep, index)
        if wid is None:
            continue
        if wid in seen:
            rep.add(wid, "id", "yinelenen id (ilk görüldüğü sıra: %d)" % seen[wid])
        else:
            seen[wid] = index
    return seen


def validate_batch_file(path):
    """Çıplak JSON dizi biçimindeki parti dosyası."""
    rep = Reporter(path)
    try:
        with open(path, encoding="utf-8") as handle:
            data = json.load(handle)
    except (OSError, ValueError) as exc:
        rep.add("-", "-", "okunamadı: %s" % exc)
        return rep.errors
    if not isinstance(data, list):
        rep.add("-", "-", "kök öğe JSON dizi olmalı, %s geldi" % type(data).__name__)
        return rep.errors
    if not data:
        rep.add("-", "-", "parti boş")
        return rep.errors
    _validate_word_list(data, rep)
    return rep.errors


def validate_words_file(path):
    """Birleşik words.json dosyası."""
    rep = Reporter(path)
    try:
        with open(path, encoding="utf-8") as handle:
            data = json.load(handle)
    except (OSError, ValueError) as exc:
        rep.add("-", "-", "okunamadı: %s" % exc)
        return rep.errors
    if not isinstance(data, dict):
        rep.add("-", "-", "kök öğe nesne olmalı, %s geldi" % type(data).__name__)
        return rep.errors

    for key in sorted(k for k in data if k not in
                      ("schemaVersion", "contentVersion", "schedule", "languages", "words")):
        rep.add("-", key, "şemada tanımsız alan")

    if data.get("schemaVersion") != SCHEMA_VERSION:
        rep.add("-", "schemaVersion", "%d olmalı, %r geldi"
                % (SCHEMA_VERSION, data.get("schemaVersion")))
    cver = data.get("contentVersion")
    if not isinstance(cver, int) or isinstance(cver, bool) or cver < 1:
        rep.add("-", "contentVersion", "1 veya daha büyük tam sayı olmalı")

    words = data.get("words")
    if not isinstance(words, list) or not words:
        rep.add("-", "words", "en az 1 kelime içeren dizi olmalı")
        return rep.errors
    seen = _validate_word_list(words, rep)

    # schedule
    schedule = data.get("schedule")
    if not isinstance(schedule, dict):
        rep.add("-", "schedule", "nesne olmalı")
    else:
        for key in sorted(k for k in schedule if k not in ("start", "ids")):
            rep.add("-", "schedule." + key, "şemada tanımsız alan")
        start = schedule.get("start")
        if not isinstance(start, str) or not DATE_RE.match(start):
            rep.add("-", "schedule.start", "YYYY-MM-DD biçiminde olmalı, %r geldi"
                    % (start,))
        ids = schedule.get("ids")
        if not isinstance(ids, list) or not ids:
            rep.add("-", "schedule.ids", "en az 1 id içeren dizi olmalı")
        else:
            schedule_seen = set()
            for i, sid in enumerate(ids):
                if not isinstance(sid, str) or not sid.strip():
                    rep.add("-", "schedule.ids[%d]" % i, "dolu metin olmalı")
                    continue
                sid = nfc(sid)
                if sid in schedule_seen:
                    rep.add("-", "schedule.ids[%d]" % i, "yinelenen id: %s" % sid)
                schedule_seen.add(sid)
                if sid not in seen:
                    rep.add("-", "schedule.ids[%d]" % i,
                            "words içinde bulunmayan id: %s" % sid)
            for missing in sorted(set(seen) - schedule_seen):
                rep.add(missing, "schedule.ids",
                        "kelime programda yok, hiçbir gün gösterilmez")

    # languages
    langs = data.get("languages")
    if not isinstance(langs, dict) or not langs:
        rep.add("-", "languages", "dolu nesne olmalı")
    else:
        for code, name in sorted(langs.items()):
            if code not in LANGUAGES:
                rep.add("-", "languages." + str(code), "bilinmeyen dil kodu")
            if not isinstance(name, str) or not name.strip():
                rep.add("-", "languages." + str(code), "dil adı boş bırakılamaz")
        for code in sorted(collect_languages(words) - set(langs)):
            rep.add("-", "languages", "kullanılan dil kodu sözlükte yok: %s" % code)

    return rep.errors


def default_words_path():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    return os.path.join(root, "Resources", "Content", "words.json")


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Köken kelime verisini doğrular.")
    parser.add_argument("--batch", action="append", default=[], metavar="DOSYA",
                        help="Parti dosyası (çıplak JSON dizi). Tekrarlanabilir.")
    parser.add_argument("--words", metavar="DOSYA",
                        help="Birleşik words.json dosyası.")
    args = parser.parse_args(argv)

    errors = []
    checked = 0
    for path in args.batch:
        errors.extend(validate_batch_file(path))
        checked += 1
    if args.words or not args.batch:
        path = args.words or default_words_path()
        if not args.words and not os.path.exists(path):
            # Henüz içerik birleştirilmemiş olabilir; bu bir hata değil.
            print("Henüz içerik yok: %s (doğrulanacak bir şey bulunamadı)" % path)
            return 0
        errors.extend(validate_words_file(path))
        checked += 1

    if errors:
        for line in errors:
            print(line)
        print("\n%d hata, %d dosya." % (len(errors), checked), file=sys.stderr)
        return 1
    print("Doğrulama geçti: %d dosya, hata yok." % checked)
    return 0


if __name__ == "__main__":
    sys.exit(main())
