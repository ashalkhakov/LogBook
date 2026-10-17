# Logbook's model, by CSDP

Halpin's Conceptual Schema Design Procedure, step by step. The ORM model it
ends with is `Model/Logbook.orm`. Everything else is derived from it: the Core
Data model, the OData service, the sync, and the code that checks the
constraints.

## Scope

- **Vehicles:** one person's cars, diesel and petrol only (no electric or
  hybrid for now). The owner is the signed-in user and a driver too. Other
  drivers may drive a car, and then keep its data as the owner does.
  Everything syncs between devices and people, as SimpleNotes does.
- **What it records:**
  - meter readings;
  - trips;
  - fill-ups;
  - services and the tasks in them, each with its own cost;
  - tyre sets;
  - documents;
  - other costs: parking, tolls, washes;
  - incomes: paid rides, freight, refunds, the car's sale;
  - inspections: going through a checklist the users write, item by item;
  - schedules of work the users plan, and the reminders they mark done.
- **Every record of an event** says when it happened, to the minute, and
  who was driving. It may carry a note and attached files.
- **Reports** per vehicle, and per kind of event.
- **Units** (distance, volume) are set for the app. Amounts may be entered
  in any currency and are reported in the preferred one.

## Step 1: examples as elementary facts

The things Logbook records, each given as an example and then as the
elementary facts it holds. Still a draft.

### A vehicle

> Our blue Golf is a 2014 Volkswagen Golf 1.4 TSI, VIN WVWZZZ1KZEW000001,
> registration 123 ABC. We bought it on 2019-05-02 for 9,500 EUR with
> 84,210 km on it.

- Vehicle 'Blue Golf' is of Make 'Volkswagen'.
- Vehicle 'Blue Golf' is of Model 'Golf 1.4 TSI'.
- Vehicle 'Blue Golf' was built in Year 2014.
- Vehicle 'Blue Golf' uses Fuel 'Petrol 95'.
- Vehicle 'Blue Golf' has VIN 'WVWZZZ1KZEW000001'.
- Vehicle 'Blue Golf' has Registration '123 ABC'.
- Vehicle 'Blue Golf' was acquired on Date 2019-05-02.
- Vehicle 'Blue Golf' was acquired at Distance 84210.
- Vehicle 'Blue Golf' was acquired for Money 9500 EUR.

> We expect to keep it 8 years, or another 120,000 km, and to sell it for
> 2,500 EUR. An online valuation said 4,000 EUR on 2026-10-01. *(Later:)*
> Sold on 2027-08-30 for 3,000 EUR.

- Vehicle 'Blue Golf' is expected to be kept for Period 8 years.
- Vehicle 'Blue Golf' is expected to be kept for Distance 120000 more.
- Vehicle 'Blue Golf' is expected to sell for Money 2500 EUR.
- Vehicle 'Blue Golf' was valued at Money 4000 EUR on Date 2026-10-01.
- Vehicle 'Blue Golf' was sold on Date 2027-08-30.
- Vehicle 'Blue Golf' was sold for Money 3000 EUR.

All of these are optional. They're what the balance's views need (see
Reports): the expectations for depreciation by time or by distance, the
valuations for what it's worth now, and the sale for every view.

The sale is recorded as an income of kind 'Car sale' (see Incomes); that
the vehicle was sold, when and for how much, is worked out from it.

### Owner and drivers

> Anna owns the Golf and signs in as anna@example.org. Ben drives it too,
> and keeps its log as Anna does.

- Vehicle 'Blue Golf' is owned by User 'anna@example.org'.
- User 'anna@example.org' has Name 'Anna'.
- User 'ben@example.org' drives Vehicle 'Blue Golf'.

A driver is a user, signed in, with whom the owner shares the vehicle. The
owner drives it too, and whoever drives it can keep all of its data. Who
drove, who filled up and who paid are users. A driver sees the vehicles
shared with them, and may add vehicles of their own, which they then own.
The owner may stop sharing.

> Ben adds his own van; he owns it, and shares it with nobody.

- Vehicle 'Ben's van' is owned by User 'ben@example.org'.

### A meter reading

> On 2026-10-01 at 07:45 Anna read the Golf's odometer: 153,120 km.

- MeterReading 21 is of Vehicle 'Blue Golf'.
- MeterReading 21 was at Moment 2026-10-01 07:45.
- MeterReading 21 shows Distance 153120.
- MeterReading 21 had driver User 'anna@example.org'.

Every event below that happens at a distance (fill-up, service, trip,
income) also gives a reading of the meter. Whether that makes them meter
readings too, or just events with a distance, is for step 6 (subtypes).

### What every event has

Each event (meter reading, trip, fill-up, service, tyre change, expense,
income, inspection) happened at a moment, a date and a time of day: two fill-ups on one
day must come in order, or the consumption between them is wrong. Each
says who was driving, and may carry a note and any number of attached
files (a receipt, a photo):

- FillUp 1 has Note 'Price was up 10 cents'.
- Attachment 'receipt-0914.jpg' is of FillUp 1.

The driver is who drove the car then: not always who entered the record,
nor who paid.

### A trip

> On 2026-09-20 Anna drove the Golf from Berlin to Hamburg on business,
> 152,410 km to 152,700 km, starting at 08:10 and arriving at 11:25.

- Trip 3 is of Vehicle 'Blue Golf'.
- Trip 3 was on Date 2026-09-20.
- Trip 3 started at Distance 152410.
- Trip 3 ended at Distance 152700.
- Trip 3 started at Time 08:10.
- Trip 3 ended at Time 11:25.
- Trip 3 went from Place 'Berlin'.
- Trip 3 went to Place 'Hamburg'.
- Trip 3 has Purpose 'Business'.
- Trip 3 had driver User 'anna@example.org'.

How far and how long it took are derived: 290 km, 3 h 15 min.

Trips are recorded freely: they need not agree with the meter, nor with
each other (gaps and overlaps are allowed). The owner may change what was
recorded before; whether drivers may too, or only add, is a permission,
not a fact (see below).

### A fill-up

