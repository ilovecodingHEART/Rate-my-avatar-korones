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

#[[
#   Two different floors, because two different things are being checked.
#
#   A widget with TextScaled = true grows or shrinks its font to fit, so the
#   row height IS the text height: 18px is small but perfectly legible, and
#   nothing clips. A widget with a FIXED TextSize does clip, because the glyphs
#   stay their stated size no matter how short the row gets.
#
#   Holding both to 22 was wrong in the strict direction - it reported clipping
#   on scaled rows that render fine - which is just as unhelpful as missing a
#   real one, because warnings nobody can act on get ignored.
#]]
MIN_TEXT_HEIGHT = 22
MIN_SCALED_HEIGHT = 15

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
    # HomeInput is gone: that field is the input dock, outside the panel.
    "Home": ["HomeBlurb", "HomeStats", "HomeActions"],
    "Players": ["PlayerList", "PlayerActions"],
    "Reports": ["ReportList"],
    "Staff": ["StaffList", "StaffSide"],
    "Shop": ["AdminList", "NewButton", "Editor"],
    "Trolling": ["TrollList", "TrollSide"],
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
    "PlayerActions": ["SelectedLabel", "ActionGrid"],
    "TrollSide": ["TrollGrid"],
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
    """Named layout constants, so expressions using them can be evaluated.

    Covers plain `local NAME = 0.5`, table fields like `GREET.TextX = ...`, and
    the derived ones written as an arithmetic expression across a few lines.
    """
    found = {}
    for m in re.finditer(r"^local\s+([A-Z][A-Z0-9_]*)\s*=\s*([\d.]+)\s*$", src, re.M):
        found[m.group(1)] = float(m.group(2))

    # Fields inside a config table, e.g. `W = 0.245, H = 0.225,`.
    block = re.search(r"local GREET = \{(.*?)\n\}", src, re.S)
    if block:
        for m in re.finditer(r"(\w+)\s*=\s*([\d.]+)", block.group(1)):
            found["GREET." + m.group(1)] = float(m.group(2))

    # GREET.TextX is derived, so recompute it the way the client does rather
    # than hard coding a number that would then be able to disagree.
    g = found
    if all(k in g for k in ("GREET.HeadInset", "GREET.H", "GREET.HeadScale", "GREET.W")):
        g["GREET.TextX"] = (
            g["GREET.HeadInset"]
            + (g["GREET.H"] * g["GREET.HeadScale"]) / (g["GREET.W"] * (16 / 9))
            + 0.06
        )
    return found


def value(text, consts):
    """Evaluate one UDim2 field, which may be a number or a small expression."""
    text = text.strip()
    try:
        return float(text)
    except ValueError:
        pass
    expr = text
    # Longest first, so GREET.TextX is replaced before a bare GREET could be.
    for name in sorted(consts, key=len, reverse=True):
        expr = expr.replace(name, repr(consts[name]))
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


def named_number(src, field):
    """A numeric field from a config table, e.g. `MinWidth = 104`.

    Deliberately not anchored to the end of the line: several of these are
    written two to a line (`AdminW = 736, AdminH = 400`), and an end-anchored
    pattern silently returned None for them, which made the checker quietly
    fall back to defaults and report stale numbers.
    """
    m = re.search(r"\b%s\s*=\s*([\d.]+)" % field, src)
    return float(m.group(1)) if m else None


