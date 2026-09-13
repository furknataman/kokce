#!/usr/bin/env python3
"""Köken üretim hattı: kelime listesinden 20'lik partiler hâlinde içerik üretir.

Kelime listesini (scripts/wordlist.json veya scripts/wordlist.raw.json) okur,
N'inci partiyi prompt şablonuna yerleştirir, codex exec ile çalıştırır,
çıktıdan JSON diziyi ayıklar ve scripts/batches/NN.json dosyasına yazar.

Kullanım:
    python3 scripts/generate_batch.py --batch 1
    python3 scripts/generate_batch.py --batch 1 --dry-run
    python3 scripts/generate_batch.py --all

Parti numaraları 1 tabanlıdır: --batch 1 listedeki 1-20, --batch 2 21-40.
Dosya adları iki hanelidir (01.json, 02.json, ...).
"""

import argparse
import datetime
import glob
import json
import os
import re
import subprocess
import sys

from validate_words import RARITY, slugify_id

SCRIPTS_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR = os.path.dirname(SCRIPTS_DIR)
BATCHES_DIR = os.path.join(SCRIPTS_DIR, "batches")
LOG_DIR = os.path.join(SCRIPTS_DIR, "log")
PROMPT_PATH = os.path.join(SCRIPTS_DIR, "prompts", "generate_batch.md")
SOURCES_DIR = os.path.join(SCRIPTS_DIR, "sources")
COGNATE_RE = re.compile(r"eşköken", re.IGNORECASE)
NOTE_MAX = 400      # prompt'u şişirmemek için kırpma sınırları
QUOTE_MAX = 220
HISTORY_MAX = 3
WORDLIST_CANDIDATES = ["wordlist.json", "wordlist.raw.json"]
DEFAULT_MODEL = "gpt-6-astra"
DEFAULT_SIZE = 20


def show(path):
    """Yolu depo köküne göre gösterir; kök dışındaysa mutlak yol."""
    path = os.path.abspath(path)
    if path.startswith(ROOT_DIR + os.sep):
        return os.path.relpath(path, ROOT_DIR)
    return path


def find_wordlist(explicit=None):
    if explicit:
        return explicit
    for name in WORDLIST_CANDIDATES:
        path = os.path.join(SCRIPTS_DIR, name)
        if os.path.exists(path):
            return path
    raise SystemExit(
        "Kelime listesi bulunamadı. Beklenen: %s"
        % ", ".join(os.path.join("scripts", n) for n in WORDLIST_CANDIDATES))


def load_wordlist(path):
    """{"word", "hint", "rarity", "note"} sözlüklerini döner. Bilinmeyen alan None.

    Kabul edilen biçimler:
      {"words": [{"word": "kalem", "originHint": "ar<grc", "rarity": "gündelik"}, ...]}
      {"words": ["kalem", ...]}
      [{"word": "kalem"}, ...]  /  ["kalem", ...]
    """
    with open(path, encoding="utf-8") as handle:
        data = json.load(handle)
    if isinstance(data, dict):
        data = data.get("words")
    if not isinstance(data, list):
        raise SystemExit("%s: kelime dizisi bulunamadı." % path)

    def text(value):
        return value.strip() if isinstance(value, str) and value.strip() else None

    words = []
    for item in data:
        if isinstance(item, str):
            word, hint, rarity, note = item, None, None, None
        elif isinstance(item, dict):
            word = item.get("word") or item.get("kelime")
            hint = text(item.get("originHint"))
            rarity = text(item.get("rarity"))
            note = text(item.get("note"))
        else:
            word = hint = rarity = note = None
        if not isinstance(word, str) or not word.strip():
            raise SystemExit("%s: geçersiz kelime girdisi: %r" % (path, item))
        if rarity is not None and rarity not in RARITY:
            raise SystemExit("%s: %s için geçersiz rarity: %r"
                             % (path, word, rarity))
        words.append({"word": word.strip(), "hint": hint, "rarity": rarity,
                      "note": note})
    if not words:
        raise SystemExit("%s: kelime listesi boş." % path)
    return words


def prompt_version(text):
    match = re.search(r"\(v(\d+)\)", text.splitlines()[0] if text else "")
    return "v%s" % match.group(1) if match else "bilinmiyor"


