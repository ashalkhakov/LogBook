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
  - reminders the users set themselves.
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

### Reminders

> In 6 months or at 160,000 km, whichever comes first: change the oil
> filter. Every 15,000 km: change the oil. On 2026-11-15: put the winter
> tyres on.

- Reminder 5 is of Vehicle 'Blue Golf'.
- Reminder 5 says Text 'Change the oil filter'.
- Reminder 5 is due at Distance 160000.
- Reminder 5 is due on Date 2027-04-17.
- Reminder 6 says Text 'Change the oil'.
- Reminder 6 recurs every Distance 15000.
- Reminder 6 recurs every Period 6 months.

Users write their own, per vehicle; no manufacturer's catalogue for now. A
reminder is only a reminder: it is ticked off by hand. It may also be
linked to the work that did it.

> The oil filter was changed in Service 7.

- Reminder 5 was done by Service 7.

 A
reminder is due at a distance, on a date, or both (whichever comes first),
once or recurring. When it is done, a recurring one moves on from that
distance or date.

### Reports

Reports are information outputs too: each says derived facts. Per vehicle,
over a period:

1. **Balance:** revenues minus costs (acquisition included?); per day; in
   the preferred currency per distance unit.
2. **Distance driven:** total, and average per day.
3. **Costs:** total, average per day, per distance unit.
4. **Revenues:** total, average per day, per distance unit.
5. **Costs and revenues over time:** bar chart by date.
6. **Costs by kind:** pie chart (fill-ups, services, tyres, documents,
   parking, tolls, washes, ...).
7. **Costs by month:** bar chart.

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
- A driver may add records to a vehicle shared with them. Whether they may
  change or remove older ones is to be decided.

## Open questions

1. **Balance.** Which of the options below the reports offer.
2. **Drivers and history.** May a driver change records, or only add
   them? Only their own? Only recent ones?