> On 2026-09-14 at 17:20, at 152,300 km, 42.5 L of petrol for 74.10 EUR, at
> Shell on Main St. Filled to the brim. Ben was driving.

- FillUp 1 is of Vehicle 'Blue Golf'.
- FillUp 1 was at Moment 2026-09-14 17:20.
- FillUp 1 was at Distance 152300.
- FillUp 1 was of Volume 42.5.
- FillUp 1 was of Fuel 'Petrol 95'.
- FillUp 1 cost Money 74.10 EUR.
- FillUp 1 was at Station 'Shell, Main St'.
- FillUp 1 filled the tank. *(unary)*
- FillUp 1 had driver User 'ben@example.org'.

The price per litre (1.744 EUR/L) is worked out from the cost and the
volume. The form takes any two of price, cost and volume and fills in the
third, as a pump shows them; what's kept is the cost and the volume, as on
the receipt.

### A service

> On 2026-06-01 at 09:30, at 148,000 km, Anna took the Golf for its annual
> service at Garage Müller: oil and filter changed (95 EUR), brake fluid
> replaced (60 EUR), labour 165 EUR. The filter was a Mann W 712/95. The
> garage took 20 EUR off, and she paid by card, in 2 instalments.

- Service 7 is of Vehicle 'Blue Golf'.
- Service 7 was at Moment 2026-06-01 09:30.
- Service 7 was at Distance 148000.
- Service 7 has Title 'Annual service'.
- Service 7 was done by Garage 'Garage Müller'.
- Service 7 had driver User 'anna@example.org'.
- Service 7 included Task 'Oil change' for Money 95 EUR.
- Service 7 included Task 'Brake fluid change' for Money 60 EUR.
- Service 7 included Task 'Labour' for Money 165 EUR.
- In Service 7, Task 'Oil change' has Note 'Filter: Mann W 712/95'.
- Service 7 is of ServiceKind 'Maintenance'.
- Service 7 had a discount of Money 20 EUR.
- Service 7 was paid by PaymentMethod 'Card'.
- Service 7 was paid in Instalments 2.

Each task in a service has its own cost. The service's cost is their sum
less the discount (300 EUR), so it's derived, not stored. "Service
included Task for Money" is a ternary; step 4 checks that it is
elementary. Parts are only noted on tasks, not kept as a catalogue. The
tasks are a list the users keep (battery, air filter, tyre balancing,
labour, ...), and so are the payment methods. A service paid at once is
paid in one instalment.

A repair is a service too, with tasks, of ServiceKind 'Repair'. Reports
count maintenance and repairs as kinds of cost each.

> The Golf's windscreen was replaced at Carglass on 2026-07-12, 410 EUR.

- Service 8 is of ServiceKind 'Repair'.
- Service 8 included Task 'Windscreen replacement' for Money 410 EUR.

### Tyres

> Our winter set, Continental WinterContact TS 870, 205/55 R16, went on the
> Golf on 2025-11-02 at 141,500 km with 8 mm of tread, and came off on
> 2026-04-05 at 146,900 km. The summer set went on the same day.

- TyreSet 'Golf winter' is of Season 'Winter'.
- TyreSet 'Golf winter' is of TyreModel 'Continental WinterContact TS 870'.
- TyreSet 'Golf winter' is of Size '205/55 R16'.
- TyreSet 'Golf winter' was bought for Money 480 EUR.
- TyreChange 4 fitted TyreSet 'Golf summer' on Vehicle 'Blue Golf'.
- TyreChange 4 removed TyreSet 'Golf winter'.
- TyreChange 4 was at Moment 2026-04-05 10:00.
- TyreChange 4 was at Distance 146900.
- TyreChange 4 had driver User 'anna@example.org'.
- TyreSet 'Golf winter' had Tread 8 mm at TyreChange 3. *(when fitted)*

From the tyre changes, the app works out which set is on the car, and how
far each set has been driven.

### A document

> The Golf is insured by Allianz, policy 77-123456, from 2025-12-01 to
> 2026-12-01, for 610 EUR. The roadworthiness test (TÜV) runs until
> 2027-03. Here is the scanned policy.

- Document 'Allianz 77-123456' is of Vehicle 'Blue Golf'.
- Document 'Allianz 77-123456' is of DocumentKind 'Insurance'.
- Document 'Allianz 77-123456' is valid from Date 2025-12-01.
- Document 'Allianz 77-123456' expires on Date 2026-12-01.
- Document 'Allianz 77-123456' cost Money 610 EUR.
- Document 'Allianz 77-123456' has Attachment 'policy.pdf'.

### Other costs

> Anna parked at the airport, 2026-08-03 06:15, 36 EUR. Toll on the A2,
> 12.50 EUR. A car wash, 9 EUR.

- Expense 12 is of Vehicle 'Blue Golf'.
- Expense 12 was at Moment 2026-08-03 06:15.
- Expense 12 is of ExpenseKind 'Parking'.
- Expense 12 cost Money 36 EUR.
- Expense 12 had driver User 'anna@example.org'.
- Expense 12 has Note 'Airport'.

### Incomes

> As a taxi driver would: at the end of a ride, 2026-10-02 19:05, at
> 153,314 km, Ben was paid 23.50 EUR through a ride-hailing app.

- Income 30 is of Vehicle 'Blue Golf'.
- Income 30 was at Moment 2026-10-02 19:05.
- Income 30 was at Distance 153314.
- Income 30 is of IncomeKind 'Transport app'.
- Income 30 earned Money 23.50 EUR.
- Income 30 had driver User 'ben@example.org'.

> The ride itself, 18:40 to 19:05, 153,300 km to 153,314 km, was logged as
> a trip.

- Income 30 was for Trip 9.

> The Golf was sold on 2027-08-30 at 171,020 km for 3,000 EUR, paid in 3
> instalments.

- Income 41 is of IncomeKind 'Car sale'.
- Income 41 earned Money 3000 EUR.
- Income 41 was paid in Instalments 3.

