# Stock: what the app does with it

The model's stock section ([`Model/Logbook.orm`](../Model/Logbook.orm), the
Stock diagram) says what may be recorded of catalogs, items, kits, orders,
shipments, receipts, moves and holdings, and what must hold of it. This is
the design of what the apps do with it: the screens people work in, and the
procedures that change stock, as [PROCESSES.md](PROCESSES.md) is for
reminders. It is a design; [Steps](#steps) says in what order it would be
built, [Decisions](#decisions) what was settled, and
[Extensions](#extensions) how it grows toward a warehouse system.

The app is a clone of KiWi Stock Control (screenshots in `stock/`), grown
toward what warehouse systems do, without becoming one: a person with a
garage of parts, or a small shop, should find it no more work than KiWi.

## What it covers

| Area | What people do | Where |
|---|---|---|
| Setup | catalogs, their currency and units; warehouses, locations within them; who works where | [Setup](#setup) |
| Catalog | items, categories, suppliers, customers, attributes; kits and their recipes | [Items](#items), [Kits](#kits) |
| Orders | purchase and sale orders, their lines, confirmed, closed or cancelled | [Orders](#orders) |
| Fulfilment | receiving purchases, shipping sales, in parts, phantom kits expanded | [Receiving](#receiving), [Shipping](#shipping) |
| Stock | holdings per location; transfers, adjustments, counts; assemblies | [Holdings](#holdings), [Moves](#moves-transfers-and-adjustments), [Counts](#counts), [Assembly](#assembly) |
| Planning | what is committed, available, coming; what to reorder | [Available](#on-hand-committed-available), [Reorder](#reorder) |
| Looking back | an item's history, the changelog, statistics | [Overview](#overview-and-history) |

Not in the first version, as agreed: barcodes, PDF and CSV export, alerts
and passwords. Designed to come after it: returns, picking and packing as
steps of their own, lots and serial numbers, fulfilment orders, costing
beyond the item's unit cost ([Extensions](#extensions)).

## The ideas it rests on

**Every change of stock is a move.** A move is so many of an item, from a
location, to a location, or both; nothing else changes how many are kept.
A move says what made it: a receipt, a shipment, an assembly, a count, or
an adjustment and its reason (the model allows one of these at most; a move
of none is a transfer). The moves are the ledger; everything else about
quantities is worked out from them.

**A holding is what the moves leave.** How many of an item are at a
location is the moves into it less the moves out of it. The model should
say so: "Holding has Quantity" derived from the moves, and stored
([Holdings](#holdings)). Then no screen sets a quantity by hand, a holding
can never disagree with its history, and since a quantity is never below
zero, a move out of more than is there is refused, as the rule it breaks
says.

**What is worked out is the model's, not the app's.** A line's shipped and
outstanding quantities, an order partly or fully shipped, what a kit can
make, what is committed and available: derived fact types, stored, kept up
to date at every save on the server and on the phone alike
(ORMKit's `docs/DERIVATION.md`). The apps show them;
they never compute them.

**What happens is procedure.** Confirming an order, expanding a phantom
kit, receiving, shipping, counting, assembling: each is a procedure in
`Shared/LBProcedures.h` (or a new `LBStockProcedures.h`) on the generated
classes, run by the server as an OData action and by the iOS app in its
own store, as reminders' are. What a procedure makes is named by what it is
made of, so two devices that do the same make the same objects
([Names](#names)).

**A screen is a form.** Each screen is anchored on one object (an item, an
order, a shipment) and shows some of its facts, as
ORMKit's `docs/FORMS.md` has it. Built by hand for now,
each is written down here as the facts it shows and the procedures it
calls, so it can be generated once forms are.

## Setup

**Catalog** (KiWi's group): its name, its currency, its weight and size
units, its own prefix for document numbers; the categories (a tree), the
contacts, the item attributes it uses.

**Contacts:** a person or a company the catalog deals with: its name,
email, phone, note, and its addresses, one of them where it is shipped
to and one where it is billed. Being a customer or a supplier is a part a
contact plays; a company both is one contact, its addresses kept once. A
sale order takes its customer's addresses as they were when it was made;
a shipment says where it went. A user owns their catalogs; KiWi's "Reset quantities to
zero" becomes a count of everything to zero ([Counts](#counts)), not a
setting.

**Warehouses and locations.** A catalog has warehouses; a warehouse has
locations, nested (a room, its shelves, a shelf's bins). Each warehouse
says when it was last counted and when it is next to be. A new catalog gets
one warehouse with one location ("Main", "Default"), so a person with one
shelf never sees either until they want a second.

**Who works where.** A warehouse's staff: a user and their role, keeper or
manager. The catalog's owner may do anything; a manager what keepers may,
and orders, counts and the warehouse's locations; a keeper receives, ships,
moves, counts and assembles at their warehouses. Nobody else sees the
catalog. ([Who may](#who-may) has the table.)

## Items

**The item list** (KiWi's Items): each item's name, its category path, how
many are kept in all, and a mark when it is below its reorder point;
searched by name, tag, description; filtered by category, supplier,
warehouse; the catalog chosen above it.

**The item** (KiWi's item card), its sections:
- what it is: its SKU, name, category, description, photos, note, count
  unit, the catalog's attributes it has;
- its codes: the barcodes and tags it is scanned or read by;
- whom it is bought from: its supplier items, the preferred one first;
- money: its price and unit cost, in the catalog's currency;
- quantities: on hand, committed, available, incoming
  ([below](#on-hand-committed-available)), and each location's holding;
  each holding opens its moves;
- weight and size: as KiWi has them, and the totals for what is kept;
- dates: created, purchased, expires;
- reordering: each warehouse's reorder point and level;
- a kit's recipe and what it can make ([Kits](#kits));
- history: its moves, newest first, each with what made it and by whom;
  its open order lines.

Deleting an item that has moves or order lines is refused (the model's
rules); one with neither is deleted with its holdings at zero.

**Its SKU** is the catalog's own number for it: on its labels, on every
order, in the changelog; kept whoever supplies it, and what customers
order it by. Every item has one, unique in its catalog; one left out is
given, the catalog's prefix and a running number (`GAR-00042`). Taking a
supplier's is only a starting point: an item made from a supplier's
listing may start with their SKU as its own, and from then on it is
the catalog's.

**Supplier items.** What a supplier sells of an item: its own SKU for it
(written on purchase orders to it), its description, what it charges, in
what packs, at the least how many, and how many days it takes. An item may
have several; the one it is preferably bought from is what reordering
buys (else its only one), at that supplier's cost, at least its minimum,
in whole packs (120 wanted, packs of 50: 150).

**Codes.** What is printed on an item or its pack and scanned (a GTIN:
EAN-13, UPC-A, EAN-8; a Code 128; a QR code), or read from its RFID tag
(an EPC), and how many units each stands for (a case's barcode, its
count). An RFID tag of a GTIN's (an SGTIN: a GTIN and a serial) is read
as its GTIN, so no tag need be entered one by one; its serial is the
unit's, once there are [serials](#lots-serials-and-expiry). Scanning is
not in the first version; the codes are kept from the start.

## Kits

An item becomes a kit when it is given a recipe: lines of so many of other
items, for a batch of it, and the batch's yield. Its card then shows the
recipe and how many it can make, from its components as kept. It is
assembled (made ahead and kept) or a phantom (never kept: sold as its
components), chosen once; a phantom's holdings, moves and assemblies are
refused by the model.

The recipe is edited on the item; a component that would make the kit
contain itself is refused (the model's ring rule).

## On hand, committed, available

What warehouse systems show of an item, and what the model should derive,
stored, per item (per warehouse is for later: [fulfilment
orders](#fulfilment-orders) give it):

| Quantity | Is | In the model |
|---|---|---|
| on hand | what the holdings keep | `StockItem totals Quantity` (there) |
| committed | what confirmed sale orders still want of it: their lines' outstanding | to add |
| available | on hand less committed | to add |
| incoming | what confirmed purchase orders still bring: their lines' outstanding | to add |
| can make | a kit's, from its components on hand | `StockItem can make Quantity` (there) |

A phantom kit's available is what it can make from its components'
available; its committed is its components' lines'.

## Orders

**The order lists:** purchases and sales apart, each order's number,
supplier or customer, date placed, state, how far filled (nothing yet,
partly, fully), its total; the open first.

**An order:** its supplier or customer, number, date, note; its lines, each
an item, a quantity, a price (sales) or unit cost (purchases), and for an
open order what is received or shipped and what is outstanding; its
receipts or shipments. A sale line of a phantom kit shows its component
lines under it, unpriced.

**Its states,** as the model has them: a draft, confirmed, closed, or
cancelled. The procedures:

| Action | Does | From |
|---|---|---|
| `Confirm` | a draft confirmed: its phantom kits' lines expanded ([below](#expand)); what it wants now committed | draft |
| `Close` | done with, whatever is outstanding: no longer committed or incoming | confirmed |
| `Cancel` | never to be filled: refused once something is received or shipped | draft, confirmed |
| `Reopen` | a closed one confirmed again | closed |

A draft's lines are changed freely; a confirmed order's too, but a line
cannot go below what is already received or shipped.

### Expand

When a sale order is confirmed, or a phantom kit's line is added to a
confirmed one, its line is given a line for each component: so many as its
kits take in whole batches (⌈kits ÷ yield⌉ × so many per batch, as the
model's rule says), named by the kit line and the component. Changing the
kit line's quantity changes them; deleting it deletes them. What a kit line
has shipped is contracted back from them by the model, whole batches of the
least shipped.

## Receiving

A **receipt** is what came in of a purchase order at once: a day, a
location, and for each line received, how many. The receive screen opens
from the order with each outstanding line's quantity offered, to be
lowered for what did not come; `Receive` makes the receipt and a move into
the location for each line, in one save. A receipt received in part leaves
the rest outstanding; the order is partly received until none is.

## Shipping

A **shipment** is what went out of a sale order at once: a day, a
location, and for each line shipped, how many. The ship screen opens from
the order with each outstanding line's quantity offered (a phantom kit's
as its components' lines), lowered to what is available at the location;
`Ship` makes the shipment and a move out of the location for each line.
Shipping more than is there is refused by the holding's quantity; more
than a line is for is warned of (the model's deontic rule). The order is
partly shipped until nothing is outstanding.

Picking and packing are not steps of their own in the first version
([Extensions](#extensions)).

## Holdings

A holding is an item at a location and how many are there. Its quantity,
derived from the moves, changes only as they do; a holding is made by the
first move into its location and kept at zero after the last out, so its
history stays reachable. The item card and the location's screen list
holdings; neither edits a quantity.

## Moves: transfers and adjustments

**A transfer** moves so many of an item from one location to another (a
shelf to another, a warehouse to another): `Transfer`, one move with both.

**An adjustment** adds or takes away outside any order, with a reason:
opening (the stock an item starts with), found, damaged, lost, expired,
other. `Adjust` makes one move, to or from the location.

**The changelog** (KiWi's): every move, newest first: when, the item, the
location's quantity before and after, what made it, by whom; filtered by
item, location, reason, what made it, a span of days.

## Counts

A **count** is a stock take: at a warehouse or one of its locations, on a
day, by a user, how many of each item were found. `Count` compares each
with its holding and makes an adjustment of the difference (reason
"Count"), and sets the warehouse's last counted day when the whole
warehouse was counted. A count of a location lists its holdings with their
quantities hidden or shown, as the counter chooses; an item found that
was not expected is added.

A count is an object of its own in the model, as a shipment is:
`StockCount` (of a location, on a day, by a user), grouping its
adjustments ([Changes to the model](#changes-to-the-model)).

## Assembly

`Assemble` makes so many batches of an assembled kit at a location: a move
out of each component, so many per batch, and a move in of the kit, its
yield per batch; refused where a component is short. `Disassemble` the
other way round. The screen opens from the kit's card, with what it can
make offered.

## Reorder

Each item may have, per warehouse, a reorder point and a level. When what
is available and incoming there falls below the point, the item is due: the
overview lists those due, and `Reorder` makes draft purchase orders, one
per supplier, of a line each for the level less what is available and
incoming. Nothing is ordered until a person confirms the drafts. ("Due" is
a derived fact type: [Changes](#changes-to-the-model).)

## Overview and history

**Overview** (KiWi's): the catalog's statistics (items, total quantity,
total value at price and at cost, total weight and volume, categories,
locations, suppliers), the items due for reorder, the open orders, the
next counts due.

**An item's history**, a location's, an order's: their moves, as the
changelog shows them.

## Who may

| | Owner | Manager | Keeper |
|---|---|---|---|
| catalog, items, kits, categories, suppliers, customers | yes | | |
| warehouses, locations, staff | yes | locations of theirs | |
| orders: make, confirm, close, cancel | yes | yes | |
| receive, ship, transfer, adjust, count, assemble | yes | at theirs | at theirs |
| see the catalog | yes | yes | yes |

The server checks each request against it (`Server/LBPermissions.h`); the
model's rules check what each leaves.

## Names

What a procedure makes is named, as reminders' are (a name-based UUID in
Logbook's namespace):

| What is made | Its name |
|---|---|
| a phantom kit line's component line | `<kit line id> component <item id>` |
| a receipt, a shipment | `<order id> receipt <n>`, `<order id> shipment <n>` (n counted up) |
| a receipt's or shipment's move | `<receipt or shipment id> for <line id>` |
| an assembly's moves | `<assembly id> uses <item id>`, `<assembly id> makes` |
| a count's adjustment | `<count id> for <item id> at <location id>` |
| a holding | `<item id> at <location id>` |
| a reorder's draft order, its lines | `reorder <rule date> from <supplier id>`, `<order id> for <item id>` |

A holding named by its item and location is one holding however many
devices make it.

## Platforms

- **The server** runs every procedure as an action bound to what it acts
  on (`Server/LBStockActions.h`), saved whole or refused (400, the
  procedure's words), each by whom the table above lets:

  | Action | Bound to | Parameters | Answers |
  |---|---|---|---|
  | `Confirm`, `Close`, `Cancel`, `Reopen` | an order | | the order |
  | `ExpandKits` | a sale order | | the order |
  | `Ship` | a sale order | `Lines` {line id: quantity}, `From`, `Day` | the shipment |
  | `Receive` | a purchase order | `Lines` {line id: quantity}, `At`, `Day` | the receipt |
  | `Transfer` | an item | `Quantity`, `From`, `To` | the move |
  | `Adjust` | an item | `Quantity` (less than none: out), `At`, `Reason`, `Note` | the move |
  | `Assemble` | a kit | `Batches`, `At`, `Day`, `Disassemble` | the assembly |
  | `Count` | a warehouse | `Location` (none: all of it), `Found` [{Item, Location, Quantity}], `Day` | the count |
  | `Reorder` | a warehouse | `Day` | the drafts |

  An order or a count posted with no number is given the next.
- **The desktop app** has a window for each thing stock is made of. The
  Stock window lists: the catalog's items, sales, purchases, the
  changelog (each move with what its locations held before and after),
  counts, and the overview (with what is held weighs and takes up, in the
  catalog's units). What it lists opens in a window of its own, which
  edits it: an item (its stock, recipe, suppliers, codes, size, reorder
  rules), an order, a count being taken, the catalog's settings. Each
  window has its own context and reads only what it shows; after a save
  or an action it says stock changed, and the others read theirs again.
  The actions are the server's, as the Reminders tab calls them.
- **The iOS app** has KiWi's tabs (Items, Orders, Overview, Settings), runs
  the procedures in its own store, and syncs.

## Changes to the model

Made (`lb-stock-check` checks each), as the design above needs them:
1. **A holding's quantity derived from the moves,** stored: its moves to
   its location less those from it, of its item. (Of its lot too, once
   there are [lots](#lots-serials-and-expiry): the holding should be
   designed for them now.)
2. **Committed, available, incoming,** per item, derived and stored.
3. **A count:** `StockCount` of a location, on a day, by a user, a move
   part of at most one, those moves adjustments of reason "Count".
4. **Due for reorder:** `ReorderRule is due`, derived (available and
   incoming below its point).
5. **Numbers:** a document's number is the app's prefix for its kind
   (`PO`, `SO`, `RC` a receipt, `SH` a shipment, `CT` a count), the
   catalog's own prefix as its owner types it in setup (`GAR`), and a
   running number of that kind in the catalog: `PO-GAR-0042`. The running
   number is the model's (`RunningNumber`: unique per catalog for orders,
   per order for receipts and shipments, per warehouse for counts); the
   text is made from it. A supplier's or customer's own reference is a
   fact of its own.
6. **Contacts:** `Contact` and `Address`; `Customer` and `Supplier` each of
   one contact, in its catalog; a sale order's ship-to and bill-to, a
   shipment's ship-to.
7. **SKUs, supplier items, codes:** `StockItem has SKU` (required, unique
   per catalog); `SupplierItem` (the supplier's SKU, cost, pack size,
   minimum, lead days; one preferred per item) for what was one supplier
   per item; `ItemCode` (code, kind, units) for KiWi's tag.

## Steps

1. Done: the model's changes above, and `lb-stock-check` for each.
2. Done: the procedures, in `Shared/LBStockProcedures.h`, checked by
   `lb-stock-check`: holdings made by moves, transfer and adjust, assemble
   and take apart, orders numbered, confirmed (expanded), closed,
   cancelled and reopened, receive and ship, count, reorder.
3. Done: the server's actions and permissions (`Server/LBStockActions.h`,
   `Server/LBPermissions.h`), checked over HTTP by
   `Tests/serve-and-check.py`.
4. The desktop Stock window: items and the item card, then orders,
   receiving and shipping, then the changelog, counts, overview, setup.
5. The iOS tabs.

## Extensions

How the design grows toward a warehouse system, each in the model's terms,
each approved. None is in the first version; each is drawn so the first
does not have to be undone for it. Picking and packing and lots are as
ShipStream has them; fulfilment orders are Shopify's.

### Returns

Goods come back against the line they went out on, and go back against
the line they came in on; the money (refunds, credit notes) is not stock's.

```
CustomerReturn(.id) is of SaleOrder; was received on Date; at Location; has Note.
Move returns SaleLine.                       -- into the return's location
SaleLine has returned Quantity.  ** total of its returning moves
ReturnReason: 'Damaged', 'Wrong item', 'Not wanted', 'Other'.
CustomerReturn is for ReturnReason.

SupplierReturn(.id) is of PurchaseOrder; was shipped on Date; from Location.
Move returns PurchaseLine.                   -- out of the return's location
PurchaseLine has returned Quantity.  ** total
```

- A return's moves are of the line's item, into (or out of) the return's
  location, as a receipt's and a shipment's are; a move is part of one
  document at most.
- What a returned item becomes is its location: back on a shelf for sale,
  or into one marked not for sale (`Location is not for sale`), from which
  it is adjusted away as damaged or moved back once checked. On hand
  counts only what is for sale.
- A line can return no more than went out (an alethic rule: returned ≤
  shipped). A return does not make the line outstanding again; sending a
  replacement is a new line, or a new order.
- A phantom kit comes back as its components, against their lines.

### Picking and packing

A shipment becomes a process of three steps, each with its moves, so
holdings say where the goods are at every step:

```
Location is a staging area.
Pick(.id) is for Shipment; is assigned to User; was done at Moment.
Move is part of Pick.                        -- a bin to the staging area
Package(.id) is of Shipment; weighs Weight; measures Size×3;
  has TrackingNumber; is sent by Carrier.
Package holds Quantity of SaleLine.          -- what is packed in it
Shipment was shipped on Date.                -- now optional: planned first
```

- **Planned:** a shipment is made with its lines and quantities and no day:
  what is to go out. What it plans is committed, as now.
- **Picked:** each pick moves its lines' goods from their bins to a staging
  area, a keeper per pick; picking follows the bins' order (a location's
  sequence) and, with lots, the earliest expiry first.
- **Packed:** packages are made and filled; each says what it holds of each
  line, its weight and size; a packing slip lists them.
- **Shipped:** on the day it goes, a move of each line out of the staging
  area, and its tracking numbers.
- Its state is derived and stored, as an order's is, so lists and queries
  read it: planned, picked (every line picked), packed (every line
  packed), shipped (it has its day).
- For a small shop it stays one step: `Ship` picks, packs nothing and ships
  at once, as in the first version.

### Lots, serials and expiry

Some items are kept by lot (food, medicines, paint: what came in together,
with one expiry), some by serial number (one of each: tools, machines).

```
StockItem is kept by lot.  StockItem is kept by serial.   -- not both
Lot(.id) is of StockItem; has LotNumber; expires on Date; was made on Date.
For each StockItem and LotNumber, at most one Lot is of it and has it.
Serial(.id) is of StockItem; has SerialNumber; (unique per item).
Move is of Lot.  Move is of Serial.
Holding is of Lot.                           -- optional; one per item, location and lot
```

- A move of an item kept by lot names its lot, and its lot is of its item
  (a join subset); one kept by serial names its serial and is of 1.
  An item kept by neither names neither.
- **Holdings are kept per lot:** one per item, location and lot (none where
  the item has no lots). The derived holding quantity of the first version
  sums the moves of its item at its location and, where it has one, of its
  lot: designed so now, nothing changes when lots come.
- A serial is where its last move left it: `Serial is at Location`,
  derived. A serial shipped is gone; returned, it is back.
- RFID: a serial's EPC is its tag (an SGTIN, its GTIN and its serial,
  or a code of the catalog's own); a tag read is the unit it is on.
- Expiry: picking takes the earliest expiry first; the overview lists lots
  expiring soon; an expired lot is adjusted away (reason "Expired").
  The item's own expiry date of the first version moves to its lots.
- Receiving asks the lot (number, expiry) or the serials of each line kept
  so; a count counts per lot.

### Fulfilment orders

When one sale ships from several warehouses, what ships from where is
decided before any of it is picked. Shopify calls that a fulfilment order:

```
FulfilmentOrder(.id) is of SaleOrder; is from Warehouse;
  is in FulfilmentState ('Open', 'In progress', 'On hold', 'Closed', 'Cancelled').
FulfilmentLine(.id) is of FulfilmentOrder; is for SaleLine; is for Quantity.
Shipment is of FulfilmentOrder.              -- its sale order through it
```

- **Routing:** on `Confirm`, the order's lines are assigned to warehouses:
  all to one that has everything available, else split, the most to the
  one with most; each warehouse's share a fulfilment order. A person can
  move a line, or a share of it, to another, or hold one.
- A sale line's fulfilment lines add up to it (a rule); a shipment ships
  only what its fulfilment order assigns, from its warehouse's locations.
- **Committed per warehouse** follows: a warehouse's fulfilment lines'
  outstanding. With it, available per warehouse, and reorder rules that
  look at their own warehouse (the per-item first version says per
  item).
- A warehouse's keepers see their fulfilment orders as their work list:
  open, in progress, on hold.
- The purchase side's counterpart (an advance shipping notice: what a
  supplier says is on its way, to which warehouse) can come the same way.

### Bills of materials with revisions

A kit is an item, so it has a SKU and is sold and kept by it. Its recipe
has no identity of its own: one recipe per kit. Where an item is made by
more than one recipe, or by revisions of one (v1, v2), the recipe becomes
an object, `BillOfMaterials` (of an item, its revision, one of them
current), and the kit lines are its rather than the item's; assemblies
and expansions then say which they followed.

### Costing

The item's unit cost is a fact as the person enters it. Next: each receipt
line's cost, and the item's average cost worked out from them (moving
average), so the stock's value is at what it cost; a sale line's margin at
it. FIFO costing needs lots, and comes after them.

## Decisions

1. A holding's quantity is derived from the moves, and stored.
2. A count is a `StockCount`, grouping its adjustments.
3. Committed, available and incoming are per item for now; per warehouse
   comes with fulfilment orders.
4. Numbers: the app's prefix for the kind of document, the catalog's own
   prefix that its owner types in, and a running number
   ([Changes](#changes-to-the-model), 5).
5. The desktop app's stock is a window of its own.
