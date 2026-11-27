#!/usr/bin/env python3
"""The XIBs as the HIG (OS X, 2014) has them, checked from their sources:

- no key equivalent that is a space or a raw line break (a Return written
  as a line break in an attribute reads as a space: Space, not Return,
  would press the button);
- every push button titled Cancel answers Escape (Dismissing Dialogs);
- a static label with a control just to its right on its row ends with a
  colon (Use a Colon to Connect a Label with Controls);
- an image-only pull-down (a + with a menu) has its arrow beside the image,
  not drawn over it;
- the menu bar: File, Edit, View, Go, Window, Help, in that order;
- (both platforms) no scroll view's document view written as
  key="documentView": GNUstep's XIB loader leaves it out.

    python3 Tests/hig-check.py AppKit/*.xib
"""
import re
import sys
import xml.etree.ElementTree as ET

CONTROLS = {"textField", "popUpButton", "comboBox", "datePicker", "customView", "button", "segmentedControl", "stepper", "slider", "searchField"}
problems = []


def frame(e):
    r = e.find("rect")
    return None if r is None else [float(r.get(k)) for k in ("x", "y", "width", "height")]


def shows_value(e):
    c = e.find("textFieldCell")
    return c is not None and (c.get("editable") == "YES" or c.get("borderStyle") == "bezel" or e.find("connections/binding") is not None)


for path in sys.argv[1:]:
    name = path.split("/")[-1]
    text = open(path).read()
    for m in re.finditer(r'keyEquivalent="(\s+)"', text):
        line = text.count("\n", 0, m.start()) + 1
        problems.append("%s:%d: a key equivalent that is %r (Return is &#13;)" % (name, line, m.group(1)))
    for m in re.finditer(r'<(?:view|customView)\b[^>]*key="documentView"', text):
        line = text.count("\n", 0, m.start()) + 1
        problems.append("%s:%d: a scroll view's document view keyed documentView: GNUstep's XIB loader leaves it out "
                        "(put it in the clip view's subviews, as a table is)" % (name, line))
    root = ET.fromstring(text)
    for cell in root.iter("buttonCell"):
        if cell.get("type") == "push" and cell.get("title") == "Cancel":
            key = cell.get("keyEquivalent")
            child = cell.find("string[@key='keyEquivalent']")
            if not (key == "\x1b" or (child is not None and (child.text or "").strip() == "Gw")):
                problems.append("%s: Cancel (%s) does not answer Escape" % (name, cell.get("id")))
    for cell in root.iter("popUpButtonCell"):
        if cell.get("pullsDown") == "YES" and cell.get("imagePosition") == "only" and cell.get("arrowPosition", "arrowAtCenter") == "arrowAtCenter":
            problems.append("%s: the pull-down %s draws its arrow over its image (arrowAtBottom puts it beside)" % (name, cell.get("id")))
    for subviews in root.iter("subviews"):
        kids = list(subviews)
        for e in kids:
            if e.tag != "textField" or shows_value(e) or e.find("connections/binding") is not None:
                continue
            c = e.find("textFieldCell")
            t = (c.get("title") if c is not None else "") or ""
            if not t or t[-1] in ":…?." or len(t) > 40:
                continue
            fl = frame(e)
            if not fl:
                continue
            cy = fl[1] + fl[3] / 2
            for o in kids:
                fo = frame(o)
                if o is e or o.tag not in CONTROLS or not fo:
                    continue
                if o.tag == "button" and (o.find("buttonCell") is None or o.find("buttonCell").get("type") not in ("check", "radio")):
                    continue
                if o.tag == "textField" and not shows_value(o):
                    continue
                if fo[1] - 6 <= cy <= fo[1] + fo[3] + 6 and fl[0] + fl[2] - 6 <= fo[0] <= fl[0] + fl[2] + 40:
                    problems.append("%s: the label %r (%s) introduces %s: it ends with a colon" % (name, t, c.get("id"), o.get("id")))
                    break
    menu = root.find(".//menu[@systemMenu='main']")
    if menu is not None:
        titles = [i.get("title") for i in menu.find("items")]
        want = ["File", "Edit", "View", "Go", "Window", "Help"]
        if [t for t in titles if t in want] != want:
            problems.append("%s: the menus are %s, not ... %s" % (name, titles, ", ".join(want)))

for p in problems:
    print(p)
print("hig: %d failed" % len(problems))
sys.exit(1 if problems else 0)
