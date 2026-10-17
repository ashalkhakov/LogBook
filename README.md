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

Early days: the model comes first.
