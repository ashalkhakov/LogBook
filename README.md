# Logbook

A car logbook: what each vehicle needs and when, what it had done, and what
it cost. It keeps fill-ups, services, the parts fitted, and what is coming
due, and it works offline on every device, syncing through a server of your
own.

It is built on [ORMKit](../NativeORM2):
- **The model:** an ORM model, designed by Halpin's conceptual schema
  design procedure ([docs/CSDP.md](docs/CSDP.md)): `Model/Logbook.orm`,
  the one source of it.
- **Generated from it, by the build:** the Core Data model, the code and
  tables that keep its constraints, and its listing; through them the
  OData service and the sync.
- **Written by hand:** the forms, in the manner of TopoText's SimpleNotes:
  - an AppKit app for macOS and GNUstep;
  - an iOS app;
  - a server.

Early days: the model is done, the server runs it, and the desktop app
keeps a vehicle's records, its schedules and reminders, and its reports.

## Schedules and reminders

What happens to a reminder is procedure, not model: closed when an event
does its work, the schedule's next made, moved, cancelled and replaced,
reopened when the record that closed it is discarded
([docs/PROCESSES.md](docs/PROCESSES.md)). `Shared/LBProcedures.h` carries
each out on the model's generated classes, Foundation and Core Data
only, and the model's rules check what it leaves at save. What a
procedure makes is named by what it is made of (a name-based UUID: "next
of" the reminder it follows), so two devices that do the same, offline,
make the same objects.

- The server runs them as OData actions bound to what they act on
  (`Start`, `Complete`, `Reschedule`, `Cancel`, `Discard`:
  `Server/LBActions.h`), and closes the reminders an event does the work
  of whenever it saves one, whichever device sent it.
- The desktop app, online, calls the actions from its Reminders tab: the
  chosen vehicle's schedules and reminders, the open first, overdue as the
  model's queries say, and how each was moved before.
- The mobile app will run the same procedures in its own store, and sync
  what they made.

## The model

`Model/Logbook.orm` is the model, and the only copy of it: its facts,
constraints, queries and derivations, its Core Data mapping, and its
diagrams. It is ORMKit's model in NORMA's file format, so NORMA opens it
too. Change it in ORMDesigner, or apply lines of FORML to it, as the
listing says them:

```sh
ormtool apply Model/Logbook.orm changes.forml   # "- line" takes one away
```

([docs/CSDP.md](docs/CSDP.md#the-model) says how.) What the apps and the
server use is generated from it by the build, into `build/Model`
(`obj/Model` on GNUstep), with ORMKit's `ormtool`, built from
`../NativeORM2` first:
- `Logbook.xcdatamodeld`, the Core Data model (compiled to `Logbook.momd`,
  and its classes generated, as Xcode does);
- `Constraints/`: `LogbookValidation.h` and `.m`, and `Logbook.ormplans`,
  the code and tables that keep the model's rules and work out its stored
  derivations;
- `Logbook.forml`, the listing: every statement of the model, a line each,
  as the verbalizer says it, for reading and for copying lines from.

None of it is kept in git, nor edited: it is made again whenever the
model, or ormtool, changes.

## The server

`logbook-server` serves the logbook over OData for the apps to sync with:
ODataKit's service, with ODataSync's part of it, and the model's rules
kept as it writes. Before it saves a request, or a change set at its end,
the stored derivations are worked out and every rule is checked for what
the change reaches (the generated code in `build/Model/Constraints`); a change
that breaks one is refused, `400`, and nothing of it is saved.

```sh
make -f Makefile.apple && make -f Makefile.apple check     # macOS
make && make check                                          # GNUstep
.tools/gnustep.sh make check                                # GNUstep, in ORMKit's image
build/logbook-server -StoreURL logbook.sqlite -Port 8080 -Localhost NO
```

It builds on ORMKit's runtime from `../NativeORM2`, and on the ODataKit
release ORMKit pins. `make check` checks the procedures over a store of
their own (`Tests/LBProceduresCheck.m`), then `Tests/serve-and-check.py`
runs the server on a temporary store and checks it over HTTP: the
reference data, a change set saved with what it derives, one a rule
refuses, the actions and automatic completion, and who may do what,
signed in; then `Tests/app-check.sh` drives the desktop app against one.

### Signing in with Keycloak (or another OpenID Connect provider)

As SimpleNotes does:

1. In the realm, add a client with Client ID `logbook`: public (no client
   authentication), with **OAuth 2.0 Device Authorization Grant** on. The
   apps sign in with a code entered in a browser, so they need no redirect
   URI. Its tokens carry the user's email (the realm's default `email`
   scope): that is who they are in the logbook.
2. Run the server with the realm as its issuer:

   ```sh
   build/logbook-server -StoreURL logbook.sqlite -Port 8080 -Localhost NO \
     -ServiceRoot https://logbook.example.com/odata/ \
     -JWTIssuer https://id.example.com/realms/<realm> -AllowAnonymous NO
   ```

   `-JWTAudience` additionally checks the tokens' audience, if your realm
   sets one. Each setting is an `LB_` variable too (`LB_JWT_ISSUER`).
   `$metadata` stays readable without signing in, so the apps can find
   out where to sign in.

Once signed in, who may see and change what is the model's
([Permissions](docs/CSDP.md#permissions)):
- a user sees the vehicles they drive (own, or are a driver of) and what is
  recorded of them, themselves, and the people they share a vehicle with;
- a vehicle is its maker's; only its owner changes it, shares it, values
  it, and changes or removes what is recorded of it;
- whoever drives a vehicle adds records to it, entered by them;
- a user is named by their email: a vehicle is shared with someone by it,
  before they first sign in too; what else is said of a user is theirs;
- units and kinds of cost are the app's; an exchange rate is added, never
  changed;
- whoever drives a vehicle closes and moves its reminders; its owner
  starts its schedules, cancels its reminders and discards its records.

Without a sign-in (no `JWTIssuer`), anyone who can reach the server may do
anything: for trying it out.
