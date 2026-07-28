#!/usr/bin/env python3
"""Work out where every panel widget actually lands, and complain about it.

The client builds its UI in code, so nothing in the .rbxl says what the panel
looks like. This reads the Size/Position/AnchorPoint numbers as written in the
source, resolves them against their parents, and turns the whole panel into
pixel rectangles on a reference screen.

It then flags what is wrong but hard to see when you are reading scale factors
one line at a time:

  * two widgets in the same parent sitting on top of each other
  * a child sticking out past its parent
  * a widget too short to render its text legibly

Scale factors compose, so a row that looks fine as "0.335 down the page" can
still land on top of the one above it once both are multiplied by the same
parent height. That is exactly the bug this is here to catch.
"""
import re
import sys

# A 16:9 window, which is what the screenshots come from. The layout is checked
# at this size and again at the panel's minimum, because the bug that started
# all this only showed up once everything had scaled down.
SCREEN_W, SCREEN_H = 1280, 720

# Scale fields may be a plain number or a small expression built from named
# constants, e.g. `1 - GREET_TEXT_X - 0.04`. Both have to be readable here or
# the widget is silently skipped and its overlap never checked.
TERM = r"[-\w.\s+*/()]+?"
UDIM2 = re.compile(
    r"UDim2\.new\(\s*(%s)\s*,\s*(%s)\s*,\s*(%s)\s*,\s*(%s)\s*\)"
    % (TERM, TERM, TERM, TERM)
)
VECTOR2 = re.compile(r"Vector2\.new\(\s*([-\d.]+)\s*,\s*([-\d.]+)\s*\)")

# Anything shorter than this cannot show a line of text without clipping.
MIN_TEXT_HEIGHT = 22

#[[
#   Which widget lives inside which, and which siblings are laid out by hand
#   rather than by a UIListLayout. Only hand placed siblings can collide, so
#   only those are checked against each other.
#]]
PANEL = {
    "AdminFrame": {
        "children": ["Greet", "PageNav", "PageHost", "AdminStatus"],
        # Drawn outside the panel on purpose.
        "outside": ["AdminTitle", "AdminClose"],
    },
    "PageHost": {"children": []},
}

PAGES = {
    "Home": ["HomeBlurb", "HomeStats", "HomeInput", "HomeActions"],
    "Players": ["PlayerList", "PlayerActions"],
    "Reports": ["ReportList"],
    "Staff": ["StaffList", "StaffSide"],
    "Shop": ["AdminList", "NewButton", "Editor"],
}

# Widgets positioned inside a page's own sub-frame rather than the page itself.
#[[
#   Widgets held square by a UIAspectRatioConstraint. Their width comes from
#   their HEIGHT, not from the "0" written in the Size, so the source read on
#   its own makes them look zero width. The greeting headshot overlapping the
#   "Hello," label was exactly this being invisible in the numbers.
#]]
SQUARE = ["GreetImage"]

NESTED = {
    "PlayerActions": ["SelectedLabel", "ActionInput", "ActionGrid"],
    "StaffSide": [
        "AddTitle", "AddHint", "StaffIdBox", "StaffNameBox",
        "MakeModButton", "MakeAdminButton", "RemoveStaffButton",
        "BanTitle", "BanList",
    ],
}


class Box:
    def __init__(self, name):
        self.name = name
        self.size = None
        self.pos = (0.0, 0.0, 0.0, 0.0)
        self.anchor = (0.0, 0.0)
        self.line = 0

    def rect(self, pw, ph, px, py):
        xs, xo, ys, yo = self.size
        w = xs * pw + xo
        h = ys * ph + yo
        if self.name in SQUARE:
            # Held square off its height by an aspect ratio constraint.
            w = h
        pxs, pxo, pys, pyo = self.pos
        x = px + pxs * pw + pxo - self.anchor[0] * w
        y = py + pys * ph + pyo - self.anchor[1] * h
        return x, y, w, h


