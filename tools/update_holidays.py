#!/usr/bin/env python3
"""刷新内置节假日数据。

数据源：timor.tech 的公开 API（整理自国务院办公厅每年发布的节假日安排通知）。
用法：python3 tools/update_holidays.py [年份...]   默认刷 2025 2026 2027

注意：国务院一般在**前一年 11 月左右**公布次年安排。查不到就是还没发布，
不是脚本坏了 —— 输出里会显示该年 0 条。
"""
import json
import sys
import urllib.request

YEARS = [int(a) for a in sys.argv[1:]] or [2025, 2026, 2027]
OUT = "Kebiaobao/Resources/holidays.json"


def fetch(year: int) -> dict:
    req = urllib.request.Request(
        f"https://timor.tech/api/holiday/year/{year}",
        headers={"User-Agent": "Mozilla/5.0"},
    )
    return json.load(urllib.request.urlopen(req, timeout=25)).get("holiday") or {}


def main() -> None:
    table = {}
    for y in YEARS:
        try:
            got = fetch(y)
        except Exception as e:                      # 网络/接口异常不致命，保留旧数据
            print(f"{y}: 抓取失败 {e}")
            continue
        for v in got.values():
            table[v["date"]] = {
                "holiday": bool(v["holiday"]),
                "name": v.get("name", ""),
                "target": v.get("target") or "",
            }
        print(f"{y}: {len(got)} 条")

    if not table:
        sys.exit("一条都没拿到，未写入（避免清空已有数据）")

    # 合并：保留已有但本次没抓到的年份（例如接口临时缺 2027）
    try:
        old = json.load(open(OUT, encoding="utf-8"))
        table = {**old, **table}
    except FileNotFoundError:
        pass

    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(table, f, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    years = sorted({k[:4] for k in table})
    print(f"写入 {OUT}：{len(table)} 条，覆盖 {','.join(years)}")


if __name__ == "__main__":
    main()
