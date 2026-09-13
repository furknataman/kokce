#!/usr/bin/env python3
"""build_schedule_ids sözleşmesinin testi: takvim yalnızca sona eklenir.

Çalıştır: python3 scripts/tests/schedule_order_test.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from build_words import build_schedule_ids  # noqa: E402


def make(prefix, count, rarity, store):
    ids = []
    for i in range(count):
        wid = "%s%03d" % (prefix, i)
        store[wid] = rarity
        ids.append(wid)
    return ids


def main():
    rarity = {}
    old_daily = make("g", 250, "gündelik", rarity)
    old_rare = make("a", 288, "az-bilinen", rarity)
    existing = build_schedule_ids([], old_daily + old_rare, rarity)
    assert len(existing) == 538, len(existing)

    # 282 yeni az-bilinen kelime eklenir.
    fresh = make("y", 282, "az-bilinen", rarity)
    grown = build_schedule_ids(existing, old_daily + old_rare + fresh, rarity)

    assert len(grown) == 820, len(grown)
    assert grown[:538] == existing, "mevcut 538 id'nin sırası değişti"
    assert set(grown[538:]) == set(fresh), "yeni id'ler sona eklenmedi"
    assert len(set(grown)) == len(grown), "yinelenen id"

    # Sabit tohum: aynı girdi aynı çıktıyı verir.
    again = build_schedule_ids(existing, old_daily + old_rare + fresh, rarity)
    assert again == grown, "sonuç deterministik değil"

    # Düşen id çıkarılır, kalanların göreli sırası korunur.
    kept_ids = [i for i in old_daily + old_rare if i not in ("g005", "a007")]
    shrunk = build_schedule_ids(existing, kept_ids, rarity)
    survivors = [i for i in existing if i in set(kept_ids)]
    assert shrunk == survivors, "düşen id sonrası sıra korunmadı"

    print("schedule_order_test: 5 doğrulama geçti "
          "(538 id sabit, 282 yeni id sona eklendi).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