def build_prompt(template, entries):
    lines = []
    for i, entry in enumerate(entries, 1):
        line = "%d. %s" % (i, entry["word"])
        if entry.get("hint"):
            line += " — ipucu: %s" % entry["hint"]
        if entry.get("rarity"):
            line += " — rarity: %s" % entry["rarity"]
        if entry.get("note"):
            line += " — ipucu anlam: %s" % entry["note"]
        lines.append(line)
    prompt = template.replace("{{WORDS}}", "\n".join(lines))
    if "{{SOURCES}}" in prompt:
        prompt = prompt.replace(
            "{{SOURCES}}", build_sources_block([e["word"] for e in entries]))
    return prompt


def _cut(text, limit):
    if not text:
        return None
    text = text.strip()
    return text if len(text) <= limit else text[:limit].rstrip() + "…"


def load_source_record(word):
    path = os.path.join(SOURCES_DIR, "%s.json" % slugify_id(word))
    if not os.path.exists(path):
        return None
    try:
        with open(path, encoding="utf-8") as handle:
            return json.load(handle)
    except (OSError, ValueError):
        return None


def render_source(word, record):
    """Tek kelimenin kaynak özetini markdown olarak üretir."""
    out = ["### %s" % word]
    nis = (record or {}).get("nisanyan") or {}
    tdk = (record or {}).get("tdk") or {}
    kub = (record or {}).get("kubbealti") or {}
    if not nis.get("found") and not tdk.get("found") and not kub.get("found"):
        out.append("")
        out.append("Kaynak kaydı bulunamadı. Bu kelimede genel kurallar geçerlidir: "
                   "bildiğini yaz, bilmediğine `null` koy, uydurma.")
        return "\n".join(out)

    for entry in nis.get("entries") or []:
        out.append("")
        out.append("**Nişanyan — %s**" % entry.get("name", word))
        chain = entry.get("chain") or []
        transmission = [st for st in chain
                        if not COGNATE_RE.search(st.get("relation") or "")]
        cognates = [st for st in chain
                    if COGNATE_RE.search(st.get("relation") or "")]

        def render_step(step):
            langs = " / ".join(step.get("languages") or []) or "?"
            form = step.get("romanizedText") or step.get("originalText") or "?"
            meaning = step.get("definition") or ""
            relation = step.get("relation")
            line = "- %s › %s" % (langs, form)
            if meaning:
                line += " › %s" % meaning
            if relation:
                line += "  [%s]" % relation
            return line

        if transmission:
            out.append("")
            out.append("AKTARIM ZİNCİRİ (eskiden yeniye) — `chain` alanına "
                       "yalnızca bunlar girer:")
            for step in transmission:
                out.append(render_step(step))
        if cognates:
            out.append("")
            out.append("EŞ KÖKENLİLER — **`chain` alanına KOYMA.** Bunlar "
                       "sözcüğün geçtiği yol değil, başka dillerdeki "
                       "akrabalarıdır. İstersen `funFact` ya da `relatives` "
                       "içinde `\"eş köken\"` ilişkisiyle anabilirsin:")
            for step in cognates:
                out.append(render_step(step))
        histories = entry.get("histories") or []
        if histories:
            out.append("")
            out.append("Tanıklıklar (eskiden yeniye):")
            for hist in histories[:HISTORY_MAX]:
                bits = [hist.get("date") or "?"]
                who = " — ".join(x for x in (hist.get("source"), hist.get("book")) if x)
                if who:
                    bits.append(who)
                out.append("- %s" % ", ".join(bits))
                quote = _cut(hist.get("quote"), QUOTE_MAX)
                if quote:
                    out.append("  > %s" % quote)
        note = _cut(entry.get("note"), NOTE_MAX)
        if note:
            out.append("")
            out.append("Not: %s" % note)
        if entry.get("url"):
            out.append("")
            out.append("Bağlantı: %s" % entry["url"])

    for entry in (kub.get("entries") or [])[:2]:
        out.append("")
        out.append("**Kubbealtı Lugatı — %s**" % (entry.get("kelime") or word))
        if entry.get("origin"):
            out.append("")
            out.append("Köken satırı: %s" % entry["origin"])
        if entry.get("meaning"):
            out.append("")
            out.append("İlk anlam: %s" % entry["meaning"])
        if entry.get("url"):
            out.append("")
            out.append("Bağlantı: %s" % entry["url"])

    for entry in (tdk.get("entries") or [])[:1]:
        out.append("")
        bits = []
        if entry.get("lisan"):
            bits.append("köken kaydı: %s" % entry["lisan"])
        meanings = entry.get("meanings") or []
        if meanings:
            bits.append("anlam: %s" % meanings[0])
        out.append("**TDK** — %s" % " · ".join(bits) if bits else "**TDK** — kayıt var")
    return "\n".join(out)