An income is a record of its own, of a kind from a list the users keep:
'Transport app', 'Trip', 'Freight', 'Refund', 'Car sale', and their own.
It may name the trip it was for; a trip needn't be paid. A paid trip
needn't name its places, but it does say how long it took and how far it
went.

### Checklists and inspections

> Anna's checklist "Before a long trip": tyre pressure, lights, oil level,
> wipers and washer fluid, spare wheel. On 2026-10-10 at 08:00, at
> 153,200 km, she went through it on the Golf: all fine but the washer
> fluid, which was low.

- Checklist 'Before a long trip' is kept by User 'anna@example.org'.
- ChecklistItem 'Tyre pressure' is in Checklist 'Before a long trip' at
  Position 1.
- ChecklistItem 'Washer fluid' is in Checklist 'Before a long trip' at
  Position 4.
- Inspection 50 is of Vehicle 'Blue Golf'.
- Inspection 50 went through Checklist 'Before a long trip'.
- Inspection 50 was at Moment 2026-10-10 08:00.
- Inspection 50 was at Distance 153200.
- Inspection 50 had driver User 'anna@example.org'.
- In Inspection 50, ChecklistItem 'Tyre pressure' was found Result 'OK'.
- In Inspection 50, ChecklistItem 'Washer fluid' was found Result 'Not OK'.
- In Inspection 50, ChecklistItem 'Washer fluid' has Note 'Low, topped
  up'.

A **checklist** is a list of things to check, in order, that a user
writes once and uses on any of their vehicles: before a long trip, when
handing the car to another driver, a monthly look round. Drivers use the
checklists of the vehicle's owner. An **inspection** is one going
through it, on one vehicle, at a moment: an event like the others. Each
item is found 'OK' or 'Not OK', and may have a note (and the inspection
photos, as attachments). An item left unchecked has no result.

A checklist can be planned work too:

> Go through "Monthly look round" every month.

- Schedule 'Monthly' is for Checklist 'Monthly look round'.

and an inspection through it does that work.

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

Distances and volumes are stored in one unit and shown in the app's. Which
unit they're stored in is for later.

### Schedules and reminders

> Change the oil every 15,000 km or every 12 months, whichever comes first,
> counting from the last change (148,000 km, 2026-06-01). And once: put the
> winter tyres on by 2026-11-15.

> Change the oil every 15,000 km or every 12 months, whichever comes first,
> counting from the last change. Renew the parking permit every year. And
> once: have the air conditioning checked by 2027-05-01.

- Schedule 'Oil' is of Vehicle 'Blue Golf'.
- Schedule 'Oil' is for Task 'Oil change'.
- Schedule 'Oil' recurs every Distance 15000 km.
- Schedule 'Oil' recurs every Duration 12 months.
- Schedule 'Permit' is for ExpenseKind 'Parking'.
- Schedule 'Permit' has Note 'Residents' permit, zone 4'.
- Schedule 'Permit' recurs every Duration 12 months.
- Reminder 5 comes from Schedule 'Oil'.
- Reminder 5 is due at Distance 163000 km.
- Reminder 5 is due on Date 2027-06-01.
- Reminder 6 is of Vehicle 'Blue Golf'.
- Reminder 6 is for Task 'Air conditioning'.
- Reminder 6 has Note 'It smells musty'.
- Reminder 6 is due on Date 2027-05-01.

> The oil was changed at Garage Müller on 2027-05-20 at 162,400 km.

- Reminder 5 was done at Moment 2027-05-20 11:00.
- Reminder 5 was done at Distance 162400 km.
- Reminder 5 was done by Service 12.

A **schedule** is planned work: which work, and how often, by distance,
by time, or both, whichever comes first. The work is a task (what a
service does), a kind of expense (what an expense pays for) or a
checklist (what an inspection goes through). It is never done itself.

A **reminder** is one time the work is due. The work it's for is its
schedule's, or, set once by hand with no schedule, its own. It is done by
the first record of that work after it was set: a service that includes
the task, an expense of that kind, or an inspection through the
checklist. Saving such a record marks the
reminder done, with the record's moment and distance, and links it to the
record; the owner may also mark one done by hand, with no record. A
schedule's reminders come one after another: when one is done, the next
is due its intervals after when and where it was done. Users write their
own schedules and reminders, per vehicle; there's no manufacturer's
catalogue for now.

### Reports

Reports are information outputs too: each says derived facts. Per vehicle,
over a period:

1. **Balance:** incomes minus costs; per day; in the preferred currency
   per distance unit. Every view is offered, for the user to choose:
   - **cash:** the purchase and the sale counted on the days they were
     paid;
   - **running:** the purchase and the sale left out;
   - **depreciation over time:** the expected loss of value (purchase minus
     expected sale) spread over the expected years, a cost each day; the
     sale's difference from the value left is a gain or loss on its day;
   - **depreciation by distance:** the same, spread over the expected
     distance, a cost each distance unit driven;
   - **what it's worth:** the loss of value between valuations (the
     purchase, each valuation, the sale).

   A view whose inputs are missing isn't offered.
2. **Distance driven:** total, and average per day.
3. **Costs:** total, average per day, per distance unit.
4. **Incomes:** total, average per day, per distance unit; by kind of
   income.
5. **Costs and incomes over time:** a bar chart by month, each bar split by
   kind of record (fill-ups, services, expenses, ...).
6. **Costs by kind:** pie chart (fill-ups, services, tyres, documents,
   parking, tolls, washes, ...).
7. **Costs by month:** bar chart.
8. **Fuel consumption:** per full tank over time (a chart), and the
   average over the period, in L/100 km, km/L or mpg; fuel cost per
   distance. For each, the latest, the lowest and the highest beside the
   average. All fuels together, or one fuel. The volume and the cost of
   fuel over the period.
9. **Mileage:** the meter's reading over time, a chart with a point for
   each record, marked by its kind.
10. **Service costs by task:** pie chart (new tyres, labour, battery,
    diagnostics, ...).
11. **Each month in the history:** its costs, distance driven and fuel
    consumption, and how its consumption compares with the month before's
    (5% lower than June).
12. **Each fill-up in the history:** its consumption since the full
    fill-up before.
