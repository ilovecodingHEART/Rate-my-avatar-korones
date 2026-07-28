#!/usr/bin/env python3
"""Draw the admin panel from the numbers in the source, as a PNG.

Not a renderer. It draws each widget's rectangle and label at the position the
layout maths puts it, which is enough to see a collision or a squashed row
without opening Studio. Colours are pulled from the THEME table so it reads
like the real panel rather than a wireframe.
"""
import re
import sys

sys.path.insert(0, "tools")
from checklayout import (  # noqa: E402
    SCREEN_W, SCREEN_H, PAGES, NESTED, constants, parse_block,
)

try:
    from PIL import Image, ImageDraw
except ImportError:
    print("needs pillow:  pip install --break-system-packages pillow")
    raise SystemExit(1)


def theme(src):
    """The THEME table, so the preview matches the real palette."""
    out = {}
    block = re.search(r"local THEME = \{(.*?)\n\}", src, re.S)
    if block:
        for m in re.finditer(
                r"(\w+)\s*=\s*Color3\.fromRGB\((\d+),\s*(\d+),\s*(\d+)\)",
                block.group(1)):
            out[m.group(1)] = (int(m.group(2)), int(m.group(3)), int(m.group(4)))
    return out


def draw(path, page, out_path):
    src = open(path, encoding="utf8").read()
    consts = constants(src)
    T = theme(src)

    bg = T.get("PanelBackground", (12, 12, 14))
    card = T.get("CardBackground", (22, 23, 27))
    idle = T.get("TabIdle", (20, 21, 25))
    text = T.get("Text", (236, 238, 242))
    muted = T.get("MutedText", (150, 156, 166))
    outline = (0, 0, 0)

    img = Image.new("RGB", (SCREEN_W, SCREEN_H), (60, 70, 85))
    d = ImageDraw.Draw(img)

    def box(rect, fill, label=None, colour=None, width=3):
        x, y, w, h = rect
        d.rectangle([x, y, x + w, y + h], fill=fill, outline=outline, width=width)
        if label:
            d.text((x + 6, y + 4), label, fill=colour or text)

    frame = parse_block(src, "AdminFrame", consts)
    frect = frame.rect(SCREEN_W, SCREEN_H, 0, 0)
    fx, fy, fw, fh = frect
    box(frect, bg, None, width=4)

    title = parse_block(src, "AdminTitle", consts)
    if title.size:
        tx, ty, tw, th = title.rect(fw, fh, fx, fy)
        d.text((tx + tw / 2 - 60, ty + th / 2 - 6), "Admin  -  " + page, fill=text)

    # Greeting card and its contents.
    greet = parse_block(src, "Greet", consts)
    if greet.size:
        grect = greet.rect(fw, fh, fx, fy)
        box(grect, card)
        gx, gy, gw, gh = grect
        for name, label, colour in (
                ("GreetImage", "", muted),
                ("GreetHello", "Hello, qzc.", text),
                ("GreetRank", "Admin", T.get("AdminBadge", muted))):
            b = parse_block(src, name, consts)
            if not b.size:
                continue
            r = b.rect(gw, gh, gx, gy)
            if name == "GreetImage":
                d.ellipse([r[0], r[1], r[0] + r[2], r[1] + r[3]],
                          fill=T.get("InputBackground", (24, 25, 29)),
                          outline=outline, width=2)
                d.text((r[0] + r[2] / 2 - 4, r[1] + r[3] / 2 - 6), "Q", fill=muted)
            else:
                d.text((r[0] + 2, r[1] + r[3] / 2 - 6), label, fill=colour)

    # Sidebar.
    nav = parse_block(src, "PageNav", consts)
    if nav.size:
        nx, ny, nw, nh = nav.rect(fw, fh, fx, fy)
        for i, name in enumerate(
                ["Home", "Players", "Reports", "Staff", "Shop", "Trolling"]):
            bh = nh * 0.14
            by = ny + i * (bh + nh * 0.025)
            active = (name == page)
            box((nx + nw * 0.03, by, nw * 0.94, bh),
                T.get("TabActive", (34, 36, 42)) if active else idle,
                None, width=4 if active else 3)
            d.text((nx + nw * 0.5 - 18, by + bh / 2 - 6), name,
                   fill=text if active else muted)

    host = parse_block(src, "PageHost", consts)
    hx, hy, hw, hh = host.rect(fw, fh, fx, fy)

    # The selected page's own widgets.
    labels = {
        "HomeBlurb": "You are Admin. Every button here has a chat command..",
        "HomeStats": "",
        "HomeInput": "Message, or a number for Set Time..",
        "HomeActions": "",
        "PlayerList": "player list",
        "PlayerActions": "",
        "ReportList": "report queue",
        "StaffList": "staff list",
        "StaffSide": "",
        "TrollList": "player list",
        "TrollSide": "",
        "AdminList": "passes",
        "NewButton": "+ New Gamepass",
        "Editor": "",
    }

    for name in PAGES[page]:
        b = parse_block(src, name, consts)
        if not b.size:
            continue
        r = b.rect(hw, hh, hx, hy)
        fill = card if name.endswith("List") or name == "HomeInput" else idle
        if name in ("HomeStats", "HomeActions", "PlayerActions", "StaffSide",
                    "Editor", "TrollSide"):
            fill = None
            d.rectangle([r[0], r[1], r[0] + r[2], r[1] + r[3]],
                        outline=(70, 75, 85), width=1)
        else:
            box(r, fill, labels.get(name, name), muted)

        if name == "HomeStats":
            for i, cap in enumerate(("1  In server", "0  Open reports", "0  Booths claimed")):
                cw = r[2] * 0.31
                cx = r[0] + i * (cw + r[2] * 0.025)
                box((cx, r[1], cw, r[3]), card)
                d.text((cx + 10, r[1] + r[3] / 2 - 6), cap, fill=text)

        if name == "HomeActions":
            names = ["Announce", "Set Time", "Lock Server", "Unlock Server", "Reset Booths"]
            n, pad = 5, 0.015
            cell = (1 - pad * (n + 1)) / n
            for i, cap in enumerate(names):
                cw = r[2] * cell
                cx = r[0] + r[2] * pad + i * (cw + r[2] * pad)
                ch = r[3] * 0.86
                danger = cap.startswith("Reset")
                box((cx, r[1], cw, ch),
                    T.get("DangerBackground", (34, 22, 24)) if danger else (30, 32, 37))
                d.text((cx + 6, r[1] + ch / 2 - 6), cap,
                       fill=T.get("DangerText", text) if danger else text)

        for holder, kids in NESTED.items():
            if holder == name:
                for kid in kids:
                    kb = parse_block(src, kid, consts)
                    if not kb.size:
                        continue
                    kr = kb.rect(r[2], r[3], r[0], r[1])
                    box(kr, idle, kid, muted, width=2)

    # HUD buttons down the left.
    toggle_size = (0.107, 0, 0.071, 0)
    for i, cap in enumerate(("Booth Menu", "Shop", "Admin", "Report")):
        bw = toggle_size[0] * SCREEN_W
        bh = toggle_size[2] * SCREEN_H
        bx = 0.007 * SCREEN_W
        by = (0.550 - 0.085 * i) * SCREEN_H
        box((bx, by, bw, bh), bg)
        d.text((bx + 8, by + bh / 2 - 6), cap, fill=text)

    img.save(out_path)
    print("wrote " + out_path)


if __name__ == "__main__":
    page = sys.argv[1] if len(sys.argv) > 1 else "Home"
    draw("src/Client.client.lua", page, "/tmp/panel_%s.png" % page.lower())