def build_sources_block(words):
    blocks = []
    for word in words:
        blocks.append(render_source(word, load_source_record(word)))
    return "\n\n".join(blocks)


def extract_json_array(text):
    """Codex çıktısından ilk üst düzey JSON diziyi ayıklar.

    Kod bloğu sarmalayıcısını soyar, dizi dışındaki metni atar.
    """
    cleaned = text.strip()
    fence = re.search(r"```(?:json)?\s*(.+?)```", cleaned, re.DOTALL)
    if fence:
        cleaned = fence.group(1).strip()

    start = cleaned.find("[")
    if start == -1:
        raise ValueError("çıktıda JSON dizi başlangıcı ([) yok")

    depth = 0
    in_string = False
    escaped = False
    for i in range(start, len(cleaned)):
        ch = cleaned[i]
        if in_string:
            if escaped:
                escaped = False
            elif ch == "\\":
                escaped = True
            elif ch == '"':
                in_string = False
            continue
        if ch == '"':
            in_string = True
        elif ch == "[":
            depth += 1
        elif ch == "]":
            depth -= 1
            if depth == 0:
                return json.loads(cleaned[start:i + 1])
    raise ValueError("JSON dizi kapanmamış (çıktı kesilmiş olabilir)")


def run_codex(prompt, raw_path, log_path, model, timeout):
    cmd = [
        "codex", "exec",
        "-s", "read-only",
        "--skip-git-repo-check",
        "-C", ROOT_DIR,
        "-m", model,
        "--color", "never",
        "-o", raw_path,
        "-",
    ]
    proc = subprocess.run(
        cmd, input=prompt, capture_output=True, text=True, timeout=timeout)
    with open(log_path, "w", encoding="utf-8") as handle:
        handle.write(proc.stdout or "")
        if proc.stderr:
            handle.write("\n--- stderr ---\n")
            handle.write(proc.stderr)
    return proc


