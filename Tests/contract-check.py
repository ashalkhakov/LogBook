#!/usr/bin/env python3
# The app's views against the model's forms' contracts (ORMKit's
# docs/FORMS.md, "A view of the app's own"): each object controller a XIB
# names "<Name>Form" is a view of the form <Name> (Forms/<Name>.ormform,
# ormtool xforms), or of Record<Name> where there is no <Name> (a record's
# tab: FillUpForm, RecordFillUp). Its controls bind the form's values
# through LBFormValues (AppKit/LBFormValues.h):
#
#   selection.<element>[.<key>...]      an element's value (a reference's
#                                       object, read on through it)
#   selection.choices.<element>...      a reference's choices
#   selection.choices.<repeat>.<element>  a repeat's rows' choices
#   selection.items.<element>           the values the model lists for it
#   selection.<repeat>                  a repeat's rows (an array
#                                       controller's content), whose columns
#                                       bind arrangedObjects.<element of the
#                                       repeat>
#
# Each binding names something the contract has, each element the
# contract enters is bound by some control, and each reference it enters
# offers the form's choices (a pop-up's content): the view implements the
# form, no more and no less. Fails (exit 1) saying each that does not.
#
#   Tests/contract-check.py build/Model/Forms AppKit/MainWindow.xib AppKit/StockPurchase.xib
import os
import plistlib
import sys
import xml.etree.ElementTree as ET


def contract(path):
    with open(path, 'rb') as f:
        return plistlib.load(f)


def elements(form):
    return {e['name']: e for e in form.get('elements', [])}


def choices_of(form):
    return set((form.get('choices') or {}).keys())


def check_rows(problems, rid, label, repeat, bindings, offered):
    rows = elements(repeat)
    row_bound = set()
    for owner, dest, binding, path in bindings:
        if dest != rid or not (path.startswith('arrangedObjects.') or path.startswith('selection.')):
            continue
        keys = path.split('.', 1)[1].split('.')
        if keys[0] in rows:
            row_bound.add(keys[0])
        else:
            problems.append('%s: %s binds %s, which %s has not' % (rid, owner.get('id'), path, label))
    for element in rows.values():
        if element.get('role') == 'entered' and element['name'] not in row_bound:
            problems.append('%s: %s enters %s, which no control binds' % (rid, label, element['name']))
        if element.get('role') == 'entered' and element['name'] in choices_of(repeat) and element['name'] not in offered:
            problems.append('%s: %s chooses %s from its choices, which no control offers' % (rid, label, element['name']))


def check_xib(xib, forms, problems):
    root = ET.parse(xib).getroot()
    bindings = []
    for owner in root.iter():
        for b in owner.findall('connections/binding'):
            bindings.append((owner, b.get('destination'), b.get('name'), b.get('keyPath') or ''))
    checked = 0
    for controller in root.iter('objectController'):
        cid = controller.get('id') or ''
        if not cid.endswith('Form'):
            continue
        prefix = cid[:-len('Form')]
        name = prefix if os.path.exists('%s/%s.ormform' % (forms, prefix)) else 'Record' + (controller.get('objectClassName') or prefix)
        try:
            form = contract('%s/%s.ormform' % (forms, name))
        except FileNotFoundError:
            problems.append('%s: %s: no form %s in the model' % (os.path.basename(xib), cid, name))
            continue
        checked += 1
        own = elements(form)
        repeats = form.get('repeats', {}) or {}
        bound, offered = set(), set()
        row_offered = {r: set() for r in repeats}
        repeat_controllers = {}
        for owner, dest, binding, path in bindings:
            if dest != cid or not path.startswith('selection.'):
                continue
            keys = path[len('selection.'):].split('.')
            first = keys[0]
            if first == 'choices':
                if len(keys) > 2 and keys[1] in repeats and keys[2] in choices_of(repeats[keys[1]]):
                    if binding == 'content':
                        row_offered[keys[1]].add(keys[2])
                elif len(keys) > 1 and keys[1] in choices_of(form):
                    if binding == 'content':
                        offered.add(keys[1])
                else:
                    problems.append('%s: %s binds %s: %s offers no such choices' % (cid, owner.get('id'), path, name))
                continue
            if first == 'items':
                if len(keys) < 2 or keys[1] not in own or not own[keys[1]].get('items'):
                    problems.append('%s: %s binds %s: %s lists no such values' % (cid, owner.get('id'), path, name))
                continue
            if first in own:
                bound.add(first)
            elif first in repeats:
                bound.add(first)
                repeat_controllers[owner.get('id')] = first
            else:
                problems.append('%s: %s binds %s, which %s has not' % (cid, owner.get('id'), path, name))
        for rid, repeat in repeat_controllers.items():
            check_rows(problems, rid, '%s.%s' % (name, repeat), repeats[repeat], bindings, row_offered[repeat])
        for element in own.values():
            if element.get('role') == 'entered' and element['name'] not in bound:
                problems.append('%s: %s enters %s, which no control binds' % (cid, name, element['name']))
            if element.get('role') == 'entered' and element['name'] in choices_of(form) and element['name'] not in offered:
                problems.append('%s: %s chooses %s from its choices, which no control offers' % (cid, name, element['name']))
    return checked


def main(forms, xibs):
    problems = []
    checked = sum(check_xib(xib, forms, problems) for xib in xibs)
    for problem in problems:
        print('contract-check: ' + problem)
    print('contract-check: %d views, %d not as their forms say' % (checked, len(problems)))
    return 1 if problems or not checked else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1], sys.argv[2:]))
