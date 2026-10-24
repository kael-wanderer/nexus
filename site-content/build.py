"""Build Nexus-page.md and Nexus-sections.json from page_data.py, and check every limit.

    python3 site-content/build.py

Exits non-zero, writing nothing, if any field is over its limit or a picture is missing."""

import json
import os
import re
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from page_data import CATALOG, FAQ, FEATURES, QUESTIONS, RELEASE, SCREENSHOTS  # noqa: E402

BANNED = ["revolutionary", "seamless", "supercharge"]
errors = []


def check(label, text, limit):
    n = len(text)
    if n > limit:
        errors.append(f"{label}: {n} > {limit}")
    for word in BANNED:
        if word in text.lower():
            errors.append(f"{label}: banned word '{word}'")
    return n


def counted(label, text, limit):
    return f"{text}  `({check(label, text, limit)}/{limit})`"


def png_size(path):
    with open(path, "rb") as f:
        head = f.read(24)
    return struct.unpack(">II", head[16:24])


# Catalog
check("summary", CATALOG["summary"], 200)
check("requirements", CATALOG["requirements"], 80)
details_len = len(CATALOG["details"])
if not 300 <= details_len <= 600:
    errors.append(f"details: {details_len} not in 300-600")
if not 3 <= len(CATALOG["tags"]) <= 6:
    errors.append("tags: need 3-6")
if not re.fullmatch(r"#[0-9A-Fa-f]{6}", CATALOG["accent"]):
    errors.append("accent: not a hex colour")

# Screenshots
shots = {name for name, _ in SCREENSHOTS}
if not 6 <= len(SCREENSHOTS) <= 10:
    errors.append("screenshots: need 6-10")
for name, label in SCREENSHOTS:
    check(f"label {name}", label, 60)
    path = os.path.join(HERE, "screenshots", name)
    if not os.path.exists(path):
        errors.append(f"{name}: missing")
    elif os.path.getsize(path) >= 12 * 1024 * 1024:
        errors.append(f"{name}: 12 MB or larger")

# Feature sections
if not 3 <= len(FEATURES) <= 6:
    errors.append("features: need 3-6 sections")
for i, s in enumerate(FEATURES, 1):
    p = f"section {i}"
    if s["background"] not in ("plain", "tint", "dark"):
        errors.append(f"{p}: bad background")
    if i > 1 and s["background"] == FEATURES[i - 2]["background"]:
        errors.append(f"{p}: same background as the section before")
    check(f"{p} kicker", s["kicker"], 40)
    check(f"{p} title", s["title"], 70)
    check(f"{p} description", s["description"], 320)
    if s["layout"] == "split":
        if len(s["bullets"]) > 5:
            errors.append(f"{p}: more than 5 bullets")
        for j, b in enumerate(s["bullets"], 1):
            check(f"{p} bullet {j}", b, 120)
        if s["side"] not in ("left", "right"):
            errors.append(f"{p}: bad side")
        pics = s["media"]["pictures"]
        if not 1 <= len(pics) <= 2 or any(x not in shots for x in pics):
            errors.append(f"{p}: media must be 1-2 known screenshots")
    elif s["layout"] == "showcase":
        if not 2 <= len(s["tiles"]) <= 4:
            errors.append(f"{p}: need 2-4 tiles")
        for j, t in enumerate(s["tiles"], 1):
            check(f"{p} tile {j} title", t["title"], 40)
            check(f"{p} tile {j} caption", t["caption"], 120)
            if t["picture"] not in shots:
                errors.append(f"{p} tile {j}: unknown picture")
    elif s["layout"] == "cards":
        if not 2 <= len(s["cards"]) <= 6:
            errors.append(f"{p}: need 2-6 cards")
        for j, c in enumerate(s["cards"], 1):
            check(f"{p} card {j} title", c["title"], 40)
            check(f"{p} card {j} text", c["text"], 200)
    else:
        errors.append(f"{p}: unknown layout")
sides = [s["side"] for s in FEATURES if s["layout"] == "split"]
if any(a == b for a, b in zip(sides, sides[1:])):
    errors.append("split sections do not alternate sides")

# FAQ
if not 6 <= len(FAQ) <= 12:
    errors.append("faq: need 6-12 items")
for i, (q, a) in enumerate(FAQ, 1):
    check(f"faq {i} question", q, 120)
    check(f"faq {i} answer", a, 600)

if not 3 <= len(RELEASE["whats_new"]) <= 6:
    errors.append("release: need 3-6 bullets")
for i, b in enumerate(RELEASE["whats_new"], 1):
    check(f"release bullet {i}", b, 600)


# Accent contrast, reported in the questions
def luminance(hex_colour):
    channels = [int(hex_colour[i : i + 2], 16) / 255 for i in (1, 3, 5)]
    lin = [c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4 for c in channels]
    return 0.2126 * lin[0] + 0.7152 * lin[1] + 0.0722 * lin[2]


