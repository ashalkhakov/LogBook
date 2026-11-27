# Logbook's model, by CSDP

Halpin's Conceptual Schema Design Procedure, step by step. The ORM model it
ends with is `Model/Logbook.orm`, the one source. Everything else is
generated from it by the build: the Core Data model, the OData service, the
sync, the code that checks the constraints, and the schema's listing.

## Scope

- **Assets:** what a person keeps, uses and maintains, as ISO 55000 means
  an asset (an item of value to its owner) and ISO 14224 an equipment
  unit. Vehicles are one kind: cars, motorcycles and bicycles, a motorised
  one diesel or petrol (no electric or hybrid for now). Generators, power
  stations, boilers and tools are others, each of an equipment class
  (ISO 14224's taxonomy). An asset bought through Stock is that stock
  unit; a component fitted to an asset may be an asset too, so assets
  make a hierarchy. The owner is the signed-in user. Others with whom the
  owner shares an asset (a vehicle's drivers) keep its data as the owner
  does. Everything syncs between devices and people, as SimpleNotes does.
- **Meters:** each asset's own, in its unit: kilometres or miles, hours,
  charge cycles, kilowatt-hours. Schedules, wear and costs go by it.
- **What it records:**
  - meter readings;
  - trips (vehicles');
  - fill-ups (any asset that uses a fuel);
  - work orders, as a CMMS keeps them: a work request, then a service
    planned and done, corrective or preventive (EN 13306), with its tasks,
    labour and parts, each with its own cost;
  - failures (ISO 14224: mode, mechanism, cause, detection, impact) and
    downtime;
  - tyre sets (vehicles');
  - components that wear and are replaced (a chain, brake pads, a
    battery): units of stock items, fitted, removed, put away;
  - documents: insurance, warranties, manuals;
  - other costs: parking, tolls, washes;
  - incomes: paid rides, freight, refunds, an asset's sale;
  - inspections: going through a checklist the users write, item by item;
    an answer may raise work;
  - schedules of work the users plan, and the reminders they mark done.
- **Every record of an event** says when it happened, to the minute, and
  who it was by (a vehicle's driver). It may carry a note and attached
  files.
- **Reports** per asset, and per kind of event; and the maintenance
  indicators of EN 15341, per asset, per class and per component.
- **Units** (distance, volume) are set for the app; a meter's is the
  asset's. Amounts may be entered in any currency and are reported in the
  preferred one.

The maintenance standards are measured against their scopes and public
summaries; their texts are paid for. Where a list comes from one (ISO
14224's failure codes), it starts from what is public, and the users
extend it.

## Step 1: examples as elementary facts

The things Logbook records, each given as an example and then as the
elementary facts it holds. Still a draft.

### An asset

> Our blue Golf is a 2014 Volkswagen Golf 1.4 TSI, VIN WVWZZZ1KZEW000001,
> registration 123 ABC. We bought it on 2019-05-02 for 9,500 EUR with
> 84,210 km on it.

- Asset 'Blue Golf' is a Vehicle, of VehicleKind 'Car'.
- Asset 'Blue Golf' is of Make 'Volkswagen'.
- Asset 'Blue Golf' is of Model 'Golf 1.4 TSI'.
- Asset 'Blue Golf' uses Fuel 'Petrol 95'.
- Asset 'Blue Golf' is metered in UsageUnit 'km'.
- Asset 'Blue Golf' was acquired on Date 2019-05-02.
- Asset 'Blue Golf' was acquired at Usage 84210 km.
- Asset 'Blue Golf' was acquired for Money 9500 EUR.
- Vehicle 'Blue Golf' was built in Year 2014.
- Vehicle 'Blue Golf' has VIN 'WVWZZZ1KZEW000001'.
- Vehicle 'Blue Golf' has Registration '123 ABC'.

> Anna also keeps a Honda EU22i generator in the garage, bought on
> 2024-04-10 for 1,150 EUR, its hour meter at 0. It runs on petrol and is
> rated at 2.2 kW.

- Asset 'Generator' is of EquipmentClass 'Generator'.
- Asset 'Generator' is of Make 'Honda'.
- Asset 'Generator' is of Model 'EU22i'.
- Asset 'Generator' uses Fuel 'Petrol 95'.
- Asset 'Generator' is metered in UsageUnit 'h'.
- Asset 'Generator' was acquired on Date 2024-04-10.
- Asset 'Generator' was acquired at Usage 0 h.
- Asset 'Generator' was acquired for Money 1150 EUR.
- Asset 'Generator' has Value 2.2 for ClassAttribute 'Rated power'.

An **asset** is anything a user keeps and maintains. A vehicle is one,
with what only vehicles have: a kind (car, motorcycle, bicycle), the year
built, a VIN, a registration, trips and tyres. Everything else is any
asset's: its name, owner and who shares it, its make and model, the fuel
it uses, its meter, what it was acquired for and at, what it is expected
to last and sell for, its valuations and its sale, and every record of
it. A generator is filled up and serviced as a car is.

Every asset is of an **equipment class**: a vehicle's is its kind, others'
a class of their own ('Generator', 'Power station', 'Boiler'). A class is
in a category ('Vehicles', 'Electrical', 'Rotating'), and says the
attributes its assets are described by (a generator's rated power, in
kW), so that assets of one class can be compared, as ISO 14224's taxonomy
has them. A stock item's category says which maintainable item a unit is
(a chain, brake pads) and of which classes: chains are maintainable items
of bicycles.

> We expect to keep the Golf 8 years, or another 120,000 km, and to sell
> it for 2,500 EUR. An online valuation said 4,000 EUR on 2026-10-01.
> *(Later:)* Sold on 2027-08-30 for 3,000 EUR.

- Asset 'Blue Golf' is expected to be kept for Period 8 years.
- Asset 'Blue Golf' is expected to be used Usage 120000 km more.
- Asset 'Blue Golf' is expected to sell for Money 2500 EUR.
- Asset 'Blue Golf' was valued at Money 4000 EUR on Date 2026-10-01.
- Asset 'Blue Golf' was sold on Date 2027-08-30.
- Asset 'Blue Golf' was sold for Money 3000 EUR.

All of these are optional. They're what the balance's views need (see
Reports): the expectations for depreciation by time or by usage, the
valuations for what it's worth now, and the sale for every view.

The sale is recorded as an income of kind 'Sale' (see Incomes); that the
asset was sold, when and for how much, is worked out from it.

> The generator is critical: the house has no other power in a cut. The
> old lawnmower was scrapped on 2026-05-02.

- Asset 'Generator' has Criticality 'High'.
- Asset 'Lawnmower' was disposed of on Date 2026-05-02.

An asset is in service, out of service (while a downtime of it lasts), in
stock (a unit that is an asset, on a shelf) or disposed of (sold or
scrapped): its **state** is worked out, never set. Its **criticality**
says how much depends on it (high, medium, low), for the risk-based
planning ISO 55001 asks for.

### Owner and sharing

> Anna owns the Golf and signs in as anna@example.org. Ben drives it too,
> and keeps its log as Anna does.

- Asset 'Blue Golf' is owned by User 'anna@example.org'.
- User 'anna@example.org' has Name 'Anna'.
- Asset 'Blue Golf' is shared with User 'ben@example.org'.

Whoever an asset is shared with is a user, signed in; for a vehicle,
they're its drivers. The owner may use it too, and whoever shares it can
keep all of its data. Who an event was by (who drove, who ran the
generator), who filled up and who paid are users. A user sees the assets
shared with them, and may add assets of their own, which they then own.
The owner may stop sharing.

> Ben adds his own van; he owns it, and shares it with nobody.

- Asset "Ben's van" is owned by User 'ben@example.org'.

### Meters

> On 2026-10-01 at 07:45 Anna read the Golf's odometer: 153,120 km. On
> 2026-11-15 she read the generator's hour meter: 212 h.

- MeterReading 21 is of Asset 'Blue Golf'.
- MeterReading 21 was at Moment 2026-10-01 07:45.
- MeterReading 21 shows Usage 153120 km.
- MeterReading 21 was by User 'anna@example.org'.
- MeterReading 40 is of Asset 'Generator'.
- MeterReading 40 shows Usage 212 h.

A **usage** is what a meter shows: a quantity in a unit (153,120 km;
212 h; 340 cycles). Each asset's meter counts in one dimension: a
vehicle's distance, a generator's running time, a power station's charge
cycles or the energy it delivered.

- UsageUnit 'km' is of Dimension 'distance'; so is 'mi'.
- UsageUnit 'h' is of Dimension 'time'.
- UsageUnit 'cycles' is of Dimension 'cycles'.
- UsageUnit 'kWh' is of Dimension 'energy'.

A reading is kept in the unit it was read in, in the meter's dimension: a
US car's odometer read in miles, its user shown km. Every event below
that happens at a usage (fill-up, service, trip, income, failure) also
gives a reading of the meter. Whether that makes them meter readings too,
or just events with a usage, is for step 6 (subtypes).

An asset with no meter (a bicycle) has what it covered worked out from
what it did: its trips (see A component).

### What every event has

Each event (meter reading, trip, fill-up, service, tyre change, expense,
income, inspection, failure, downtime) happened at a moment, a date and a
time of day: two fill-ups on one day must come in order, or the
consumption between them is wrong. Each says who it was by, and may carry
a note and any number of attached files (a receipt, a photo):

- FillUp 1 has Note 'Price was up 10 cents'.
- Attachment 'receipt-0914.jpg' is of FillUp 1.

Who an event was by is who drove or used the asset then: not always who
entered the record, nor who paid.

### A trip

> On 2026-09-20 Anna drove the Golf from Berlin to Hamburg on business,
> 152,410 km to 152,700 km, starting at 08:10 and arriving at 11:25.

- Trip 3 is of Vehicle 'Blue Golf'.
- Trip 3 was on Date 2026-09-20.
- Trip 3 started at Usage 152410 km.
- Trip 3 ended at Usage 152700 km.
- Trip 3 started at Time 08:10.
- Trip 3 ended at Time 11:25.
- Trip 3 went from Place 'Berlin'.
- Trip 3 went to Place 'Hamburg'.
- Trip 3 has Purpose 'Business'.
- Trip 3 was by User 'anna@example.org'.

How far and how long it took are derived: 290 km, 3 h 15 min. Only
vehicles make trips, so a trip's readings are in a distance unit, and its
length is a distance.

Trips are recorded freely: they need not agree with the meter, nor with
each other (gaps and overlaps are allowed). The owner may change what was
recorded before; whether others may too, or only add, is a permission,
not a fact (see below).

### A fill-up

> On 2026-09-14 at 17:20, at 152,300 km, 42.5 L of petrol for 74.10 EUR, at
> Shell on Main St. Filled to the brim. Ben was driving. *And:* Anna
> filled the generator's tank with 3.6 L at 214 h.

- FillUp 1 is of Asset 'Blue Golf'.
- FillUp 1 was at Moment 2026-09-14 17:20.
- FillUp 1 was at Usage 152300 km.
- FillUp 1 was of Volume 42.5 L.
- FillUp 1 was of Fuel 'Petrol 95'.
- FillUp 1 cost Money 74.10 EUR.
- FillUp 1 was at Station 'Shell, Main St'.
- FillUp 1 filled the tank. *(unary)*
- FillUp 1 was by User 'ben@example.org'.
- FillUp 41 is of Asset 'Generator', at Usage 214 h, of Volume 3.6 L.

The price per litre (1.744 EUR/L) is worked out from the cost and the
volume. The form takes any two of price, cost and volume and fills in the
third, as a pump shows them; what's kept is the cost and the volume, as on
the receipt. Any asset that uses a fuel is filled up; its consumption is
per its meter: litres per 100 km, litres per hour.

### A work request

> The generator won't start. On 2026-11-20 at 18:00 Anna asks for it to be
> looked at, urgently.

- WorkRequest 60 is of Asset 'Generator'.
- WorkRequest 60 was made at Moment 2026-11-20 18:00.
- WorkRequest 60 was made by User 'anna@example.org'.
- WorkRequest 60 has Title "Won't start".
- WorkRequest 60 has Priority 'Urgent'.

A **work request** is someone asking for work on an asset, in EN 13460's
words: what is wrong or wanted, how urgent. It becomes a work order (a
service, below), or is turned down on a date. A reminder falling due may
raise an order too, and so may an inspection's answer (see Checklists).

### A service

A **service is the work order**, from planned to done. EN 13460 names a
request, an order and a report; the order and its report are one record
at two stages, as SAP's maintenance order with its confirmations and
Maximo's work order with its actuals are.

> Ben plans the repair for Saturday 2026-11-22, and reserves a spark plug
> from the garage's stock for it.

- Service 61 was raised from WorkRequest 60.
- Service 61 is of Asset 'Generator'.
- Service 61 is of MaintenanceType 'Corrective, immediate'.
- Service 61 is in WorkState 'Planned'.
- Service 61 is planned for Date 2026-11-22.
- Service 61 is assigned to User 'ben@example.org'.
- Service 61 reserves Quantity 1 of StockItem 'NGK BPR6ES'.

> He does it on the day: at 10:00, at 214 h, he replaces the fouled spark
> plug in 45 minutes, and the generator runs again.

- Service 61 is in WorkState 'Done'.
- Service 61 was at Moment 2026-11-22 10:00.
- Service 61 was at Usage 214 h.
- Service 61 was by User 'ben@example.org'.
- Service 61 included Task 'Spark plug replacement'.
- Labour 62 is of Service 61.
- Labour 62 was by User 'ben@example.org'.
- Labour 62 took WorkTime 0.75 h.
- Service 61 repaired Failure 63.

> On 2026-06-01 at 09:30, at 148,000 km, Anna took the Golf for its annual
> service at Garage Müller: oil and filter changed (95 EUR), brake fluid
> replaced (60 EUR), labour 165 EUR. The filter was a Mann W 712/95. The
> garage took 20 EUR off, and she paid by card, in 2 instalments.

- Service 7 is of Asset 'Blue Golf'.
- Service 7 is in WorkState 'Done'.
- Service 7 is of MaintenanceType 'Preventive, predetermined'.
- Service 7 was at Moment 2026-06-01 09:30.
- Service 7 was at Usage 148000 km.
- Service 7 has Title 'Annual service'.
- Service 7 was done by Garage 'Garage Müller'.
- Service 7 was by User 'anna@example.org'.
- Service 7 included Task 'Oil change' for Money 95 EUR.
- Service 7 included Task 'Brake fluid change' for Money 60 EUR.
- Labour 9 is of Service 7, by Garage 'Garage Müller', for Money 165 EUR.
- In Service 7, Task 'Oil change' has Note 'Filter: Mann W 712/95'.
- Service 7 had a discount of Money 20 EUR.
- Service 7 was paid by PaymentMethod 'Card'.
- Service 7 was paid in Instalments 2.

A service planned says what is to be done, when and by whom, and the
parts it reserves: committed, as a sale order's lines are. Done, it says
when and at what reading it was done, its tasks and their costs, its
labour, and the failures it repaired. Its states are draft, planned,
released, in progress, done, closed and cancelled; a service recorded
after the fact, as most are, is one made done. Its way through the states
is a process, as an order to cash is (MaintenanceOrder.bpmn).

Each task in a service has its own cost, and so does each labour: the
hours worked, by a user or a garage. The service's cost is their sum less
the discount (300 EUR), so it's derived, not stored. "Service included
Task for Money" is a ternary; step 4 checks that it is elementary. Parts
are noted on tasks, or taken from stock (see Stock's parts used by
services). The tasks are a list the users keep (battery, air filter, tyre
balancing, ...), and so are the payment methods. A service paid at once
is paid in one instalment.

Every service says whether it was **preventive or corrective**, EN 13306's
types of maintenance: preventive is done before a failure, predetermined
(by a schedule: a date, a usage) or condition-based (an inspection or a
measurement said it was time); corrective is done after one, at once or
deferred. Reports count maintenance (preventive) and repairs (corrective)
as kinds of cost each, and the indicators rest on the difference.

> The Golf's windscreen was replaced at Carglass on 2026-07-12, 410 EUR.

- Service 8 is of MaintenanceType 'Corrective, deferred'.
- Service 8 included Task 'Windscreen replacement' for Money 410 EUR.

### A failure

> The generator had failed to start at 17:50, when Anna tried to run it,
> at 212 h. The spark plug was fouled: it had idled too long. It could not
> run at all.

- Failure 63 is of Asset 'Generator'.
- Failure 63 was at Moment 2026-11-20 17:50.
- Failure 63 was at Usage 212 h.
- Failure 63 is of FailureMode 'Fails to start on demand'.
- Failure 63 has FailureMechanism 'Contamination'.
- Failure 63 has FailureCause 'Operation'.
- Failure 63 was found by DetectionMethod 'On demand'.
- Failure 63 had FailureImpact 'Critical'.
- Failure 63 was of StockUnit u12 (the spark plug).
- FailureMode 'Fails to start on demand' applies to EquipmentClass
  'Generator'.

A **failure** is ISO 14224's failure event: of an asset, when and at what
reading, its mode (what was seen), its mechanism (how it came about), its
cause (why: design, fabrication, installation, operation, maintenance),
how it was found, its impact on the asset's function (critical: it
stopped; degraded; incipient: not yet), and the maintainable item that
failed, when one is known. Each is a coded list, so that failures can be
counted; the modes are listed per equipment class.

### Downtime

> The generator was out of service from the failure until the repair was
> done, at 10:45. The Golf was off the road for its annual service, a
> planned morning.

- Downtime 64 is of Asset 'Generator'.
- Downtime 64 started at Moment 2026-11-20 17:50.
- Downtime 64 ended at Moment 2026-11-22 10:45.
- Downtime 64 was for Failure 63.
- Downtime 68 is of Asset 'Blue Golf', was for Service 7, was planned.

A **downtime** is a time the asset could not do its work, EN 13306's down
state: after a failure, or planned, for preventive work. The rest of the
time it was in service is its uptime. With failures and corrective
services, these give MTBF, MTTR and availability.

### Tyres

> Our winter set, Continental WinterContact TS 870, 205/55 R16, went on the
> Golf on 2025-11-02 at 141,500 km with 8 mm of tread, and came off on
> 2026-04-05 at 146,900 km. The summer set went on the same day.

- TyreSet 'Golf winter' is of Season 'Winter'.
- TyreSet 'Golf winter' is of TyreModel 'Continental WinterContact TS 870'.
- TyreSet 'Golf winter' is of Size '205/55 R16'.
- TyreSet 'Golf winter' was bought for Money 480 EUR.
- TyreSet 'Golf winter' was bought on Date 2025-10-20.
- TyreChange 4 fitted TyreSet 'Golf summer' on Vehicle 'Blue Golf'.
- TyreChange 4 removed TyreSet 'Golf winter'.
- TyreChange 4 was at Moment 2026-04-05 10:00.
- TyreChange 4 was at Usage 146900 km.
- TyreChange 4 was by User 'anna@example.org'.
- TyreSet 'Golf winter' had Tread 8 mm at TyreChange 3. *(when fitted)*

From the tyre changes, the app works out which set is on the car, and how
far each set has been driven. Which set a change removed is worked out
too: the one on the car before it (step 7). Tyres are vehicles' only.

### A component

> Anna's bicycle, the Commuter, a Surly Long Haul Trucker, has no meter:
> what it has covered is what its rides covered, 3,900 km since she bought
> it. She keeps her spare parts in her garage. She bought a KMC X9 chain,
> serial unknown, for 25 EUR, kept it on the garage's shelf, and fitted it
> on 2026-08-01 at 3,900 km, taking the old one off and throwing it away.
> She fitted a GravelKing tyre into the rear wheel set, which wears on no
> ride on her trainer. She replaces the chain every 3,000 km.

- Asset 'Commuter' is a Vehicle, of VehicleKind 'Bicycle'.
- Asset 'Commuter' has no meter.
- Trip 30 of Vehicle 'Commuter' covered Distance 25 km.
- Trip 32 of Vehicle 'Commuter' is virtual.
- StockUnit u1 is of StockItem 'KMC X9', of Category 'Chain', made by
  Manufacturer 'KMC'.
- Move m1 moved StockUnit u1 to Location 'Garage / Shelf'.
- ComponentChange 31 fitted StockUnit u1, on Asset 'Commuter'.
- ComponentChange 31 removed StockUnit u0.
- ComponentChange 31 was at Moment 2026-08-01 10:00, at Usage 3900 km.
- Move m2 is made for ComponentChange 31: StockUnit u1 out of the shelf,
  for AdjustmentReason 'Fitted'.
- ComponentChange 33 fitted StockUnit u2 into StockUnit u3 (the wheel set),
  at MountPosition 'Rear'; ComponentChange 33 skips virtual trips.
- Schedule 10 of Asset 'Commuter' is for Task 'Chain', recurring after
  Usage 3000 km.

A component is a unit of a stock item (step 3 of the stock's: StockUnit, a
thing told from the others where it has a serial number), not a record of
the asset: the same unit is stock on a shelf, then fitted to a bicycle,
then taken off and put away, or fitted to another. So a spare chain and a
fitted one are one fact type's population, as InvenTree's installed items
and MainTrack's assignments (of a component to a bike, or to another
component: a tyre to a wheel) both have it.

A change of the asset fits it at a moment and a reading, to the asset or
into another unit fitted to it, at a position, and may remove one, which
it may put away at a location. Fitted from stock, the unit moves out of
it (a move made for the change, Fitted); one removed and put away moves
back in there (Removed); one not put away is thrown away. Where a unit is,
is worked out from its moves (UnitPlace): nowhere in stock while fitted.

How far a component has worn is worked out: each time it was fitted, what
its asset's meter covered from that change's reading until it was removed
(or fitted elsewhere, or the unit it went into was removed), or until now;
less the virtual trips then where the change skips them. A change does the
work of the task named as its unit's item's category, so a schedule for
the task 'Chain' closes its reminder when a chain is fitted, as a service
of a task does.

A vehicle with no meter has its events' readings worked out from its
trips: what it was acquired at, then each trip's length added as it ends;
an event at a moment is at what was covered before it. A trip says how far
it went (its length) where its vehicle has no meter; its start and end
readings follow.

A bicycle has no fuel, VIN or registration, and is never filled up; a car
or a motorcycle uses a fuel and was built in a year. A vehicle stored
before vehicles had kinds says none, and is taken as motorised.

### A unit that is an asset

> Anna bought an EcoFlow River 2 Pro power station through Stock, serial
> R2P-0042, and put it in service at home as 'River power'. Its extra
> battery, serial EB-0107, is fitted to it; the battery has a warranty of
> its own and counts its own charge cycles.

- StockUnit u7 is of StockItem 'EcoFlow River 2 Pro', made by Manufacturer
  'EcoFlow'.
- StockUnit u7 has SerialNumber 'R2P-0042'.
- Asset 'River power' is StockUnit u7.
- Asset 'River power' is of EquipmentClass 'Power station'.
- Asset 'River power' is metered in UsageUnit 'cycles'.
- Move m9 moved StockUnit u7 out of Location 'Garage / Shelf', for
  AdjustmentReason 'Put in service'; Move m9 is made for Asset 'River
  power'.
- Asset 'River battery' is StockUnit u8.
- Asset 'River battery' is metered in UsageUnit 'cycles'.
- ComponentChange 50 fitted StockUnit u8 on Asset 'River power'.

An asset bought through Stock **is** that unit: one thing, seen as stock
while it is on a shelf and as an asset once in service, as IBM Maximo's
rotating items and SAP's equipment with a material and a serial number
are. Its make, model and serial are the unit's (its item's manufacturer,
the item, the unit's serial), not entered again. Putting it in service
moves it out of stock, as fitting a component does; taking it out of
service puts it back. An asset need not be a unit: a car bought privately
is an asset only.

Any unit may be made an asset where its own history matters (a battery
pack, an engine, a wheel set), and a unit fitted to an asset may be one.
It is then both: a component of what it is fitted in, and an asset with
its own records, meter, warranty and failures. That is the equipment
hierarchy of ISO 14224 (an equipment unit, its subunits, its maintainable
items). Its history follows it: moved to another power station, or back to
the shelf, it keeps its records. And what it is fitted in sees it too: a
record of the battery concerns the power station as well, while the
battery is fitted, so the station's costs, failures and indicators count
it. A component that is an asset with no meter of its own wears by its
parent's, as any component does. A chain is no asset: a unit fitted, no
more.

### A document

> The Golf is insured by Allianz, policy 77-123456, from 2025-12-01 to
> 2026-12-01, for 610 EUR. The roadworthiness test (TÜV) runs until
> 2027-03. Here is the scanned policy.

- Document 'Allianz 77-123456' is of Asset 'Blue Golf'.
- Document 'Allianz 77-123456' is of DocumentKind 'Insurance'.
- Document 'Allianz 77-123456' is valid from Date 2025-12-01.
- Document 'Allianz 77-123456' expires on Date 2026-12-01.
- Document 'Allianz 77-123456' cost Money 610 EUR.
- Document 'Allianz 77-123456' has Attachment 'policy.pdf'.

> The power station has a 5-year warranty, to 2031-11-01, and its manual.
> The extra battery's warranty runs to 2028-11-01 or 800 cycles, whichever
> comes first. The chain came with a year's warranty.

- Document 'River warranty' is of Asset 'River power', of DocumentKind
  'Warranty', expires on Date 2031-11-01.
- Document 'River manual' is of Asset 'River power', of DocumentKind
  'Manual', has Attachment 'manual.pdf'.
- Document 'Battery warranty' is of Asset 'River battery', expires on Date
  2028-11-01.
- Document 'Battery warranty' is valid until Usage 800 cycles.
- Document 'Chain warranty' covers StockUnit u1.

A warranty, a manual and a drawing are documents of their asset, with
what documents have: dates, a cost, attachments. A warranty may end at a
usage as well as on a date, whichever comes first. A unit that is no asset
(the chain) may have a warranty too; the document then covers the unit,
and is of the asset it is fitted to, if any.

### Other costs

> Anna parked at the airport, 2026-08-03 06:15, 36 EUR. Toll on the A2,
> 12.50 EUR. A car wash, 9 EUR.

- Expense 12 is of Asset 'Blue Golf'.
- Expense 12 was at Moment 2026-08-03 06:15.
- Expense 12 is of ExpenseKind 'Parking'.
- Expense 12 cost Money 36 EUR.
- Expense 12 was by User 'anna@example.org'.
- Expense 12 has Note 'Airport'.

### Incomes

> As a taxi driver would: at the end of a ride, 2026-10-02 19:05, at
> 153,314 km, Ben was paid 23.50 EUR through a ride-hailing app.

- Income 30 is of Asset 'Blue Golf'.
- Income 30 was at Moment 2026-10-02 19:05.
- Income 30 was at Usage 153314 km.
- Income 30 is of IncomeKind 'Transport app'.
- Income 30 earned Money 23.50 EUR.
- Income 30 was by User 'ben@example.org'.

> The ride itself, 18:40 to 19:05, 153,300 km to 153,314 km, was logged as
> a trip.

- Income 30 was for Trip 9.

> The Golf was sold on 2027-08-30 at 171,020 km for 3,000 EUR, paid in 3
> instalments.

- Income 41 is of IncomeKind 'Sale'.
- Income 41 earned Money 3000 EUR.
- Income 41 was paid in Instalments 3.

An income is a record of its own, of a kind from a list the users keep:
'Transport app', 'Trip', 'Freight', 'Refund', 'Sale', and their own. It
may name the trip it was for; a trip needn't be paid. A paid trip needn't
name its places, but it does say how long it took and how far it went.
Any asset may be sold; its sale is its income of kind 'Sale'.

### Checklists and inspections

> Anna's checklist "Basic vehicle inspection" asks: Is the registration
> certificate in the car? Are the tyres in good condition? Has the oil
> level been checked? Which of these are not working: low beams, high
> beams, indicators, brake lights, horn? On 2026-08-28 at 12:00, at
> 151,600 km, she went through it on the Golf: yes, yes, yes; the low and
> high beams aren't working. She took a photo.

- Checklist 'Basic vehicle inspection' is kept by User 'anna@example.org'.
- Question 'Is the registration certificate in the car?' is in Checklist
  'Basic vehicle inspection' at Position 1.
- Question 'Is the registration certificate in the car?' is answered by
  AnswerKind 'Yes or no'.
- Question 'Which of these are not working?' is at Position 4.
- Question 'Which of these are not working?' is answered by AnswerKind
  'Any of'.
- Option 'Low beams' is in Question 'Which of these are not working?' at
  Position 1.
- Option 'Low beams' calls for Task 'Lamp replacement'.
- Inspection 50 is of Asset 'Blue Golf'.
- Inspection 50 went through Checklist 'Basic vehicle inspection'.
- Inspection 50 was at Moment 2026-08-28 12:00.
- Inspection 50 was at Usage 151600 km.
- Inspection 50 was by User 'anna@example.org'.
- In Inspection 50, Question 'Is the registration certificate in the car?'
  was answered 'Yes'.
- In Inspection 50, Question 'Which of these are not working?' was
  answered with Option 'Low beams'.
- In Inspection 50, Question 'Which of these are not working?' was
  answered with Option 'High beams'.
- Attachment 'lights.jpg' is of Inspection 50.

> The power station's monthly check asks its battery health, in %: below
> 80%, the battery is to be replaced. On 2026-11-01 Anna reads 76%.

- Question 'Battery health' is answered by AnswerKind 'Measurement'.
- Question 'Battery health' measures in Unit '%'.
- Question 'Battery health' has lower limit Quantity 80.
- Question 'Battery health' calls for Task 'Battery replacement' when out
  of limits.
- In Inspection 70, Question 'Battery health' was answered Quantity 76.
- WorkRequest 71 was raised from that answer.

A **checklist** is a form, in Drivvo's words: questions in order, that a
user writes once and uses on any of their assets (a daily inspection, a
look round before a long trip, a monthly check of a power station).
Whoever shares an asset uses the checklists of its owner. A question is
answered in one of three ways:
- **yes or no;**
- **any of** its options, in order: none, some or all of them may be
  chosen. Choosing none is an answer too ("nothing isn't working");
- **a measurement:** a number in a unit, with the limits it ought to be
  within.

An **inspection** is one going through a checklist, on one asset, at a
moment: an event like the others, with who it was by, its note and files.
A question may be left unanswered. Whether a yes or an option is good news
depends on the question ("Which are *not* working?"), so the app does not
judge it, unless the question says: an option may call for a task, and so
may a measurement out of its limits. That is **condition-based work**: such
an answer, saved, raises a work request for the task, as a reading
reaching a reminder's usage makes it due. Readings sent by a device (a
power station's own report, later) are measurements the same way.

A checklist can be planned work too:

> Go through "Basic vehicle inspection" every month.

- Schedule 'Monthly' is for Checklist 'Basic vehicle inspection'.

and an inspection through it does that work.

Richer forms (text, conditions between questions) are for later,
described by XForms rather than by fact types.

### Money

> 74.10 EUR, on 2026-09-14; the preferred currency is USD, and that day
> 1 EUR = 1.09 USD. The receipt for the Swiss toll says 40 CHF = 41.60 EUR.

- Money is a value object: an Amount in a Currency (74.10, 'EUR').
- Rate: on Date 2026-09-14, 1 Currency 'EUR' is worth 1.09 Currency 'USD'.
- The app's preferred Currency is 'USD'.
- Expense 13 cost Money 40 CHF.
- Expense 13 was charged Money 41.60 EUR.

Each amount is kept as entered. Rates are as flexible as can be: a table
of rates by date, entered by hand or fetched, used for any amount on that
date (or the latest date before it). An amount may also say what it was
charged in another currency, as a receipt or a card statement gives it,
which then counts for that amount in that currency.

### Units

- The app's distance Unit is 'km' (or 'mi'), its volume Unit 'L' (or US
  gal, imperial gal).
- A meter's unit is its asset's: 'km', 'mi', 'h', 'cycles', 'kWh'.

Usages, distances and volumes are kept in the unit they were entered in,
and distances and volumes shown in the app's; a usage in another
dimension (hours, cycles) is shown as it is.

### Schedules and reminders

> Change the Golf's oil every 15,000 km or every 12 months, whichever
> comes first, counting from the last change (148,000 km, 2026-06-01).
> Change the generator's every 100 hours or 12 months. Renew the parking
> permit every year. And once: have the air conditioning checked by
> 2027-05-01.

- Schedule 'Oil' is of Asset 'Blue Golf'.
- Schedule 'Oil' is for Task 'Oil change'.
- Schedule 'Oil' recurs every Usage 15000 km.
- Schedule 'Oil' recurs every Duration 12 months.
- Schedule 'Generator oil' is of Asset 'Generator', for Task 'Oil change'.
- Schedule 'Generator oil' recurs every Usage 100 h.
- Schedule 'Generator oil' recurs every Duration 12 months.
- Schedule 'Permit' is for ExpenseKind 'Parking'.
- Schedule 'Permit' has Note 'Residents' permit, zone 4'.
- Schedule 'Permit' recurs every Duration 12 months.
- Reminder 5 comes from Schedule 'Oil'.
- Reminder 5 is due at Usage 163000 km.
- Reminder 5 is due on Date 2027-06-01.
- Reminder 5 was set at Moment 2026-06-01 10:00.
- Reminder 6 is of Asset 'Blue Golf'.
- Reminder 6 is for Task 'Air conditioning'.
- Reminder 6 has Note 'It smells musty'.
- Reminder 6 is due on Date 2027-05-01.

> Two weeks before the oil is due, a work order is raised for it, and
> planned. The oil was changed at Garage Müller on 2027-05-20 at
> 162,400 km.

- Service 12 was raised from Reminder 5.
- Reminder 5 was done at Moment 2027-05-20 11:00.
- Reminder 5 was done at Usage 162400 km.
- Reminder 5 was done by Service 12.

> We're away in May: move the air conditioning to June. Then: forget it,
> it's fine; check it with the next service instead.

- Rescheduling 1 is of Reminder 6.
- Rescheduling 1 was made at Moment 2027-04-28 20:10 by User 'anna@example.org'.
- Rescheduling 1 moved from Date 2027-05-01.
- Reminder 6 is due on Date 2027-06-01.
- Reminder 6 was cancelled on Date 2027-05-25.
- Reminder 9 replaces Reminder 6.

A **schedule** is planned work, the preventive maintenance of EN 13306
predetermined by it: which work, and how often, by usage, by time, or
both, whichever comes first. The work is a task (what a service does), a
kind of expense (what an expense pays for) or a checklist (what an
inspection goes through). It is never done itself.

A **reminder** is one time the work is due. The work it's for is its
schedule's, or, set once by hand with no schedule, its own. It is open,
done or cancelled. It may raise a work order, a service planned for it.
It is done by the first record of that work after it was set: a service
done that includes the task, an expense of that kind, or an inspection
through the checklist; the reminder is then done at the record's moment,
and at its usage when it has one, and links to it. The owner may also
mark one done by hand, with no record. A reminder skipped or given up is
cancelled, on a date, and may be replaced by a new one. One moved to
another date or usage keeps what it is due at now, and a **rescheduling**
says what it was due at before, when and by whom it was moved. A
schedule's reminders come one after another: when one is done, the next
is due its intervals after when and where it was done; a schedule has one
open at a time. Users write their own schedules and reminders, per asset;
there's no manufacturer's catalogue for now.

Closing a reminder, making the next, raising its order, reopening one
whose record was entered in error: these are things the app does as it
records what happened, not facts derived from others.
[PROCESSES.md](PROCESSES.md) describes them.

### Reports

Reports are information outputs too: each says derived facts. Per asset,
over a period (the driving ones for vehicles; fuel for assets that use a
fuel, per their meter):

1. **Balance:** incomes minus costs; per day; in the preferred currency
   per unit of usage. Every view is offered, for the user to choose:
   - **cash:** the purchase and the sale counted on the days they were
     paid;
   - **running:** the purchase and the sale left out;
   - **depreciation over time:** the expected loss of value (purchase minus
     expected sale) spread over the expected years, a cost each day; the
     sale's difference from the value left is a gain or loss on its day;
   - **depreciation by usage:** the same, spread over the expected usage,
     a cost each unit of usage;
   - **what it's worth:** the loss of value between valuations (the
     purchase, each valuation, the sale).

   A view whose inputs are missing isn't offered.
2. **Usage:** total (distance driven, hours run), and average per day.
3. **Costs:** total, average per day, per unit of usage.
4. **Incomes:** total, average per day, per unit of usage; by kind of
   income.
5. **Costs and incomes over time:** a bar chart by month, each bar split by
   kind of record (fill-ups, services, expenses, ...).
6. **Costs by kind:** pie chart (fuel, maintenance, repairs, tyres,
   documents, parking, tolls, washes, ...).
7. **Costs by month:** bar chart.
8. **Fuel consumption:** per full tank over time (a chart), and the
   average over the period, in L/100 km, km/L or mpg for a vehicle, L/h
   for an asset metered in hours; fuel cost per unit of usage. For each,
   the latest, the lowest and the highest beside the average. All fuels
   together, or one fuel. The volume and the cost of fuel over the period.
9. **Readings:** the meter's reading over time, a chart with a point for
   each record, marked by its kind.
10. **Service costs by task:** pie chart (new tyres, labour, battery,
    diagnostics, ...).
11. **Each month in the history:** its costs, usage and fuel consumption,
    and how its consumption compares with the month before's (5% lower
    than June).
12. **Each fill-up in the history:** its consumption since the full
    fill-up before.
13. **Each inspection in the history:** its answers, in the checklist's
    order, and the questions left unanswered.
14. **Maintenance indicators** (EN 15341), per asset, per equipment class
    and per maintainable item (a stock item's category); an asset counts
    its components' records while they were fitted:
    - **preventive share:** preventive services' cost, and labour hours,
      over all services';
    - **MTBF:** uptime over the failures in the period;
    - **MTTR:** downtime after failures over those failures;
    - **availability:** uptime over uptime and downtime;
    - **maintenance cost per usage:** services' cost over the usage;
    - **backlog:** the work orders not done at the period's end, by count
      and by planned labour, the critical assets' first;
    - **schedule compliance:** the reminders due in the period done by
      their date or usage, over all those due.
15. **Failures:** counted by mode, by cause, by maintainable item, by
    class; each in the history with its downtime and its repair.

There are the same reports per kind of event (fill-ups, services,
expenses, incomes, trips, meter readings, inspections, failures), as tabs.

As facts, for example:
- Asset 'Blue Golf' cost Money 1234 USD in Period 2026-09.
- Asset 'Blue Golf' was used Usage 1820 km in Period 2026-09.
- Asset 'Blue Golf' cost Money 0.21 USD per unit of usage in Period
  2026-09.
- Costs of Kind 'Fuel' for Asset 'Blue Golf' were Money 410 USD in Period
  2026-09.
- Asset 'Generator' was available Percentage 98.4 in Period 2026-11.
- EquipmentClass 'Generator' had an MTBF of WorkTime 610 h in Period 2026.

Every one is derived, from events' amounts, dates and usages, from
failures and downtime, and from rates. Usage over the period is the
meter's difference, from the readings every event gives. These become
ORMKit derivation queries.

## Permissions

These are not facts about assets. They're rules about who may change
what, for the service and the apps to enforce:

- The owner may change anything about their assets, including what was
  recorded before.
- Whoever shares an asset may add records of their own to it (a vehicle's
  driver their fill-ups, a technician their labour), and may not change or
  remove any record, but for moving a work order assigned to them through
  its states.

So every record says who entered it:

> Ben entered the fill-up.

- FillUp 1 was entered by User 'ben@example.org'.

"Their own records" are those they entered. That is a fact about each
record, not about the people in it: Ben may enter a fill-up Anna drove
to.

## Step 2: the fact types, checked against the examples

### How things are identified

Records made on a device and synced need ids that don't clash. So the
things Logbook records are identified by an id the app makes (a UUID,
written `v1`, `t3` here):
- Asset (a vehicle by its asset's), Trip, FillUp, Service, ServiceItem,
  Labour, WorkRequest, Failure, Downtime, MeterReading, TyreSet,
  TyreChange, Document, Expense, Income, Schedule, Reminder, Attachment,
  Checklist, Question, Option, Inspection, Answer.

The rest are identified by what they are:

| Entity type | Identified by |
| --- | --- |
| User | email |
| Make, Model, Fuel, Garage, Station, Place, TyreModel, ClassAttribute | name |
| ExpenseKind, IncomeKind, DocumentKind, Purpose, Season, Task, PaymentMethod | name, from a list |
| EquipmentClass, EquipmentCategory, FailureMode, FailureMechanism, DetectionMethod | name, from a list the users extend, seeded from ISO 14224 |
| Title, Note, ChecklistName, QuestionText, OptionText | text |
| AnswerKind | name, from a fixed list: 'Yes or no', 'Any of', 'Measurement' |
| YesNo | from a fixed list: 'Yes', 'No' |
| MaintenanceType | name, from a fixed list (EN 13306) |
| WorkState, Priority, Criticality, FailureCause, FailureImpact | name, from fixed lists (step 6) |
| Position | a count, 1 or more |
| Instalments | a count, 1 or more |
| Currency | ISO code ('EUR', 'USD') |
| DistanceUnit | code, from a list: 'km', 'mi' |
| UsageUnit | code, from a list: 'km', 'mi', 'h', 'cycles', 'kWh' |
| Dimension | name, from a fixed list: 'distance', 'time', 'cycles', 'energy' |
| VolumeUnit | code, from a list: 'L', 'gal (US)', 'gal (imp)' |
| Duration | months |
| WorkTime | hours |
| Tread | mm |
| Money | its Amount and its Currency together (74.10 EUR) |
| Usage | its Quantity and its UsageUnit together (152300 km, 212 h) |
| Distance | its Quantity and its DistanceUnit together (25 km) |
| Volume | its Quantity and its VolumeUnit together (42.5 L) |

Money, usages, distances and volumes have no identity of their own. Two
fill-ups costing 74.10 EUR cost the same money, and two trips of 14 km
went as far. Each is kept as it was entered, in its own unit or currency.
The Core Data mapping absorbs each into whatever has it, as a quantity
and a unit.

The app shows each in the user's preferred unit or currency, converting as
it goes:
- **money:** by exchange rates, which change and are kept by date (below);
- **usages, distances and volumes:** by fixed factors within a dimension
  (1 mi = 1.609344 km, 1 gal (US) = 3.785411784 L, 1 gal (imp) =
  4.54609 L). These are part of the model, not data anyone enters. Hours,
  cycles and kilowatt-hours have one unit each.

So a US car's odometer can be read in miles, and its fill-ups in gallons,
while the user sees km and L, or the other way round.

Moments (a date with a time of day, to the minute) and dates are values.
Events happen at moments; what is only ever a day (when a document is
valid, when a reminder is due, a valuation, a work order's planned day)
is a date.

### People and assets

```
Asset is owned by User                          v1 | anna@example.org
                                                v2 | ben@example.org
                                                a1 | anna@example.org
Asset is shared with User                       v1 | ben@example.org
User has PersonName                             anna@example.org | 'Anna'
Asset has AssetName                             v1 | 'Blue Golf'
                                                v2 | "Ben's van"
                                                a1 | 'Generator'
Asset is of Make                                v1 | 'Volkswagen'
                                                a1 | 'Honda'
Asset is of Model                               v1 | 'Golf 1.4 TSI'
                                                a1 | 'EU22i'
Asset uses Fuel                                 v1 | 'Petrol 95'
                                                a1 | 'Petrol 95'
Asset is of EquipmentClass                      a1 | 'Generator'
                                                a3 | 'Power station'
Asset has Criticality                           a1 | 'High'
Asset was disposed of on Date                   a5 | 2026-05-02
Asset is StockUnit                              a3 | u7
                                                a4 | u8
Vehicle is of VehicleKind                       v1 | 'Car'
                                                v3 | 'Bicycle'
Vehicle was built in Year                       v1 | 2014
Vehicle has VIN                                 v1 | 'WVWZZZ1KZEW000001'
Vehicle has RegistrationNumber                  v1 | '123 ABC'
```

### Classes

```
EquipmentClass is in EquipmentCategory          'Generator' | 'Electrical'
                                                'Car' | 'Vehicles'
                                                'Bicycle' | 'Vehicles'
EquipmentClass has ClassAttribute in Unit       'Generator' | 'Rated power' | 'kW'
Asset has Value for ClassAttribute              a1 | 2.2 | 'Rated power'
Category is a maintainable item of EquipmentClass   'Chain' | 'Bicycle'
                                                'Battery' | 'Power station'
FailureMode applies to EquipmentClass           'Fails to start on demand' | 'Generator'
```

A vehicle's kind is its class: 'Car', 'Motorcycle' and 'Bicycle' are
classes in 'Vehicles' (step 6, a subtype).

### What an asset cost, and is worth

```
Asset was acquired on Date                      v1 | 2019-05-02
Asset was acquired at Usage                     v1 | 84210 km
                                                a1 | 0 h
Asset was acquired for Money                    v1 | 9500 EUR
Asset is expected to be kept for Duration       v1 | 96
Asset is expected to be used Usage more         v1 | 120000 km
Asset is expected to sell for Money             v1 | 2500 EUR
Asset was valued on Date at Money               v1 | 2026-10-01 | 4000 EUR
                                                v1 | 2027-03-01 | 3600 EUR
Asset was sold on Date *                        v1 | 2027-08-30
Asset was sold for Money *                      v1 | 3000 EUR
```

\* Derived, from the asset's income of kind 'Sale' (step 5).

### Money and preferences

```
Money has Amount                                (74.10 EUR) | 74.10
Money is in Currency                            (74.10 EUR) | 'EUR'
Usage has Quantity                              (152300 km) | 152300
                                                (212 h) | 212
Usage is in UsageUnit                           (152300 km) | 'km'
                                                (212 h) | 'h'
UsageUnit is of Dimension                       'km' | 'distance'
                                                'mi' | 'distance'
                                                'h' | 'time'
                                                'cycles' | 'cycles'
                                                'kWh' | 'energy'
UsageUnit is worth Factor of its base           'mi' | 1.609344
                                                'km' | 1
Distance has Quantity                           (25 km) | 25
Distance is in DistanceUnit                     (25 km) | 'km'
Volume has Quantity                             (42.5 L) | 42.5
Volume is in VolumeUnit                         (42.5 L) | 'L'
                                                (11.2 gal (US)) | 'gal (US)'
on Date one Currency was worth Factor Currency  2026-09-14 | 'EUR' | 1.09 | 'USD'
                                                2026-09-15 | 'EUR' | 1.08 | 'USD'
User prefers Currency                           anna@example.org | 'USD'
User measures distance in DistanceUnit          anna@example.org | 'km'
User measures volume in VolumeUnit              anna@example.org | 'L'
```

The exchange rate is a quaternary: the date, the two currencies and the
factor. Step 4 checks that it's elementary. What an amount was charged in
another currency goes with the record that has it, below. A unit's factor
is to its dimension's base: the km for distance; hours, cycles and kWh
are their own.

The preferred units and currency are each user's. They sync with the user,
so every device of theirs shows the same. They say only how things are
shown; what was entered keeps its own unit.

### Meters, meter readings and trips

```
Asset is metered in UsageUnit                   v1 | 'km'
                                                a1 | 'h'
                                                a3 | 'cycles'
Asset has no meter                              v3
MeterReading is of Asset                        r21 | v1
                                                r40 | a1
MeterReading was at Moment                      r21 | 2026-10-01 07:45
MeterReading shows Usage                        r21 | 153120 km
                                                r22 | 94640 mi
                                                r40 | 212 h
MeterReading was by User                        r21 | anna@example.org
Trip is of Vehicle                              t3 | v1
                                                t9 | v1
Trip started at Moment                          t3 | 2026-09-20 08:10
                                                t9 | 2026-10-02 18:40
Trip ended at Moment                            t3 | 2026-09-20 11:25
Trip started at Usage                           t3 | 152410 km
Trip ended at Usage                             t3 | 152700 km
Trip covered Distance                           t30 | 25 km
Trip is virtual                                 t32
Trip went from Place                            t3 | 'Berlin'
Trip went to Place                              t3 | 'Hamburg'
Trip has Purpose                                t3 | 'Business'
Trip was by User                                t3 | anna@example.org
                                                t9 | ben@example.org
```

A trip's date is its start's. "Started on Date" and "started at Time" from
step 1 become one moment: a trip may run past midnight. A trip covers a
distance where its vehicle has no meter; its readings follow from it.

### Fill-ups

```
FillUp is of Asset                              f1 | v1
                                                f2 | v2
                                                f41 | a1
FillUp was at Moment                            f1 | 2026-09-14 17:20
FillUp was at Usage                             f1 | 152300 km
                                                f41 | 214 h
FillUp was of Volume                            f1 | 42.5 L
                                                f2 | 11.2 gal (US)
FillUp was of Fuel                              f1 | 'Petrol 95'
FillUp cost Money                               f1 | 74.10 EUR
FillUp was at Station                           f1 | 'Shell, Main St'
FillUp filled the tank                          f1
FillUp was by User                              f1 | ben@example.org
```

### Work requests and services

```
WorkRequest is of Asset                         wr60 | a1
WorkRequest was made at Moment                  wr60 | 2026-11-20 18:00
WorkRequest was made by User                    wr60 | anna@example.org
WorkRequest has Title                           wr60 | "Won't start"
WorkRequest has Priority                        wr60 | 'Urgent'
WorkRequest was turned down on Date             wr65 | 2026-11-21
Service is of Asset                             s7 | v1
                                                s8 | v1
                                                s61 | a1
Service was raised from WorkRequest             s61 | wr60
Service was raised from Reminder                s12 | m5
Service is of MaintenanceType                   s7 | 'Preventive, predetermined'
                                                s8 | 'Corrective, deferred'
                                                s61 | 'Corrective, immediate'
Service is in WorkState                         s7 | 'Done'
                                                s61 | 'Done'
Service is planned for Date                     s61 | 2026-11-22
Service is assigned to User                     s61 | ben@example.org
Service reserves Quantity of StockItem          s61 | 1 | 'NGK BPR6ES'
Service was at Moment                           s7 | 2026-06-01 09:30
Service was at Usage                            s7 | 148000 km
                                                s61 | 214 h
Service has Title                               s7 | 'Annual service'
Service was by User                             s7 | anna@example.org
Service was done by Garage                      s7 | 'Garage Müller'
                                                s8 | 'Carglass'
Service is paid in Currency                     s7 | 'EUR'
Service had a discount of Money                 s7 | 20 EUR
Service was paid by PaymentMethod               s7 | 'Card'
Service was paid in Instalments                 s7 | 2
Service repaired Failure                        s61 | f63
ServiceItem is part of Service                  i1 | s7
                                                i2 | s7
ServiceItem is of Task                          i1 | 'Oil change'
                                                i2 | 'Brake fluid change'
ServiceItem cost Money                          i1 | 95 EUR
                                                i4 | 40 CHF
ServiceItem has Note                            i1 | 'Filter: Mann W 712/95'
ServiceItem was charged Money                   i4 | 41.60 EUR
Labour is of Service                            l9 | s7
                                                l62 | s61
Labour was by User                              l62 | ben@example.org
Labour was by Garage                            l9 | 'Garage Müller'
Labour took WorkTime                            l62 | 0.75
Labour cost Money                               l9 | 165 EUR
```

A service is paid in one currency, and its items' and labour's costs are
entered in it. An item may be entered in another (a part bought abroad),
and then converted into the service's: by what it was charged in that
currency, if the receipt says, or by the rates. The discount is in the
service's currency.

Step 1's "Service included Task for Money", with a note on that inclusion,
is a fact about a fact. So the inclusion is an object of its own, the
ServiceItem, with the task, the cost and the note as its facts. Two items
of one service may name the same task, so an item is not the objectified
pair of its service and task (that would be one per pair): it has an id of
its own, and is part of its service. Labour is an object of its own for
the same reason: two days' work by two people on one order.

### Failures and downtime

```
Failure is of Asset                             f63 | a1
Failure was at Moment                           f63 | 2026-11-20 17:50
Failure was at Usage                            f63 | 212 h
Failure is of FailureMode                       f63 | 'Fails to start on demand'
Failure has FailureMechanism                    f63 | 'Contamination'
Failure has FailureCause                        f63 | 'Operation'
Failure was found by DetectionMethod            f63 | 'On demand'
Failure had FailureImpact                       f63 | 'Critical'
Failure was of StockUnit                        f63 | u12
Failure was by User                             f63 | anna@example.org
Downtime is of Asset                            d64 | a1
                                                d68 | v1
Downtime started at Moment                      d64 | 2026-11-20 17:50
Downtime ended at Moment                        d64 | 2026-11-22 10:45
Downtime was for Failure                        d64 | f63
Downtime was for Service                        d68 | s7
Downtime was planned                            d68
```

### Tyres

```
TyreSet is kept for Vehicle                     ts1 | v1
                                                ts2 | v1
TyreSet has TyreSetName                         ts1 | 'Golf winter'
TyreSet is for Season                           ts1 | 'Winter'
                                                ts2 | 'Summer'
TyreSet is of TyreModel                         ts1 | 'Continental WinterContact TS 870'
TyreSet is of TyreSize                          ts1 | '205/55 R16'
TyreSet was bought for Money                    ts1 | 480 EUR
TyreSet was bought on Date                      ts1 | 2025-10-20
TyreChange is of Vehicle                        c4 | v1
TyreChange was at Moment                        c4 | 2026-04-05 10:00
TyreChange was at Usage                         c4 | 146900 km
TyreChange was by User                          c4 | anna@example.org
TyreChange fitted TyreSet                       c3 | ts1
                                                c4 | ts2
TyreChange removed TyreSet *                    c4 | ts1
TyreChange measured Tread                       c3 | 8
```

The tread is measured on the set fitted, at the change: "TyreSet had Tread
at TyreChange" from step 1 reads more simply from the change.

### Components, and units that are assets

```
ComponentChange is of Asset                     cc31 | v3
                                                cc50 | a3
ComponentChange fitted StockUnit                cc31 | u1
                                                cc50 | u8
ComponentChange fitted it into StockUnit        cc33 | u3
ComponentChange removed StockUnit               cc31 | u0
ComponentChange skips virtual trips             cc33
Move is made for ComponentChange                m2 | cc31
Move is made for Asset                          m9 | a3
Asset is fitted in Asset *                      a4 | a3
Record concerns Asset *                         d83 | a4
                                                d83 | a3
```

\* Derived (step 5). A unit that is an asset is put in service with a move
of reason 'Put in service' made for it, and taken out with 'Taken out of
service', beside 'Fitted' and 'Removed'.

### Documents and other costs

```
Document is of Asset                            d1 | v1
                                                d80 | a3
Document is of DocumentKind                     d1 | 'Insurance'
                                                d80 | 'Warranty'
Document was issued by Issuer                   d1 | 'Allianz'
Document has DocumentNumber                     d1 | '77-123456'
Document is valid from Date                     d1 | 2025-12-01
Document expires on Date                        d1 | 2026-12-01
                                                d80 | 2031-11-01
Document is valid until Usage                   d81 | 800 cycles
Document covers StockUnit                       d82 | u1
Document cost Money                             d1 | 610 EUR
Expense is of Asset                             e12 | v1
                                                e13 | v1
Expense was at Moment                           e12 | 2026-08-03 06:15
Expense was at Usage                            e13 | 152950 km
Expense is of ExpenseKind                       e12 | 'Parking'
                                                e13 | 'Toll'
Expense cost Money                              e12 | 36 EUR
                                                e13 | 40 CHF
Expense has Note                                e12 | 'Airport'
Expense was charged Money                       e13 | 41.60 EUR
Expense was by User                             e12 | anna@example.org
```

The issuer and the number replace step 1's single name 'Allianz 77-123456'.

### Incomes

```
Income is of Asset                              n30 | v1
                                                n41 | v1
Income was at Moment                            n30 | 2026-10-02 19:05
                                                n41 | 2027-08-30 15:00
Income was at Usage                             n30 | 153314 km
                                                n41 | 171020 km
Income is of IncomeKind                         n30 | 'Transport app'
                                                n41 | 'Sale'
Income earned Money                             n30 | 23.50 EUR
                                                n41 | 3000 EUR
Income was by User                              n30 | ben@example.org
                                                n41 | anna@example.org
Income was paid in Instalments                  n41 | 3
Income was for Trip                             n30 | t9
Income has Note                                 n41 | 'To a colleague'
```

### Notes and attachments

```
Trip has Note                                   t3 | 'Client meeting'
FillUp has Note                                 f1 | 'Price was up 10 cents'
...                                             (every record the same)
Attachment is of FillUp                         a1 | f1
Attachment is of Document                       a2 | d1
...                                             (every record the same)
Attachment has FileName                         a1 | 'receipt-0914.jpg'
                                                a2 | 'policy.pdf'
```

A record may have many attachments, each of one record. An attachment is
a file, and has its content: "Attachment has Content" (raw data, large),
mandatory, as a file has some (a photo taken on the phone always does).
In Core Data it is stored externally, beside the store, and the sync
carries it as any value of the record's, `Edm.Binary` in JSON.

### Schedules and reminders

```
Schedule is of Asset                            sc1 | v1
                                                sc2 | v1
                                                sc4 | a1
Schedule is for Task                            sc1 | 'Oil change'
Schedule is for ExpenseKind                     sc2 | 'Parking'
Schedule has Note                               sc2 | "Residents' permit, zone 4"
Schedule recurs every Usage                     sc1 | 15000 km
                                                sc4 | 100 h
Schedule recurs every Duration                  sc1 | 12
                                                sc2 | 12
Reminder is of Asset                            m5 | v1
                                                m6 | v1
Reminder comes from Schedule                    m5 | sc1
Reminder is for Task                            m6 | 'Air conditioning'
Reminder has Note                               m6 | 'It smells musty'
Reminder is due at Usage                        m5 | 163000 km
Reminder is due on Date                         m5 | 2027-06-01
                                                m6 | 2027-05-01
Reminder was set at Moment                      m5 | 2026-06-01 10:00
                                                m6 | 2026-10-02 18:30
Reminder was done at Moment                     m5 | 2027-05-20 11:00
Reminder was done at Usage                      m5 | 162400 km
Reminder was done by Service                    m5 | s12
Reminder was done by Expense                    m7 | e20
Reminder was cancelled on Date                  m6 | 2027-05-25
Reminder replaces Reminder                      m9 | m6
Rescheduling is of Reminder                     rs1 | m6
Rescheduling was made at Moment                 rs1 | 2027-04-28 20:10
Rescheduling was made by User                   rs1 | anna@example.org
Rescheduling moved from Date                    rs1 | 2027-05-01
Rescheduling moved from Usage                   rs2 | 160000 km
```

A reminder from a schedule is for the schedule's work; "is for" on a
reminder is for one on its own. Work that is a task is done by a service
done that includes it; work that is a kind of expense, by an expense of
that kind. A schedule's reminders are kept as records: when one is done,
the app makes the next one, due its intervals after when and where it was
done. The owner may change any reminder afterwards, its due usage and
date included; moving it records a rescheduling, from what it was due at.
Done (at a moment, maybe at a usage and by a record) and cancelled (on a
date) are entered facts: the app's service layer enters them as it
records the work, and clears them when that record is discarded
([PROCESSES.md](PROCESSES.md)). A service raised from a reminder is
entered so too, when the reminder is near.

### Checklists and inspections

```
Checklist is kept by User                       cl1 | anna@example.org
Checklist has ChecklistName                     cl1 | 'Basic vehicle inspection'
Question is in Checklist                        q1 | cl1
                                                q4 | cl1
Question says QuestionText                      q1 | 'Is the registration certificate in the car?'
                                                q4 | 'Which of these are not working?'
                                                q9 | 'Battery health'
Question is at Position                         q1 | 1
                                                q4 | 4
Question is answered by AnswerKind              q1 | 'Yes or no'
                                                q4 | 'Any of'
                                                q9 | 'Measurement'
Question measures in Unit                       q9 | '%'
Question has lower limit Quantity               q9 | 80
Question has upper limit Quantity               q10 | 4.5
Question calls for Task when out of limits      q9 | 'Battery replacement'
Option is in Question                           o1 | q4
                                                o2 | q4
Option says OptionText                          o1 | 'Low beams'
                                                o2 | 'High beams'
Option is at Position                           o1 | 1
                                                o2 | 2
Option calls for Task                           o1 | 'Lamp replacement'
Inspection is of Asset                          in50 | v1
                                                in70 | a3
Inspection went through Checklist               in50 | cl1
Inspection was at Moment                        in50 | 2026-08-28 12:00
Inspection was at Usage                         in50 | 151600 km
Inspection was by User                          in50 | anna@example.org
Answer is of Inspection                         an1 | in50
                                                an4 | in50
Answer is to Question                           an1 | q1
                                                an4 | q4
Answer says YesNo                               an1 | 'Yes'
Answer chose Option                             an4 | o1
                                                an4 | o2
Answer measured Quantity                        an70 | 76
Answer has Note                                 an4 | 'Both fuses?'
WorkRequest was raised from Answer              wr71 | an70
Schedule is for Checklist                       sc3 | cl1
Reminder was done by Inspection                 m8 | in51
```

Questions and options are records with ids, not just their text: one may
be reworded later, and the inspections that answered it still point at
it. Step 1's "In Inspection, Question was answered ...", with a note on
it, is a fact about a fact, as a service's item was. So each answer is an
object of its own, the Answer (objectification). A yes-or-no answer says
which; an any-of answer chooses its options, as many as apply; a
measurement says its quantity, in its question's unit.

### Who entered what

```
Trip was entered by User                        t3 | anna@example.org
FillUp was entered by User                      f1 | ben@example.org
...                                             (every record the same)
```

### What's left for later steps

- **Repetition.** Every kind of record repeats "is of Asset", "was at
  Moment", "was at Usage", "was by User", "has Note", attachments,
  "cost Money", "was entered by User" and its own rate. Step 6 decides
  whether they are one supertype (an Event, or a Record) with these fact
  types once, and which records are costs and which incomes.
- **Vehicles and assets.** What only a vehicle has, and what any asset
  has: step 6's subtype.
- **Reminders done by work.** "Reminder was done by Service", "by
  Expense" and "by Inspection", and "is for Task", "for ExpenseKind" and
  "for Checklist": the same question, a supertype of the work and of what
  does it.
- **Not stored, worked out:** a trip's distance and duration; a service's
  cost; which tyre set is on; how far a set or a component has gone; what
  is fitted in what; an asset's state; when a reminder is next due; usage
  over a period; every report and indicator. Step 3 lists these
  derivations.

## Step 3: entity types combined, arithmetic derived

### Entity types combined

Two entity types are one when their instances can be compared as the same
kind of thing.

- **Usage** is one type, whatever role it plays. A meter's reading
  (acquired at, shows, at, a trip's start and end), a length of use (used
  more) and an interval (recurs every, valid until) are all usages. A
  reminder is due when a reading reaches a sum of readings and intervals,
  and a component's wear is a difference of readings. Comparing and
  subtracting them is the point. A usage compares only with one of its
  dimension: kilometres with miles, never with hours.
- **Distance** stays a type of its own, for what only is one: a trip's
  length where its vehicle has no meter, and the user's unit of distance.
  A vehicle's usages are distances in value, of the dimension 'distance'.
- **Asset** is one type for what step 2 kept apart as vehicles and the
  generator: every record is of an asset, and the same facts are said of
  each. A vehicle is an asset with more (step 6).
- **User** is one type for the owner, whoever shares an asset, whoever an
  event was by, who made a request, who a work order is assigned to, who
  did its labour, and who entered each record. The same person plays all
  of these.
- **Fuel** is one type: what an asset uses, and what a fill-up was of.
- **EquipmentClass** takes VehicleKind in: a car, a motorcycle, a bicycle
  and a generator are classes alike, compared in one taxonomy.
- **CostKind replaces ServiceKind and ExpenseKind.** The pie chart puts
  fill-ups, maintenance, repairs, tyres, documents, parking, tolls and
  washes side by side as kinds of cost. So there is one list of kinds, and
  each record gets its kind:
  - a fill-up is 'Fuel';
  - a service is 'Maintenance' if preventive, 'Repair' if corrective: no
    longer chosen, it follows from its maintenance type;
  - buying a tyre set is 'Tyres';
  - a document is 'Documents';
  - an expense is 'Parking', 'Toll', 'Wash', or another kind of its own.

  Expenses say their kind; for the rest it is fixed by what they are,
  which is a derivation (step 5). A schedule or reminder for a kind of
  expense is then for a CostKind, one of the kinds an expense may be of
  (step 6).
- **Moment** is one type for when every event happened, a trip's start
  and end, a downtime's start and end, when a request was made and when a
  reminder was done. They are compared to put records in order.
- **Task** is one type for what a service does, what a schedule or a
  reminder is for, and what an answer calls for.

What stays apart:
- **Garage, Station and Place:** they play different roles, and nothing
  compares a garage with a trip's destination.
- **Model and TyreModel.**
- **Note and Title:** text, but nothing compares one with the other.
- **IncomeKind:** incomes aren't costs, and their kinds are a list of
  their own.
- **WorkTime and Duration:** hours of work and months of keeping or
  recurring; a work time is no usage either (labour is not the asset's
  meter).
- **The failure lists** (mode, mechanism, cause, detection, impact): each
  answers its own question about a failure.
- **DocumentKind, Purpose and PaymentMethod:** lists of their own.
- **AnswerKind, YesNo, MaintenanceType, WorkState, Priority,
  Criticality:** fixed lists of their own.

### What is worked out, not stored

Each in the user's preferred units and currency, unless it says otherwise.

**Conversions**

1. *A usage or a distance in a unit:* its quantity × the fixed factor
   between the units, within its dimension. The same for volumes.
2. *Money in a currency:* what it was charged in that currency, if the
   record says. Otherwise the amount × the rate between the currencies on
   its date, or on the latest date before it with a rate. When there is no rate at
   all, the amount can't be shown in that currency, and the report says
   so.

**Records**

3. *A trip's distance:* where it ended − where it started.
4. *A trip's duration:* when it ended − when it started.
5. *A service's cost:* the sum of its items' and its labour's costs, less
   its discount, in the service's currency (an item entered in another
   converted by what it was charged, or the rates).
6. *An asset's reading at a moment:* the latest usage any of its records
   gives at or before that moment (acquisition, meter readings, trips'
   ends, fill-ups, services, tyre changes, incomes, failures), in its
   meter's unit. The forms show it as the last reading, beside the meter.
7. *A fill-up's price per volume:* its cost ÷ its volume.
8. *Which tyre set is on a vehicle:* the one its latest tyre change
   fitted.
9. *How far a tyre set or a component has gone:* over each time it was
   on, the reading at the change that removed it − the reading at the
   change that fitted it (to the asset's latest reading while it is still
   on); a component that is an asset with a meter of its own, by its own
   readings.

**Components and assets**

10. *What an asset is fitted in* (`Asset is fitted in Asset`): for a unit
    that is an asset, the asset its latest component change fitted it on,
    or the asset of the unit it was fitted into, while no later change
    removed it; and what that is fitted in, in turn.
11. *What a record concerns* (`Record concerns Asset`): the asset it is
    of, and every asset that one was fitted in at the record's moment.
12. *A unit asset's make, model and serial:* its item's manufacturer, its
    item, its unit's serial number.
13. *An asset's state:* 'Disposed' if it was sold or disposed of; else
    'Out of service' if a downtime of it has started and not ended; else
    'In stock' if it is a unit at a location; else 'In service'.

**Reminders and work orders**

14. *When a schedule's next reminder is due:* the usage and date its last
    reminder was done + the schedule's intervals. Before any was done,
    counted from when the schedule was set up: its first reminder's due
    usage and date are given then.
15. *Whether a reminder is due, or overdue:* open, and the asset's
    latest reading has reached its usage, or today its date, whichever
    comes first.
16. *How far and how long until a reminder is due:* its due usage − the
    asset's latest reading; its due date − today.
17. *Whether a work order is late:* not done, and its planned date past.

**Fuel**

18. *Consumption (L/100 km, km/L or mpg, as the user prefers, for a
    vehicle; L/h for an asset metered in hours),* the full-tank method:
    the volume put in since the full fill-up before ÷ the usage since it.
    Only between two fill-ups that filled the tank; a partial fill-up's
    volume counts toward the next full one. Fill-ups are taken in the
    order of their moments. Each full fill-up shows the consumption up to
    it.
19. *Fuel cost per usage:* the same, with cost for volume.

**Reports,** per asset and over a period, then per kind of record:

20. *Usage:* the reading at the period's end − the reading at its start.
21. *Costs:* the sum of the costs of the records in the period.
22. *Income:* the sum of the incomes in the period.
23. *Per day:* a total ÷ the days in the period.
24. *Per usage:* a total ÷ the usage.
25. *Costs by kind, by month, by kind of record each month; incomes by
    kind; service costs by task:* the sums so grouped. A service's
    discount is spread over its tasks and labour in proportion to their
    costs.
26. *Fuel consumption:* each full-tank interval's consumption (a chart
    over time); the latest, the lowest and the highest of them; and the
    average over the period (all the volume ÷ all the usage between the
    first and the last full fill-up in it). The same for the fuel cost per
    usage. All fuels, or the fill-ups of one fuel. The total volume and
    cost of fuel.
27. *Readings:* each record's moment and usage, in order.
28. *A month against the month before:* its average consumption ÷ the
    month before's − 1, as a percentage up or down.
29. *Balance:* income − costs, then in each view:
    - *cash:* − the purchase price on its date, + the sale price on its
      date;
    - *running:* nothing more;
    - *depreciation over time:* − (purchase price − expected sale price) ÷
      expected duration, a cost per day;
    - *depreciation by usage:* − (purchase price − expected sale price) ÷
      expected further usage, a cost per unit of usage;
    - *what it's worth:* − the drop in value between valuations, counted
      on the date of the valuation that shows it;
    - and in the depreciation views, when sold: + (sale price − the value
      left on paper), on the sale's date.

**Indicators** (EN 15341), over the records that concern an asset (11),
per asset; per class and per maintainable item over their assets and
units:

30. *Downtime in a period:* the sum of its downtimes' overlap with the
    period; *after failures*, those for a failure.
31. *Uptime in a period:* the period's time while the asset was kept and
    not disposed of, − its downtime.
32. *Preventive share:* the cost (and the labour hours) of preventive
    services done in the period ÷ those of all services done in it.
33. *MTBF:* uptime ÷ the failures in the period; *MTTR:* downtime after
    failures ÷ those failures.
34. *Availability:* uptime ÷ (uptime + downtime).
35. *Maintenance cost per usage:* the services' cost ÷ the usage (20).
36. *Backlog:* the work orders not done nor cancelled at the period's end,
    their count and their planned labour, by criticality.
37. *Schedule compliance:* the reminders due in the period that were done
    by their date and usage ÷ all those due.

### For ORMKit

These derivations become ORMKit derivation queries. A few need more than
ORMKit's queries do today, which is part of what building Logbook will
show:
- arithmetic between values (differences, products, quotients);
- the record before or after another, in order of moments (the fill-up
  before, the next reading); the lowest and highest;
- unit and currency conversion, the latter by the latest rate on or
  before a date;
- dates and durations (days in a period, months between dates, the
  overlap of a downtime with a period);
- grouping by month;
- the transitive closure of a relation (what is fitted in what, in turn).

## Step 4: uniqueness, and whether each fact type is elementary

A uniqueness constraint says which roles' values occur at most once
together. It also tests elementarity: a fact type of n roles whose
uniqueness spans fewer than n − 1 roles splits into smaller ones (Halpin's
n − 1 rule).

### Each at most one

Most fact types say one thing about one record, so the record's role is
unique. Each asset, record or user has at most one of each of these:

- **Asset:** owner, name, make, model, fuel, class, criticality, meter
  unit, the unit it is, date, usage and price acquired, expected
  duration, expected further usage, expected sale price, date and price
  sold, date disposed of.
- **Vehicle:** kind, year built, VIN, registration.
- **EquipmentClass:** category.
- **User:** name, preferred currency, distance unit, volume unit.
- **MeterReading:** asset, moment, usage, who it was by.
- **Trip:** vehicle, start and end moments, start and end usages, the
  distance it covered, from, to, purpose, who it was by.
- **FillUp:** asset, moment, usage, volume, fuel, cost, station, who it
  was by. Filling the tank is a unary: a fill-up did or didn't.
- **WorkRequest:** asset, moment, who made it, title, priority, the date
  it was turned down, the answer it was raised from.
- **Service:** asset, moment, usage, title, garage, maintenance type,
  state, planned date, who it is assigned to, the request or the
  reminder it was raised from, currency, who it was by, discount,
  payment method, instalments.
- **ServiceItem:** service, task, cost, what it was charged, note.
- **Labour:** service, user or garage, work time, cost.
- **Failure:** asset, moment, usage, mode, mechanism, cause, detection
  method, impact, the unit that failed, who it was by.
- **Downtime:** asset, start, end, the failure or the service it was for.
- **TyreSet:** vehicle, name, season, model, size, price, date bought.
- **TyreChange:** vehicle, moment, usage, the set fitted, the set
  removed, tread, who it was by.
- **ComponentChange:** asset, moment, usage, the unit fitted, the unit it
  went into, its position, the unit removed, where that was put away.
- **Document:** asset, kind, issuer, number, valid from, expires, valid
  until usage, the unit it covers, cost.
- **Expense:** asset, moment, kind, cost, what it was charged, who it was
  by.
- **Income:** asset, moment, usage, kind, money, who it was by,
  instalments, the trip it was for.
- **Checklist:** who keeps it, name.
- **Question:** checklist, text, position, kind of answer, unit, lower
  and upper limit, the task it calls for out of limits.
- **Option:** question, text, position, the task it calls for.
- **Inspection:** asset, checklist, moment, usage, who it was by.
- **Answer:** inspection, question, yes or no, quantity measured, note.
  *Answer chose Option* is many to many: an answer chooses many options,
  and an option is chosen in many inspections. The uniqueness spans both
  roles.
- **Schedule:** asset, task, kind of expense or checklist, note, usage
  interval, time interval.
- **Reminder:** asset, schedule, task, kind of expense or checklist,
  note, due usage, due date, done moment, done usage, the record it was
  done by.
- **Attachment:** the record it is of, file name.
- **Every record:** who entered it, note.

The other role is not unique in any of these: many trips are of one
vehicle, many fill-ups cost 74.10 EUR, one set is fitted by many changes
over the years, a record has many attachments, a request raises at most
one order but a reminder's order is one of many over the years.

**Also unique the other way:**
- **Asset is StockUnit:** a unit is at most one asset. An asset is at
  most one unit, so the fact type is one to one.
- **Service was raised from WorkRequest:** a request becomes at most one
  order. And from a reminder: one order per reminder.
- **WorkRequest was raised from Answer:** an answer raises at most one.
- **Income was for Trip:** a trip is paid by at most one income.
- **An answer's inspection and question:** an inspection answers each
  question at most once. An external uniqueness over the two, so the
  inspection and the question together identify the answer, as a service
  item's could not (two items of a service may name the same task).
- **A question's checklist and position, an option's question and
  position:** one at each place in a list.
- **Money, Usage, Distance, Volume:** each has one amount and one currency
  (or quantity and unit), and the two together identify it: (74.10, 'EUR')
  is one money. That is the reference scheme from step 2, an external
  uniqueness over the two.

**Not unique the other way**, deliberately:
- **A VIN** may be on two vehicles. A car sold from one user to another is
  in both logbooks, each with its own history. A serial number is unique
  per item, in Stock.
- **Registration numbers** change hands, and come back.
- **Names** (assets, tyre sets) aren't checked: two assets may both be
  'Golf'.

### Many to many

- **Asset is shared with User:** a user shares many assets, and an asset
  is shared with many users. The uniqueness spans both roles: each pair
  once.
- **Service repaired Failure:** one visit may repair two failures, and a
  failure may take two visits.
- **FailureMode applies to EquipmentClass**, **Category is a maintainable
  item of EquipmentClass:** lists against lists, each pair once.

### More than two roles

- **Asset was valued on Date at Money:** one value per asset per date.
  The uniqueness spans the asset and the date: n − 1 = 2 roles, so it is
  elementary.

  ```
  v1 | 2026-10-01 | 4000 EUR
  v1 | 2027-03-01 | 3600 EUR     different dates: fine
  v1 | 2026-10-01 | 3900 EUR     the same date again: not allowed
  ```

- **Service reserves Quantity of StockItem:** one quantity per order per
  item; the uniqueness spans the service and the item, elementary.
- **EquipmentClass has ClassAttribute in Unit:** one unit per class's
  attribute; **Asset has Value for ClassAttribute:** one value per
  asset's attribute. Each spans two of three roles, elementary.
- **On Date one Currency was worth Factor Currency:** one factor per date
  per pair of currencies. The uniqueness spans the date and both
  currencies: n − 1 = 3 roles, elementary.

  ```
  2026-09-14 | EUR | 1.09 | USD
  2026-09-14 | EUR | 1.10 | USD   the same day and pair again: not allowed
  ```

  The rate the other way (USD to EUR) is derived, 1 ÷ the factor, and
  stored, so that reports read rates in both directions alike (step 5).

- **"Was converted at Factor into Currency"** (step 2, for expenses and
  service items) *wasn't elementary*. Each expense has at most one
  conversion, so the uniqueness spanned one role of three, fewer than
  n − 1. It splits into a factor and a currency. But the receipt says it
  more simply as what the expense was charged in the other currency:
  "Expense was charged Money 41.60 EUR". One binary, with the factor
  derived (41.60 ÷ 40). Steps 1 to 3 now say it so.
- **"Labour was by User or Garage for WorkTime and Money"** would be one
  fact with an optional part: it splits into the labour's own binaries,
  each unique on the labour.

## Step 5: what must be there, and logical derivations

### What every one must have

A mandatory role says every instance of the type plays it. The rule here:
**a record states all of its facts**. A fact is optional only where it can
honestly be missing, and each such case is listed with why.

| Record | Must have | May lack, and why |
| --- | --- | --- |
| Asset | owner, name; a meter unit or no meter | make and model (a home-made one; a unit asset's are derived); class (a vehicle has its kind instead); fuel (a bicycle, a power station use none); criticality (not yet assessed); the unit it is (an asset bought privately); what it was bought for, the expectations, valuations, the sale, the disposal (each balance view needs only some) |
| Vehicle | (an asset's) | its kind (none: one stored before kinds, a motorised one); year (a bicycle has none: a motorised one has it, by rule); VIN and registration (not every car has them to hand, a bicycle none) |
| EquipmentClass | category | attributes, failure modes (not yet described) |
| User | email | name and preferences (preferences default to km, L and the device's currency) |
| MeterReading | asset, moment, usage, who it was by | |
| Trip | vehicle, start and end moments, start and end usages, who it was by | from, to and purpose (a paid ride may not record them) |
| FillUp | asset, moment, usage, volume, fuel, cost, station, who it was by | |
| WorkRequest | asset, moment, who made it, title | priority (normal, when missing); the answer it came from; the date turned down, until it is |
| Service | asset, state, maintenance type, currency | moment, usage and who it was by, until it is done (then a must: the service did happen); planned date and who it is assigned to (a service recorded after the fact has neither); the request or reminder it came from; items and labour (a service may list none); title (its type and tasks say what it was); garage (work done at home, or a garage not known: Drivvo's services often name none); discount; payment method; instalments (paid at once, when missing) |
| ServiceItem | service, task | cost (a task done at home, or its cost not known: MainTrack's are mostly so); note; what it was charged in another currency (only when it was) |
| Labour | service; a user or a garage, exactly one; work time or cost, or both | the other (a garage's bill gives only the cost; one's own work only the hours) |
| Failure | asset, moment, mode, impact, who it was by | usage (an asset with no meter); mechanism, cause, detection method, the unit that failed (not always known, and found out later) |
| Downtime | asset, start | end (still down); the failure or the service it was for (a stop with neither, a storm); planned (a downtime that doesn't say so wasn't) |
| TyreSet | vehicle, name, season, model, size | price and the date bought, both or neither (a set that came with the car) |
| TyreChange | vehicle, moment, usage, the set fitted, tread, who it was by | |
| ComponentChange | asset, moment, usage, the unit fitted, who it was by | the unit it went into (fitted to the asset itself), its position, the one it removed (fitted to an empty place), where that was put away (thrown away), skipping virtual trips (it wears on every trip) |
| StockUnit | item | its serial number (a chain has none), note |
| Trip (of a vehicle with no meter) | distance covered | its readings, worked out |
| Document | asset or a unit it covers, kind, issuer, number, valid from | expiry and usage limit (a registration certificate doesn't expire); cost (some are free) |
| Expense | asset, moment, kind, cost, who it was by | usage (any event may say one); what it was charged in another currency |
| Income | asset, moment, kind, money, who it was by | usage (a refund comes away from the asset); the trip (only a ride logged as a trip has one); instalments (paid at once, when missing) |
| Attachment | the record it is of, file name | |
| Checklist | who keeps it, name | questions (a new checklist, still being written) |
| Question | checklist, text, position, kind of answer | options (only an any-of question has them); unit and limits (only a measurement has them); the task it calls for |
| Option | question, text, position | the task it calls for |
| Inspection | asset, checklist, moment, usage, who it was by | answers (a question may be left unanswered) |
| Answer | inspection, question | yes or no (only for a yes-or-no question); options chosen (none may apply); quantity (only for a measurement); note |
| Schedule | asset; its work: a task, a kind of expense or a checklist, exactly one (exclusive-or); at least one interval | the other interval: it may recur by usage only, by time only, or both (inclusive-or); note |
| Reminder | asset; a due usage or a due date or both (inclusive-or); its schedule or work of its own, a task, a kind of expense or a checklist, exactly one of the four (exclusive-or) | note; the done moment, done usage and the event that did it, until it is done; then the moment is a must, the usage and the event optional (an event with no usage, or done by hand); the date it was cancelled, until it is (not both done and cancelled); the reminder it replaces, and the one replacing it |
| Rescheduling | the reminder, when and by whom it was made; what the reminder was due at before, a date or a usage or both (inclusive-or) | note |
| Every record | who entered it | note; attachments (any number, none included) |
| Money, Usage, Distance, Volume | amount and currency; quantity and unit | |
| An exchange rate | all four roles | |

Some of these are more than single mandatory roles:
- **A service that is done** ('Done' or 'Closed') has a moment, a usage
  where its asset is metered, and who it was by; one not yet done has
  none of them, and may not do a reminder's work nor repair a failure. A
  rule on the state, not a mandatory role (step 6, a subtype).
- **A reminder that is done** has a done moment, and a done usage only
  with it: a subset constraint (step 6). An expense with no usage does
  a reminder's work too, so a done reminder need not have a usage.
- **"FillUp filled the tank"**, **"Downtime was planned"** are yes or no:
  a fill-up that doesn't say so didn't fill it. A unary can't be
  mandatory; leaving it out is the "no".

Who an event was by is a must on every event that happened, as a record
states all of its facts. The forms fill it in with the signed-in user, to
be changed when someone else did it.

**What is stored already** takes the new musts so: every service stored
is 'Done', and preventive or corrective as its kind was ('Maintenance':
'Preventive, predetermined'; 'Repair': 'Corrective, immediate'); its
'Labour' items stay items. Every vehicle is an asset, metered in km, or
in the unit its readings were in, or with no meter as it had none.

### Logical derivations

Facts worked out from others by rules, not arithmetic:

1. **Each record's kind of cost** (`Record is of CostKind`):
   - a fill-up is of 'Fuel';
   - a service is of 'Maintenance' if its type is preventive, of 'Repair'
     if corrective;
   - a tyre set, bought, is of 'Tyres';
   - a document with a cost is of 'Documents';
   - an expense is of the kind it says.

   So the kind is stored only for expenses. The derived fact puts every
   cost in one list, for the reports. Incomes are not costs, and have
   kinds of their own.
2. **Who uses an asset** (`User uses Asset`): the users it is shared
   with, and its owner. *Partly derived*: the sharing is stored, and the
   owner is derived. A vehicle's are its drivers.
3. **Who an asset is shared with:** its users other than its owner.
4. **A reminder's work** (a task, a kind of expense or a checklist): its
   own, or its schedule's. Its note likewise.
5. **Whether a reminder is open, done or cancelled:** done, it has a done
   moment; cancelled, a cancel date; open, neither.
6. **What did a reminder's work** (`Reminder was done by Event`): the
   first record of its asset, after it was set, that does its work: a
   service done with an item of its task, a component change fitting a
   unit of an item of the category its task is named as, an expense of
   its kind, or an inspection through its checklist. *Not a derivation:*
   the app's service layer, saving such a record, enters the reminder done
   by it, at its moment and at its usage when it has one, and makes the
   schedule's next ([PROCESSES.md](PROCESSES.md)). The owner may change
   that afterwards, or mark a reminder done by hand. What the model says
   of it is checked: done by an event, at that event's moment
   (`ReminderDoneAtItsEventsMoment`), and at its usage where it has one
   (`ReminderDoneAtItsEventsMileage`).
7. **That an asset was sold, when and for how much:** from its income of
   kind 'Sale', the date of its moment and its money. An asset has at
   most one (step 6).
8. **The reverse exchange rate:** if on a date one X is worth F Y, then
   one Y is worth 1 ÷ F X. *Derived and stored*: worked out when a rate is
   entered, and kept, so that reports read rates both ways alike. A rate
   entered by hand both ways keeps the one entered.
9. **Which questions an inspection left unanswered:** its checklist's
   questions with no answer of it.
10. **Which checklists a user may use on an asset:** its owner's.
11. **Which set a tyre change removed** (`TyreChange removed TyreSet`):
    the set the vehicle's tyre change before it fitted. None for the first
    change recorded. *Derived*, not stored (step 7).
12. **Which records a user other than the owner may change:** none, but
    a work order assigned to them, through its states. The owner may
    change any of their assets' records. That's a permission, from the
    facts of who owns, who it is assigned to and who entered, enforced by
    the service (see Permissions).
13. **What an asset is fitted in, and what a record concerns** (step 3,
    10 and 11): from the component changes, never entered.
14. **A unit asset's make, model and serial** (step 3, 12): its unit's.
15. **An asset's state** (step 3, 13).
16. **Which answers call for work:** an answer choosing an option that
    calls for a task, or measuring a quantity outside its question's
    limits. *Not a derivation:* the service layer, saving such an
    answer, enters a work request raised from it, for the task; the owner
    may turn it down. And a reminder near its due date or usage raises a
    service planned for it the same way ([PROCESSES.md](PROCESSES.md)).

## Step 6: value, set-comparison and subtype constraints

### Value constraints

A value constraint lists or bounds what a value may be.

**Fixed lists,** part of the model:

| Value type | Values |
| --- | --- |
| DistanceUnit | 'km', 'mi' |
| UsageUnit | 'km', 'mi', 'h', 'cycles', 'kWh' |
| Dimension | 'distance', 'time', 'cycles', 'energy' |
| VolumeUnit | 'L', 'gal (US)', 'gal (imp)' |
| ServiceKind | 'Maintenance', 'Repair' |
| MaintenanceType | 'Preventive, predetermined', 'Preventive, condition-based', 'Corrective, immediate', 'Corrective, deferred' (EN 13306) |
| WorkState | 'Draft', 'Planned', 'Released', 'In progress', 'Done', 'Closed', 'Cancelled' |
| Priority | 'Urgent', 'High', 'Normal', 'Low' |
| Criticality | 'High', 'Medium', 'Low' |
| AssetState | 'In service', 'Out of service', 'In stock', 'Disposed' |
| FailureCause | 'Design', 'Fabrication', 'Installation', 'Operation', 'Maintenance', 'Unknown' (ISO 14224's groups) |
| FailureImpact | 'Critical', 'Degraded', 'Incipient' (ISO 14224) |
| Season | 'Summer', 'Winter', 'All-season' |
| AnswerKind | 'Yes or no', 'Any of', 'Measurement' |
| YesNo | 'Yes', 'No' |

**Lists the users keep:** Task, ExpenseKind, IncomeKind, DocumentKind,
Purpose, PaymentMethod, Fuel, EquipmentClass, EquipmentCategory,
FailureMode, FailureMechanism, DetectionMethod. A new logbook starts with
a few of each (Drivvo's are a fair start; for classes, failure modes,
mechanisms and detection methods, ISO 14224's, as far as they are
public), and users add their own. These have no value constraint; the
starting ones are data.

**Ranges:**

| Value | Range | Why |
| --- | --- | --- |
| Amount, of every money | > 0 | a cost of nothing isn't recorded; a free document has no cost |
| Quantity of a usage, as a reading (acquired at, shows, at, started, ended, due at, done at) | ≥ 0 | a new meter reads 0 |
| Quantity of a usage, as a length (recurs every, used more, valid until) | > 0 | |
| Quantity of a distance, a volume | > 0 | |
| WorkTime | > 0 | |
| Factor of an exchange rate, of a unit | > 0 | |
| Duration (kept for, recurs every) | ≥ 1 month | |
| Year built | 1886 and on | |
| Tread | 0 to 20 mm | |
| Instalments, Position | ≥ 1 | |
| Currency | three capital letters, ISO 4217 | |
| VIN | 17 letters and digits, not I, O or Q | |

A usage is one type (step 3), so its ranges are on the roles, not the
type: a reading may be 0, an interval may not.

### Subtypes

**Asset** has a subtype, **Vehicle**, asserted: a vehicle is an asset
entered as one. What only vehicles have is Vehicle's: its kind, the year
built, its VIN and registration; trips, tyre sets and tyre changes are of
a Vehicle. Everything else is said once, of Asset. In Core Data Vehicle is
Asset's subentity, as Event is Record's, and a vehicle stored before keeps
its id. **VehicleKind** is a subtype of **EquipmentClass**: 'Car',
'Motorcycle', 'Bicycle', in the category 'Vehicles'. An asset that is no
vehicle has a class that is no vehicle kind (below).

**FuelledAsset** is an asset that uses a fuel: *each FuelledAsset is by
definition an Asset that uses some Fuel*. Only those are filled up.

**ComponentAsset** is an asset that is a unit: *each ComponentAsset is by
definition an Asset that is some StockUnit*. Its make, model and serial
are its unit's (step 5, derivation 14), so it enters none.

**Record** is every kind of thing users enter, with an id: MeterReading,
Trip, FillUp, Service, TyreChange, ComponentChange, Expense, Income,
Inspection, Failure, Downtime, WorkRequest, TyreSet, Document, Schedule,
Reminder. What step 2 repeated for each is said once, of Record:
- Record is of Asset;
- Record was entered by User;
- Record has Note;
- Attachment is of Record.

**Event** is a record of something that happened: MeterReading, Trip,
FillUp, Service, TyreChange, ComponentChange, Expense, Income,
Inspection, Failure, Downtime. Once, of Event:
- Event was at Moment (a trip's is when it started, a downtime's when it
  started; each also ended at a moment);
- Event was by User.

**MeteredEvent** is an event that was at a usage: *each MeteredEvent is
by definition an Event that was at some Usage* (`MeteredEventRule`).
"Event was at Usage" is said once, of Event, and is optional there: an
expense or an income may say its usage, and need not. Every meter
reading, trip (where it started), fill-up, tyre change, component change
and inspection is asserted a MeteredEvent, so its usage is a must: the
generated code checks "Each FillUp is a MeteredEvent" as a rule of
FillUp, and the same of the others; a failure is one where its asset is
metered. This answers step 1's question: each of these gives a reading of
the meter, and a MeterReading is the event that does nothing else. An
asset's reading at a moment (step 3, derivation 6), and the meter going
up, are over its MeteredEvents: every event with a usage.

**DoneService** is a service that happened: *each DoneService is by
definition a Service that is in WorkState 'Done' or 'Closed'*. Each
DoneService is a MeteredEvent (its asset metered), and was at a moment
and by a user; only a DoneService does a reminder's work or repairs a
failure. A service planned is a record, not yet an event that happened.

MeteredEvent and DoneService are no entities of their own in Core Data (a
derived subtype's fact types are its supertype's): the usage is Event's,
optional there, and FillUp, Service, Trip, TyreChange, ComponentChange,
MeterReading, Inspection, Failure and Downtime are Event's subentities.

**Cost** is a record that cost money: *each Cost is a Record that cost
some Money*. Every fill-up, service and expense is one; a tyre set or a
document is one when it has a price. Once, of Cost:
- Cost cost Money (a service's is derived: its items and labour less its
  discount);
- Cost was charged Money (in another currency, when the receipt says;
  a fill-up abroad, too);
- Cost is of CostKind (derived, step 5).

A cost counts in reports on its date: an event's moment, a tyre set's
date bought, a document's valid-from date. Doing this showed that a tyre
set's price had no date, so "TyreSet was bought on Date" is added, with
an equality constraint: a price if and only if a date. A service counts
once done, on its moment.

**CostKind** has two subtypes, its values split between them:
- **ServiceKind:** 'Maintenance', 'Repair', each a service's by its
  maintenance type;
- **ExpenseKind:** each CostKind that is not 'Fuel', 'Maintenance',
  'Repair', 'Tyres' or 'Documents'. Those five are the kinds fixed by what
  a record is; the users' own kinds are all expense kinds.

So "Schedule is for ExpenseKind" can only name a kind an expense can be
of, by its type, with no constraint of its own.

**AssetSale** is an income of kind 'Sale': *each AssetSale is an Income
that is of IncomeKind 'Sale'*. "AssetSale is of Asset" is unique on the
asset's side: an asset is sold at most once. The asset's sale (step 5,
derivation 7) is read from it.

**Not made subtypes:**
- **What a reminder is for** (a task, a kind of expense, a checklist).
  Three fact types with an exclusive-or, not a supertype "Work": they are
  identified differently (by name, by name, by id), and share nothing
  else.
- **What did a reminder's work** is one fact type, *Reminder was done by
  Event*, instead of three: services, expenses and inspections are all
  events. Which event may do it is the derivation's (step 5).
- **The work request** is not a state of its service: it may be turned
  down and never become one, and an order may come from a reminder
  instead. Two records, one raised from the other.
- **Who did the labour** (a user or a garage): two fact types with an
  exclusive-or, as a reminder's work is.

### Set-comparison constraints

**Equality** (one if and only if the other):
- a tyre set's price and its date bought;
- a question's unit and its being answered 'Measurement'.

**Subset** (the one only with the other):
- *Reminder was done by Event*, and *Reminder was done at Usage*, only
  for a reminder with a done moment;
- *Reminder was done by Event* and *Service repaired Failure* only for a
  DoneService, where the event is a service;
- *Reminder replaces Reminder* only where both are of the same asset (a
  join subset);
- *Income was for Trip* only where the income and the trip are of the
  same vehicle; the same for *Reminder was done by Event*, *Reminder comes
  from Schedule*, *Service was raised from WorkRequest*, *Service was
  raised from Reminder*, *Downtime was for Failure*, *Downtime was for
  Service*, *TyreChange fitted TyreSet* and *TyreChange removed TyreSet*
  (join subsets, through each one's asset);
- *Service repaired Failure* only where the failure concerns the
  service's asset: of it, or of an asset fitted in it then (a join subset
  through *Record concerns Asset*);
- *Event was by User* and *Record was entered by User* only for a user
  who uses the record's asset; *Service is assigned to User* the same (a
  join subset through *User uses Asset*);
- *Inspection went through Checklist* only for a checklist kept by the
  asset's owner;
- an inspection's answers only to questions of its checklist, and an
  answer's chosen options only of its question (join subsets);
- *Answer says YesNo* only for a question answered 'Yes or no', *Answer
  chose Option* only for one answered 'Any of', *Answer measured Quantity*
  only for a 'Measurement'; *Option is in Question* only for 'Any of'
  questions, a question's limits only for a 'Measurement';
- *FillUp is of Asset* only for a FuelledAsset; *Trip*, *TyreSet*,
  *TyreChange* only of a Vehicle;
- *Failure was of StockUnit* only for a unit fitted in the failure's
  asset then, or the asset's own unit.

**Exclusion** (not both):
- a tyre change doesn't fit and remove the same set (a set already on
  isn't fitted again);
- a reminder is not both done and cancelled;
- a reminder comes from a schedule, or is for a task, a kind of expense
  or a checklist of its own: exactly one (step 5's exclusive-or; a
  schedule's the same, over its three);
- *Asset is shared with User* and *Asset is owned by User*: the owner
  isn't shared with (step 5, derivation 3);
- *Labour was by User* and *Labour was by Garage*: exactly one;
- an asset's class is a vehicle kind only for a vehicle: *Asset is of
  EquipmentClass* names no VehicleKind, and a vehicle says *Vehicle is of
  VehicleKind* instead;
- *Asset is of Make* and *Asset is of Model*, as entered, and *Asset is
  StockUnit*: a unit asset's are derived;
- *Document covers StockUnit* only for a unit that is no asset;
- *WorkRequest was turned down on Date* and *Service was raised from
  WorkRequest*: a request is turned down or ordered, not both.

### For ORMKit

- **Subtypes defined by a rule** (Cost, AssetSale, FuelledAsset,
  ComponentAsset, DoneService, the kinds): each is run by a derivation
  query of the subtype, as a fact type's is
  ([DERIVATION.md](https://github.com/ashalkhakov/ORMKit/blob/master/docs/DERIVATION.md#subtypes)).
- **An asserted subtype with a supertype that is not a record** (Vehicle
  under Asset) is mapped as Record's are: a Core Data subentity, one
  table, its own OData type deriving from its supertype's.
- **Patterns** (a currency code, a VIN) are not value constraints NORMA
  has; they're a data type's facet. They can be checked by code generated
  from a constraint written as a rule.
- **Value ranges per role** on a shared value type, and **join subsets**,
  NORMA has, and ORMKit with it.

## Step 7: other constraints, and the final checks

### Ring constraints

A ring constraint is on two roles played by the same type. Logbook has
few such fact types; these need one:
- **On Date one Currency was worth Factor Currency:** irreflexive over
  the two currencies. A currency isn't worth anything in itself.
- **Reminder replaces Reminder:** acyclic, so irreflexive too. A reminder
  replaces at most one, and is replaced by at most one.
- **Asset is fitted in Asset:** acyclic, so irreflexive too. No asset is
  fitted in itself, nor in what is fitted in it. A component change that
  would make it so is refused.
- **ComponentChange fitted StockUnit into StockUnit:** irreflexive: a
  unit doesn't go into itself.

### Value comparisons

A value comparison constraint compares two values of one instance.

| Instance | Constraint |
| --- | --- |
| Trip | it ended at or after the moment it started; at or beyond the usage it started |
| Document | it expires after it's valid from |
| Asset | sold (its AssetSale's moment) or disposed of on or after it was acquired |
| TyreSet | bought on or before the first change that fitted it |
| Reminder | done on or after the moment it was set (its record's moment) |
| Downtime | it ended at or after it started |
| Question | its lower limit below its upper |
| Service | planned for a date on or after the moment of the request it was raised from |
| Failure | at or before the moment of each service that repaired it |

### Frequency constraints

- **A schedule has at most one reminder open,** neither done nor
  cancelled. The next is made only when one is done (or cancelled). That's
  a uniqueness on a subtype: *each OpenReminder is a Reminder that was
  neither done nor cancelled*, and *OpenReminder comes from Schedule* is
  unique on the schedule's side; written as a rule (`OneOpenReminder`). An
  asset may have several open, of its schedules and one-offs. Two
  devices offline making a schedule's next both: the server refuses the
  second, and the sync settles it.
- **An asset has at most one downtime not ended:** it is down or it
  isn't.
- **A checklist an inspection went through has at least one question.**

### Deontic constraints: what ought to be, not what must

An alethic constraint can't be broken: the app refuses what breaks it. A
deontic one ought not to be, and the app warns, then keeps what was
entered. The users said records may be entered freely and history edited
afterwards, so the rules about the meter and time are deontic:

- **The meter only goes up.** An asset's metered events, in order of
  their moments, ought to have usages that don't go down. The form shows
  the last reading beside the meter, and warns when the new one is lower.
- **Events fall while the asset is kept:** on or after it was acquired,
  at or beyond the usage it was acquired at, and not after it was sold or
  disposed of.
- **A fill-up's fuel ought to be one the asset uses.** Not a must:
  Drivvo's logs show premium and regular petrol in one car. "Asset uses
  Fuel" is the form's default.
- **A document ought not to be expired** while its asset is kept: that's
  what a reminder is for, and the app shows it as one.
- **A corrective service ought to say the failure it repaired,** and a
  failure ought to say its downtime, where it stopped the asset
  ('Critical').
- **A work request ought to be answered,** ordered or turned down, within
  a week; a work order ought to be done by its planned date.
- **A critical asset ought to have a schedule:** preventive work planned
  for it, as ISO 55001's risk-based planning asks.

Trips may overlap and leave gaps (step 1): no constraint at all.

### Final check 1: the examples against the constraints

Every example from step 1, as a population, against every constraint.
One broke one: Inspection 50, on 2026-08-28, said 153,200 km, but the
meter reading of 2026-10-01 says 153,120 km. Only a deontic constraint,
but the example was wrong; it is now 151,600 km. The rest hold:

```
2024-04-10        0 h    generator a1 acquired
2025-10-20               tyre set ts1 bought
2025-11-02   141500 km   tyre change c3 fits ts1
2025-12-01               insurance d1 valid (to 2026-12-01)
2026-04-05   146900 km   tyre change c4 fits ts2, removes ts1
2026-05-02               lawnmower a5 disposed of
2026-06-01   148000 km   service s7, done, preventive; downtime d68, planned; schedule sc1 counts from it
2026-08-03               expense e12 (no usage)
2026-08-28   151600 km   inspection in50; option o1 calls for a lamp replacement
2026-09-14   152300 km   fill-up f1
2026-09-20   152410 km → 152700 km   trip t3
2026-10-01   153120 km   meter reading r21
2026-10-02   153300 km → 153314 km   trip t9; income n30 for it
2026-11-01               inspection in70 of a3: 76 %, below 80: request wr71
2026-11-15      212 h    meter reading r40
2026-11-20      212 h    failure f63; downtime d64 starts; request wr60
2026-11-22      214 h    service s61 done, corrective, repairs f63; d64 ends
2027-05-20   162400 km   reminder m5 done by s12 (due 163000 km, 2027-06-01)
2027-08-30   171020 km   sale n41
```

The battery a4 is fitted in the power station a3 (cc50): the hierarchy is
acyclic, and a4's documents concern a3 as well. The chain u1 is no asset;
its warranty covers the unit.

### Final check 2: nothing stored that can be derived

Each derivable fact is derived, unless kept for a reason:
- **Which set a tyre change removed** was stored; it's the set fitted by
  the change before. It's now derived (step 5, derivation 11), and can no
  longer disagree with the changes.
- **A service's kind of cost** was stored; it follows from its
  maintenance type now (step 5, derivation 1), and can't disagree with it.
- **A unit asset's make, model and serial** are its unit's, never
  entered again (derivation 14).
- **What is fitted in what, what a record concerns, an asset's state:**
  derived from component changes, downtime, sales and disposals.
- **A reminder's asset,** for one from a schedule, is the schedule's.
  *Partly derived*: stored for a reminder of its own, derived for one
  from a schedule. The join subset of step 6 then always holds.
- **A schedule's next reminder, its due usage and date,** and **a work
  order raised from a reminder or a request from an answer:** entered, by
  the app's service layer, and the owner may change them afterwards (step
  2). That's a process, not a derivation ([PROCESSES.md](PROCESSES.md));
  `ReminderNextDue` says when by date.
- **The reverse exchange rate:** *derived and stored*, so reports read
  both directions alike (step 5).
- **A service's cost, an asset's sale, a record's kind of cost, who uses
  an asset, every indicator:** derived, not stored.

### Final check 3: every report from the facts

Each report of step 1 against the derivations of step 3:

| Report | From |
| --- | --- |
| Balance, every view | costs, incomes, the purchase, expectations, valuations, the sale, rates |
| Usage, readings | metered events' moments and usages |
| Costs, by kind, by month, by task | costs with their dates and kinds; service items and labour, with the discount spread |
| Incomes, by kind | incomes |
| Fuel consumption, its lowest, highest and latest, by fuel | fill-ups in order of moments, full or not, per the meter's unit |
| Each month against the one before | the same, grouped by month |
| Reminders due, how far and how long | reminders, the latest reading, today |
| Inspections | answers, questions in order |
| Indicators | services done, their types and labour; failures; downtime; reminders due and done; readings; what is fitted in what |
| Failures | failures, their codes, downtime and repairs |

Inputs found missing on the way, and now there: a moment for every event
(the cross-check with Drivvo), a date for a tyre set's price (step 6), a
start and an end for every downtime (availability needs both), and a
service's maintenance type (the preventive share and MTBF need it).

### Final check 4: every fact type can be populated

The constraints together allow a population of every fact type: step 1's
examples are one. The exclusive-ors (what a reminder is for; yes or no,
chosen options or a quantity; labour by a user or a garage; a class or a
vehicle kind) each leave every role a case of its own, and every subtype
a member (Vehicle: v1; MeteredEvent: a fill-up; DoneService: s61, while
planned it is none; Cost: a fill-up; AssetSale: n41; FuelledAsset: a1;
ComponentAsset: a3; OpenReminder: m6).

### For ORMKit

- **Value comparisons and deontic constraints** ORMKit already has: the
  Core Data validation it generates checks value comparisons, and marks
  each rule from a deontic constraint as such, for the app to warn rather
  than refuse.
- **Ordering by moment** ("the change before", "the readings in order")
  is the step 3 gap again, now in constraints too; and so is the
  transitive closure for an acyclic ring over a derived fact type.

## The model

The model is [`Model/Logbook.orm`](../Model/Logbook.orm), and nothing
else is: every fact type, constraint, subtype, derivation and query above,
the Core Data mapping (its settings and names), and a diagram for each
part of the schema. It is ORMKit's model saved as NORMA's file, so NORMA
opens it as well; the comments of the listing below are the notes of the
elements they come before, NORMA's own Notes (a query's in ORMKit's
namespace).

Change it in ORMDesigner, or by applying lines of FORML to it:

```sh
ormtool apply Model/Logbook.orm changes.forml
```

Each line is a statement as the listing says it, and is applied as one
change: what the model lacks is made (on the diagram of a `# heading`
above it, else of what it names), what it says already is left as it is,
a `// comment` just before a line becomes the note of what that line says,
and a line starting `- ` takes away what it says: `- Car has VIN` a fact
type, `- Each Vehicle has at most one VIN.` a constraint, `- ++ ...` a
fact type's derivation, `- Reference data: km, 1` a fact, `- // ...` a
note, `- Query Name:` a query. A query given again under its name, its
outline after it, replaces the one the model has. Lines are compared with
the listing's, so copy them from it. The file is written only when every
line was read.

What the build generates from it, into `build/Model` (`obj/Model` on
GNUstep), and never keeps in git: the Core Data model
(`Logbook.xcdatamodeld`), the code and tables that keep the constraints
and work out the stored derivations (`Constraints/LogbookValidation.h`,
`.m` and `Logbook.ormplans`), and the listing, `Logbook.forml`: every
statement of the model, a line each as ORMKit's verbalizer says it, part
by part as the diagrams have them, each element's note as a comment before
it, each query as its outline.

```sh
ormtool forml Model/Logbook.orm                # the listing
ormtool coredata Model/Logbook.orm Out.xcdatamodeld Logbook --validation Out/
```

`ormtool build schema.txt model.orm` makes a new model from such text: it
is how `Logbook.orm` began, not how it changes.

**Names in the store.** The model's names changed (Vehicle's facts are
Asset's, a distance read off a meter is a usage), the store's did not:
the Core Data attributes and the OData properties keep the role names
they had (`distanceQuantity`, `keepDistanceQuantity`, `driver`), so a
store kept on a device and the server's database migrate by Core Data's
lightweight migration, Asset added as Vehicle's parent entity, and the
sync carries what it carried. New attributes are named after their new
roles.

Currency codes and VINs have patterns, ORMKit's own (NORMA has none):
Core Data checks them.

What each unit is worth in its dimension's base is reference data: facts
of the app's own, which every store starts with (`LogbookReferenceData`
seeds them), not the user's. A usage, a distance or a volume converts by
a step to its unit's factor and a product. So are the kinds of cost the
model names, by their names alone ("Reference data: Maintenance" after
CostKind): 'Maintenance' and 'Repair', what ServiceKind is by definition,
and 'Fuel', 'Tyres' and 'Documents', what a fill-up, a tyre set and a
document are of ("Cost is of CostKind", derived, and mandatory for every
cost). Being there from the start, no user's kind of expense takes one of
their names; users add kinds of expense of their own. The fixed lists of
step 6 are reference data the same way, and so are the classes, failure
modes, mechanisms and detection methods a new logbook starts with.

What no graphical constraint says is a rule, a query whose answers are
what must not be ([RULES.md](https://github.com/ashalkhakov/ORMKit/blob/master/docs/RULES.md)), written
in the schema as its outline:
- a schedule has at most one reminder open, neither done nor cancelled
  (`OneOpenReminder`); an asset at most one downtime not ended;
- a reminder done by an event was done at its moment, and at its usage
  where it has one (`ReminderDoneAtItsEventsMoment`,
  `ReminderDoneAtItsEventsMileage`);
- an answer's options are its question's; yes or no only for a yes-or-no
  question, options only for an any-of one, a quantity only for a
  measurement (`AnswerOptionsOfItsQuestion`, `YesOrNoAnswers`,
  `AnyOfAnswers`, `OptionsOfAnyOfQuestions`);
- a service is at a moment and a usage, and does a reminder's work or
  repairs a failure, only once done;
- what is fitted in what has no cycle;
- an asset's readings are in its meter's dimension;
- the meter goes up: an asset's later reading, in its dimension's base
  whatever its unit, ought not to be lower (`MeterGoesUp`, deontic);
- a trip ends no nearer than it started, in kilometres whatever its units
  (`TripEndsNoNearer`);
- events fall while the asset is kept, on or after the day it was
  acquired and on or before the day it was sold or disposed of
  (`EventsWhileKept`, `EventsBeforeSale`, deontic);
- a tyre set is bought no later than the day it is fitted
  (`TyresBoughtBeforeFitted`);
- the deontic rules of maintenance: a corrective service names its
  failure, a request is answered within a week, a critical asset has a
  schedule.

Some of what is worked out is computed by queries, with value nodes
([EXPRESSIONS.md](https://github.com/ashalkhakov/ORMKit/blob/master/docs/EXPRESSIONS.md)): a trip's
length in its user's unit (`TripLength`), and a fill-up's price per
unit of volume (`PricePerVolume`), in the units its record is in. "The one before"
is an aggregate value, the latest earlier, that another node is compared
with: the fill-up before each (`FillUpBefore`), and the consumption at
each full tank, the fuel put in since the full tank before over the
usage since (`FullTankConsumption`). Dates are computed too: how long
a trip lasted, a fact type derived by a query with a value node ("Trip
lasted Minutes", `TripLasted`; `TripDuration` lists it), and when a done reminder's
schedule is next due by date (`ReminderNextDue`); which open reminders
are overdue, by date (`OverdueReminders`, against `today()`) or by the
asset's latest usage (`OverdueByMileage`), and which were closed late,
done or cancelled after their date (`LateReminders`) or done past their
usage (`DoneLateByMileage`). The report by month is a grouped list: each
asset's costs for each month in its owner's currency, each cost at the
latest exchange rate on or before its day, the latest month first
(`CostsByMonth`). The indicators are grouped lists the same way, per
asset, per class and per maintainable item, over a period.

A service's cost is worked out from its items and labour, less its
discount, in its currency (`ServiceCost`): "Record cost Money" is partly
derived and stored, so the generated code sets a service's cost at save,
and any other record keeps the cost entered for it.

An asset's one sale is kept by its derived sale date, unique for the
asset: the date of its sale's moment (`SaleDate`, derived and stored),
and what the sale earned (`SellingPrice`). The tyre set a change removed
is the one the vehicle's change before it fitted (`RemovedSet`, the one
before, derived and stored), so that no change fitting and removing the
same set is checked on it. A partly derived fact type is stored as well
(a record's cost). A record's asset is entered: a reminder from a
schedule is of the schedule's asset because the service layer records it
so ([PROCESSES.md](PROCESSES.md)), and a rule checks it. Who uses an asset
is partly derived and not stored: the users it is shared with are
entered, and its owner uses it by a rule (`OwnerDrives`), which queries
and the rules about users go through beside what is entered. Every
constraint is checked by the generated code, and so is every absorbed
value that may be left out: a usage or an amount of money, absorbed into
what has it, is whole or none, so a reading's quantity is not saved
without its unit, nor the unit without it.

The subtypes defined by a rule keep it as NORMA keeps a subtype's
derivation rule, and run it as a query: a Cost is a record that cost
some money (`CostRule`), a MeteredEvent an event at some usage
(`MeteredEventRule`), a DoneService a service done or closed, a
FuelledAsset an asset that uses a fuel, a ComponentAsset an asset that is
a unit, an AssetSale an income of kind 'Sale' (`CarSaleRule`), a
ServiceKind a cost kind that is 'Maintenance' or 'Repair'
(`ServiceKindRule`, one of a list). A derived subtype is no entity of its
own in Core Data: its fact types are its supertype's, so every record has
what a cost is charged, whichever entity it is. A subtype asserted of one
(a FillUp is a Cost and a MeteredEvent) is checked to be one by its rule.
Vehicle, asserted, is an entity of its own under Asset.

## Next

The Core Data model, the OData service and the checks are generated from
the model, and the apps written around them. For the maintenance part,
in this order: assets, usage and units that are assets; fuel and the
hierarchy; classes, states and criticality; failures, downtime and
labour; work orders and their process; condition-based work and
warranties; the indicators.
