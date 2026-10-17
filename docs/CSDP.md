# Logbook's model, by CSDP

Halpin's Conceptual Schema Design Procedure, step by step. The ORM model it
ends with is `Model/Logbook.orm`. Everything else is derived from it: the Core
Data model, the OData service, the sync, and the code that checks the
constraints.

## Scope

- **Vehicles:** one person's cars, diesel and petrol only (no electric or
  hybrid for now). Different drivers may drive them, and everything syncs
  between devices, as SimpleNotes does.
- **What it records:**
  - meter readings;
  - trips;
  - fill-ups;
  - services and the tasks in them, each with its own cost;
  - tyre sets;
  - documents;
  - other costs: repairs, parking, tolls, washes;
  - revenues.
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
- Vehicle 'Blue Golf' uses Fuel 'Petrol'.
- Vehicle 'Blue Golf' has VIN 'WVWZZZ1KZEW000001'.
- Vehicle 'Blue Golf' has Registration '123 ABC'.
- Vehicle 'Blue Golf' was acquired on Date 2019-05-02.
- Vehicle 'Blue Golf' was acquired at Distance 84210.
- Vehicle 'Blue Golf' was acquired for Money 9500 EUR.

### A driver

> Anna and Ben both drive the Golf. Anna drove it to Hamburg.

- Driver 'Anna' drives Vehicle 'Blue Golf'.
- Driver 'Ben' drives Vehicle 'Blue Golf'.
- Trip 3 was driven by Driver 'Anna'.

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
> 152,410 km to 152,700 km. The client pays 0.30 EUR a kilometre.

- Trip 3 is of Vehicle 'Blue Golf'.
- Trip 3 was on Date 2026-09-20.
- Trip 3 started at Distance 152410.
- Trip 3 ended at Distance 152700.
- Trip 3 went from Place 'Berlin'.
- Trip 3 went to Place 'Hamburg'.
- Trip 3 has Purpose 'Business'.
- Trip 3 was driven by Driver 'Anna'.
- Trip 3 earned Money 87 EUR. *(a revenue: see below)*

### A fill-up

> On 2026-09-14, at 152,300 km, 42.5 L of petrol for 74.10 EUR, at Shell on
> Main St. Filled to the brim. Ben paid.

- FillUp 1 is of Vehicle 'Blue Golf'.
- FillUp 1 was on Date 2026-09-14.
- FillUp 1 was at Distance 152300.
- FillUp 1 was of Volume 42.5.
- FillUp 1 was of Fuel 'Petrol'.
- FillUp 1 cost Money 74.10 EUR.
- FillUp 1 was at Station 'Shell, Main St'.
- FillUp 1 filled the tank. *(unary)*
- FillUp 1 was paid by Driver 'Ben'.

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
- In Service 7, Task 'Oil change' fitted Part 'Mann W 712/95'.

Each task in a service has its own cost. The service's cost is their sum,
so it's derived, not stored. "Service included Task for Money" is a ternary;
step 4 checks that it is elementary.

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
> car wash, 9 EUR. A new windscreen wiper, 24 EUR.

- Expense 12 is of Vehicle 'Blue Golf'.
- Expense 12 was on Date 2026-08-03.
- Expense 12 is of ExpenseKind 'Parking'.
- Expense 12 cost Money 36 EUR.
- Expense 12 has Note 'Airport'.

Repairs could be services, or expenses of kind 'Repair'. To be settled.

### Revenues

> The client paid 87 EUR for the Hamburg trip. We sold the old roof box for
> 40 EUR.

- Revenue 2 is of Vehicle 'Blue Golf'.
- Revenue 2 was on Date 2026-09-25.
- Revenue 2 earned Money 87 EUR.
- Revenue 2 is for Trip 3.

### Money

> 74.10 EUR, on 2026-09-14; the preferred currency is USD, and that day
> 1 EUR = 1.09 USD.

- Money is a value object: an Amount in a Currency (74.10, 'EUR').
- Rate: on Date 2026-09-14, 1 Currency 'EUR' is worth 1.09 Currency 'USD'.
- The app's preferred Currency is 'USD'.

Each amount is kept as entered. Reports convert it by the rate on its date.
Whether rates are entered by hand, fetched, or stored with each amount is
an open question.

### Units

- The app's distance Unit is 'km' (or 'mi'), its volume Unit 'L' (or US
  gal, imperial gal).

Distances and volumes are stored in one unit and shown in the app's. Which
unit they're stored in is for later.

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

## Open questions

1. **Revenues.** What earns money: trips reimbursed (per distance, or a
   fixed sum), selling the car or parts, renting it out? Is a trip's
   revenue its own event, or part of the trip?
2. **Balance.** Do the acquisition price and a sale price count, as
   capital, or depreciation? Or only running costs against revenues?
3. **Rates.** Entered by hand, fetched from a source (which?), or fixed at
   entry with each amount?
4. **Repairs:** services with tasks, or expenses of a kind?
5. **Drivers:** people with an account who sync, or just names for "who
   drove/paid"? Does each driver see all of the owner's vehicles?
6. **Parts:** kept as a catalogue (part numbers, brands, prices), or just
   noted on tasks?
7. **Fuel types:** petrol grades (95, 98), diesel, LPG/CNG?
8. **Recurring tasks:** do the intervals belong to a task in general
   ("oil every 15,000 km"), or per vehicle?
