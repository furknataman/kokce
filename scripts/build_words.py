#!/usr/bin/env python3
"""Köken birleştirici: parti dosyalarından Resources/Content/words.json üretir.

Girdi:
  scripts/batches/*.json  — üretilmiş kelime partileri (çıplak JSON dizi)
  scripts/review/*.json   — doğrulayıcı kararları [{"id","verdict","objections"}]
  scripts/fixes/*.json    — "fix" kararı alan maddelerin düzeltilmiş hâlleri

Karar işleyişi:
  ok   → madde alınır, reviewed: true
  fix  → aynı id'li düzeltilmiş madde fixes/ içinden alınır, reviewed: true
         (düzeltme yoksa madde atlanır ve rapor edilir)
  drop → madde atılır
  karar yok → madde alınır, reviewed: false (sayısı raporlanır)

schedule.ids: mevcut words.json'daki sıra korunur (düşen id'ler çıkarılır),
yeni id'ler sabit tohumla (2026) karıştırılıp sona eklenir.

Kullanım:
    python3 scripts/build_words.py
    python3 scripts/build_words.py --out /tmp/words.json
    python3 scripts/build_words.py --strict-reviewed
"""

import argparse
import glob
import json
import os
import random
import sys

from validate_words import (
    LANGUAGES, RARITY, SCHEMA_VERSION, collect_languages, nfc, slugify_id,
    validate_words_file,
)

SCRIPTS_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR = os.path.dirname(SCRIPTS_DIR)
BATCHES_DIR = os.path.join(SCRIPTS_DIR, "batches")
REVIEW_DIR = os.path.join(SCRIPTS_DIR, "review")
FIXES_DIR = os.path.join(SCRIPTS_DIR, "fixes")
DEFAULT_OUT = os.path.join(ROOT_DIR, "Resources", "Content", "words.json")
DEFAULT_START = "2026-10-01"
SHUFFLE_SEED = 2026
VERDICTS = {"ok", "fix", "drop"}


def load_json(path):
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def _as_list(data, path):
    if isinstance(data, dict):
        for key in ("items", "words", "results", "reviews"):
            if isinstance(data.get(key), list):
                return data[key]
        raise SystemExit("%s: JSON dizi bekleniyordu." % path)
    if not isinstance(data, list):
        raise SystemExit("%s: JSON dizi bekleniyordu." % path)
    return data


def item_id(item, path):
    """Maddenin id'sini döner; yoksa word alanından üretir."""
    wid = item.get("id")
    if isinstance(wid, str) and wid.strip():
        return nfc(wid.strip())
    word = item.get("word")
    if isinstance(word, str) and word.strip():
        return slugify_id(word)
    raise SystemExit("%s: id'si olmayan madde var." % path)


def load_batches(directory):
    """Tüm parti dosyalarını okur, (id, madde) sırasını döner."""
    items = []
    seen = {}
    paths = sorted(glob.glob(os.path.join(directory, "*.json")))
    for path in paths:
        for item in _as_list(load_json(path), path):
            if not isinstance(item, dict):
                raise SystemExit("%s: nesne olmayan madde var." % path)
            wid = item_id(item, path)
            if wid in seen:
                print("Uyarı: %s içindeki %s daha önce %s dosyasında geçti, "
                      "ikincisi yok sayıldı."
                      % (os.path.basename(path), wid, seen[wid]), file=sys.stderr)
                continue
            seen[wid] = os.path.basename(path)
            items.append((wid, item))
    return items, paths


def load_reviews(directory):
    """id → (verdict, objections) sözlüğü. NN.auto.json dosyaları hariç."""
    verdicts = {}
    for path in sorted(glob.glob(os.path.join(directory, "*.json"))):
        if path.endswith(".auto.json"):
            continue
        for entry in _as_list(load_json(path), path):
            if not isinstance(entry, dict):
                continue
            wid = entry.get("id")
            verdict = entry.get("verdict")
            if not isinstance(wid, str) or not wid.strip():
                print("Uyarı: %s içinde id'siz karar var." % os.path.basename(path),
                      file=sys.stderr)
                continue
            if verdict not in VERDICTS:
                raise SystemExit("%s: geçersiz verdict %r (id: %s)"
                                 % (path, verdict, wid))
            verdicts[nfc(wid.strip())] = (verdict, entry.get("objections") or [])
    return verdicts


