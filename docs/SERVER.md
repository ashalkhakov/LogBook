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
stores, which the AppImage carries. The processes' store (the orders'
steps, `Server/LBWorkflow.h`) then goes in the same database, in a schema
of its own (`workflow`; in MySQL, a database of that name), apart from the
logbook's tables. Elsewhere, name it:

| Setting | Default | |
|---|---|---|
| `-Workflow` | `Workflow.sqlite` beside a SQLite store; the logbook's database on a database server | a SQLite file, or a database's URL (`postgresql://user:password@host:5432/workflow`) |
| `-WorkflowStoreType` | a URL's by its scheme (`postgresql:`, `mysql:`), a file's `SQLite`, the logbook's when `-Workflow` is not given | `SQLite`, `PostgreSQL` or `MySQL` |
| `-WorkflowSchema` | `workflow` | the schema the processes are kept in on a database server |

## In Docker

The server's image holds the server, `logbook-import`, what they read
beside them (the model, its tables, the permissions, the processes, the
forms' contracts), FreeCoreData's PostgreSQL and MySQL/MariaDB stores, and
the libraries they all run on. It has no shell and no package manager
(`Docker/server.Dockerfile`, built on the releases `.github/pins.env`
names, as SimpleNotes' server image is). A release publishes it as
`ghcr.io/ashalkhakov/logbook-server`, for amd64 and arm64.

```sh
docker run -p 8080:8080 -v logbook:/data ghcr.io/ashalkhakov/logbook-server
docker build -f Docker/server.Dockerfile -t logbook-server .   # from the repository's root
```

It runs as an unprivileged user (10001), and by default keeps its SQLite
store, and the processes' store beside it, in the `/data` volume. Configure
it with environment variables, `LB_` and a setting's name:

| Variable | Default | |
|---|---|---|
| `LB_STORE_TYPE` | `SQLite` | `SQLite`, `PostgreSQL` or `MySQL` |
| `LB_STORE_URL` | `/data/logbook.sqlite` | a path for SQLite, else the database's URL (`postgresql://user:password@host:5432/logbook`) |
| `LB_WORKFLOW` | `Workflow.sqlite` beside a SQLite store; the logbook's database on a database server | the processes' store: a file, or a database's URL |
| `LB_WORKFLOW_STORE_TYPE` | `LB_WORKFLOW`'s, by its scheme or as a file; else the logbook's | `SQLite`, `PostgreSQL` or `MySQL` |
| `LB_WORKFLOW_SCHEMA` | `workflow` | its schema on a database server |
| `LB_SERVICE_ROOT` | `http://<container>:8080/odata/` | the public URL the service is reached at: set it behind a reverse proxy, as its links begin with it |
| `LB_PORT` | `8080` | |
| `LB_JWT_ISSUER`, `LB_ALLOW_ANONYMOUS` | | signing in (below) |
| `LB_ACCESS_LOG` | `json` | JSON lines, for a log collector |
| `LB_HEALTH_PATH` | `/health` | for the orchestrator or the proxy |

With PostgreSQL, the logbook and its processes both in the database (the
processes in its `workflow` schema):

```sh
docker run -p 8080:8080 \
  -e LB_STORE_TYPE=PostgreSQL -e LB_STORE_URL=postgresql://logbook:secret@db:5432/logbook \
  ghcr.io/ashalkhakov/logbook-server
```

The processes in a database of their own instead:
`-e LB_WORKFLOW=postgresql://logbook:secret@db:5432/workflow`; in a SQLite
file still: `-v logbook:/data -e LB_WORKFLOW=/data/Workflow.sqlite`.

Behind a reverse proxy (Nginx Proxy Manager, Caddy, Traefik), forward a
host to the container's port 8080, and give the address users reach as
`LB_SERVICE_ROOT` (`https://logbook.example.com/odata/`).

## Importing another app's data

`logbook-import` puts another app's data into a user's logbook, as
the desktop's File > Import… does: it syncs the user's logbook into a
store of its own, enters each record through the model's form, and syncs
them up, so the server keeps its rules and permissions as for any device.
What the export says that Logbook has no place for is said first, and
nothing is made unless `-LeaveOut YES` says to go ahead.

```sh
build/logbook-import -Server https://logbook.example.com/ Drivvo.csv
build/logbook-import -Server https://logbook.example.com/ -Make Chevrolet -Year 2021 Drivvo.csv
docker run --rm -v "$PWD":/in --entrypoint /app/logbook-import ghcr.io/ashalkhakov/logbook-server \
  -Server https://logbook.example.com/ /in/Drivvo.csv
```

A server that asks for a sign-in is signed in to by its device flow (a
code to type at a page) or a password; one that asks for none takes
`-Email`.

What it reads:

- **Drivvo's CSV export** goes into your vehicle it is. It's found by its
  licence plate (case, spaces and dashes aside), else its name, else its
  model when only one of your vehicles has it; `-Vehicle` names one instead.
  When none is, a vehicle is made of what the export says: its name (else
  its model), model, plate, fuel and year. The export says no make, and 0
  for an unknown year, so `-Make` (and `-Year`) say them. Its fill-ups and
  services go in; its one fuel is taken as the vehicle's, its services as
  Maintenance.
- **MainTrack's store** (`Maintrack.sqlite`: on a Mac where MainTrack is
  installed, in `~/Library/Group Containers/group.kiwiswift.mainTrack/`)
  makes its own vehicles, so takes no `-Vehicle`: each bike a bicycle (of
  its name, else its brand and model), each component one of the bike it
  was first fitted to, each ride a trip (its readings added up from the
  rides before it), each assignment a component change (retiring the part
  taken off then), each invoice a service, its log entries the tasks. It
  reads a copy of the store, so MainTrack may be running.

```sh
build/logbook-import -Server https://logbook.example.com/ \
  ~/Library/Group\ Containers/group.kiwiswift.mainTrack/Maintrack.sqlite
```

- **An InvenTree instance** (`-InvenTree <its address>`) goes into one of
  the user's catalogs, named by `-Catalog` (made if the user has none of
  that name). It's read through InvenTree's API with a token that may
  read: `LB_INVENTREE_TOKEN` in the environment, else `-Token`. It makes:
  - its top stock locations as warehouses, the rest as locations in them;
  - its part categories as categories;
  - its suppliers as contacts and suppliers;
  - its parts as items, with each one's manufacturer and MPN;
  - its supplier parts as supplier items;
  - each stock item with a serial as a unit;
  - its purchase orders with their lines: Complete closed, Placed
    confirmed, Pending a draft;
  - receipts and moves by each stock item's tracking history, ending where
    InvenTree has it now. Stock bought outside an order is an opening
    adjustment, its price said in a note.

  InvenTree's references (PO-0001, its part and stock numbers) are kept in
  notes, so importing again passes over what's there and makes only
  what's new.

```sh
LB_INVENTREE_TOKEN=inv-... build/logbook-import -Server https://logbook.example.com/ \
  -InvenTree https://inventree.example.com -Catalog Home -LeaveOut YES
```

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

   Each setting is an `LB_` variable too (`LB_JWT_ISSUER`). `$metadata`
   stays readable without signing in, so the apps can find out where to
   sign in.
3. To check that the tokens are meant for Logbook (recommended), give
   `-JWTAudience logbook` (`LB_JWT_AUDIENCE=logbook`) **and** make
   Keycloak put `logbook` in them: Keycloak leaves a client out of its own
   tokens' audience (they say `account`). In Clients → `logbook` → Client
   scopes → `logbook-dedicated` → Add mapper → By configuration →
   **Audience**: Included Client Audience `logbook`, Add to access token
   on. Without the mapper the server refuses every token (401, "The token
   is not for this service": its log says so as `auth_failure`
   `audience`), and the apps say the server refused the sign-in.

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