def constants(src):
    """Named layout constants, so expressions using them can be evaluated."""
    found = {}
    for m in re.finditer(r"^local\s+([A-Z][A-Z0-9_]*)\s*=\s*([\d.]+)\s*$", src, re.M):
        found[m.group(1)] = float(m.group(2))
    return found


def value(text, consts):
    """Evaluate one UDim2 field, which may be a number or a small expression."""
    text = text.strip()
    try:
        return float(text)
    except ValueError:
        pass
    expr = text
    for name, v in consts.items():
        expr = re.sub(r"\b%s\b" % name, repr(v), expr)
    if not re.fullmatch(r"[-\d.\s+*/()]+", expr):
        return None
    try:
        return float(eval(expr, {"__builtins__": {}}, {}))
    except Exception:
        return None


def quad(match, consts):
    out = []
    for g in match.groups():
        v = value(g, consts)
        if v is None:
            return None
        out.append(v)
    return tuple(out)


def parse_block(src, varname, consts=None):
    """Collect the geometry assignments for one variable, as written."""
    consts = consts or {}
    box = Box(varname)

    # `local X = MakeSmallButton(...)` style helpers set no Size of their own,
    # so only the explicit assignments afterwards matter.
    for m in re.finditer(r"^\s*%s\.(\w+)\s*=\s*(.+)$" % re.escape(varname), src, re.M):
        prop, raw = m.group(1), m.group(2)
        line = src[: m.start()].count("\n") + 1
        if prop == "Size":
            g = UDIM2.search(raw)
            if g and quad(g, consts):
                box.size = quad(g, consts)
                box.line = line
        elif prop == "Position":
            g = UDIM2.search(raw)
            if g and quad(g, consts):
                box.pos = quad(g, consts)
        elif prop == "AnchorPoint":
            g = VECTOR2.search(raw)
            if g:
                box.anchor = tuple(float(x) for x in g.groups())

    # The Home page places its rows from the HOME_BANDS table via HomeBand(),
    # so resolve that the same way the client does.
    if box.size is None:
        call = re.search(
            r"HomeBand\(\s*%s\s*,\s*\"(\w+)\"\s*\)" % re.escape(varname), src)
        if call:
            band = re.search(
                r"^\s*%s\s*=\s*\{\s*([\d.]+)\s*,\s*([\d.]+)\s*\}"
                % call.group(1), src, re.M)
            if band:
                top, height = float(band.group(1)), float(band.group(2))
                box.size = (1.0, 0.0, height, 0.0)
                box.pos = (0.0, 0.0, top, 0.0)
                box.line = src[: call.start()].count("\n") + 1

    # MakeScroller takes its size and position as call arguments instead of
    # assigning them, so read them out of the call itself. The two UDim2s are
    # always size then position.
    if box.size is None:
        call = re.search(
            r"local\s+%s\s*=\s*MakeScroller\(" % re.escape(varname), src)
        if call:
            tail = src[call.end(): call.end() + 400]
            found = UDIM2.findall(tail)
            if len(found) >= 2:
                sz = [value(x, consts) for x in found[0]]
                ps = [value(x, consts) for x in found[1]]
                if None not in sz and None not in ps:
                    box.size = tuple(sz)
                    box.pos = tuple(ps)
                box.line = src[: call.start()].count("\n") + 1

            # A later assignment still wins over the call argument.
            for m in re.finditer(
                    r"^\s*%s\.(Size|Position)\s*=\s*(.+)$" % re.escape(varname),
                    src, re.M):
                g = UDIM2.search(m.group(2))
                if g and quad(g, consts):
                    if m.group(1) == "Size":
                        box.size = quad(g, consts)
                    else:
                        box.pos = quad(g, consts)
    return box


def overlaps(a, b, slack=1.0):
    ax, ay, aw, ah = a
    bx, by, bw, bh = b
    return not (
        ax + aw <= bx + slack or bx + bw <= ax + slack
        or ay + ah <= by + slack or by + bh <= ay + slack
    )