def load_auto_reviews(directory):
    """crosscheck.py kararları: id → verdict ("ok" | "check")."""
    verdicts = {}
    for path in sorted(glob.glob(os.path.join(directory, "*.auto.json"))):
        for entry in _as_list(load_json(path), path):
            if not isinstance(entry, dict):
                continue
            wid = entry.get("id")
            verdict = entry.get("verdict")
            if isinstance(wid, str) and wid.strip() and verdict in ("ok", "check"):
                verdicts[nfc(wid.strip())] = verdict
    return verdicts


def load_fixes(directory):
    """id → düzeltilmiş madde."""
    fixes = {}
    for path in sorted(glob.glob(os.path.join(directory, "*.json"))):
        for item in _as_list(load_json(path), path):
            if isinstance(item, dict):
                fixes[item_id(item, path)] = item
    return fixes


def merge(items, verdicts, auto_verdicts, fixes, strict_reviewed):
    """Kararları uygular. (id, madde) listesi ve sayaçları döner.

    review/NN.json kaydı her zaman review/NN.auto.json kaydından önce gelir.
    """
    kept = []
    stats = {"ok": 0, "fix": 0, "drop": 0, "auto": 0, "unreviewed": 0,
             "missing_fix": 0}
    for wid, item in items:
        verdict, _objections = verdicts.get(wid, (None, []))
        if verdict == "drop":
            stats["drop"] += 1
            continue
        if verdict == "fix":
            fixed = fixes.get(wid)
            if fixed is None:
                stats["missing_fix"] += 1
                print("Uyarı: %s için 'fix' kararı var ama scripts/fixes içinde "
                      "düzeltmesi yok, atlandı." % wid, file=sys.stderr)
                continue
            original_rarity = item.get("rarity")
            item = dict(fixed)
            # rarity kelime listesinin verisidir, düzeltmenin değil: düzeltme
            # dosyası geçerli bir değer taşımıyorsa parti dosyasındaki kalır.
            if item.get("rarity") not in RARITY and original_rarity in RARITY:
                item["rarity"] = original_rarity
            item["reviewed"] = True
            stats["fix"] += 1
        elif verdict == "ok":
            item = dict(item)
            item["reviewed"] = True
            stats["ok"] += 1
        elif auto_verdicts.get(wid) == "ok":
            # Programatik çapraz denetimden geçti, insan/LLM kaydı yok.
            item = dict(item)
            item["reviewed"] = True
            stats["auto"] += 1
        else:
            if strict_reviewed:
                stats["unreviewed"] += 1
                continue
            item = dict(item)
            item["reviewed"] = False
            stats["unreviewed"] += 1
        item["id"] = wid
        kept.append((wid, item))
    return kept, stats


def read_existing(path):
    """Var olan words.json'dan sıra, start ve contentVersion bilgisini alır."""
    if not os.path.exists(path):
        return {"order": [], "schedule_ids": [], "start": DEFAULT_START,
                "content_version": 0}
    data = load_json(path)
    schedule = data.get("schedule") or {}
    words = data.get("words") or []
    order = [nfc(w["id"]) for w in words
             if isinstance(w, dict) and isinstance(w.get("id"), str)]
    ids = [nfc(i) for i in schedule.get("ids") or [] if isinstance(i, str)]
    start = schedule.get("start")
    cver = data.get("contentVersion")
    return {
        "order": order,
        "schedule_ids": ids,
        "start": start if isinstance(start, str) and start else DEFAULT_START,
        "content_version": cver if isinstance(cver, int) and not isinstance(cver, bool) else 0,
    }


def interleave(first, second):
    """İki listeyi oranlarına göre serpiştirir; ilk öğe `first` listesinden gelir.

    250 gündelik + 300 az-bilinen için sonuç çoğunlukla dönüşümlüdür, fazlalık
    sona yığılmaz.
    """
    out = []
    la, lb = len(first), len(second)
    ia = ib = 0
    while ia < la or ib < lb:
        take_first = ib >= lb or (ia < la and (ia / la if la else 1) <=
                                  (ib / lb if lb else 1))
        if take_first:
            out.append(first[ia])
            ia += 1
        else:
            out.append(second[ib])
            ib += 1
    return out


