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
#   (in a repeat whose rows each choose of their own, as an answer's
#   options of its question's, a row's choices.<element> and items.<element>)
#   selection.<repeat>                  a repeat's rows (an array
#                                       controller's content), whose columns
#                                       bind arrangedObjects.<element of the
#                                       repeat>
#
# Each binding names something the contract has, each element the
# contract enters is bound by some control, and each reference it enters
# offers the form's choices (a pop-up's content): the view implements the
# form, no more and no less. And the app's flows (<Flow>.ormflow, ormtool
# xforms --flow, in the forms' directory): each screen's form has a view,
# and each trigger from it is a control of that view's XIB (its
# identifier), so the views implement the flow too. Fails (exit 1) saying
# each that does not.
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


OFFERING = ('content', 'contentArray', 'contentSet')


def check_rows(problems, rid, label, repeat, bindings, offered):
    rows = elements(repeat)
    row_bound = set()
    for owner, dest, binding, path in bindings:
        if dest != rid or not (path.startswith('arrangedObjects.') or path.startswith('selection.')):
            continue
        keys = path.split('.', 1)[1].split('.')
        if keys[0].startswith('@'):
            continue  # a collection operator (arrangedObjects.@count): the rows', no element
        if keys[0] == 'choices' and len(keys) > 1 and keys[1] in choices_of(repeat):
            if binding in OFFERING:
                offered.add(keys[1])
            continue
        if keys[0] == 'items' and len(keys) > 1 and keys[1] in rows and rows[keys[1]].get('items'):
            continue
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
                    if binding in OFFERING:
                        row_offered[keys[1]].add(keys[2])
                elif len(keys) > 1 and keys[1] in choices_of(form):
                    if binding in OFFERING:
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


def views_of(xibs):
    """Each form a XIB has a view of: the XIB, and its controls' identifiers."""
    views = {}
    for xib in xibs:
        root = ET.parse(xib).getroot()
        identifiers = {e.get('identifier') for e in root.iter() if e.get('identifier')}
        for controller in root.iter('objectController'):
            cid = controller.get('id') or ''
            if cid.endswith('Form'):
                views[cid[:-len('Form')]] = (xib, identifiers)
    return views


def check_flows(forms, xibs, problems):
    views = views_of(xibs)
    flows = sorted(f for f in os.listdir(forms) if f.endswith('.ormflow'))
    for name in flows:
        flow = contract(os.path.join(forms, name))
        screens = flow.get('screens', {})
        for sid, screen in sorted(screens.items()):
            form = screen.get('form')
            if form and form not in views:
                problems.append('%s: %s shows %s, which no view is of' % (name, sid, form))
        for way in flow.get('transitions', []):
            if way.get('on') != 'Trigger':
                continue
            form = screens.get(way.get('from'), {}).get('form')
            view = views.get(form)
            if view and way.get('control') not in view[1]:
                problems.append('%s: %s\'s trigger %s is no control of %s' % (name, form, way.get('control'), os.path.basename(view[0])))
    return len(flows)


def main(forms, xibs):
    problems = []
    checked = sum(check_xib(xib, forms, problems) for xib in xibs)
    flows = check_flows(forms, xibs, problems)
    for problem in problems:
        print('contract-check: ' + problem)
    print('contract-check: %d views, %d flows, %d not as their forms say' % (checked, flows, len(problems)))
    return 1 if problems or not checked else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1], sys.argv[2:]))
