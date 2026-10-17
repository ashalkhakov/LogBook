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
  - revenues: what paid trips earn;
  - schedules of work the users plan, and the reminders they mark done.
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

> On 2026-10-01 the Golf's odometer showed 153,120 km.

- MeterReading 21 is of Vehicle 'Blue Golf'.
- MeterReading 21 was on Date 2026-10-01.
- MeterReading 21 shows Distance 153120.

Every event below that happens at a distance (fill-up, service, trip) also
gives a reading of the meter. Whether that makes them meter readings too, or
just events with a distance, is for step 6 (subtypes).

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
- Trip 3 was driven by User 'anna@example.org'.

How far and how long it took are derived: 290 km, 3 h 15 min.

Trips are recorded freely: they need not agree with the meter, nor with
each other (gaps and overlaps are allowed). The owner may change what was
recorded before; whether drivers may too, or only add, is a permission,
not a fact (see below).

### A fill-up

> On 2026-09-14, at 152,300 km, 42.5 L of petrol for 74.10 EUR, at Shell on
> Main St. Filled to the brim. Ben paid.

- FillUp 1 is of Vehicle 'Blue Golf'.
- FillUp 1 was on Date 2026-09-14.
- FillUp 1 was at Distance 152300.
- FillUp 1 was of Volume 42.5.
- FillUp 1 was of Fuel 'Petrol 95'.
- FillUp 1 cost Money 74.10 EUR.
- FillUp 1 was at Station 'Shell, Main St'.
- FillUp 1 filled the tank. *(unary)*
- FillUp 1 was paid by User 'ben@example.org'.

### A service

> On 2026-06-01, at 148,000 km, the Golf had its annual service at Garage
> Müller: oil and filter changed (95 EUR), brake fluid replaced (60 EUR),
> labour 165 EUR. The filter was a Mann W 712/95.

- Service 7 is of Vehicle 'Blue Golf'.
- Service 7 was on Date 2026-06-01.
- Service 7 was at Distance 148000.
- Service 7 was done by Garage 'Garage Müller'.
- Service 7 included Task 'Oil change' for Money 95 EUR.
- Service 7 included Task 'Brake fluid change' for Money 60 EUR.
- Service 7 included Task 'Labour' for Money 165 EUR.
- In Service 7, Task 'Oil change' has Note 'Filter: Mann W 712/95'.
- Service 7 is of ServiceKind 'Maintenance'.

Each task in a service has its own cost. The service's cost is their sum,
so it's derived, not stored. "Service included Task for Money" is a ternary;
step 4 checks that it is elementary. Parts are only noted on tasks, not
kept as a catalogue.

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
- TyreChange 4 was on Date 2026-04-05.
- TyreChange 4 was at Distance 146900.
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

> Parking at the airport, 2026-08-03, 36 EUR. Toll on the A2, 12.50 EUR. A
> car wash, 9 EUR.

- Expense 12 is of Vehicle 'Blue Golf'.
- Expense 12 was on Date 2026-08-03.
- Expense 12 is of ExpenseKind 'Parking'.
- Expense 12 cost Money 36 EUR.
- Expense 12 has Note 'Airport'.

### Revenues: paid trips

> As a taxi driver would: at the end of a ride, 2026-10-02, 18:40 to 19:05,
> 14 km, paid 23.50 EUR.

- Trip 9 is of Vehicle 'Blue Golf'.
- Trip 9 was on Date 2026-10-02.
- Trip 9 started at Time 18:40.
- Trip 9 ended at Time 19:05.
- Trip 9 started at Distance 153300.
- Trip 9 ended at Distance 153314.
- Trip 9 was paid Money 23.50 EUR.

Revenue is what paid trips earn. A trip need not be paid. A paid trip
needn't name its places, but it does say how long it took and how far it
went.

### Money

> 74.10 EUR, on 2026-09-14; the preferred currency is USD, and that day
> 1 EUR = 1.09 USD. The receipt for the Swiss toll says 40 CHF = 41.60 EUR.

