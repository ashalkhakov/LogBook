# Logbook

A car logbook: what each vehicle needs and when, what it had done, and what
it cost. It keeps fill-ups, services, the parts fitted, and what is coming
due, and it works offline on every device, syncing through a server of your
own.

It is built on [ORMKit](../NativeORM2):
- **The model:** an ORM model, designed by Halpin's conceptual schema
  design procedure ([docs/CSDP.md](docs/CSDP.md)).
- **Derived from it:** the Core Data model, the OData service, the sync,
  and the code that checks its constraints.
- **Written by hand:** the forms, in the manner of TopoText's SimpleNotes:
  - an AppKit app for macOS and GNUstep;
  - an iOS app;
  - a server.

Early days: the model is done, and the server runs it.

## The server

`logbook-server` serves the logbook over OData for the apps to sync with:
ODataKit's service, with ODataSync's part of it, and the model's rules
kept as it writes. Before it saves a request, or a change set at its end,
the stored derivations are worked out and every rule is checked for what
the change reaches (the generated code in `Model/Constraints`); a change
that breaks one is refused, `400`, and nothing of it is saved.

```sh
make -f Makefile.apple && make -f Makefile.apple check     # macOS
make && make check                                          # GNUstep
.tools/gnustep.sh make check                                # GNUstep, in ORMKit's image
build/logbook-server -StoreURL logbook.sqlite -Port 8080 -Localhost NO
```

It builds on ORMKit's runtime from `../NativeORM2`, and on the ODataKit
release ORMKit pins. `Tests/serve-and-check.py` runs it on a temporary
store and checks it over HTTP: the reference data, a change set saved
with what it derives, and one a rule refuses. Signing in, and who may
change what ([Permissions](docs/CSDP.md#permissions)), come next.