def generate(number, words, template, args):
    tag = "%02d" % number
    out_path = os.path.join(BATCHES_DIR, "%s.json" % tag)
    raw_path = os.path.join(BATCHES_DIR, "%s.raw.txt" % tag)
    log_path = os.path.join(LOG_DIR, "%s.codex.log" % tag)
    meta_path = os.path.join(LOG_DIR, "%s.meta.json" % tag)

    if os.path.exists(out_path) and not args.force and not args.dry_run \
            and not args.only:
        print("%s: zaten var, atlanıyor." % show(out_path))
        return True

    start = (number - 1) * args.size
    chunk = words[start:start + args.size]
    if not chunk:
        print("Parti %d: kelime kalmadı." % number, file=sys.stderr)
        return False

    wanted = None
    if args.only:
        wanted = {slugify_id(w.strip()) for w in args.only.split(",") if w.strip()}
        chunk = [e for e in chunk if slugify_id(e["word"]) in wanted]
        if not chunk:
            print("Parti %s: --only ile eşleşen kelime yok." % tag, file=sys.stderr)
            return False

    chunk_words = [e["word"] for e in chunk]
    prompt = build_prompt(template, chunk)
    if args.dry_run:
        print("--- parti %s: %d kelime (%d-%d) ---"
              % (tag, len(chunk), start + 1, start + len(chunk)))
        print(prompt)
        return True

    os.makedirs(BATCHES_DIR, exist_ok=True)
    os.makedirs(LOG_DIR, exist_ok=True)
    print("Parti %s üretiliyor: %d kelime (%s ...)"
          % (tag, len(chunk), ", ".join(chunk_words[:3])))

    try:
        proc = run_codex(prompt, raw_path, log_path, args.model, args.timeout)
    except subprocess.TimeoutExpired:
        print("Parti %s: codex %d saniyede bitmedi." % (tag, args.timeout),
              file=sys.stderr)
        return False
    except FileNotFoundError:
        raise SystemExit("codex bulunamadı. Codex CLI kurulu mu?")

    if proc.returncode != 0:
        print("Parti %s: codex çıkış kodu %d. Kayıt: %s"
              % (tag, proc.returncode, show(log_path)),
              file=sys.stderr)
        return False

    if not os.path.exists(raw_path):
        print("Parti %s: son mesaj dosyası yazılmadı." % tag, file=sys.stderr)
        return False
    with open(raw_path, encoding="utf-8") as handle:
        raw = handle.read()

    try:
        items = extract_json_array(raw)
    except ValueError as exc:
        print("Parti %s: JSON ayıklanamadı (%s). Ham çıktı: %s"
              % (tag, exc, show(raw_path)), file=sys.stderr)
        return False

    if not isinstance(items, list):
        print("Parti %s: JSON dizi bekleniyordu." % tag, file=sys.stderr)
        return False
    if len(items) != len(chunk):
        print("Parti %s: %d kelime istendi, %d madde geldi. Parti yazılmadı, "
              "ham çıktı incelenmeli: %s"
              % (tag, len(chunk), len(items), show(raw_path)), file=sys.stderr)
        return False

    # id'yi word alanından yeniden üret: doğrulayıcı ile üretici arasındaki
    # tek fark kaynağını baştan kapatır.
    for item in items:
        if isinstance(item, dict) and isinstance(item.get("word"), str) \
                and item["word"].strip():
            item["id"] = slugify_id(item["word"])
    # rarity modelin kanaati değil, kelime listesinin verisidir: her hâlükârda
    # listeden yazılır.
    apply_rarity(items, chunk)
    # Boş bırakılan zincir anlamlarını bir önceki adımdan tamamla.
    fill_chain_meanings(items)
    lowercase_chain_meanings(items)
    normalize_relatives(items)

    if wanted and os.path.exists(out_path):
        # Yeniden üretilen maddeler var olan partiye yerinde işlenir.
        with open(out_path, encoding="utf-8") as handle:
            existing = json.load(handle)
        by_id = {slugify_id(i.get("word") or i.get("id") or ""): i
                 for i in items if isinstance(i, dict)}
        merged, replaced = [], 0
        for old_item in existing:
            key = slugify_id(old_item.get("word") or old_item.get("id") or "")
            if key in by_id:
                merged.append(by_id.pop(key))
                replaced += 1
            else:
                merged.append(old_item)
        merged.extend(by_id.values())
        items = merged
        print("Parti %s: %d madde yenisiyle değiştirildi." % (tag, replaced))

    with open(out_path, "w", encoding="utf-8") as handle:
        json.dump(items, handle, ensure_ascii=False, indent=2)
        handle.write("\n")

    meta = {
        "batch": number,
        "file": show(out_path),
        "promptVersion": prompt_version(open(PROMPT_PATH, encoding="utf-8").read()),
        "promptFile": show(PROMPT_PATH),
        "model": args.model,
        "generatedAt": datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
        "requestedWords": chunk_words,
        "originHints": {e["word"]: e["hint"] for e in chunk if e["hint"]},
        "rarity": {e["word"]: e["rarity"] for e in chunk if e["rarity"]},
        "notes": {e["word"]: e["note"] for e in chunk if e["note"]},
        "requestedCount": len(chunk),
        "returnedCount": len(items),
        "rawFile": show(raw_path),
        "logFile": show(log_path),
    }
    with open(meta_path, "w", encoding="utf-8") as handle:
        json.dump(meta, handle, ensure_ascii=False, indent=2)
        handle.write("\n")

    print("Parti %s yazıldı: %d madde → %s"
          % (tag, len(items), show(out_path)))
    return True


def apply_rarity(items, entries):
    """rarity alanını kelime listesinden maddelere yazar. Kaç madde değişti döner."""
    by_id = {}
    for entry in entries:
        if entry.get("rarity"):
            by_id[slugify_id(entry["word"])] = entry["rarity"]
    changed = missing = 0
    for item in items:
        if not isinstance(item, dict):
            continue
        word = item.get("word") or item.get("id") or ""
        rarity = by_id.get(slugify_id(word))
        if rarity is None:
            missing += 1
            continue
        if item.get("rarity") != rarity:
            item["rarity"] = rarity
            changed += 1
    return changed, missing