- Money is a value object: an Amount in a Currency (74.10, 'EUR').
- Rate: on Date 2026-09-14, 1 Currency 'EUR' is worth 1.09 Currency 'USD'.
- The app's preferred Currency is 'USD'.
- Expense 13's Money 40 CHF was converted at Rate 1.04 EUR per CHF.

Each amount is kept as entered. Rates are as flexible as can be: a table
of rates by date, entered by hand or fetched, used for any amount on that
date (or the latest date before it). An amount may carry its own rate, as
a receipt or a card statement gives it, which then counts for that amount.

### Units

- The app's distance Unit is 'km' (or 'mi'), its volume Unit 'L' (or US
  gal, imperial gal).

Distances and volumes are stored in one unit and shown in the app's. Which
unit they're stored in is for later.

### Schedules and reminders

> Change the oil every 15,000 km or every 12 months, whichever comes first,
> counting from the last change (148,000 km, 2026-06-01). And once: put the
> winter tyres on by 2026-11-15.

- Schedule 'Oil' is of Vehicle 'Blue Golf'.
- Schedule 'Oil' says Text 'Change the oil'.
- Schedule 'Oil' recurs every Distance 15000 km.
- Schedule 'Oil' recurs every Duration 12 months.
- Reminder 5 comes from Schedule 'Oil'.
- Reminder 5 is due at Distance 163000 km.
- Reminder 5 is due on Date 2027-06-01.
- Reminder 6 is of Vehicle 'Blue Golf'.
- Reminder 6 says Text 'Put the winter tyres on'.
- Reminder 6 is due on Date 2026-11-15.

> The oil was changed at Garage Müller on 2027-05-20 at 162,400 km.

- Reminder 5 was done on Date 2027-05-20.
- Reminder 5 was done at Distance 162400 km.
- Reminder 5 was done by Service 12.

A **schedule** is planned work: what to do, and how often, by distance,
by time, or both, whichever comes first. It is never done itself.

A **reminder** is one time the work is due. It is marked done, with when
and at what distance, and may be linked to the work that did it. A
schedule's reminders come one after another: when one is done, the next is
due its intervals after when and where it was done. A reminder may also
stand on its own, set once by hand, with no schedule. Users write their
own schedules and reminders, per vehicle; there's no manufacturer's
catalogue for now.

### Reports

Reports are information outputs too: each says derived facts. Per vehicle,
over a period:

1. **Balance:** revenues minus costs; per day; in the preferred currency
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
4. **Revenues:** total, average per day, per distance unit.
5. **Costs and revenues over time:** bar chart by date.
6. **Costs by kind:** pie chart (fill-ups, services, tyres, documents,
   parking, tolls, washes, ...).
7. **Costs by month:** bar chart.
8. **Fuel consumption:** per full tank over time (a chart), and the
   average over the period, in L/100 km, km/L or mpg; fuel cost per
   distance.

There are the same reports per kind of event (fill-ups, services, ...).

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
record, not about the people in it: Ben may enter a fill-up Anna paid.

## Step 2: the fact types, checked against the examples

### How things are identified

Records made on a device and synced need ids that don't clash. So the
things Logbook records are identified by an id the app makes (a UUID,
written `v1`, `t3` here):
- Vehicle, Trip, FillUp, Service, ServiceItem, MeterReading, TyreSet,
  TyreChange, Document, Expense, Reminder.

The rest are identified by what they are:

| Entity type | Identified by |
| --- | --- |
| User | email |
| Make, CarModel, Fuel, Garage, Station, Place, TyreModel | name |
| ServiceKind, ExpenseKind, DocumentKind, Purpose, Season | name, from a list |
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

Moments (a date with a time) and dates are values.

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
Vehicle was sold on Date                        v1 | 2027-08-30
Vehicle was sold for Money                      v1 | 3000 EUR
```

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
factor. Step 4 checks that it's elementary. An amount's own rate goes with
the record that has it, below.

The preferred units and currency are each user's. They sync with the user,
so every device of theirs shows the same. They say only how things are
shown; what was entered keeps its own unit.

### Meter readings and trips

```
MeterReading is of Vehicle                      r21 | v1
                                                r22 | v2
