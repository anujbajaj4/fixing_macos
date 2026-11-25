"""Turns downloads.csv (date,version,dmg,installer; one row per release per day) into a
Markdown summary: totals, change over a day and a week, per-version counts, a sparkline.
Usage: python3 scripts/stats_summary.py downloads.csv > README.md"""
import csv
import sys
from collections import defaultdict

rows = list(csv.DictReader(open(sys.argv[1])))
by_day = defaultdict(lambda: {"dmg": 0, "installer": 0, "versions": {}})
for r in rows:
    d = by_day[r["date"]]
    d["dmg"] += int(r["dmg"])
    d["installer"] += int(r["installer"])
    d["versions"][r["version"]] = int(r["dmg"])
days = sorted(by_day)
print("# MC Close downloads\n")
if not days:
    print("No data yet.")
    sys.exit()
today = by_day[days[-1]]


def ago(n):
    return by_day[days[-1 - n]]["dmg"] if len(days) > n else None


def change(n):
    old = ago(n)
    return "n/a" if old is None else f"+{today['dmg'] - old}"


print(f"Updated {days[-1]} (UTC), recorded once a day by `.github/workflows/stats.yml`.\n")
print("| | App (.dmg) downloads |")
print("|---|---|")
print(f"| Total | **{today['dmg']}** |")
print(f"| Since yesterday | {change(1)} |")
print(f"| Last 7 days | {change(7)} |")
print(f"| Installer script fetched | {today['installer']} |\n")
blocks = "▁▂▃▄▅▆▇█"
totals = [by_day[d]["dmg"] for d in days][-60:]
daily = [b - a for a, b in zip(totals, totals[1:])] or [0]
top = max(daily) or 1
print("New downloads per day, last 60 days: `" + "".join(blocks[min(7, v * 7 // top)] for v in daily) + "`\n")
print("## By version\n")
print("| Version | Downloads |")
print("|---|---|")
for v, n in sorted(today["versions"].items(), key=lambda kv: [int(x) if x.isdigit() else 0 for x in kv[0].lstrip("v").split(".")], reverse=True):
    print(f"| {v} | {n} |")
print("\n## What these numbers mean\n")
print("- Every install or update downloads the .dmg once: the Terminal command, the in-app updater and a browser download all count.")
print("- They're a lower bound for people (one person can install several times) and an upper bound for new users.")
print("- They include test downloads by the author. Copies shared by AirDrop or a USB stick aren't counted.")
print("- The raw numbers are in `downloads.csv`.")