def check(path, verbose=True):
    src = open(path, encoding="utf8").read()
    consts = constants(src)
    problems = []

    def say(*a):
        if verbose:
            print(*a)

    frame = parse_block(src, "AdminFrame", consts)
    if not frame.size:
        print("could not find AdminFrame in " + path)
        return 1

    frame_rect = frame.rect(SCREEN_W, SCREEN_H, 0, 0)
    fx, fy, fw, fh = frame_rect
    say("AdminFrame              %4.0f x %-4.0f at (%4.0f, %4.0f)" % (fw, fh, fx, fy))

    def check_group(parent_rect, names, label, indent="  "):
        """Lay a set of hand placed siblings out and check them against each other."""
        px, py, pw, ph = parent_rect
        rects = {}

        for name in names:
            b = parse_block(src, name, consts)
            if not b.size:
                continue
            r = b.rect(pw, ph, px, py)
            rects[name] = (r, b)
            say("%s%-20s %4.0f x %-4.0f at (%4.0f, %4.0f)"
                % (indent, name, r[2], r[3], r[0], r[1]))

            if r[0] < px - 2 or r[1] < py - 2 \
               or r[0] + r[2] > px + pw + 2 or r[1] + r[3] > py + ph + 2:
                problems.append(
                    "%s: %s does not fit inside its parent (line %d)"
                    % (label, name, b.line)
                )

            if 0 < r[3] < MIN_TEXT_HEIGHT:
                problems.append(
                    "%s: %s is only %.0fpx tall, text will clip (line %d)"
                    % (label, name, r[3], b.line)
                )

        ordered = list(rects)
        for i, a in enumerate(ordered):
            for b in ordered[i + 1:]:
                if overlaps(rects[a][0], rects[b][0]):
                    ay, ah = rects[a][0][1], rects[a][0][3]
                    by = rects[b][0][1]
                    problems.append(
                        "%s: %s overlaps %s by %.0fpx (lines %d and %d)"
                        % (label, a, b, (ay + ah) - by,
                           rects[a][1].line, rects[b][1].line)
                    )
        return rects

    top = check_group(frame_rect, PANEL["AdminFrame"]["children"], "AdminFrame")

    # Inside the greeting card, where the round headshot and the text share a
    # row and can quietly run into each other.
    if "Greet" in top:
        say("")
        say("  inside Greet")
        check_group(top["Greet"][0], ["GreetImage", "GreetHello", "GreetRank"],
                    "Greet", indent="    ")

    host = top.get("PageHost")
    if not host:
        print("could not find PageHost")
        return 1

    # Every page fills PageHost exactly, so they all share its rectangle.
    page_rect = host[0]
    for page, names in PAGES.items():
        say("")
        say("  page %s" % page)
        inner = check_group(page_rect, names, "page " + page, indent="    ")

        for holder, kids in NESTED.items():
            if holder in inner:
                say("      inside %s" % holder)
                check_group(inner[holder][0], kids, holder, indent="        ")

    say("")
    if problems:
        print("%d layout problem(s):" % len(problems))
        for p in problems:
            print("  - " + p)
        return 1

    print("layout is clean: nothing overlaps, nothing overflows, nothing is too short")
    return 0


def min_panel_size(src):
    """The UISizeConstraint floor on AdminFrame, if there is one."""
    m = re.search(r"minSize\.MinSize = Vector2\.new\((\d+),\s*(\d+)\)", src)
    if m:
        return float(m.group(1)), float(m.group(2))
    return None


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("-")]
    quiet = "-q" in sys.argv
    path = args[0] if args else "src/Client.client.lua"

    rc = check(path, verbose=not quiet)

    # Again at whatever window makes the panel exactly its minimum size, which
    # is the smallest it will ever actually be drawn.
    body = open(path, encoding="utf8").read()
    floor = min_panel_size(body)
    if floor:
        frame = parse_block(body, "AdminFrame", constants(body))
        SCREEN_W = floor[0] / frame.size[0]
        SCREEN_H = floor[1] / frame.size[2]
        print("")
        print("--- at the panel's minimum size (%.0fx%.0f window) ---"
              % (SCREEN_W, SCREEN_H))
        rc |= check(path, verbose=not quiet)

    sys.exit(rc)