def build_schedule_ids(previous_ids, current_ids, rarity_by_id):
    """Eski sırayı korur, düşenleri atar, yenileri sabit tohumla karıştırıp ekler.

    Yeni id'ler gündelik ve az-bilinen olarak ayrılıp dönüşümlü serpiştirilir,
    böylece ardışık günlerde tanıdık ve şaşırtıcı kelimeler birbirini izler.
    """
    current = set(current_ids)
    kept = [i for i in previous_ids if i in current]
    known = set(kept)
    fresh = [i for i in current_ids if i not in known]
    random.Random(SHUFFLE_SEED).shuffle(fresh)
    daily = [i for i in fresh if rarity_by_id.get(i) == "gündelik"]
    rare = [i for i in fresh if rarity_by_id.get(i) == "az-bilinen"]
    unknown = [i for i in fresh if rarity_by_id.get(i) not in RARITY]
    return kept + interleave(daily, rare) + unknown


def order_words(kept, previous_order):
    """Mevcut words.json sırasını korur, yeni maddeleri sona ekler."""
    by_id = dict(kept)
    ordered = [by_id[i] for i in previous_order if i in by_id]
    placed = set(previous_order)
    ordered.extend(item for wid, item in kept if wid not in placed)
    return ordered


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Parti dosyalarını words.json içinde birleştirir.")
    parser.add_argument("--out", default=DEFAULT_OUT, metavar="DOSYA",
                        help="Çıktı dosyası (varsayılan: Resources/Content/words.json).")
    parser.add_argument("--batches-dir", default=BATCHES_DIR)
    parser.add_argument("--review-dir", default=REVIEW_DIR)
    parser.add_argument("--fixes-dir", default=FIXES_DIR)
    parser.add_argument("--strict-reviewed", action="store_true",
                        help="Yalnızca doğrulayıcıdan geçmiş maddeleri yazar.")
    parser.add_argument("--no-validate", action="store_true",
                        help="Yazdıktan sonra doğrulama çalıştırmaz.")
    args = parser.parse_args(argv)

    items, batch_paths = load_batches(args.batches_dir)
    if not items:
        raise SystemExit("%s içinde parti dosyası yok." % args.batches_dir)
    verdicts = load_reviews(args.review_dir)
    auto_verdicts = load_auto_reviews(args.review_dir)
    fixes = load_fixes(args.fixes_dir)

    kept, stats = merge(items, verdicts, auto_verdicts, fixes,
                        args.strict_reviewed)
    if not kept:
        raise SystemExit("Hiçbir madde kalmadı, dosya yazılmadı.")

    existing = read_existing(args.out)
    current_ids = [wid for wid, _ in kept]
    rarity_by_id = {wid: item.get("rarity") for wid, item in kept}
    schedule_ids = build_schedule_ids(existing["schedule_ids"], current_ids,
                                      rarity_by_id)
    words = order_words(kept, existing["order"])

    used = collect_languages(words)
    unknown = sorted(used - set(LANGUAGES))
    if unknown:
        raise SystemExit("Şemada olmayan dil kodu: %s. Önce scripts/schema.md ve "
                         "validate_words.py güncellenmeli." % ", ".join(unknown))
    languages = {code: LANGUAGES[code] for code in sorted(used)}

    document = {
        "schemaVersion": SCHEMA_VERSION,
        "contentVersion": existing["content_version"] + 1,
        "schedule": {"start": existing["start"], "ids": schedule_ids},
        "languages": languages,
        "words": words,
    }

    out_dir = os.path.dirname(os.path.abspath(args.out))
    if out_dir:
        os.makedirs(out_dir, exist_ok=True)
    with open(args.out, "w", encoding="utf-8") as handle:
        json.dump(document, handle, ensure_ascii=False, indent=2, sort_keys=False)
        handle.write("\n")

    print("Parti dosyası: %d · madde: %d" % (len(batch_paths), len(items)))
    print("ok: %d · fix: %d · drop: %d · otomatik: %d · kararsız: %d · "
          "eksik düzeltme: %d"
          % (stats["ok"], stats["fix"], stats["drop"], stats["auto"],
             stats["unreviewed"], stats["missing_fix"]))
    if stats["unreviewed"] and not args.strict_reviewed:
        print("Uyarı: %d madde doğrulayıcıdan geçmedi, reviewed: false olarak "
              "yazıldı." % stats["unreviewed"], file=sys.stderr)
    print("Yazıldı: %s (contentVersion %d, %d kelime, %d dil)"
          % (args.out, document["contentVersion"], len(words), len(languages)))

    if args.no_validate:
        return 0
    errors = validate_words_file(args.out)
    if errors:
        for line in errors:
            print(line)
        print("\nDoğrulama başarısız: %d hata." % len(errors), file=sys.stderr)
        return 1
    print("Doğrulama geçti.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