def fill_chain_meanings(items):
    """chain[].meaning boşsa bir önceki adımın anlamını yazar.

    İlk adım boşsa ileriye bakıp ilk dolu anlamı alır. Hiçbir adımda anlam
    yoksa dokunmaz; doğrulayıcı yakalar.
    """
    filled = 0
    for item in items:
        if not isinstance(item, dict):
            continue
        chain = item.get("chain")
        if not isinstance(chain, list):
            continue
        steps = [st for st in chain if isinstance(st, dict)]
        previous = None
        for step in steps:
            meaning = step.get("meaning")
            if isinstance(meaning, str) and meaning.strip():
                previous = meaning.strip()
            elif previous is not None:
                step["meaning"] = previous
                filled += 1
        # İlk adımlar boş kaldıysa ilk dolu anlamla geriye doğru doldur.
        first_filled = next((st["meaning"] for st in steps
                             if isinstance(st.get("meaning"), str)
                             and st["meaning"].strip()), None)
        if first_filled is None:
            continue
        for step in steps:
            meaning = step.get("meaning")
            if isinstance(meaning, str) and meaning.strip():
                break
            step["meaning"] = first_filled
            filled += 1
    return filled


_LOWER_MAP = str.maketrans({"İ": "i", "I": "ı"})


def lowercase_chain_meanings(items):
    """Zincir anlamlarının baş harfini küçültür — ama hep ya da hiç.

    Anlamların **tamamı** büyük harfle başlıyorsa bu bir biçim tercihidir ve
    küçültülür. Birkaçı büyükse bunlar özel addır (Rosa, Tulipa, İran) ve
    dokunulmaz.
    """
    meanings = [st for item in items if isinstance(item, dict)
                for st in item.get("chain") or []
                if isinstance(st, dict) and isinstance(st.get("meaning"), str)
                and st["meaning"].strip()]
    if len(meanings) < 2:
        return 0
    if not all(st["meaning"][0].isupper() for st in meanings):
        return 0
    for st in meanings:
        text = st["meaning"]
        st["meaning"] = text[0].translate(_LOWER_MAP).lower() + text[1:]
    return len(meanings)


def normalize_relatives(items):
    """relatives her zaman dizidir; null olanları boş diziye çevirir."""
    changed = 0
    for item in items:
        if isinstance(item, dict) and item.get("relatives") is None:
            item["relatives"] = []
            changed += 1
    return changed


