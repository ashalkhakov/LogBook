#!/bin/sh
# Every form and flow the model has (ormtool xforms' output) and every
# window (AppKit/*.xib) is in the app's resources: the GNUmakefile names
# them one by one (LB_FORMS, Logbook_RESOURCE_FILES), and one left out is
# found only when the app opens it.
#
#   Tests/bundle-check.sh Logbook.app/Resources obj/Model/Forms
set -e
resources=$1
forms=$2
missing=
for f in "$forms"/*.ormform "$forms"/*.ormflow AppKit/*.xib; do
  name=$(basename "$f")
  [ -e "$resources/$name" ] || missing="$missing $name"
done
if [ -n "$missing" ]; then
  echo "FAIL not in $resources (the GNUmakefile's LB_FORMS, Logbook_RESOURCE_FILES):$missing"
  exit 1
fi
echo "bundle: every form, flow and window in $resources"
