# The server

`logbook-server` serves the logbook over OData for the apps to sync with:
ODataKit's service, with ODataSync's part of it, and the model's rules
kept as it writes. Before it saves a request, or a change set at its end,
the stored derivations are worked out and every rule is checked for what
the change reaches (the generated code in `build/Model/Constraints`); a change
that breaks one is refused, `400`, and nothing of it is saved.

```sh
build/logbook-server -StoreURL logbook.sqlite -Port 8080 -Localhost NO   # built (BUILDING.md)
./Logbook-*.AppImage --server -StoreURL logbook.sqlite -Port 8080 -Localhost NO   # Linux, the release's
```

`-StoreType PostgreSQL` or `MySQL` (with `-StoreURL` the database's URL)
keeps it in a database server instead of a SQLite file: FreeCoreData's
stores, which the AppImage carries.

## Signing in with Keycloak (or another OpenID Connect provider)

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

Once signed in, who may see and change what, and call which action, is
the permissions file's, `Server/Logbook.permissions.plist`
([Permissions](CSDP.md#permissions); the stock's in
[STOCK.md](STOCK.md#who-may)). It is ODataKit's
([permissions.md](https://github.com/ashalkhakov/ODataKit/blob/master/docs/permissions.md)):
relations in the manner of Google's Zanzibar, which the service checks on
every read, write and action. The build checks the file against the model
(`odatakit-permissions check`), and the server does not start with one
that does not fit. What it says:
- a user sees the vehicles they drive (own, or are a driver of) and what is
  recorded of them, themselves, and the people they share a vehicle with;
- a vehicle is its maker's; only its owner changes it, shares it, values
  it, and changes or removes what is recorded of it;
- whoever drives a vehicle adds records to it, entered by them, with
  their items, photos and answers;
- a user is named by their email: a vehicle is shared with someone by it,
  before they first sign in too; what else is said of a user is theirs;
- units and kinds of cost are the app's (the model's reference data,
  every store's from the start: 'Maintenance' and 'Repair', a service's,
  'Fuel', 'Tyres', 'Documents'); a user adds kinds of expense of their
  own, which no one removes; an exchange rate is added, never changed;
- whoever drives a vehicle closes and moves its reminders; its owner
  starts its schedules, cancels its reminders and discards its records.

A request that names no one holds nothing the file limits (with
`-AllowAnonymous NO`, it is refused outright). Without a sign-in (no
`JWTIssuer`), the file is not read, and anyone who can reach the server
may do anything: for trying it out.