13. **Each inspection in the history:** how many of its items were found
    'Not OK', and which.

There are the same reports per kind of event (fill-ups, services,
expenses, incomes, trips, meter readings, inspections), as tabs.

As facts, for example:
- Vehicle 'Blue Golf' cost Money 1234 USD in Period 2026-09.
- Vehicle 'Blue Golf' was driven Distance 1820 in Period 2026-09.
- Vehicle 'Blue Golf' cost Money 0.21 USD per distance unit in Period
  2026-09.
- Costs of Kind 'Fuel' for Vehicle 'Blue Golf' were Money 410 USD in Period
  2026-09.

Every one is derived, from events' amounts, dates and distances, and from
rates. Distance driven is the meter's difference over the period, from the
readings every event gives. These become ORMKit derivation queries.

## Permissions

These are not facts about cars. They're rules about who may change what,
for the service and the apps to enforce:

- The owner may change anything about their vehicles, including what was
  recorded before.
- A driver may add records of their own to a vehicle shared with them,
  and may not change or remove any record.

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
- Vehicle, Trip, FillUp, Service, ServiceItem, MeterReading, TyreSet,
  TyreChange, Document, Expense, Income, Schedule, Reminder, Attachment,
  Checklist, ChecklistItem, Inspection, Check.

The rest are identified by what they are:

| Entity type | Identified by |
| --- | --- |
| User | email |
| Make, CarModel, Fuel, Garage, Station, Place, TyreModel | name |
| ServiceKind, ExpenseKind, IncomeKind, DocumentKind, Purpose, Season, Task, PaymentMethod | name, from a list |
| Title, Note, ChecklistName, ItemText | text |
| Result | name, from a fixed list: 'OK', 'Not OK' |
| Position | a count, 1 or more |
| Instalments | a count, 1 or more |
| Currency | ISO code ('EUR', 'USD') |
| DistanceUnit | code, from a list: 'km', 'mi' |
| VolumeUnit | code, from a list: 'L', 'gal (US)', 'gal (imp)' |
| Duration | months |
| Tread | mm |
| Money | its Amount and its Currency together (74.10 EUR) |
| Distance | its Quantity and its DistanceUnit together (152300 km) |
| Volume | its Quantity and its VolumeUnit together (42.5 L) |

Money, distances and volumes have no identity of their own. Two fill-ups
costing 74.10 EUR cost the same money, and two trips of 14 km went as far.
Each is kept as it was entered, in its own unit or currency. The Core Data
mapping absorbs each into whatever has it, as a quantity and a unit.

The app shows each in the user's preferred unit or currency, converting as
it goes:
- **money:** by exchange rates, which change and are kept by date (below);
- **distances and volumes:** by fixed factors (1 mi = 1.609344 km,
  1 gal (US) = 3.785411784 L, 1 gal (imp) = 4.54609 L). These are part of
  the model, not data anyone enters.

So a US car's odometer can be read in miles, and its fill-ups in gallons,
while the user sees km and L, or the other way round.

Moments (a date with a time of day, to the minute) and dates are values.
Events happen at moments; what is only ever a day (when a document is
valid, when a reminder is due, a valuation) is a date.

### People and vehicles

```
Vehicle is owned by User                        v1 | anna@example.org
                                                v2 | ben@example.org
User drives Vehicle                             ben@example.org | v1
User has PersonName                             anna@example.org | 'Anna'
Vehicle has VehicleName                         v1 | 'Blue Golf'
                                                v2 | "Ben's van"
Vehicle is of Make                              v1 | 'Volkswagen'
Vehicle is of CarModel                          v1 | 'Golf 1.4 TSI'
Vehicle was built in Year                       v1 | 2014
Vehicle uses Fuel                               v1 | 'Petrol 95'
Vehicle has VIN                                 v1 | 'WVWZZZ1KZEW000001'
Vehicle has RegistrationNumber                  v1 | '123 ABC'
```

### What a vehicle cost, and is worth

```
Vehicle was acquired on Date                    v1 | 2019-05-02
Vehicle was acquired at Distance                v1 | 84210 km
Vehicle was acquired for Money                  v1 | 9500 EUR
Vehicle is expected to be kept for Duration     v1 | 96
Vehicle is expected to be driven Distance more  v1 | 120000 km
Vehicle is expected to sell for Money           v1 | 2500 EUR
Vehicle was valued on Date at Money             v1 | 2026-10-01 | 4000 EUR
                                                v1 | 2027-03-01 | 3600 EUR
Vehicle was sold on Date *                      v1 | 2027-08-30
Vehicle was sold for Money *                    v1 | 3000 EUR
```

\* Derived, from the vehicle's income of kind 'Car sale' (step 5).

### Money and preferences

```
Money has Amount                                (74.10 EUR) | 74.10
Money is in Currency                            (74.10 EUR) | 'EUR'
Distance has Quantity                           (152300 km) | 152300
Distance is in DistanceUnit                     (152300 km) | 'km'
                                                (94640 mi) | 'mi'
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
another currency goes with the record that has it, below.

The preferred units and currency are each user's. They sync with the user,
so every device of theirs shows the same. They say only how things are
shown; what was entered keeps its own unit.

### Meter readings and trips

```
MeterReading is of Vehicle                      r21 | v1
                                                r22 | v2
MeterReading was at Moment                      r21 | 2026-10-01 07:45
MeterReading shows Distance                     r21 | 153120 km
                                                r22 | 94640 mi
MeterReading had driver User                    r21 | anna@example.org
Trip is of Vehicle                              t3 | v1
                                                t9 | v1
Trip started at Moment                          t3 | 2026-09-20 08:10
                                                t9 | 2026-10-02 18:40
Trip ended at Moment                            t3 | 2026-09-20 11:25
Trip started at Distance                        t3 | 152410 km
Trip ended at Distance                          t3 | 152700 km
Trip went from Place                            t3 | 'Berlin'
Trip went to Place                              t3 | 'Hamburg'
Trip has Purpose                                t3 | 'Business'
Trip had driver User                            t3 | anna@example.org
                                                t9 | ben@example.org