def contrast(a, b):
    la, lb = sorted((luminance(a), luminance(b)), reverse=True)
    return (la + 0.05) / (lb + 0.05)


if errors:
    print("FAILED")
    for e in errors:
        print("  " + e)
    sys.exit(1)

# JSON
sections = {"requirements": CATALOG["requirements"], "features": FEATURES,
            "faq": [{"question": q, "answer": a} for q, a in FAQ]}
with open(os.path.join(HERE, "Nexus-sections.json"), "w") as f:
    json.dump(sections, f, ensure_ascii=False, indent=2)
    f.write("\n")

# Markdown
c = CATALOG
md = ["# Nexus — product page copy", "",
      "Source of truth: `page_data.py`. Rebuild and re-check with `python3 site-content/build.py`.",
      "Counts are characters; the figure after the slash is the admin's limit.", "",
      "## Catalog fields", "",
      f"- **Name:** {c['name']}",
      "- **Pronunciation:** — (left blank; see questions)",
      f"- **Summary / tagline:** {counted('summary', c['summary'], 200)}",
      f"- **Details:** {c['details']}  `({len(c['details'])}, target 300–600)`",
      f"- **Category:** {c['category']}",
      f"- **Tags:** {', '.join(c['tags'])}",
      f"- **Platform / OS:** {c['platform']}",
      f"- **License:** {c['license']}",
      f"- **Requirements:** {counted('requirements', c['requirements'], 80)}",
      f"- **Accent colour:** `{c['accent']}` — a darker shade of the icon's gold star (#E1AD66) "
      f"(white text on it: {contrast(c['accent'], '#FFFFFF'):.1f}:1)", "",
      "## Screenshots", "",
      "All 2880 × 1800 px PNG (1440 × 900 pt at 2×), in `screenshots/`.", "",
      "| File | Label |", "|---|---|"]
for name, label in SCREENSHOTS:
    md.append(f"| `{name}` | {counted('label', label, 60)} |")
md += ["", "## Feature sections", ""]
for i, s in enumerate(FEATURES, 1):
    md += [f"### {i}. {s['kicker']} — `{s['layout']}`, background `{s['background']}`"
           + (f", side `{s['side']}`" if s["layout"] == "split" else "")
           + (f", numbered `{'yes' if s['numbered'] else 'no'}`" if s["layout"] == "cards" else ""), "",
           f"- **Kicker:** {counted('k', s['kicker'], 40)}",
           f"- **Title:** {counted('t', s['title'], 70)}",
           f"- **Description:** {counted('d', s['description'], 320)}"]
    if s["layout"] == "split":
        md.append("- **Bullets:**")
        md += [f"  {j}. {counted('b', b, 120)}" for j, b in enumerate(s["bullets"], 1)]
        md.append(f"- **Media:** {', '.join('`' + p + '`' for p in s['media']['pictures'])}")
    elif s["layout"] == "showcase":
        md.append("- **Tiles:**")
        for j, t in enumerate(s["tiles"], 1):
            md += [f"  {j}. **{counted('tt', t['title'], 40)}** — picture `{t['picture']}`",
                   f"     Caption: {counted('tc', t['caption'], 120)}"]
    else:
        md.append("- **Cards:**")
        for j, cd in enumerate(s["cards"], 1):
            md += [f"  {j}. **{counted('ct', cd['title'], 40)}**",
                   f"     {counted('cx', cd['text'], 200)}"]
    md.append("")
md += ["## FAQ", ""]
for i, (q, a) in enumerate(FAQ, 1):
    md += [f"{i}. **{counted('q', q, 120)}**", f"   {counted('a', a, 600)}", ""]
md += ["## Release note", "",
       f"**Version {RELEASE['version']}** (build {RELEASE['build']}, {RELEASE['date']})", "",
       "What's new:", ""]
md += [f"- {b}" for b in RELEASE["whats_new"]]
md += ["", "## Questions for owner", ""]
md += [f"{i}. {q}" for i, q in enumerate(QUESTIONS, 1)]
md.append("")
with open(os.path.join(HERE, "Nexus-page.md"), "w") as f:
    f.write("\n".join(md))

print("OK — every field within its limit")
for name, _ in SCREENSHOTS:
    path = os.path.join(HERE, "screenshots", name)
    w, h = png_size(path)
    print(f"  {name}: {w}x{h}, {os.path.getsize(path) / 1e6:.1f} MB")
print(f"  accent {c['accent']} vs white: {contrast(c['accent'], '#FFFFFF'):.2f}:1; "
      f"#8A5A1C vs white: {contrast('#8A5A1C', '#FFFFFF'):.2f}:1")