MeterReading was on Date                        r21 | 2026-10-01
MeterReading shows Distance                     r21 | 153120 km
                                                r22 | 94640 mi
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
Trip was driven by User                         t3 | anna@example.org
Trip was paid Money                             t9 | 23.50 EUR
```

A trip's date is its start's. "Started on Date" and "started at Time" from
step 1 become one moment: a trip may run past midnight.

### Fill-ups

```
FillUp is of Vehicle                            f1 | v1
                                                f2 | v2
FillUp was on Date                              f1 | 2026-09-14
FillUp was at Distance                          f1 | 152300 km
FillUp was of Volume                            f1 | 42.5 L
                                                f2 | 11.2 gal (US)
FillUp was of Fuel                              f1 | 'Petrol 95'
FillUp cost Money                               f1 | 74.10 EUR
FillUp was at Station                           f1 | 'Shell, Main St'
FillUp filled the tank                          f1
FillUp was paid by User                         f1 | ben@example.org
```

### Services

```
Service is of Vehicle                           s7 | v1
                                                s8 | v1
Service was on Date                             s7 | 2026-06-01
Service was at Distance                         s7 | 148000 km
Service was done by Garage                      s7 | 'Garage Müller'
                                                s8 | 'Carglass'
Service is of ServiceKind                       s7 | 'Maintenance'
                                                s8 | 'Repair'
Service is paid in Currency                     s7 | 'EUR'
ServiceItem is part of Service                  i1 | s7
                                                i2 | s7
                                                i3 | s7
ServiceItem is of Task                          i1 | 'Oil change'
                                                i2 | 'Brake fluid change'
                                                i3 | 'Labour'
ServiceItem cost Money                          i1 | 95 EUR
                                                i4 | 40 CHF
ServiceItem has Note                            i1 | 'Filter: Mann W 712/95'
ServiceItem was converted at Factor into Currency  i4 | 1.04 | 'EUR'

A service is paid in one currency, and its items' costs are entered in it.
An item may be entered in another (a part bought abroad), and then
converted into the service's, by its own factor or by the rates.
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
TyreChange was on Date                          c4 | 2026-04-05
TyreChange was at Distance                      c4 | 146900 km
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
Document has Attachment                         d1 | 'policy.pdf'
Expense is of Vehicle                           e12 | v1
                                                e13 | v1
Expense was on Date                             e12 | 2026-08-03
Expense is of ExpenseKind                       e12 | 'Parking'
                                                e13 | 'Toll'
Expense cost Money                              e12 | 36 EUR
                                                e13 | 40 CHF
Expense has Note                                e12 | 'Airport'
Expense was converted at Factor into Currency   e13 | 1.04 | 'EUR'
```

The issuer and the number replace step 1's single name 'Allianz 77-123456'.
An attachment is a file. How the sync carries files is for later.

### Schedules and reminders

```
Schedule is of Vehicle                          sc1 | v1
Schedule says Text                              sc1 | 'Change the oil'
Schedule recurs every Distance                  sc1 | 15000 km
Schedule recurs every Duration                  sc1 | 12
Reminder is of Vehicle                          m5 | v1
                                                m6 | v1
Reminder comes from Schedule                    m5 | sc1
Reminder says Text                              m6 | 'Put the winter tyres on'
Reminder is due at Distance                     m5 | 163000 km
Reminder is due on Date                         m5 | 2027-06-01
                                                m6 | 2026-11-15