```

A trip's date is its start's. "Started on Date" and "started at Time" from
step 1 become one moment: a trip may run past midnight.

### Fill-ups

```
FillUp is of Vehicle                            f1 | v1
                                                f2 | v2
FillUp was at Moment                            f1 | 2026-09-14 17:20
FillUp was at Distance                          f1 | 152300 km
FillUp was of Volume                            f1 | 42.5 L
                                                f2 | 11.2 gal (US)
FillUp was of Fuel                              f1 | 'Petrol 95'
FillUp cost Money                               f1 | 74.10 EUR
FillUp was at Station                           f1 | 'Shell, Main St'
FillUp filled the tank                          f1
FillUp had driver User                          f1 | ben@example.org
```

### Services

```
Service is of Vehicle                           s7 | v1
                                                s8 | v1
Service was at Moment                           s7 | 2026-06-01 09:30
Service was at Distance                         s7 | 148000 km
Service has Title                               s7 | 'Annual service'
Service had driver User                         s7 | anna@example.org
Service was done by Garage                      s7 | 'Garage Müller'
                                                s8 | 'Carglass'
Service is of ServiceKind                       s7 | 'Maintenance'
                                                s8 | 'Repair'
Service is paid in Currency                     s7 | 'EUR'
Service had a discount of Money                 s7 | 20 EUR
Service was paid by PaymentMethod               s7 | 'Card'
Service was paid in Instalments                 s7 | 2
ServiceItem is part of Service                  i1 | s7
                                                i2 | s7
                                                i3 | s7
ServiceItem is of Task                          i1 | 'Oil change'
                                                i2 | 'Brake fluid change'
                                                i3 | 'Labour'
ServiceItem cost Money                          i1 | 95 EUR
                                                i4 | 40 CHF
ServiceItem has Note                            i1 | 'Filter: Mann W 712/95'
ServiceItem was charged Money                   i4 | 41.60 EUR

A service is paid in one currency, and its items' costs are entered in it.
An item may be entered in another (a part bought abroad), and then
converted into the service's: by what it was charged in that currency, if
the receipt says, or by the rates. The discount is in the service's
currency.
```

Step 1's "Service included Task for Money", with a note on that inclusion,
is a fact about a fact. So the inclusion is an object of its own, the
ServiceItem (ORM's objectification), with the task, the cost and the note
as its facts. Two items of one service may name the same task, such as
labour on two days.

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
TyreChange is of Vehicle                        c4 | v1
TyreChange was at Moment                        c4 | 2026-04-05 10:00
TyreChange was at Distance                      c4 | 146900 km
TyreChange had driver User                      c4 | anna@example.org
TyreChange fitted TyreSet                       c3 | ts1
                                                c4 | ts2
TyreChange removed TyreSet                      c4 | ts1
TyreChange measured Tread                       c3 | 8
```

The tread is measured on the set fitted, at the change: "TyreSet had Tread
at TyreChange" from step 1 reads more simply from the change.

### Documents and other costs

```
Document is of Vehicle                          d1 | v1
Document is of DocumentKind                     d1 | 'Insurance'
Document was issued by Issuer                   d1 | 'Allianz'
Document has DocumentNumber                     d1 | '77-123456'
Document is valid from Date                     d1 | 2025-12-01
Document expires on Date                        d1 | 2026-12-01
Document cost Money                             d1 | 610 EUR
Expense is of Vehicle                           e12 | v1
                                                e13 | v1
Expense was at Moment                           e12 | 2026-08-03 06:15
Expense is of ExpenseKind                       e12 | 'Parking'
                                                e13 | 'Toll'
Expense cost Money                              e12 | 36 EUR
                                                e13 | 40 CHF
Expense has Note                                e12 | 'Airport'
Expense was charged Money                       e13 | 41.60 EUR
Expense had driver User                         e12 | anna@example.org
```

The issuer and the number replace step 1's single name 'Allianz 77-123456'.

### Incomes

```
Income is of Vehicle                            n30 | v1
                                                n41 | v1
Income was at Moment                            n30 | 2026-10-02 19:05
                                                n41 | 2027-08-30 15:00
Income was at Distance                          n30 | 153314 km
                                                n41 | 171020 km
Income is of IncomeKind                         n30 | 'Transport app'
                                                n41 | 'Car sale'
Income earned Money                             n30 | 23.50 EUR
                                                n41 | 3000 EUR
Income had driver User                          n30 | ben@example.org
                                                n41 | anna@example.org
Income was paid in Instalments                  n41 | 3
Income was for Trip                             n30 | t9
Income has Note                                 n41 | 'To a colleague'
```

### Notes and attachments

```
Trip has Note                                   t3 | 'Client meeting'
FillUp has Note                                 f1 | 'Price was up 10 cents'
...                                             (every event the same)
Attachment is of FillUp                         a1 | f1
Attachment is of Document                       a2 | d1
...                                             (every event, and documents)
Attachment has FileName                         a1 | 'receipt-0914.jpg'
                                                a2 | 'policy.pdf'
```

A record may have many attachments, each of one record. An attachment is
a file; how the sync carries files is for later.

### Schedules and reminders

```
Schedule is of Vehicle                          sc1 | v1
                                                sc2 | v1
Schedule is for Task                            sc1 | 'Oil change'
Schedule is for ExpenseKind                     sc2 | 'Parking'
Schedule has Note                               sc2 | "Residents' permit, zone 4"
Schedule recurs every Distance                  sc1 | 15000 km
Schedule recurs every Duration                  sc1 | 12
                                                sc2 | 12
Reminder is of Vehicle                          m5 | v1
                                                m6 | v1
Reminder comes from Schedule                    m5 | sc1
Reminder is for Task                            m6 | 'Air conditioning'
Reminder has Note                               m6 | 'It smells musty'
Reminder is due at Distance                     m5 | 163000 km
Reminder is due on Date                         m5 | 2027-06-01
                                                m6 | 2027-05-01
Reminder was done at Moment                     m5 | 2027-05-20 11:00
Reminder was done at Distance                   m5 | 162400 km
Reminder was done by Service                    m5 | s12
Reminder was done by Expense                    m7 | e20
```

