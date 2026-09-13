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
import json
import os
import re
import subprocess
import sys

from validate_words import slugify_id

SCRIPTS_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR = os.path.dirname(SCRIPTS_DIR)
BATCHES_DIR = os.path.join(SCRIPTS_DIR, "batches")
LOG_DIR = os.path.join(SCRIPTS_DIR, "log")
PROMPT_PATH = os.path.join(SCRIPTS_DIR, "prompts", "generate_batch.md")
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
    """(kelime, originHint) çiftlerini döner. İpucu yoksa None.

    Kabul edilen biçimler:
      {"words": [{"word": "kalem", "originHint": "ar<grc"}, ...]}
      {"words": ["kalem", ...]}
      [{"word": "kalem"}, ...]  /  ["kalem", ...]
    """
    with open(path, encoding="utf-8") as handle:
        data = json.load(handle)
    if isinstance(data, dict):
        data = data.get("words")
    if not isinstance(data, list):
        raise SystemExit("%s: kelime dizisi bulunamadı." % path)

    words = []
    for item in data:
        hint = None
        if isinstance(item, str):
            word = item
        elif isinstance(item, dict):
            word = item.get("word") or item.get("kelime")
            hint = item.get("originHint")
            if not isinstance(hint, str) or not hint.strip():
                hint = None
            else:
                hint = hint.strip()
        else:
            word = None
        if not isinstance(word, str) or not word.strip():
            raise SystemExit("%s: geçersiz kelime girdisi: %r" % (path, item))
        words.append((word.strip(), hint))
    if not words:
        raise SystemExit("%s: kelime listesi boş." % path)
    return words


def prompt_version(text):
    match = re.search(r"\(v(\d+)\)", text.splitlines()[0] if text else "")
    return "v%s" % match.group(1) if match else "bilinmiyor"


def build_prompt(template, entries):
    lines = []
    for i, (word, hint) in enumerate(entries, 1):
        if hint:
            lines.append("%d. %s — ipucu: %s" % (i, word, hint))
        else:
            lines.append("%d. %s" % (i, word))
    return template.replace("{{WORDS}}", "\n".join(lines))


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

    if os.path.exists(out_path) and not args.force:
        print("%s: zaten var, atlanıyor." % show(out_path))
        return True

    start = (number - 1) * args.size
    chunk = words[start:start + args.size]
    if not chunk:
        print("Parti %d: kelime kalmadı." % number, file=sys.stderr)
        return False

    chunk_words = [word for word, _hint in chunk]
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
        "originHints": {word: hint for word, hint in chunk if hint},
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


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Köken içerik partisi üretir (codex exec).")
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--batch", type=int, metavar="N",
                       help="Üretilecek parti numarası (1 tabanlı).")
    group.add_argument("--all", action="store_true",
                       help="Tüm partileri sırayla üretir, var olanları atlar.")
    parser.add_argument("--wordlist", metavar="DOSYA",
                        help="Kelime listesi (varsayılan: scripts/wordlist.json).")
    parser.add_argument("--size", type=int, default=DEFAULT_SIZE,
                        help="Parti boyutu (varsayılan: %d)." % DEFAULT_SIZE)
    parser.add_argument("--model", default=DEFAULT_MODEL,
                        help="Codex modeli (varsayılan: %s)." % DEFAULT_MODEL)
    parser.add_argument("--timeout", type=int, default=1800,
                        help="Parti başına saniye sınırı (varsayılan: 1800).")
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