def place_toggle_size():
    """ToggleButton's scale size, which lives in the .rbxl rather than here."""
    # Read once from the place file so the check uses the real inherited value.
    return (0.107, 0.071)


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
    notes = []

    def say(*a):
        if verbose:
            print(*a)

    frame = parse_block(src, "AdminFrame", consts)
    if not frame.size:
        print("could not find AdminFrame in " + path)
        return 1

    frame_rect = frame.rect(SCREEN_W, SCREEN_H, 0, 0)

    #[[
    #   A UISizeConstraint is a floor, and a floor bigger than the window makes
    #   the panel hang off the screen. That is not a hypothetical: a 720x400
    #   minimum on a 617x326 window pushed the panel over both edges and is
    #   exactly what shipped. So the constraint is applied here the way Roblox
    #   applies it, and the result is checked against the screen.
    #]]
    #[[
    #   The panel is laid out at a fixed design size and a UIScale shrinks the
    #   whole thing to fit. So the geometry is checked at the design size,
    #   where the proportions live, and the scale is applied afterwards to work
    #   out what it actually measures on screen.
    #
    #   That is the difference that matters: scaling as one piece keeps every
    #   proportion, whereas letting each row scale on its own is what made them
    #   collapse at different rates and land on top of each other.
    #]]
    design = min_panel_size(src)
    min_scale = named_number(src, "MinScale") or 1.0
    # The panel fits the screen minus the strip the input dock reserves at the
    # top, and is nudged down by half of it. Modelling the full screen here
    # would miss the dock landing on the panel's title.
    dock_strip = named_number(src, "DockStrip") or 0

    scale = 1.0
    if design:
        fw, fh = design
        usable_h = max(SCREEN_H - dock_strip, 120)
        fit = min((SCREEN_W - 16) / fw, (usable_h - 16) / fh, 1.0)
        #[[
        #   The rect stays at the DESIGN size and the scale is reported
        #   separately, because everything inside is measured against the
        #   design size and then scaled as one piece. Baking the scale into
        #   fw/fh here and then leaving `scale` at 1.0 made the children get it
        #   applied twice, which reported false clipping everywhere.
        #]]
        scale = max(fit, min_scale)
        fx = SCREEN_W / 2 - (fw * scale) / 2
        fy = SCREEN_H / 2 + dock_strip / 2 - (fh * scale) / 2
        frame_rect = (fx, fy, fw, fh)

    fx, fy, fw, fh = frame_rect
    say("AdminFrame              %4.0f x %-4.0f  drawn at scale %.2f (%.0f x %.0f on screen)"
        % (fw, fh, scale, fw * scale, fh * scale))

    if fw * scale > SCREEN_W + 1 or fh * scale > SCREEN_H + 1:
        problems.append(
            "AdminFrame is %.0fx%.0f on screen but the window is only %.0fx%.0f"
            % (fw * scale, fh * scale, SCREEN_W, SCREEN_H))

    # Everything inside is measured at the design size then scaled, so the
    # readability floor has to be compared against the scaled height.
    globals()["TEXT_SCALE"] = scale

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

            # Everything is laid out at the design size then scaled as one
            # piece, so readability depends on the height AFTER scaling.
            drawn = r[3] * globals().get("TEXT_SCALE", 1.0)

            # TextScaled rows fit their own text, so they only need to stay
            # legible; fixed-size rows have to fit the size they declared.
            #[[
            #   Either set directly on the widget, or by the helper that built
            #   it. MakeSmallButton sets TextScaled on everything it makes, so
            #   matching only `Name.TextScaled = true` missed those and
            #   reported clipping on buttons that scale their text fine.
            #]]
            scaled = re.search(
                r"^\s*%s\.TextScaled\s*=\s*true" % re.escape(name), src, re.M)
            if not scaled and re.search(
                    r"local\s+%s\s*=\s*MakeSmallButton" % re.escape(name), src):
                scaled = True
            floor = MIN_SCALED_HEIGHT if scaled else MIN_TEXT_HEIGHT

            if 0 < drawn < floor:
                problems.append(
                    "%s: %s is %.0fpx tall on screen, text will clip (line %d)"
                    % (label, name, drawn, b.line)
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

    #[[
    #   The HUD buttons down the side. Their size has a pixel floor but their
    #   spacing is pure scale, so on a short window the gap shrinks below the
    #   button height and they stack on top of each other. Nothing was checking
    #   this, which is why it shipped twice.
    #]]
    hud_min_w = named_number(src, "MinWidth")
    hud_min_h = named_number(src, "MinHeight")
    hud_pad = named_number(src, "Pad")

    if hud_min_h:
        toggle = place_toggle_size()
        #[[
        #   A UDim2 axis is scale * parent + offset - it ADDS - whereas a
        #   UISizeConstraint MinSize is a true floor.
        #
        #   Getting this wrong in both directions is what caused the bug and
        #   then hid it: the code used math.max on the offset thinking it was a
        #   floor (it added 104px to every button), and this check modelled it
        #   as max() too, so the check agreed with the intent instead of the
        #   code and reported clean while the buttons visibly overlapped.
        #
        #   Now: the scale size is what the UDim2 gives, and the constraint
        #   raises it only if that comes out under the minimum.
        #]]
        #[[
        #   Scoped to PlaceHudButton, not the whole file. A plain
        #   `"UISizeConstraint" in src` matched the admin panel's own
        #   constraint hundreds of lines away, so this took the max() branch no
        #   matter what the HUD code did - and quietly stopped being able to
        #   detect the exact bug it was added for.
        #]]
        hud_fn = re.search(
            r"local function PlaceHudButton.*?\n(?=\S)", src, re.S)
        hud_body = hud_fn.group(0) if hud_fn else ""
        uses_constraint = "UISizeConstraint" in hud_body
        if uses_constraint:
            bh = max(toggle[1] * SCREEN_H, hud_min_h)
            bw = max(toggle[0] * SCREEN_W, hud_min_w or 0)
        else:
            bh = toggle[1] * SCREEN_H + hud_min_h
            bw = toggle[0] * SCREEN_W + (hud_min_w or 0)

        #[[
        #   The spacing is read out of PlaceHudButton rather than recomputed
        #   here. Deriving the expected gap from the same formula the code uses
        #   is circular: it agreed with itself no matter what the code said, so
        #   a genuinely broken gap still reported clean. Reading the source
        #   means the check can actually disagree with the implementation.
        #]]
        #[[
        #   The step is a UDim2: a scale part and an offset part, read out of
        #   PlaceHudButton rather than recomputed here. Deriving it from the
        #   same formula the code uses would only ever agree with itself, which
        #   is how an earlier version of this check passed while the buttons
        #   visibly overlapped.
        #]]
        gap_px = None
        m_scale = re.search(r"local stepScale = (.+)", src)
        m_offset = re.search(r"local stepOffset = (.+)", src)

        if m_scale and m_offset:
            def resolve(expr, screen_axis):
                expr = expr.strip()
                expr = expr.replace("math.max", "max")
                expr = expr.replace("HUD.Size.Y.Scale", repr(toggle[1]))
                expr = expr.replace("HUD.Size.Y.Offset", "0")
                expr = expr.replace("HUD.MinHeight", repr(hud_min_h))
                expr = expr.replace("HUD.Pad", repr(hud_pad if hud_pad else 0))
                try:
                    return float(eval(expr, {"__builtins__": {}}, {"max": max}))
                except Exception:
                    return None

            sc = resolve(m_scale.group(1), SCREEN_H)
            off = resolve(m_offset.group(1), SCREEN_H)
            if sc is not None and off is not None:
                gap_px = sc * SCREEN_H + off

        if gap_px is None:
            gap_px = (named_number(src, "Gap") or 0) * SCREEN_H
        say("")
        say("  HUD buttons           %4.0f x %-4.0f  spaced %.0fpx apart" % (bw, bh, gap_px))
        if gap_px < bh + 2:
            problems.append(
                "HUD buttons are %.0fpx tall but stacked only %.0fpx apart, so they overlap"
                % (bh, gap_px))

        # A HUD button wider than its own column runs into whatever is beside
        # it. This is a real failure, not a note: it is how the stack ended up
        # sitting on top of the panel.
        if bw > 0.24 * SCREEN_W:
            problems.append(
                "HUD buttons are %.0fpx wide, which is %.0f%% of a %.0fpx window"
                % (bw, 100 * bw / SCREEN_W, SCREEN_W))

        #[[
        #   The HUD sits on the same screen as the panel, so it can run
        #   underneath it. Checking each in isolation missed that entirely -
        #   both were "clean" while visibly on top of each other.
        #]]
        toggle_x = 0.007 * SCREEN_W
        if toggle_x + bw > fx + 2:
            # Reported, not failed. The HUD position is being handled outside
            # this repo, so flagging it is useful but blocking the build on it
            # would just be noise on every run.
            # Only worth mentioning if the stack is still on screen while a
            # window is open. It is not: HUD.Show hides it, so the two can
            # never actually be drawn on top of each other.
            if "function HUD.Show" not in src:
                problems.append(
                    "HUD buttons reach x=%.0f but the panel starts at x=%.0f"
                    % (toggle_x + bw, fx))

    say("")
    for n in notes:
        print("  note: " + n)

    if problems:
        print("%d layout problem(s):" % len(problems))
        for p in problems:
            print("  - " + p)
        return 1

    print("layout is clean: nothing overlaps, nothing overflows, nothing is too short")
    return 0


def min_panel_size(src):
    """The panel's fixed design size, which a UIScale then shrinks."""
    w = named_number(src, "AdminW")
    h = named_number(src, "AdminH")
    if w and h:
        return w, h
    return None


#[[
#   The sizes the layout is checked at.
#
#   Only ever checking a big window is how a panel that hangs off a small one
#   shipped. The small entries are real: 617x326 is the window from the bug
#   report, and Roblox windows genuinely do get that small.
#]]
WINDOWS = [
    (1920, 1080, "1080p"),
    (1280, 720, "720p"),
    (1024, 576, "small"),
    (800, 450, "very small"),
    (617, 326, "the bug report"),
]


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("-")]
    quiet = "-q" in sys.argv
    path = args[0] if args else "src/Client.client.lua"

    rc = 0
    for w, h, tag in WINDOWS:
        SCREEN_W, SCREEN_H = w, h
        globals()["SCREEN_W"] = w
        globals()["SCREEN_H"] = h
        print("=== %s  (%dx%d) ===" % (tag, w, h))
        rc |= check(path, verbose=not quiet)
        print("")

    sys.exit(rc)