A reminder from a schedule is for the schedule's work; "is for" on a
reminder is for one on its own. Work that is a task is done by a service
that includes it; work that is a kind of expense, by an expense of that
kind. A schedule's reminders are kept as records: when one is done, the
app makes the next one, due its intervals after when and where it was
done. The owner may change any reminder afterwards, its due distance and
date included.

### Checklists and inspections

```
Checklist is kept by User                       cl1 | anna@example.org
Checklist has ChecklistName                     cl1 | 'Before a long trip'
ChecklistItem is in Checklist                   ci1 | cl1
                                                ci4 | cl1
ChecklistItem says ItemText                     ci1 | 'Tyre pressure'
                                                ci4 | 'Washer fluid'
ChecklistItem is at Position                    ci1 | 1
                                                ci4 | 4
Inspection is of Vehicle                        in50 | v1
Inspection went through Checklist               in50 | cl1
Inspection was at Moment                        in50 | 2026-10-10 08:00
Inspection was at Distance                      in50 | 153200 km
Inspection had driver User                      in50 | anna@example.org
Check is of Inspection                          k1 | in50
                                                k4 | in50
Check is of ChecklistItem                       k1 | ci1
                                                k4 | ci4
Check found Result                              k1 | 'OK'
                                                k4 | 'Not OK'
Check has Note                                  k4 | 'Low, topped up'
Schedule is for Checklist                       sc3 | cl2
Reminder was done by Inspection                 m8 | in51
```

Items are records with ids, not just their text: an item's text may be
reworded later, and the inspections that checked it still point at it.
Step 1's "In Inspection, ChecklistItem was found Result", with a note on
it, is a fact about a fact, as a service's item was. So each check is an
object of its own, the Check (objectification), with the result and the
note as its facts.

### Who entered what

```
Trip was entered by User                        t3 | anna@example.org
FillUp was entered by User                      f1 | ben@example.org
...                                             (every record the same)
```

### What's left for later steps

- **Repetition.** Every kind of record repeats "is of Vehicle", "was at
  Moment", "was at Distance", "had driver User", "has Note", attachments,
  "cost Money", "was entered by User" and its own rate. Step 6 decides
  whether they are one supertype (an Event, or a Record) with these fact
  types once, and which records are costs and which incomes.
- **Reminders done by work.** "Reminder was done by Service", "by
  Expense" and "by Inspection", and "is for Task", "for ExpenseKind" and
  "for Checklist": the same question, a supertype of the work and of what
  does it.
- **Not stored, worked out:** a trip's distance and duration; a service's
  cost; which tyre set is on; how far a set has gone; when a reminder is
  next due; distance driven; every report. Step 3 lists these
  derivations.

## Step 3: entity types combined, arithmetic derived

### Entity types combined

Two entity types are one when their instances can be compared as the same
kind of thing.

- **Distance** is one type, whatever role it plays. An odometer reading
  (acquired at, shows, at), a length (driven, more) and an interval
  (recurs every) are all distances. A trip's length is a difference of two
  readings, and a reminder is due when a reading reaches a sum of readings
  and intervals. Comparing and subtracting them is the point.
- **User** is one type for the owner, a driver of the vehicle, who drove
  at each event and who entered it. The same person plays all of these.
- **Fuel** is one type: what a vehicle uses, and what a fill-up was of.
- **CostKind replaces ServiceKind and ExpenseKind.** The pie chart puts
  fill-ups, maintenance, repairs, tyres, documents, parking, tolls and
  washes side by side as kinds of cost. So there is one list of kinds, and
  each record gets its kind:
  - a fill-up is 'Fuel';
  - a service is 'Maintenance' or 'Repair' (what step 2 called its
    ServiceKind);
  - buying a tyre set is 'Tyres';
  - a document is 'Documents';
  - an expense is 'Parking', 'Toll', 'Wash', or another kind of its own.

  Services and expenses say their kind; for the rest it is fixed by what
  they are, which is a derivation (step 5). A schedule or reminder for a
  kind of expense is then for a CostKind, one of the kinds an expense may
  be of (step 6).
- **Moment** is one type for when every event happened, a trip's start
  and end, and when a reminder was done. They are compared to put records
  in order.

What stays apart:
- **Garage, Station and Place:** they play different roles, and nothing
  compares a garage with a trip's destination.
- **CarModel and TyreModel.**
- **Note and Title:** text, but nothing compares one with the other.
- **IncomeKind:** incomes aren't costs, and their kinds are a list of
  their own.
- **Task:** what a service does, not a kind of cost: a service's kind is
  'Maintenance' or 'Repair', and its items are tasks.
- **DocumentKind, Purpose and PaymentMethod:** lists of their own.
- **Result:** a check's, not a kind of anything else.

### What is worked out, not stored

Each in the user's preferred units and currency, unless it says otherwise.

**Conversions**

1. *A distance in a unit:* its quantity × the fixed factor between the
   units. The same for volumes.
2. *Money in a currency:* what it was charged in that currency, if the
   record says. Otherwise the amount × the rate between the currencies on
   its date, or on the latest date before it with a rate. When there is no rate at
   all, the amount can't be shown in that currency, and the report says
   so.

**Records**

3. *A trip's distance:* where it ended − where it started.
4. *A trip's duration:* when it ended − when it started.
5. *A service's cost:* the sum of its items' costs, less its discount,
   in the service's currency (an item entered in another converted by
   what it was charged, or the rates).
