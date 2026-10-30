# The iOS app

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
([PROCESSES.md](PROCESSES.md#offline-the-phone)).

A receipt's photo is an Attachment of its record, the image its content: a
JPEG no larger than 2000 pixels on its longest side, which syncs with the
record (`Edm.Binary` in the sync's JSON; kept in a file beside the store,
as Core Data keeps a large value), to the server and every other device
of the vehicle's. The desktop app lists a record's attachments beside it,
opens one as the system opens a file of its kind, attaches a file (Add…)
and removes one.

## Building and running it

```sh
make -f Makefile.apple ios          # build/ios/iphoneos (unsigned) and build/ios/iphonesimulator, Logbook.app
make -f Makefile.apple ios-check    # the simulator's app driven from within against a server of its own
make -f Makefile.apple ios-install DESTDIR=out   # out/iphoneos and out/iphonesimulator/Logbook.app
xcrun simctl install booted build/ios/iphonesimulator/Logbook.app
```

No Xcode project: clang links it against the iOS slices of ODataKit's
XCFrameworks and of ORMRuntime (from ORMKit's release),
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
`.deps`, to try one not released yet.
