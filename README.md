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

Early days: the model is done, the server runs it, the desktop app keeps
a vehicle's records of every kind (added, corrected and removed in its
Records tab: an inspection's answers, an income's trip, what a cost was
charged, files attached), its schedules and reminders, and its reports,
and the iOS app (below) logs on the road, offline first.

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
  (`Start`, `Continue`, `Complete`, `Reschedule`, `Cancel`, `Discard`:
  `Server/LBActions.h`), and closes the reminders an event does the work
  of whenever it saves one, whichever device sent it.
- The desktop app, online, calls the actions from its Reminders tab: the
  chosen vehicle's schedules and reminders, the open first, overdue as the
  model's queries say, and how each was moved before. A schedule is
  changed (Edit Schedule) by going on in a new one (the `Continue`
  action): its past stays as it was, its open reminder due anew. The
  kinds of expense and the checklists the forms pick from are the users'
  own, written in their own window (Expense Kinds…, Checklists…, or Edit…
  beside a pop-up), as are the exchange rates costs by month counts each
  cost at (Exchange Rates…). Kinds and rates are kept once saved.
- The iOS app runs the same procedures in its own store as it saves,
  offline or not, and syncs what they made ([iOS](#the-ios-app)).

## The iOS app

`iOS/`: a driver's logbook in the pocket, for the drivers and the owner;
managing and reporting stay with the desktop app. It keeps the logbook in a
store of its own (`Shared/LBLocalStore.h`: Core Data's SQLite, the model
generated from `Model/Logbook.orm`) and syncs it with the server through
ODataKit's ODataSync: as it opens and comes back, a little after each save,
and every minute; with sync off (a switch), what is saved waits.

- **Sign in:** the server's address; signed in as the server asks (OpenID
  Connect's device flow, a code entered in any browser; its tokens in the
  Keychain), or, for a server with no sign-in, as the email you give.
- **Timeline:** the chosen vehicle's records, newest first, by month: kind,
  when, cost; tap one to edit it.
- **Reminders:** open and overdue first (the model's queries), then done
  (by what) and cancelled; move one to another day, or, the owner, cancel
  it.
- **Vehicle:** choose one; its details; consumption at full tanks, what
  this month cost, what is due next; the owner adds a vehicle and shares it
  by email (a driver is offered no sharing); sync, what waits and what the
  server refused; pending conflicts; the account. Signing out deletes the
  phone's logbook: with changes waiting (or conflicts not settled), it
  says how many would be lost first: Sync Now (then signs out, if that
  leaves nothing to lose), Sign Out Anyway, or Cancel.
- **+**, over the tabs: a fill-up first (now, odometer, volume, cost, full
  tank, station, in the user's units and currency), a service and its
  items, an expense, a trip, a meter reading, an inspection (its
  checklist's questions); each with photos of receipts.

Saving does what the server does: the reminders the events close are
closed (automatic completion), what is derived is worked out, and every
rule is checked; a deontic rule (the meter going down) is said before
saving, and the user may go ahead; a rule broken refuses, in the model's
words. Whatever the procedures make is named by what it is made of, so the
phone and the server make the same reminders, which the sync meets as one.

A record changed on the phone and elsewhere before they meet is a
conflict: the server's version stands, the sync goes on, and what the
phone changed waits as a pending conflict (a badge on the Vehicle tab):
keep theirs, keep mine (written back as a new change), or edit by hand
([PROCESSES.md](docs/PROCESSES.md#offline-the-phone)).

A receipt's photo is an Attachment of its record, the image its content: a
JPEG no larger than 2000 pixels on its longest side, which syncs with the
record (`Edm.Binary` in the sync's JSON; kept in a file beside the store,
as Core Data keeps a large value), to the server and every other device
of the vehicle's. The desktop app lists a record's attachments beside it,
opens one as the system opens a file of its kind, attaches a file (Add…)
and removes one.

### Building and running it

```sh
make -f Makefile.apple ios          # build/ios/iphoneos (unsigned) and build/ios/iphonesimulator, Logbook.app
make -f Makefile.apple ios-check    # the simulator's app driven from within against a server of its own
make -f Makefile.apple ios-install DESTDIR=out   # out/iphoneos and out/iphonesimulator/Logbook.app
xcrun simctl install booted build/ios/iphonesimulator/Logbook.app
```

No Xcode project: clang links it against the iOS slices of ODataKit's
XCFrameworks and of ORMRuntime (built from `../NativeORM2` for iOS),
`momc` and `actool` compile its resources, its settings come from
`iOS/Logbook-iOS.xcconfig` (the bundle id, the version, `LB_DEFAULT_SERVER`,
the address the sign-in offers first). For a device, sign the app in
`build/ios/iphoneos` with your team (`DEVELOPMENT_TEAM` in
`iOS/Local.xcconfig`, which git ignores). The icon is a placeholder.
`make -f Makefile.apple check` runs `ios-check` too where Xcode has an
iPhone simulator. The self-test (`iOS/LBiOSSelfTest.h`) signs in by
email, adds a vehicle, logs a fill-up with sync off and sends it, closes a
schedule's reminder with a service (the server agreeing, by id), settles a
conflict each way, shares the vehicle, checks a driver is offered no
sharing, attaches a receipt's photo (one bundled in the simulator's app,
taken as the camera's would be: kept smaller, synced to the server and the
driver's phone), meets a deontic rule and a refusal, and signs out: warned
with changes waiting, each button as it says, and at once with none.

`ODATAKIT_DEPS=<dir>` builds against other XCFrameworks of ODataKit than
`../NativeORM2/.deps`, to try one not released yet.

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
reference data (the units, the kinds of cost), a change set saved with
what it derives, one a rule refuses, an attachment's photo there and
back, the actions and automatic completion, and who may do what, signed
in; `Tests/sync-check.sh` syncs two devices' offline stores through one,
a receipt's photo among what they sync (`Tests/LBSyncCheck.m`); then
`Tests/app-check.sh` drives the desktop app against one: every kind of
record added from its Add menu, its form typed into, saved, corrected and
saved again, each checked at the server.

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
- units and kinds of cost are the app's (the model's reference data,
  every store's from the start: 'Maintenance' and 'Repair', a service's,
  'Fuel', 'Tyres', 'Documents'); a user adds kinds of expense of their
  own, which no one removes; an exchange rate is added, never changed;
- whoever drives a vehicle closes and moves its reminders; its owner
  starts its schedules, cancels its reminders and discards its records.

Without a sign-in (no `JWTIssuer`), anyone who can reach the server may do
anything: for trying it out.