6. *A vehicle's reading at a moment:* the latest distance any of its
   records gives at or before that moment (acquisition, meter readings,
   trips' ends, fill-ups, services, tyre changes, incomes). The forms show
   it as the last reading, beside the odometer.
7. *A fill-up's price per volume:* its cost ÷ its volume.
8. *Which tyre set is on a vehicle:* the one its latest tyre change
   fitted.
9. *How far a tyre set has gone:* over each time it was on, the distance
   at the change that removed it − the distance at the change that fitted
   it (to the vehicle's latest reading while it is still on).

**Reminders**

10. *When a schedule's next reminder is due:* the distance and date its
    last reminder was done + the schedule's intervals. Before any was
    done, counted from when the schedule was set up: its first reminder's
    due distance and date are given then.
11. *Whether a reminder is due, or overdue:* not done, and the vehicle's
    latest reading has reached its distance, or today its date, whichever
    comes first.
12. *How far and how long until a reminder is due:* its due distance − the
    vehicle's latest reading; its due date − today.

**Fuel**

13. *Consumption (L/100 km, km/L or mpg, as the user prefers),* the
    full-tank method: the volume put in since the full fill-up before ÷ the
    distance driven since it. Only between two fill-ups that filled the
    tank; a partial fill-up's volume counts toward the next full one.
    Fill-ups are taken in the order of their moments. Each full fill-up
    shows the consumption up to it.
14. *Fuel cost per distance:* the same, with cost for volume.

**Reports,** per vehicle and over a period, then per kind of record:

15. *Distance driven:* the reading at the period's end − the reading at
    its start.
16. *Costs:* the sum of the costs of the records in the period.
17. *Income:* the sum of the incomes in the period.
18. *Per day:* a total ÷ the days in the period.
19. *Per distance:* a total ÷ the distance driven.
20. *Costs by kind, by month, by kind of record each month; incomes by
    kind; service costs by task:* the sums so grouped. A service's
    discount is spread over its tasks in proportion to their costs.
21. *Fuel consumption:* each full-tank interval's consumption (a chart
    over time); the latest, the lowest and the highest of them; and the
    average over the period (all the volume ÷ all the distance between the
    first and the last full fill-up in it). The same for the fuel cost per
    distance. All fuels, or the fill-ups of one fuel. The total volume and
    cost of fuel.
22. *Mileage:* each record's moment and distance, in order.
23. *A month against the month before:* its average consumption ÷ the
    month before's − 1, as a percentage up or down.
24. *Balance:* income − costs, then in each view:
    - *cash:* − the purchase price on its date, + the sale price on its
      date;
    - *running:* nothing more;
    - *depreciation over time:* − (purchase price − expected sale price) ÷
      expected duration, a cost per day;
    - *depreciation by distance:* − (purchase price − expected sale
      price) ÷ expected further distance, a cost per distance driven;
    - *what it's worth:* − the drop in value between valuations, counted
      on the date of the valuation that shows it;
    - and in the depreciation views, when sold: + (sale price − the value
      left on paper), on the sale's date.

### For ORMKit

These derivations become ORMKit derivation queries. A few need more than
ORMKit's queries do today, which is part of what building Logbook will
show:
- arithmetic between values (differences, products, quotients);
- the record before or after another, in order of moments (the fill-up
  before, the next reading); the lowest and highest;
- unit and currency conversion, the latter by the latest rate on or
  before a date;
- dates and durations (days in a period, months between dates);
- grouping by month.

## Step 4: uniqueness, and whether each fact type is elementary

A uniqueness constraint says which roles' values occur at most once
together. It also tests elementarity: a fact type of n roles whose
uniqueness spans fewer than n − 1 roles splits into smaller ones (Halpin's
n − 1 rule).

### Each at most one

Most fact types say one thing about one record, so the record's role is
unique. Each vehicle, record or user has at most one of each of these:

- **Vehicle:** owner, name, make, model, year built, fuel, VIN,
  registration, date and distance acquired, price, expected duration,
  expected further distance, expected sale price, date and price sold.
- **User:** name, preferred currency, distance unit, volume unit.
- **MeterReading:** vehicle, moment, distance, driver.
- **Trip:** vehicle, start and end moments, start and end distances, from,
  to, purpose, driver.
- **FillUp:** vehicle, moment, distance, volume, fuel, cost, station,
  driver. Filling the tank is a unary: a fill-up did or didn't.
- **Service:** vehicle, moment, distance, title, garage, kind, currency,
  driver, discount, payment method, instalments.
- **ServiceItem:** service, task, cost, what it was charged, note.
- **TyreSet:** vehicle, name, season, model, size, price.
- **TyreChange:** vehicle, moment, distance, the set fitted, the set
  removed, tread, driver.
- **Document:** vehicle, kind, issuer, number, valid from, expires,
  cost.
- **Expense:** vehicle, moment, kind, cost, what it was charged, driver.
- **Income:** vehicle, moment, distance, kind, money, driver,
  instalments, the trip it was for.
- **Checklist:** who keeps it, name.
- **ChecklistItem:** checklist, text, position.
- **Inspection:** vehicle, checklist, moment, distance, driver.
- **Check:** inspection, item, result, note.
- **Schedule:** vehicle, task, kind of expense or checklist, note,
  distance interval, time interval.
- **Reminder:** vehicle, schedule, task, kind of expense or checklist,
  note, due distance, due date, done moment, done distance, the record it
  was done by.
- **Attachment:** the record it is of, file name.
- **Every record:** who entered it, note.

The other role is not unique in any of these: many trips are of one
vehicle, many fill-ups cost 74.10 EUR, one set is fitted by many changes
over the years, a record has many attachments.

**Also unique the other way:**
- **Income was for Trip:** a trip is paid by at most one income.
- **A check's inspection and item:** an inspection checks each item at
  most once. An external uniqueness over the two, so the inspection and
  the item together identify the check, as a service item's could not
  (two items of a service may name the same task).
- **A checklist item's checklist and position:** one item at each place
  in a list.
- **Money, Distance, Volume:** each has one amount and one currency (or
  quantity and unit), and the two together identify it: (74.10, 'EUR') is
  one money. That is the reference scheme from step 2, an external
  uniqueness over the two.

**Not unique the other way**, deliberately:
- **A VIN** may be on two vehicles. A car sold from one user to another is
  in both logbooks, each with its own history.
- **Registration numbers** change hands, and come back.
- **Names** (vehicles, tyre sets) aren't checked: two vehicles may both be
  'Golf'.

### Many to many

- **User drives Vehicle:** a user drives many vehicles, and a vehicle has
  many drivers. The uniqueness spans both roles: each pair once.

### More than two roles

- **Vehicle was valued on Date at Money:** one value per vehicle per
  date. The uniqueness spans the vehicle and the date: n − 1 = 2 roles, so
  it is elementary.

  ```
  v1 | 2026-10-01 | 4000 EUR
  v1 | 2027-03-01 | 3600 EUR     different dates: fine
  v1 | 2026-10-01 | 3900 EUR     the same date again: not allowed
  ```

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

## Step 5: what must be there, and logical derivations

### What every one must have

A mandatory role says every instance of the type plays it. The rule here:
**a record states all of its facts**. A fact is optional only where it can
honestly be missing, and each such case is listed with why.

| Record | Must have | May lack, and why |
| --- | --- | --- |
| Vehicle | owner, name, make, model, year, fuel | VIN and registration (not every car has them to hand); what it was bought for, the expectations, valuations, the sale (each balance view needs only some) |
| User | email | name and preferences (preferences default to km, L and the device's currency) |
| MeterReading | vehicle, moment, distance, driver | |
| Trip | vehicle, start and end moments, start and end distances, driver | from, to and purpose (a paid ride may not record them) |
| FillUp | vehicle, moment, distance, volume, fuel, cost, station, driver | |
| Service | vehicle, moment, distance, garage, kind, currency, driver | items (a service may have no tasks listed); title (its kind and tasks say what it was); discount (none given); payment method (not everyone keeps it); instalments (paid at once, when missing) |
| ServiceItem | service, task, cost | note; what it was charged in another currency (only when it was) |
| TyreSet | vehicle, name, season, model, size | price (a set that came with the car) |
| TyreChange | vehicle, moment, distance, the set fitted, tread, driver | the set removed (the first set fitted, on a car with none recorded) |
| Document | vehicle, kind, issuer, number, valid from | expiry (a registration certificate doesn't expire); cost (some are free) |
| Expense | vehicle, moment, kind, cost, driver | what it was charged in another currency |
| Income | vehicle, moment, kind, money, driver | distance (a refund comes away from the car); the trip (only a ride logged as a trip has one); instalments (paid at once, when missing) |
| Attachment | the record it is of, file name | |
| Checklist | who keeps it, name | items (a new list, still being written) |
| ChecklistItem | checklist, text, position | |
| Inspection | vehicle, checklist, moment, distance, driver | checks (an inspection may be saved before every item is gone through) |
| Check | inspection, item, result | note |
| Schedule | vehicle; its work: a task, a kind of expense or a checklist, exactly one (exclusive-or); at least one interval | the other interval: it may recur by distance only, by time only, or both (inclusive-or); note |
| Reminder | vehicle; a due distance or a due date or both (inclusive-or); its schedule or work of its own, a task, a kind of expense or a checklist, exactly one of the four (exclusive-or) | note; the done moment, done distance and the record that did it, until it is done; then the moment and distance are a must, the record optional (done by hand); that record is a service, an expense or an inspection, exactly one (exclusive-or) |
| Every record | who entered it | note; attachments (any number, none included) |
| Money, Distance, Volume | amount and currency; quantity and unit | |
| An exchange rate | all four roles | |

Two of these are more than single mandatory roles:
- **A reminder that is done** has both a done moment and a done distance.
  That's an equality constraint between the two (step 6): it has one if and
  only if it has the other.
- **"FillUp filled the tank"** is yes or no: a fill-up that doesn't say so
  didn't fill it. A unary can't be mandatory; leaving it out is the "no".

The driver is a must on every event, as a record states all of its facts.
The forms fill it in with the signed-in user, to be changed when someone
else drove.

### Logical derivations

Facts worked out from others by rules, not arithmetic:

1. **Each record's kind of cost** (`Record is of CostKind`):
   - a fill-up is of 'Fuel';
   - a tyre set, bought, is of 'Tyres';
   - a document with a cost is of 'Documents';
   - a service or an expense is of the kind it says.

   So the kind is stored only for services and expenses. The derived fact
   puts every cost in one list, for the reports. Incomes are not costs,
   and have kinds of their own.
2. **Who drives a vehicle** (`User drives Vehicle`): the users it is
   shared with, and its owner. *Partly derived*: the sharing is stored, and
   the owner is derived.
3. **Who a vehicle is shared with:** its drivers other than its owner.
4. **A reminder's work** (a task, a kind of expense or a checklist): its
   own, or its schedule's. Its note likewise.
5. **Whether a reminder is done:** it has a done moment.
6. **What did a reminder's work** (`Reminder was done by Service`, `by
   Expense` or `by Inspection`): the first record of its vehicle, after it
   was set, that does its work: a service with an item of its task, an
   expense of its kind, or an inspection through its checklist. *Derived and stored*: when such a record is saved, the reminder
   not yet done is marked done with the record's moment and distance, and
   linked to it. The owner may change that afterwards, or mark a reminder
   done by hand.
7. **That a vehicle was sold, when and for how much:** from its income of
   kind 'Car sale', the date of its moment and its money. A vehicle has at
   most one (step 6).
8. **The reverse exchange rate:** if on a date one X is worth F Y, then
   one Y is worth 1 ÷ F X. *Derived and stored*: worked out when a rate is
   entered, and kept, so that reports read rates both ways alike. A rate
   entered by hand both ways keeps the one entered.
9. **Whether an inspection found anything:** some check of it found 'Not
   OK'. And which checklist items of its were never checked: those with
   no check.
10. **Which checklists a driver may use:** the vehicle owner's.
11. **Which records a driver may change:** none. The owner may change any
   of their vehicles' records. That's a permission, from the facts of who
   owns and who entered, enforced by the service (see Permissions).

## Next

Step 6: value constraints (the lists, positive amounts and distances,
instalments of at least 1), set-comparison constraints (a removed tyre
set was fitted before; a reminder for a kind of expense names one an
expense may be of; at most one 'Car sale' per vehicle; an inspection's
checks are of items of the checklist it went through), and subtyping (the
records' common supertype, which records are costs and which incomes, and
the work a reminder is for and what does it).
