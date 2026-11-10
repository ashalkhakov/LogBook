# Building Logbook

It builds on the releases `.github/pins.env` names: the GNUstep stack,
FreeCoreData, ODataKit, ORMKit, RDLKit and XFormsKit (`scripts/deps.sh` from
gnustep-release-actions fetches them: `apple` into `.deps`, `linux` into
`/opt/gnustep`). CI (`.github/workflows/build.yml`) builds and checks it
on Linux, macOS and iOS, and uploads the apps: Linux's an AppImage with
the server in it (`<image> --server -StoreURL logbook.sqlite`).

```sh
make -f Makefile.apple && make -f Makefile.apple check     # macOS (and iOS, where Xcode has a simulator)
make && make check                                          # GNUstep
.tools/gnustep.sh make check                                # GNUstep, in docker (.tools/gnustep.Dockerfile)
```

`make install DESTDIR=<dir>` (`-f Makefile.apple` on macOS) installs the
apps and the server, as CI packages them. iOS: [IOS.md](IOS.md#building-and-running-it).

## The checks

`make check` checks the procedures over a store of
their own (`Tests/LBProceduresCheck.m`), and the model's fill-up form
(`Tests/form-check.sh`, `Tests/LBFormCheck.m`) against a store of its own
and a server: opened for a vehicle, its drivers its choices, saved
whole, a driver who does not drive it refused at the field, read back and
changed at the server; then `Tests/serve-and-check.py`
runs the server on a temporary store and checks it over HTTP: the
reference data (the units, the kinds of cost), a change set saved with
what it derives, one a rule refuses, an attachment's photo there and
back, the actions and automatic completion, and who may do what, signed
in; `Tests/sync-check.sh` syncs two devices' offline stores through one,
a receipt's photo among what they sync (`Tests/LBSyncCheck.m`); then
`Tests/app-check.sh` drives the desktop app against one: every kind of
record added from its Add menu, its form typed into, saved, corrected and
saved again, each checked at the server, and a fill-up recorded with the
model's form both ways: Logbook's own window over the form's contract
(File > Record a Fill-Up…) and the generated one (File > Record a Fill-Up
with the Generated Form…).

## The README's pictures

`Tests/sample-logbook.py` fills a server with a logbook to look at (two
cars, their last four months, dated back from today); the self-tests'
pictures steps show it, tab by tab, and save each:

```sh
Tests/pictures.sh build/logbook-server build/Logbook.app/Contents/MacOS/Logbook docs/images -NSRequiresAquaSystemAppearance YES
xvfb-run -a Tests/pictures.sh obj/logbook-server Logbook.app/Logbook out        # GNUstep: TIFFs
Tests/ios-pictures.sh build/logbook-server build/ios/iphonesimulator/Logbook.app docs/images
```

## The model, generated

`Model/Logbook.orm` is the model, and the only copy of it: its facts,
constraints, queries and derivations, its Core Data mapping, and its
diagrams. It is ORMKit's model in NORMA's file format, so NORMA opens it
too. Change it in ORMDesigner, or apply lines of FORML to it, as the
listing says them:

```sh
ormtool apply Model/Logbook.orm changes.forml   # "- line" takes one away
```

([CSDP.md](CSDP.md#the-model) says how.) What the apps and the
server use is generated from it by the build, into `build/Model`
(`obj/Model` on GNUstep), with ORMKit's `ormtool`, from its release
(`.deps/bin` on macOS; installed with its libraries on GNUstep):
- `Logbook.xcdatamodeld`, the Core Data model (compiled to `Logbook.momd`,
  and its classes generated, as Xcode does);
- `Constraints/`: `LogbookValidation.h` and `.m`, and `Logbook.ormplans`,
  the code and tables that keep the model's rules and work out its stored
  derivations;
- `Logbook.forml`, the listing: every statement of the model, a line each,
  as the verbalizer says it, for reading and for copying lines from;
- `Forms/`: each of the model's forms (a query of the kind Form, ORMKit's
  docs/FORMS.md) as XFormsKit runs it, by `ormtool xforms`:
  `<Form>.xhtml`, the XForms document (its fields, the model's constraints
  as its checks, said in the model's words), and `<Form>.ormform`, the
  plans its reads, choices and save stand for. The desktop app keeps them
  in its resources; `Shared/LBFormHost.m` answers what they ask (`form:read`,
  `form:choices/<name>`, `form:save`) from the store, saved as any change
  is, or from the server's OData service.

  `RecordFillUp` is the one there is: a fill-up of a vehicle, the vehicle
  and who enters it given, its driver chosen from those who drive the
  vehicle, its price per unit worked out. Its outline is in the model
  (`ormtool forml` lists it; the designer's Queries window edits it), and
  changing it changes the form the next build makes. File > Record a
  Fill-Up with the Form… opens it for the chosen vehicle, beside the
  fill-up's own hand-made form.

None of it is kept in git, nor edited: it is made again whenever the
model, or ormtool, changes.

## In Xcode

`Logbook.xcworkspace` holds `Logbook.xcodeproj`, whose targets link
ORMKit's ORMRuntime from its release's XCFramework. Its schemes:
`Logbook` (the desktop app), `Logbook-iOS` (iOS's settings are
`iOS/Logbook-iOS.xcconfig`'s), `logbook-server`, `lb-procedures-check` and
`lb-sync-check`. Each first builds `Model`, which generates what they need
from the model by `make -f Makefile.apple xcode-model`; the frameworks are
the XCFrameworks in `.deps` (`scripts/deps.sh apple` from
gnustep-release-actions).

The project is generated from the makefiles' source lists: after adding a
file, `python3 .tools/genxcodeproj.py`, rather than editing it by hand. The
makefiles remain what builds and checks Logbook.
