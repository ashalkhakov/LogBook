#!/usr/bin/env bash
# The installer's PREPARE (.github/release/windows.conf): the runtime without
# the apps the kits' releases installed beside Logbook (WorkflowKit's
# WorkflowDesk, ORMKit's ORMDesigner). They are not Logbook's, and what they
# link (WorkflowDesk's XFormsKit) is not in its runtime.
set -euo pipefail
stage=$1
for app in "$stage"/runtime/Local/Applications/*.app; do
  [ -d "$app" ] || continue
  echo "not Logbook's: ${app#"$stage"/}"
  rm -rf "$app"
done