Reminder was done on Date                       m5 | 2027-05-20
Reminder was done at Distance                   m5 | 162400 km
Reminder was done by Service                    m5 | s12
```

A reminder from a schedule says what the schedule says. "Says Text" is for
one on its own. Whether a schedule's reminders are kept as records, each
made when the one before is done, or worked out from the schedule, is a
question below.

### Who entered what

```
Trip was entered by User                        t3 | anna@example.org
FillUp was entered by User                      f1 | ben@example.org
...                                             (every record the same)
```

### What's left for later steps

- **Repetition.** Every kind of record repeats "is of Vehicle", "was on
  Date", "was at Distance", "cost Money", "was entered by User" and its
  own rate. Step 6 decides whether they are one supertype (an Event, or a
  Record) with these fact types once, and which records are costs.
- **Reminders done by work.** "Reminder was done by Service" may also be
  done by a fill-up, an expense or a tyre change: the same question.
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
- **User** is one type for the owner, a driver, who paid and who entered.
  The same person plays all of these.
- **Factor** is one type: an exchange rate's, and an amount's own rate.
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
  they are, which is a derivation (step 5).

What stays apart:
- **Garage, Station and Place:** they play different roles, and nothing
  compares a garage with a trip's destination.
- **CarModel and TyreModel.**
- **Note and Reminder text:** text, but nothing compares one with the
  other.
- **DocumentKind and Purpose:** lists of their own.

### What is worked out, not stored

Each in the user's preferred units and currency, unless it says otherwise.

**Conversions**
1. *A distance in a unit:* its quantity × the fixed factor between the
   units. The same for volumes.
2. *Money in a currency:* the amount × its own factor, if it has one into
   that currency. Otherwise × the rate between the currencies on its date,
   or on the latest date before it with a rate. When there is no rate at
   all, the amount can't be shown in that currency, and the report says
   so.

**Records**
3. *A trip's distance:* where it ended − where it started.
4. *A trip's duration:* when it ended − when it started.
5. *A service's cost:* the sum of its items' costs, in the service's
   currency (an item entered in another converted by its own factor or
   the rates).
6. *A vehicle's reading on a date:* the latest distance any of its
   records gives on or before that date (acquisition, meter readings,
   trips' ends, fill-ups, services, tyre changes).
7. *Which tyre set is on a vehicle:* the one its latest tyre change
   fitted.
8. *How far a tyre set has gone:* over each time it was on, the distance
   at the change that removed it − the distance at the change that fitted
   it (to the vehicle's latest reading while it is still on).

**Reminders**
9. *When a schedule's next reminder is due:* the distance and date its
   last reminder was done + the schedule's intervals. Before any was done,
   counted from when the schedule was set up: its first reminder's due
   distance and date are given then.
10. *Whether a reminder is due, or overdue:* not done, and the vehicle's
    latest reading has reached its distance, or today its date, whichever
    comes first.

**Fuel**
11. *Consumption (L/100 km, km/L or mpg, as the user prefers),* the
    full-tank method: the volume put in since the last full fill-up ÷ the
    distance driven since it. Only between two fill-ups that filled the
    tank; a partial fill-up's volume counts toward the next full one.

**Reports,** per vehicle and over a period, then per kind of cost:
12. *Distance driven:* the reading at the period's end − the reading at
    its start.
13. *Costs:* the sum of the costs of the records in the period.
14. *Revenue:* the sum of what the trips in the period were paid.
15. *Per day:* a total ÷ the days in the period.
16. *Per distance:* a total ÷ the distance driven.
17. *Costs by kind, and by month:* the sums grouped by kind, and by month.
18. *Fuel consumption:* each full-tank interval's consumption (a chart
    over time), and the average over the period (all the volume ÷ all the
    distance between the first and the last full fill-up in it). Also the
    fuel cost per distance.
19. *Balance:* revenue − costs, then in each view:
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

### Question

**A schedule's reminders: kept, or worked out?**
- **Kept as records:** when a reminder is done, the app makes the next
  one, due its intervals later. The user can move it ("the garage said
  wait"), and it syncs like any record.
- **Worked out:** only the done ones are kept. The next one exists only as
  a derivation from the last one done.

Kept is simpler for the apps and lets a due date be changed by hand. I'd
keep them.

### For ORMKit

These derivations become ORMKit derivation queries. A few need more than
ORMKit's queries do today, which is part of what building Logbook will
show:
- arithmetic between values (differences, products, quotients);
- unit and currency conversion, the latter by the latest rate on or
  before a date;
- dates and durations (days in a period, months between dates);
- grouping by month.

## Next

Step 4: uniqueness constraints, and checking that each fact type is
elementary (the ternaries and the quaternary especially).
