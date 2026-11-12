#!/usr/bin/env python3
# The app's views against the model's forms' contracts (ORMKit's
# docs/FORMS.md, "A view of the app's own"): each object controller a XIB
# names "<Kind>Form" is a record's tab, the view of the form Record<Kind>
# (Forms/Record<Kind>.ormform, ormtool xforms). Its controls bind the
# form's values through LBFormValues (AppKit/LBFormValues.h):
#
#   selection.<element>[.<key>...]   an element's value (a reference's
#                                    object, read on through it)
#   selection.choices.<element>...   a reference's choices
#   selection.<repeat>               a repeat's rows (an array controller's
#                                    content), whose columns bind
#                                    arrangedObjects.<element of the repeat>
#
# Each binding names something the contract has, each element the
# contract enters is bound by some control, and each reference it enters
# offers the form's choices (a pop-up's content, selection.choices.<name>):
# the view implements the form, no more and no less. Fails (exit 1) saying
# each that does not.
#
#   Tests/contract-check.py AppKit/MainWindow.xib build/Model/Forms
import plistlib
import re
import sys
import xml.etree.ElementTree as ET


def contract(path):
    with open(path, 'rb') as f:
        return plistlib.load(f)


def elements(form):
    return {e['name']: e for e in form.get('elements', [])}


def main(xib, forms):
    root = ET.parse(xib).getroot()
    by_id = {e.get('id'): e for e in root.iter() if e.get('id')}
    parent = {child: p for p in root.iter() for child in p}
    bindings = []
    for owner in root.iter():
        for b in owner.findall('connections/binding'):
            bindings.append((owner, b.get('destination'), b.get('name'), b.get('keyPath') or ''))
    problems = []
    checked = 0
    for controller in root.iter('objectController'):
        cid = controller.get('id') or ''
        if not cid.endswith('Form'):
            continue
        kind = controller.get('objectClassName') or cid[:-len('Form')]
        name = 'Record' + kind
        try:
            form = contract('%s/%s.ormform' % (forms, name))
        except FileNotFoundError:
            problems.append('%s: no form %s in the model' % (cid, name))
            continue
        checked += 1
        own = elements(form)
        repeats = form.get('repeats', {}) or {}
        choices = set((form.get('choices') or {}).keys())
        bound = set()
        offered = set()
        repeat_controllers = {}
        for owner, dest, binding, path in bindings:
            if dest != cid or not path.startswith('selection.'):
                continue
            keys = path[len('selection.'):].split('.')
            first = keys[0]
            if first == 'choices':
                if len(keys) < 2 or keys[1] not in choices:
                    problems.append('%s: %s binds %s: %s offers no such choices' % (cid, owner.get('id'), path, name))
                elif binding == 'content':
                    offered.add(keys[1])
                continue
            if first in own:
                bound.add(first)
                continue
            if first in repeats:
                bound.add(first)
                repeat_controllers[owner.get('id')] = first
                continue
            problems.append('%s: %s binds %s, which %s has not' % (cid, owner.get('id'), path, name))
        # A repeat's columns: its elements.
        for rid, repeat in repeat_controllers.items():
            rows = elements(repeats[repeat])
            row_choices = set((repeats[repeat].get('choices') or {}).keys())
            row_bound = set()
            for owner, dest, binding, path in bindings:
                if dest != rid or not path.startswith('arrangedObjects.') and not path.startswith('selection.'):
                    continue
                keys = path.split('.', 1)[1].split('.')
                if keys[0] in rows:
                    row_bound.add(keys[0])
                elif not (keys[0] == 'choices' and len(keys) > 1 and keys[1] in row_choices):
                    problems.append('%s: %s binds %s, which %s.%s has not' % (rid, owner.get('id'), path, name, repeat))
            for element in rows.values():
                if element.get('role') == 'entered' and element['name'] not in row_bound:
                    problems.append('%s: %s.%s enters %s, which no control binds' % (rid, name, repeat, element['name']))
        for element in own.values():
            if element.get('role') == 'entered' and element['name'] not in bound:
                problems.append('%s: %s enters %s, which no control binds' % (cid, name, element['name']))
            if element.get('role') == 'entered' and element['name'] in choices and element['name'] not in offered:
                problems.append('%s: %s chooses %s from its choices, which no control offers' % (cid, name, element['name']))
    for problem in problems:
        print('contract-check: ' + problem)
    print('contract-check: %d views, %d not as their forms say' % (checked, len(problems)))
    return 1 if problems or not checked else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1], sys.argv[2]))
