#!/usr/bin/env python3
"""A logbook to look at: two cars and their last four months, written to a
server as a user's (the README's pictures are of it). Every date is counted
back from today, so it is never stale.

    Tests/sample-logbook.py http://127.0.0.1:8080/odata/ you@example.org

The Golf: a fill-up every twelve days or so, an oil change and its
schedule (and the brake fluid's, and the yearly inspection's, which come
due soon), a one-off reminder of the winter tyres, parking, a car wash,
its insurance, a trip, and Sam driving it too; the Octavia: a few fill-ups of diesel. A server
with no sign-in takes the email as the user's.
"""
import datetime
import json
import sys
import urllib.error
import urllib.request
import uuid

root, email = sys.argv[1], sys.argv[2]
today = datetime.datetime.now(datetime.timezone.utc).replace(hour=0, minute=0, second=0, microsecond=0)


def request(method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    r = urllib.request.Request(root + path, data=data, method=method,
                               headers={"Content-Type": "application/json", "Accept": "application/json"})
    try:
        with urllib.request.urlopen(r, timeout=30) as response:
            return json.loads(response.read() or b"{}")
    except urllib.error.HTTPError as e:
        sys.exit("%s %s: %d %s" % (method, path, e.code, e.read().decode()))


def moment(days_ago, hour=9):
    return (today - datetime.timedelta(days=days_ago, hours=-hour)).strftime("%Y-%m-%dT%H:%M:%SZ")


def day(days_ago):
    return (today - datetime.timedelta(days=days_ago)).strftime("%Y-%m-%d")


def record(vehicle, kind, **fields):
    body = {"@odata.type": "#Default." + kind, "Id": str(uuid.uuid4()),
            "EnteredBy@odata.bind": "Users('%s')" % email, "Vehicle@odata.bind": "Vehicles(%s)" % vehicle}
    body.update(fields)
    request("POST", "Records", body)
    return body["Id"]


def event(vehicle, kind, days_ago, km, **fields):
    fields.update({"Timestamp": moment(days_ago, fields.pop("hour", 9)), "Driver@odata.bind": "Users('%s')" % email})
    if km is not None:
        fields.update({"MileageQuantity": km, "MileageDistanceUnit@odata.bind": "DistanceUnits('km')"})
    return record(vehicle, kind, **fields)


def vehicle(name, make, model, year, fuel, plate):
    body = {"Id": str(uuid.uuid4()), "VehicleName": name, "Make": make, "CarModel": model, "ManufactureYear": year,
            "Fuel": fuel, "RegistrationNumber": plate, "Owner@odata.bind": "Users('%s')" % email}
    request("POST", "Vehicles", body)
    return body["Id"]


request("POST", "Users", {"Email": email, "PersonName": "Alex Morgan", "Currency": "EUR"})
for name in ("Parking", "Car wash"):
    request("POST", "CostKinds", {"@odata.type": "#Default.ExpenseKind", "Name": name})

golf = vehicle("Family Golf", "Volkswagen", "Golf VII", 2016, "Petrol", "B-AM 2016")
# Driven by Sam too, whom the owner shares it with.
request("POST", "Users", {"Email": "sam@example.org", "PersonName": "Sam Morgan"})
request("POST", "VehicleDrivers", {"Vehicle@odata.bind": "Vehicles(%s)" % golf, "User@odata.bind": "Users('sam@example.org')"})
octavia = vehicle("Work Octavia", "Skoda", "Octavia Combi", 2019, "Diesel", "B-AM 4719")

# The Golf's fill-ups: 41 to 47 litres, every twelve days, about 560 km apart.
km = 61840
stations = ["Shell", "Aral", "TotalEnergies", "Aral", "Shell"]
prices = [1.79, 1.76, 1.82, 1.74, 1.77, 1.81, 1.78, 1.75, 1.80, 1.73]
for i, days_ago in enumerate(range(118, 0, -12)):
    litres = 41 + (i * 3) % 7
    km += 540 + (i * 37) % 60
    event(golf, "FillUp", days_ago, km, hour=13, Fuel="Petrol", Station=stations[i % len(stations)], FilledTheTank=True,
          VolumeQuantity=litres, **{"VolumeVolumeUnit@odata.bind": "VolumeUnits('L')"},
          TotalAmount=round(litres * prices[i % len(prices)], 2), TotalCurrency="EUR")

# The oil changed 100 days ago, and its schedule started from it; the brake
# fluid's every two years, last 22 months ago; the inspection yearly.
service_km = 63520
service = {"@odata.type": "#Default.Service", "Id": str(uuid.uuid4()), "Timestamp": moment(100, 10),
           "MileageQuantity": service_km, "MileageDistanceUnit@odata.bind": "DistanceUnits('km')",
           "Garage": "Garage Müller", "Title": "Yearly service", "ServiceKind@odata.bind": "CostKinds('Maintenance')",
           "Currency": "EUR", "Driver@odata.bind": "Users('%s')" % email, "EnteredBy@odata.bind": "Users('%s')" % email,
           "Vehicle@odata.bind": "Vehicles(%s)" % golf}
items = [("Oil change", 89), ("Oil filter", 18.5), ("Air filter", 32), ("Wiper blades", 27)]
batch = {"requests": [dict(id="0", atomicityGroup="service", method="POST", url="Records", body=service)] + [
    dict(id=str(i + 1), atomicityGroup="service", method="POST", url="ServiceItems",
         body={"Id": str(uuid.uuid4()), "Task": task, "CostAmount": cost, "CostCurrency": "EUR",
               "Service@odata.bind": "Records(%s)" % service["Id"]}) for i, (task, cost) in enumerate(items)]}
answer = request("POST", "$batch", batch)
if any(r["status"] >= 300 for r in answer["responses"]):
    sys.exit("the service: %s" % answer)

for task, every_km, months, last_days, last_km in (("Oil change", 15000, 12, 100, service_km),
                                                  ("Brake fluid", None, 24, 670, 41200),
                                                  ("Inspection", None, 12, 340, 54300)):
    fields = {"Task": task, "Duration": months}
    if every_km:
        fields.update({"IntervalQuantity": every_km, "IntervalDistanceUnit@odata.bind": "DistanceUnits('km')"})
    schedule = record(golf, "Schedule", **fields)
    request("POST", "Records(%s)/Default.Start" % schedule,
            {"LastDoneAt": moment(last_days, 10), "LastDoneMileage": last_km, "LastDoneMileageUnit": "km"})

record(golf, "Reminder", Task="Winter tyres on", DueDate=day(-19), SetAt=moment(30))

for days_ago, kind, amount in ((96, "Parking", 4.5), (81, "Car wash", 14.9), (63, "Parking", 6), (44, "Car wash", 14.9),
                               (37, "Parking", 3.5), (15, "Parking", 7.5), (6, "Car wash", 16.9)):
    event(golf, "Expense", days_ago, None, hour=8, TotalAmount=amount, TotalCurrency="EUR",
          **{"ExpenseKind@odata.bind": "CostKinds('%s')" % kind})

record(golf, "Document", DocumentKind="Insurance", DocumentNumber="KH-2210-4471", Issuer="Allianz", Date=day(75),
       ExpiresOnDate=day(75 - 365), TotalAmount=486, TotalCurrency="EUR")

# A trip: from its start (the event's moment and mileage) to its end.
event(golf, "Trip", 52, 64480, hour=8, Moment=moment(52, 12), DistanceQuantity=64792,
      **{"DistanceDistanceUnit@odata.bind": "DistanceUnits('km')"}, Place="Berlin", WentToPlace="Leipzig",
      Purpose="Visiting family")

# The Octavia's fill-ups: diesel, fortnightly.
km = 88210
for i, days_ago in enumerate(range(110, 0, -15)):
    litres = 48 + (i * 5) % 6
    km += 780 + (i * 41) % 90
    event(octavia, "FillUp", days_ago, km, hour=6, Fuel="Diesel", Station=stations[(i + 1) % len(stations)],
          FilledTheTank=True, VolumeQuantity=litres, **{"VolumeVolumeUnit@odata.bind": "VolumeUnits('L')"},
          TotalAmount=round(litres * 1.69, 2), TotalCurrency="EUR")

print("a sample logbook: Family Golf and Work Octavia, for %s" % email)