def repair_batches(batches_dir, entries, do_rarity, do_meanings, do_lowercase,
                   do_relatives):
    """Var olan parti dosyalarını yerinde onarır (tek seferlik komutlar)."""
    paths = sorted(glob.glob(os.path.join(batches_dir, "*.json")))
    if not paths:
        raise SystemExit("%s içinde parti dosyası yok." % batches_dir)
    total_rarity = total_meanings = total_lowered = 0
    total_relatives = total_missing = 0
    for path in paths:
        with open(path, encoding="utf-8") as handle:
            items = json.load(handle)
        if not isinstance(items, list):
            print("%s: JSON dizi değil, atlandı." % show(path), file=sys.stderr)
            continue
        changed = missing = meanings = lowered = relatives = 0
        if do_rarity:
            changed, missing = apply_rarity(items, entries)
        if do_meanings:
            meanings = fill_chain_meanings(items)
        if do_lowercase:
            lowered = lowercase_chain_meanings(items)
        if do_relatives:
            relatives = normalize_relatives(items)
        if changed or meanings or lowered or relatives:
            with open(path, "w", encoding="utf-8") as handle:
                json.dump(items, handle, ensure_ascii=False, indent=2)
                handle.write("\n")
        total_rarity += changed
        total_meanings += meanings
        total_lowered += lowered
        total_relatives += relatives
        total_missing += missing
        bits = []
        if do_rarity:
            bits.append("%d rarity" % changed)
        if do_meanings:
            bits.append("%d anlam" % meanings)
        if do_lowercase:
            bits.append("%d küçültme" % lowered)
        if do_relatives:
            bits.append("%d relatives" % relatives)
        if missing:
            bits.append("%d madde listede yok" % missing)
        print("%s: %s" % (show(path), ", ".join(bits)))
    print("\nToplam: %d rarity, %d anlam, %d baş harf, %d relatives güncellendi."
          % (total_rarity, total_meanings, total_lowered, total_relatives))
    if total_missing:
        print("%d madde kelime listesinde bulunamadı, rarity yazılmadı."
              % total_missing, file=sys.stderr)
        return 1
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Köken içerik partisi üretir (codex exec).")
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--batch", type=int, metavar="N",
                       help="Üretilecek parti numarası (1 tabanlı).")
    group.add_argument("--all", action="store_true",
                       help="Tüm partileri sırayla üretir, var olanları atlar.")
    group.add_argument("--rarity-from-wordlist", action="store_true",
                       help="Üretim yapmaz; var olan parti dosyalarına rarity "
                            "alanını kelime listesinden yazar (tek seferlik).")
    group.add_argument("--fill-chain-meanings", action="store_true",
                       help="Üretim yapmaz; var olan parti dosyalarında boş "
                            "chain[].meaning alanlarını doldurur.")
    group.add_argument("--lowercase-chain-meanings", action="store_true",
                       help="Üretim yapmaz; tamamı büyük harfle başlayan "
                            "chain[].meaning alanlarının baş harfini küçültür.")
    group.add_argument("--normalize-relatives", action="store_true",
                       help="Üretim yapmaz; relatives null olan maddelere boş "
                            "dizi yazar.")
    parser.add_argument("--wordlist", metavar="DOSYA",
                        help="Kelime listesi (varsayılan: scripts/wordlist.json).")
    parser.add_argument("--size", type=int, default=DEFAULT_SIZE,
                        help="Parti boyutu (varsayılan: %d)." % DEFAULT_SIZE)
    parser.add_argument("--model", default=DEFAULT_MODEL,
                        help="Codex modeli (varsayılan: %s)." % DEFAULT_MODEL)
    parser.add_argument("--timeout", type=int, default=1800,
                        help="Parti başına saniye sınırı (varsayılan: 1800).")
    parser.add_argument("--only", metavar="KELİMELER",
                        help="Partideki yalnızca bu kelimeleri üretir "
                             "(virgülle ayrılmış id/kelime); sonuç var olan "
                             "parti dosyasına işlenir.")
    parser.add_argument("--force", action="store_true",
                        help="Var olan parti dosyasının üzerine yazar.")
    parser.add_argument("--dry-run", action="store_true",
                        help="Codex'i çağırmaz, dolu prompt'u yazdırır.")
    args = parser.parse_args(argv)

    if args.size < 1:
        raise SystemExit("--size en az 1 olmalı.")

    wordlist_path = find_wordlist(args.wordlist)
    words = load_wordlist(wordlist_path)
    with open(PROMPT_PATH, encoding="utf-8") as handle:
        template = handle.read()
    if "{{WORDS}}" not in template:
        raise SystemExit("%s: {{WORDS}} yer tutucusu yok." % PROMPT_PATH)

    total = (len(words) + args.size - 1) // args.size
    print("Kelime listesi: %s (%d kelime, %d parti)"
          % (show(wordlist_path), len(words), total))

    if args.rarity_from_wordlist or args.fill_chain_meanings \
            or args.lowercase_chain_meanings or args.normalize_relatives:
        if args.rarity_from_wordlist and not any(e["rarity"] for e in words):
            raise SystemExit("Kelime listesinde rarity alanı yok.")
        return repair_batches(BATCHES_DIR, words,
                              do_rarity=args.rarity_from_wordlist,
                              do_meanings=args.fill_chain_meanings,
                              do_lowercase=args.lowercase_chain_meanings,
                              do_relatives=args.normalize_relatives)

    if args.all:
        numbers = range(1, total + 1)
    else:
        if not 1 <= args.batch <= total:
            raise SystemExit("--batch 1 ile %d arasında olmalı." % total)
        numbers = [args.batch]

    failed = []
    for number in numbers:
        if not generate(number, words, template, args):
            failed.append(number)
            if not args.all:
                return 1
    if failed:
        print("Başarısız partiler: %s"
              % ", ".join("%02d" % n for n in failed), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
