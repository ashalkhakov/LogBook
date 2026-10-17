# Logbook's model, by CSDP

Halpin's Conceptual Schema Design Procedure, step by step. The ORM model it
ends with is `Model/Logbook.orm`. Everything else is derived from it: the Core
Data model, the OData service, the sync, and the code that checks the
constraints.

## Step 1: examples as elementary facts

These are the kinds of things a car logbook records, each given as an
example and then as the elementary facts it holds. They are a first draft,
to be corrected.

### A vehicle

> Our blue Golf is a 2014 Volkswagen Golf 1.4 TSI, VIN WVWZZZ1KZEW000001,
> registration 123 ABC. We bought it on 2019-05-02 with 84,210 km on it.

- Vehicle 'Blue Golf' is of Make 'Volkswagen'.
- Vehicle 'Blue Golf' is of Model 'Golf 1.4 TSI'.
- Vehicle 'Blue Golf' was built in Year 2014.
- Vehicle 'Blue Golf' has VIN 'WVWZZZ1KZEW000001'.
- Vehicle 'Blue Golf' has Registration '123 ABC'.
- Vehicle 'Blue Golf' was acquired on Date 2019-05-02.
- Vehicle 'Blue Golf' was acquired at Distance 84210 km.

### A fill-up

> On 2026-09-14, at 152,300 km, 42.5 L of petrol for 74.10 EUR, at Shell on
> Main St. Filled to the brim.

- FillUp 1 is of Vehicle 'Blue Golf'.
- FillUp 1 was on Date 2026-09-14.
- FillUp 1 was at Distance 152300 km.
- FillUp 1 was of Volume 42.5 L.
- FillUp 1 was of Fuel 'Petrol'.
- FillUp 1 cost Amount 74.10 EUR.
- FillUp 1 was at Station 'Shell, Main St'.
- FillUp 1 filled the tank. *(unary)*

### A service

> On 2026-06-01, at 148,000 km, the Golf had its annual service at Garage
> Müller for 320 EUR: oil and oil filter changed, brake fluid replaced. The
> filter was a Mann W 712/95.

- Service 7 is of Vehicle 'Blue Golf'.
- Service 7 was on Date 2026-06-01.
- Service 7 was at Distance 148000 km.
- Service 7 was done by Garage 'Garage Müller'.
- Service 7 cost Amount 320 EUR.
- Service 7 included Task 'Oil change'.
- Service 7 included Task 'Oil filter change'.
- Service 7 included Task 'Brake fluid change'.
- In Service 7, Task 'Oil filter change' fitted Part 'Mann W 712/95'.

### What is due

> The oil is changed every 15,000 km or every 12 months, whichever comes
> first. The insurance runs out on 2026-12-01.

- Task 'Oil change' recurs every Distance 15000 km.
- Task 'Oil change' recurs every Period 12 months.
- Vehicle 'Blue Golf' has Document 'Insurance', which expires on Date
  2026-12-01.

From the last time a task was done and its interval, the app works out when
it is next due. That is a derivation, not a fact to store.

## Open questions

1. **Trips.** Should Logbook also keep a trip log (date, from and to,
   distances, business or private, as tax offices want)? Or is it
   maintenance only?
2. **People.** Is it one person's vehicles, or a household's, or a
   fleet's, shared between drivers who sync? Do we record who drove, who
   filled up, or who paid?
3. **Tyres.** Should it track summer and winter sets, when each was
   fitted, and their tread? Or is a tyre change just another task?
4. **Documents.** Insurance, registration and the roadworthiness test,
   with expiry dates and perhaps the scanned files?
5. **Other costs.** Repairs, parking, tolls, washes, or only fuel and
   service?
6. **Units.** km or miles, L or gallons, one currency or several. Is that
   per vehicle, per user, or fixed?
7. **Electric and hybrid cars.** Charging sessions (kWh, cost, at home or
   at a public charger) beside fill-ups?
