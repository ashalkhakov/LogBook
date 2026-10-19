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
with what it derives, one a rule refuses, and who may do what, signed in.

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
  changed.

Without a sign-in (no `JWTIssuer`), anyone who can reach the server may do
anything: for trying it out.
