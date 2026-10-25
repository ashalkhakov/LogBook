#!/usr/bin/env python3
"""The server run, and asked over HTTP as a device would.

    Tests/serve-and-check.py build/logbook-server

Each part on a server of its own: a temporary store, on a free port on
loopback.

The rules, with no one signed in:
- the units and the kinds of cost every store starts with are there (the
  model's reference data: 'Maintenance' and 'Repair', a service's, and
  'Fuel', 'Tyres', 'Documents'), none of them a kind of expense;
- an attachment of a record has its content, a photo (Edm.Binary, base64
  in JSON; base64url as the server writes it), which comes back byte for
  byte; one with none is refused;
- a change set (a $batch atomicity group) of a vehicle's tyre sets and two
  tyre changes is saved whole, and the second change's removed set is the
  one the change before it fitted (derived and stored, at the end of the
  change set);
- a change set whose change fits the set the change before it fitted (so
  removes the set it fits) breaks a rule: refused, 400, and none of it
  saved; the same alone, as one request;
- any event may be at a mileage: an expense with one and one without are
  saved; a meter reading without one is refused (a MeteredEvent is an
  event at some distance); half a mileage, its quantity without its unit
  or the unit without the quantity, is refused, added or changed (a
  Distance is whole or none);
- reminders: one not said when it was set is refused; one done by an
  expense with no mileage is saved, done at
  another moment than the expense's refused; done and cancelled refused;
  a replacement of another vehicle's reminder refused; two open reminders
  of one schedule refused, but open ones of other schedules and one-offs
  of the vehicle saved, and the schedule's next once the open one is
  cancelled; a rescheduling saved, one that moved from nothing refused.

Who may do what, signed in with OpenID Connect, as deployed (JWTIssuer,
AllowAnonymous NO): an issuer of its own here stands in for the provider
(Keycloak), its discovery document and keys served on loopback, its
access tokens RS256 JWTs signed with openssl, each with the user's email.
Anna owns a vehicle and shares it with Ben; Cid is no one to it.
- a vehicle is its maker's, whatever the request says; a user is made the
  first time they write; another is added by their email alone;
- Cid sees none of it; Ben sees it once it is shared, and Anna alone
  shares it;
- Ben adds a record, entered by him whatever the request says, and
  changes or removes none; Anna, the owner, changes his; Cid adds none;
- the units are the app's; a kind of cost or of expense anyone adds, and
  no one removes, the model's ('Maintenance') neither.
- the procedures: whoever drives the vehicle closes and moves its
  reminders, its owner alone starts its schedules, cancels its reminders and
  discards its records; Ben's oil change closes Anna's reminder.
- stock (docs/STOCK.md, Who may): Anna's catalog is hers; Ben keeps its
  garage, Dee manages it, Cid is no one to it. Cid sees none of it; Ben
  sees it, adds no items or warehouses, and adjusts, transfers, ships and
  counts in the garage, but orders nothing and changes no move; Dee orders
  (numbered, given none) and confirms, reorders, and corrects a move;
  the actions refuse in the procedures' words.

The procedures, as the server's actions (Server/LBActions.h), with no one
signed in: a schedule started (its first reminder named by it, due from
the last change); a service, of the kind 'Maintenance' every store
starts with, with an item of the task closes the reminder
(automatic completion), one from before it was set, or of another task,
does not; the next made, named by it; Complete of one done, or with no
event, refused; Complete of a one-off by the event chosen, reopened when
that event is moved before it was set; Reschedule, Cancel with a
replacement; Discard of an
event whose next was touched since refused, 409, until the owner says, and
of one whose next is untouched, the next deleted with it.

LB_SERVICE_ROOT, when set, is a server already running (a store it can
fill), asked instead of one started here: the first part only.

LB_FRAMEWORK_PATH, when set, is the server's DYLD_FRAMEWORK_PATH: frameworks
built from an unreleased fix tried in place of the released ones. (macOS
drops DYLD_ variables on the way through a protected binary such as
/usr/bin/python3, so they are passed under another name.)
"""
import base64
import datetime
import http.server
import json
import os
import socket
import subprocess
import sys
import tempfile
import threading
import time
import urllib.error
import urllib.request
import uuid

SERVER = sys.argv[1] if len(sys.argv) > 1 else "build/logbook-server"
failures = []
logs = []
ROOT = None


def check(what, ok, detail=""):
    print(("ok   " if ok else "FAIL ") + what + ("" if ok else ": " + str(detail)))
    if not ok:
        failures.append(what)


def free_port():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def b64url(data):
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


class Issuer:
    """An OpenID Connect provider's part a service sees: its discovery
    document and its keys, on loopback; and access tokens it signs."""

    def __init__(self):
        self.directory = tempfile.mkdtemp()
        self.key = os.path.join(self.directory, "key.pem")
        subprocess.run(["openssl", "genrsa", "-out", self.key, "2048"], check=True, capture_output=True)
        modulus = subprocess.run(["openssl", "rsa", "-in", self.key, "-noout", "-modulus"], check=True,
                                 capture_output=True, text=True).stdout.strip().split("=", 1)[1]
        self.jwk = {"kty": "RSA", "kid": "test", "use": "sig", "alg": "RS256",
                    "n": b64url(bytes.fromhex(modulus)), "e": b64url((65537).to_bytes(3, "big"))}
        issuer = self

        class Handler(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                answers = {"/.well-known/openid-configuration": {"issuer": issuer.url, "jwks_uri": issuer.url + "/keys"},
                           "/keys": {"keys": [issuer.jwk]}}
                answer = answers.get(self.path)
                self.send_response(200 if answer else 404)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(json.dumps(answer or {}).encode())

            def log_message(self, *args):
                pass

        self.http = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.url = "http://127.0.0.1:%d" % self.http.server_address[1]
        threading.Thread(target=self.http.serve_forever, daemon=True).start()
        self.tokens = {}

    def token(self, email):
        """An access token for the user, as the provider gives one."""
        if email not in self.tokens:
            now = int(time.time())
            header = b64url(json.dumps({"alg": "RS256", "typ": "JWT", "kid": "test"}).encode())
            claims = b64url(json.dumps({"iss": self.url, "sub": str(uuid.uuid5(uuid.NAMESPACE_URL, email)), "email": email,
                                        "iat": now, "exp": now + 3600, "scope": "openid email"}).encode())
            signed = subprocess.run(["openssl", "dgst", "-sha256", "-sign", self.key], input=(header + "." + claims).encode(),
                                    check=True, capture_output=True).stdout
            self.tokens[email] = header + "." + claims + "." + b64url(signed)
        return self.tokens[email]

    def close(self):
        self.http.shutdown()


ISSUER = None


def request(method, path, body=None, user=None):
    data = json.dumps(body).encode() if body is not None else None
    headers = {"Content-Type": "application/json", "Accept": "application/json"}
    if user:
        headers["Authorization"] = "Bearer " + ISSUER.token(user)
    r = urllib.request.Request(ROOT + path, data=data, method=method, headers=headers)
    try:
        with urllib.request.urlopen(r, timeout=30) as response:
            text = response.read().decode()
            return response.status, json.loads(text) if text.startswith(("{", "[")) else text
    except urllib.error.HTTPError as e:
        text = e.read().decode()
        return e.code, json.loads(text) if text.startswith("{") else text


BATCH_USER = None


def batch(group, requests):
    """One atomicity group: its responses' statuses and bodies."""
    status, answer = request("POST", "$batch", {"requests": [
        dict(id=str(i), atomicityGroup=group, method=method, url=url, body=body)
        for i, (method, url, body) in enumerate(requests)]}, user=BATCH_USER)
    if status != 200:
        return [status], [answer]
    return [r["status"] for r in answer["responses"]], [r.get("body") for r in answer["responses"]]


def serve(*settings):
    """A server started, ROOT its service; the process."""
    global ROOT
    given = os.environ.get("LB_SERVICE_ROOT")
    port = free_port()
    ROOT = given or "http://127.0.0.1:%d/odata/" % port
    environment = dict(os.environ)
    if os.environ.get("LB_FRAMEWORK_PATH"):
        environment["DYLD_FRAMEWORK_PATH"] = os.environ["LB_FRAMEWORK_PATH"]
    # Its log to a file: a pipe nobody reads would stop it once full.
    log = tempfile.TemporaryFile(mode="w+")
    logs.append(log)
    command = ["true"] if given else [SERVER, "-StoreURL", "Temporary", "-Port", str(port), "-Localhost", "YES", *settings]
    server = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT, text=True, env=environment)
    for _ in range(100):
        try:
            urllib.request.urlopen(urllib.request.Request(ROOT + "$metadata"), timeout=1).read()
            return server
        except urllib.error.HTTPError:
            return server
        except Exception:
            if server.poll() is not None and not given:
                log.seek(0)
                sys.exit("the server stopped: " + log.read())
            time.sleep(0.1)
    return server


def stop(server):
    server.terminate()
    try:
        server.wait(timeout=10)
    except subprocess.TimeoutExpired:
        server.kill()
        server.wait()


def vehicle_body(owner=None):
    body = {"Id": str(uuid.uuid4()), "VehicleName": "Golf", "Make": "Volkswagen", "CarModel": "Golf VII",
            "ManufactureYear": 2016, "Fuel": "Petrol"}
    if owner:
        body["Owner@odata.bind"] = "Users('%s')" % owner
    return body


def tyre_set(vehicle, name, season, entered_by):
    return {"@odata.type": "#Default.TyreSet", "Id": str(uuid.uuid4()), "TyreSetName": name, "Season": season,
            "TyreModel": "Primacy 4", "TyreSize": "205/55 R16", "Vehicle@odata.bind": "Vehicles(%s)" % vehicle,
            "EnteredBy@odata.bind": "Users('%s')" % entered_by}


def tyre_change(vehicle, fits, day, km, user):
    return {"@odata.type": "#Default.TyreChange", "Id": str(uuid.uuid4()),
            "Timestamp": "2026-%sT09:00:00Z" % day, "MileageQuantity": km,
            "MileageDistanceUnit@odata.bind": "DistanceUnits('km')", "Tread": 7,
            "TyreSet@odata.bind": "Records(%s)" % fits["Id"], "Driver@odata.bind": "Users('%s')" % user,
            "EnteredBy@odata.bind": "Users('%s')" % user, "Vehicle@odata.bind": "Vehicles(%s)" % vehicle}


def the_rules():
    status, units = request("GET", "DistanceUnits")
    check("the units are there", status == 200 and sorted(u["Code"] for u in units["value"]) == ["km", "mi"], units)
    status, kinds = request("GET", "CostKinds")
    names = sorted(k["Name"] for k in kinds.get("value", [])) if status == 200 else kinds
    check("the kinds of cost are there, the model's", names == ["Documents", "Fuel", "Maintenance", "Repair", "Tyres"], names)
    check("none of them a kind of expense", status == 200
          and all(k.get("@odata.type", "#Default.CostKind") == "#Default.CostKind" for k in kinds["value"]), kinds)
    anna = "anna@example.org"
    check("a user", request("POST", "Users", {"Email": anna})[0] == 201)
    made = vehicle_body(anna)
    status, body = request("POST", "Vehicles", made)
    check("a vehicle", status == 201, body)
    vehicle = made["Id"]

    summer, winter = tyre_set(vehicle, "Summer set", "Summer", anna), tyre_set(vehicle, "Winter set", "Winter", anna)
    april, november = tyre_change(vehicle, summer, "04-01", 10000, anna), tyre_change(vehicle, winter, "11-01", 15000, anna)
    statuses, bodies = batch("g1", [("POST", "Records", summer), ("POST", "Records", winter),
                                    ("POST", "Records", april), ("POST", "Records", november)])
    check("a change set of two sets and two changes is saved", statuses == [201] * 4, (statuses, bodies))
    status, removed = request("GET", "Records(%s)/Default.TyreChange/RemovedTyreSet" % november["Id"])
    check("the second change removed the set the first fitted (derived at save)",
          status == 200 and removed.get("Id", "").lower() == summer["Id"], (status, removed))
    status, unit = request("GET", "Records(%s)/Default.TyreChange/MileageDistanceUnit" % april["Id"])
    check("a change keeps its odometer's unit (a supertype's relationship)", status == 200 and unit.get("Code") == "km",
          (status, unit))
    status, removed = request("GET", "Records(%s)/Default.TyreChange/RemovedTyreSet" % april["Id"])
    check("the first removed none", status in (204, 404) or removed.get("value") is None, (status, removed))

    status, count = request("GET", "Records/$count")
    statuses, bodies = batch("g2", [("POST", "Records", tyre_change(vehicle, winter, "12-01", 16000, anna))])
    check("fitting the set fitted before is refused", statuses == [400], (statuses, bodies))
    check("none of it saved", request("GET", "Records/$count")[1] == count)
    status, body = request("POST", "Records", tyre_change(vehicle, winter, "12-02", 16100, anna))
    check("alone, too", status == 400 and request("GET", "Records/$count")[1] == count, (status, body))
    # A request's answer has each violation a detail; a batch's the message.
    message = json.dumps(body)
    check("the refusal names the rule", "removed the same TyreSet" in message, message)
    bought = tyre_set(vehicle, "Spare set", "Summer", anna)
    bought.update({"Date": "2026-03-01", "TotalAmount": 400, "TotalCurrency": "XYZ"})
    status, body = request("POST", "Records", bought)
    check("a cost in a currency ISO 4217 has none is refused", status == 400 and "Currency" in json.dumps(body), (status, body))
    bought["TotalCurrency"] = "KZT"
    check("in one it has, saved", request("POST", "Records", bought)[0] == 201)
    attachments(summer["Id"])
    mileage_and_reminders(anna, vehicle)
    procedures(anna)
    continued(anna)


PHOTO = os.path.join(os.path.dirname(os.path.abspath(__file__)), "receipt-photo.jpg")


def attachments(record):
    """A receipt's photo attached to a record: its content, Edm.Binary,
    base64 in JSON, back as it was sent; an attachment of no content is
    none."""
    with open(PHOTO, "rb") as f:
        photo = f.read()
    attached = {"Id": str(uuid.uuid4()), "FileName": "receipt.jpg", "Content": base64.b64encode(photo).decode(),
                "Record@odata.bind": "Records(%s)" % record}
    status, body = request("POST", "Attachments", attached)
    check("an attachment with its content, a photo of %d KB" % (len(photo) // 1024), status == 201, (status, str(body)[:300]))
    status, body = request("GET", "Attachments(%s)" % attached["Id"])
    # As OData's JSON writes Edm.Binary: base64url, unpadded.
    content = body.get("Content") or "" if status == 200 else ""
    back = base64.urlsafe_b64decode(content + "=" * (-len(content) % 4))
    check("its content back, byte for byte", back == photo, (status, len(back)))
    status, body = request("GET", "Records(%s)/Attachments?$select=FileName" % record)
    check("the record's attachments", status == 200 and [a["FileName"] for a in body["value"]] == ["receipt.jpg"], (status, body))
    status, body = request("POST", "Attachments", {"Id": str(uuid.uuid4()), "FileName": "nothing.jpg",
                                                   "Record@odata.bind": "Records(%s)" % record})
    check("one with no content is refused", status == 400, (status, body))


def expense(vehicle, kind, moment, user, km=None):
    body = {"@odata.type": "#Default.Expense", "Id": str(uuid.uuid4()), "Timestamp": moment,
            "TotalAmount": 12.5, "TotalCurrency": "EUR", "ExpenseKind@odata.bind": "CostKinds('%s')" % kind,
            "Driver@odata.bind": "Users('%s')" % user, "EnteredBy@odata.bind": "Users('%s')" % user,
            "Vehicle@odata.bind": "Vehicles(%s)" % vehicle}
    if km is not None:
        body.update({"MileageQuantity": km, "MileageDistanceUnit@odata.bind": "DistanceUnits('km')"})
    return body


def reminder(vehicle, user, **facts):
    """A reminder of the vehicle, due on a date, for what the facts say:
    Kind (an expense kind), Schedule (a schedule's id, counted from a day
    a year before it is due), else a task."""
    body = {"@odata.type": "#Default.Reminder", "Id": str(uuid.uuid4()), "DueDate": facts.pop("due", "2026-06-01"),
            "SetAt": facts.pop("set", "2026-04-01T09:00:00Z"), "EnteredBy@odata.bind": "Users('%s')" % user, "Vehicle@odata.bind": "Vehicles(%s)" % vehicle}
    kind, schedule = facts.pop("Kind", None), facts.pop("Schedule", None)
    if kind:
        body["ExpenseKind@odata.bind"] = "CostKinds('%s')" % kind
    elif schedule:
        body["Schedule@odata.bind"] = "Records(%s)" % schedule
        body["CountedFromDate"] = facts.pop("counted", "2025-06-01")
    else:
        body["Task"] = "Wash"
    body.update(facts)
    return body


def mileage_and_reminders(anna, vehicle):
    """Mileage on every event, and reminders: done, cancelled, replaced,
    rescheduled; one open a schedule."""
    check("a kind of expense", request("POST", "CostKinds", {"@odata.type": "#Default.ExpenseKind", "Name": "Wash"})[0] == 201)
    status, body = request("POST", "Records", expense(vehicle, "Wash", "2026-05-01T09:00:00Z", anna, km=12000))
    check("an expense at a mileage", status == 201 and body.get("MileageQuantity") == 12000, (status, body))
    without = expense(vehicle, "Wash", "2026-05-02T09:00:00Z", anna)
    status, body = request("POST", "Records", without)
    check("an expense with none", status == 201, (status, body))
    for part, value in (("MileageQuantity", 12100), ("MileageDistanceUnit@odata.bind", "DistanceUnits('km')")):
        half = expense(vehicle, "Wash", "2026-05-02T08:00:00Z", anna)
        half[part] = value
        status, body = request("POST", "Records", half)
        check("half a mileage (%s alone) is refused" % part.split("@")[0], status == 400 and "whole Distance or none" in json.dumps(body),
              (status, body))
    status, body = request("PATCH", "Records(%s)" % without["Id"], {"@odata.type": "#Default.Expense", "MileageQuantity": 12100})
    check("and changed to half a mileage, too", status == 400 and "whole Distance or none" in json.dumps(body), (status, body))
    status, body = request("POST", "Records", {"@odata.type": "#Default.MeterReading", "Id": str(uuid.uuid4()),
                                               "Timestamp": "2026-05-03T09:00:00Z", "Driver@odata.bind": "Users('%s')" % anna,
                                               "EnteredBy@odata.bind": "Users('%s')" % anna,
                                               "Vehicle@odata.bind": "Vehicles(%s)" % vehicle})
    check("a meter reading with none is refused (it is a MeteredEvent)", status == 400 and "MeteredEvent" in json.dumps(body),
          (status, body))

    done = reminder(vehicle, anna, Kind="Wash", **{"Event@odata.bind": "Records(%s)" % without["Id"],
                                                   "DoneAt": without["Timestamp"]})
    status, body = request("POST", "Records", done)
    check("a reminder done by an expense with no mileage", status == 201, (status, body))
    status, body = request("POST", "Records", reminder(vehicle, anna, Kind="Wash", **{
        "Event@odata.bind": "Records(%s)" % without["Id"], "DoneAt": "2026-05-02T10:00:00Z"}))
    check("done by it at another moment is refused", status == 400 and "was done at that Moment" in json.dumps(body),
          (status, body))
    status, body = request("POST", "Records", reminder(vehicle, anna, DoneAt="2026-05-02T10:00:00Z", CancelDate="2026-05-02"))
    check("done and cancelled is refused", status == 400, (status, body))
    unset = reminder(vehicle, anna)
    del unset["SetAt"]
    status, body = request("POST", "Records", unset)
    check("a reminder not said when it was set is refused", status == 400, (status, body))
    cancelled = reminder(vehicle, anna, CancelDate="2026-05-02")
    check("cancelled", request("POST", "Records", cancelled)[0] == 201)
    status, body = request("POST", "Records", reminder(vehicle, anna, **{"Replaced@odata.bind": "Records(%s)" % cancelled["Id"]}))
    check("replaced by another of the vehicle", status == 201, (status, body))

    other = vehicle_body(anna)
    check("another vehicle", request("POST", "Vehicles", other)[0] == 201)
    elsewhere = reminder(other["Id"], anna, CancelDate="2026-05-02")
    check("a reminder of it, cancelled", request("POST", "Records", elsewhere)[0] == 201)
    status, body = request("POST", "Records", reminder(vehicle, anna, **{"Replaced@odata.bind": "Records(%s)" % elsewhere["Id"]}))
    check("a replacement of another vehicle's is refused", status == 400, (status, body))

    schedules = []
    for kind in ("Wash", "Parking"):
        if kind != "Wash":
            request("POST", "CostKinds", {"@odata.type": "#Default.ExpenseKind", "Name": kind})
        schedule = {"@odata.type": "#Default.Schedule", "Id": str(uuid.uuid4()), "Duration": 6,
                    "ExpenseKind@odata.bind": "CostKinds('%s')" % kind, "EnteredBy@odata.bind": "Users('%s')" % anna,
                    "Vehicle@odata.bind": "Vehicles(%s)" % vehicle}
        status, body = request("POST", "Records", schedule)
        check("a schedule (%s)" % kind, status == 201, (status, body))
        schedules.append(schedule["Id"])
    first = reminder(vehicle, anna, Schedule=schedules[0])
    check("its open reminder", request("POST", "Records", first)[0] == 201)
    status, body = request("POST", "Records", reminder(vehicle, anna, Schedule=schedules[0], due="2026-07-01"))
    check("a second open one of the schedule is refused", status == 400 and "the number of that Reminder is greater than 1" in json.dumps(body),
          (status, body))
    status, body = request("POST", "Records", reminder(vehicle, anna, Schedule=schedules[1]))
    check("one of another schedule of the vehicle, open too", status == 201, (status, body))
    status, body = request("POST", "Records", reminder(vehicle, anna))
    check("and a one-off, open", status == 201, (status, body))
    status, body = request("PATCH", "Records(%s)" % first["Id"], {"@odata.type": "#Default.Reminder", "CancelDate": "2026-05-04"})
    check("the schedule's cancelled", status in (200, 204), (status, body))
    status, body = request("POST", "Records", reminder(vehicle, anna, Schedule=schedules[0], due="2026-07-01"))
    check("then its next", status == 201, (status, body))

    rescheduling = {"Id": str(uuid.uuid4()), "Reminder@odata.bind": "Records(%s)" % done["Id"],
                    "MadeAt": "2026-05-01T08:00:00Z", "MadeBy@odata.bind": "Users('%s')" % anna, "FromDate": "2026-05-15",
                    "Note": "away"}
    status, body = request("POST", "Reschedulings", rescheduling)
    check("a rescheduling saved", status == 201, (status, body))
    status, body = request("POST", "Reschedulings", dict(rescheduling, Id=str(uuid.uuid4()), FromDate=None))
    check("one that moved from nothing is refused", status == 400, (status, body))


# The procedures' ids: name-based, in Logbook's namespace (LBProcedures.h).
NAMESPACE = uuid.uuid5(uuid.NAMESPACE_URL, "https://github.com/ashalkhakov/LogBook/reminders")


def named(name):
    return str(uuid.uuid5(NAMESPACE, name))


def now(hours=0):
    """A moment from now, as OData writes one."""
    moment = datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(hours=hours)
    return moment.strftime("%Y-%m-%dT%H:%M:%SZ")


def months_on(day, months):
    """The day so many months on, as the model's addMonths has it."""
    year, month = divmod(day.month - 1 + months, 12)
    year += day.year
    last = [31, 29 if year % 4 == 0 and (year % 100 or year % 400 == 0) else 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][month]
    return datetime.date(year, month + 1, min(day.day, last))


def oil_schedule(vehicle, user):
    return {"@odata.type": "#Default.Schedule", "Id": str(uuid.uuid4()), "Task": "Oil change", "IntervalQuantity": 15000,
            "IntervalDistanceUnit@odata.bind": "DistanceUnits('km')", "Duration": 12,
            "EnteredBy@odata.bind": "Users('%s')" % user, "Vehicle@odata.bind": "Vehicles(%s)" % vehicle}


def oil_change(vehicle, user, moment, km, tasks=("Oil change",), as_user=None):
    """A service and its items, in one change set: its statuses."""
    service = {"@odata.type": "#Default.Service", "Id": str(uuid.uuid4()), "Timestamp": moment, "MileageQuantity": km,
               "MileageDistanceUnit@odata.bind": "DistanceUnits('km')", "Garage": "Garage Müller",
               "ServiceKind@odata.bind": "CostKinds('Maintenance')", "Currency": "EUR",
               "Driver@odata.bind": "Users('%s')" % user, "EnteredBy@odata.bind": "Users('%s')" % user,
               "Vehicle@odata.bind": "Vehicles(%s)" % vehicle}
    items = [("POST", "ServiceItems", {"Id": str(uuid.uuid4()), "Task": task, "CostAmount": 40, "CostCurrency": "EUR",
                                       "Service@odata.bind": "Records(%s)" % service["Id"]}) for task in tasks]
    global BATCH_USER
    BATCH_USER = as_user
    try:
        statuses, bodies = batch("s" + service["Id"][:8], [("POST", "Records", service)] + items)
    finally:
        BATCH_USER = None
    return service, statuses, bodies


def action(path, name, body=None, user=None):
    return request("POST", "%s/Default.%s" % (path, name), body or {}, user=user)


def reminder_of(rid, user=None):
    status, body = request("GET", "Records(%s)" % rid, user=user)
    return body if status == 200 else None


def procedures(anna):
    """The procedures as the server's actions, and automatic completion,
    with no one signed in (the vehicle's owner acts)."""
    made = vehicle_body(anna)
    check("a vehicle for the procedures", request("POST", "Vehicles", made)[0] == 201)
    vehicle = made["Id"]
    status, kind = request("GET", "CostKinds('Maintenance')")
    check("a kind of service, there from the start", status == 200 and kind.get("Name") == "Maintenance", (status, kind))
    schedule = oil_schedule(vehicle, anna)
    status, body = request("POST", "Records", schedule)
    check("a schedule of the oil", status == 201, (status, body))
    sid = schedule["Id"]
    status, first = action("Records(%s)" % sid, "Start", {"LastDoneAt": "2026-06-01T10:00:00Z", "LastDoneMileage": 148000,
                                                          "LastDoneMileageUnit": "km"})
    check("Start: the first reminder, named by its schedule, due 12 months and 15000 km after the last change",
          status == 200 and first.get("Id", "").lower() == named("start of " + sid) and first.get("DueDate", "")[:10] == "2027-06-01"
          and first.get("DueMileageQuantity") == 163000, (status, first))
    status, body = action("Records(%s)" % sid, "Start")
    check("Start again is refused: it has an open reminder", status == 400 and "open reminder" in json.dumps(body), (status, body))
    first_id = named("start of " + sid)

    status, body = request("POST", "Records", reminder(vehicle, anna, Schedule=sid, set=now()))
    check("a second open reminder of the schedule is refused, as before", status == 400, (status, body))
    _, statuses, bodies = oil_change(vehicle, anna, now(-24 * 30), 150000)
    check("an oil change from before it was set saved", statuses == [201, 201], (statuses, bodies))
    check("it closes nothing", reminder_of(first_id).get("DoneAt") is None, reminder_of(first_id))
    brakes, statuses, bodies = oil_change(vehicle, anna, now(), 152000, tasks=("Brakes",))
    check("a service of another task closes nothing", statuses == [201, 201] and reminder_of(first_id).get("DoneAt") is None,
          (statuses, reminder_of(first_id)))
    service, statuses, bodies = oil_change(vehicle, anna, now(1), 152500)
    check("a service with an item of the task, saved", statuses == [201, 201], (statuses, bodies))
    first_service = service
    done = reminder_of(first_id)
    status, by = request("GET", "Records(%s)/Default.Reminder/Event" % first_id)
    check("automatic completion: the reminder done by it, at its moment and distance",
          done.get("DoneAt", "")[:16] == service["Timestamp"][:16] and done.get("DoneMileageQuantity") == 152500
          and status == 200 and by.get("Id", "").lower() == service["Id"], (done, status, by))
    next_id = named("next of " + first_id)
    after = reminder_of(next_id)
    due = months_on(datetime.date.fromisoformat(service["Timestamp"][:10]), 12).isoformat()
    check("and its next made, named by it, due from it", after is not None and after.get("DueMileageQuantity") == 167500
          and after.get("DueDate", "")[:10] == due and after.get("DoneAt") is None, after)

    status, body = action("Records(%s)" % first_id, "Complete")
    check("Complete of one done is refused", status == 400 and "done already" in json.dumps(body), (status, body))
    status, moved = action("Records(%s)" % next_id, "Reschedule", {"DueDate": "2028-01-15T00:00:00Z", "Note": "away"})
    check("Reschedule: moved, what it was due on recorded, named by it",
          status == 200 and moved.get("Id", "").lower() == named(next_id + " rescheduled 1") and moved.get("FromDate", "")[:10] == due
          and moved.get("Note") == "away" and reminder_of(next_id).get("DueDate", "")[:10] == "2028-01-15", (status, moved))
    status, replacement = action("Records(%s)" % next_id, "Cancel", {"ReplacementDueDate": "2028-03-01T00:00:00Z"})
    check("Cancel: cancelled today, a replacement named by it", status == 200
          and replacement.get("Id", "").lower() == named("replacement of " + next_id) and replacement.get("DueDate", "")[:10] == "2028-03-01"
          and (reminder_of(next_id).get("CancelDate") or "")[:10] == now()[:10], (status, replacement))
    replacement_id = named("replacement of " + next_id)
    status, replaced = request("GET", "Records(%s)/Default.Reminder/Replaced" % replacement_id)
    status2, of = request("GET", "Records(%s)/Default.Reminder/Schedule" % replacement_id)
    check("it replaces the one cancelled, of the same schedule", replaced.get("Id", "").lower() == next_id
          and of.get("Id", "").lower() == sid, (replaced, of))

    service, statuses, bodies = oil_change(vehicle, anna, now(2), 153000)
    later = named("next of " + replacement_id)
    check("the replacement closed by the next oil change, its next made", reminder_of(replacement_id).get("DoneAt")
          and reminder_of(later) is not None, reminder_of(replacement_id))
    status, body = request("PATCH", "Records(%s)" % later, {"@odata.type": "#Default.Reminder", "Note": "5W-30"})
    check("the next one noted", status in (200, 204), (status, body))
    status, body = action("Records(%s)" % service["Id"], "Discard")
    check("Discard: refused, 409, the next reminder touched since, named", status == 409
          and body.get("error", {}).get("code") == "NextReminderTouched" and body["error"].get("target") == later, (status, body))
    check("nothing of it done", reminder_of(service["Id"]) is not None and reminder_of(later) is not None)
    status, body = action("Records(%s)" % service["Id"], "Discard", {"KeepNextReminder": False})
    check("Discard, the next deleted all the same: the replacement reopened", status == 204 and reminder_of(service["Id"]) is None
          and reminder_of(later) is None and reminder_of(replacement_id).get("DoneAt") is None, (status, body))
    service, statuses, bodies = oil_change(vehicle, anna, now(3), 153100)
    check("closed again", reminder_of(replacement_id).get("DoneAt") is not None and reminder_of(later) is not None)
    status, body = action("Records(%s)" % service["Id"], "Discard")
    check("Discard, the next untouched: deleted with it, the replacement reopened", status == 204
          and reminder_of(later) is None and reminder_of(replacement_id).get("DoneAt") is None, (status, body))
    status, body = action("Records(%s)" % replacement_id, "Complete", {"DoneAt": now(4)})
    check("Complete with no event is refused: a reminder is done by an event", status == 400, (status, body))
    one_off = reminder(vehicle, anna, Task="Brakes", set=now(-1))
    check("a one-off for the brakes, set before the brakes were done", request("POST", "Records", one_off)[0] == 201)
    check("saving it closes nothing", reminder_of(one_off["Id"]).get("DoneAt") is None)
    status, body = action("Records(%s)" % one_off["Id"], "Complete", {"Event": {"@odata.id": "Records(%s)" % first_service["Id"]}})
    check("Complete by a service of another task is refused", status == 400, (status, body))
    status, body = action("Records(%s)" % one_off["Id"], "Complete", {"Event": {"@odata.id": "Records(%s)" % brakes["Id"]}})
    check("Complete by the brakes service: closed, no next", status == 204
          and (reminder_of(one_off["Id"]).get("DoneAt") or "")[:16] == brakes["Timestamp"][:16], (status, body))
    status, body = request("PATCH", "Records(%s)" % brakes["Id"], {"@odata.type": "#Default.Service", "Timestamp": now(-72)})
    check("the service moved to before the one-off was set", status in (200, 204), (status, body))
    check("moving it reopens the one-off", reminder_of(one_off["Id"]).get("DoneAt") is None, reminder_of(one_off["Id"]))


def continued(anna):
    """A schedule changed by the Continue action: a new one going on from
    it, the open reminder due anew in it; the next closing of the work
    closes it there."""
    made = vehicle_body(anna)
    check("a vehicle for a changed schedule", request("POST", "Vehicles", made)[0] == 201)
    vehicle = made["Id"]
    schedule = oil_schedule(vehicle, anna)
    request("POST", "Records", schedule)
    sid = schedule["Id"]
    status, first = action("Records(%s)" % sid, "Start", {"LastDoneAt": "2026-06-01T10:00:00Z", "LastDoneMileage": 148000,
                                                          "LastDoneMileageUnit": "km"})
    service, statuses, bodies = oil_change(vehicle, anna, now(), 150000)
    check("started, and an oil change closes its first", status == 200 and statuses == [201, 201], (status, statuses, bodies))
    next_id = named("next of " + named("start of " + sid))
    status, new = action("Records(%s)" % sid, "Continue", {"Task": "Oil change", "Interval": 10000, "IntervalUnit": "km",
                                                           "Months": 6, "Note": "older engine"})
    new_id = named("continuation of " + sid)
    check("Continue: a new schedule, named by the old one, its intervals and note", status == 200
          and new.get("Id", "").lower() == new_id and new.get("Duration") == 6 and new.get("IntervalQuantity") == 10000
          and new.get("Note") == "older engine", (status, new))
    status, of = request("GET", "Records(%s)/Default.Reminder/Schedule" % next_id)
    moved = reminder_of(next_id)
    check("the open reminder goes with it, due 10000 km on from where it is counted from", status == 200
          and of.get("Id", "").lower() == new_id and moved.get("DueMileageQuantity") == 160000
          and moved.get("CountedFromMileageQuantity") == 150000, (of, moved))
    status, continued_from = request("GET", "Records(%s)/Default.Schedule/Continued" % new_id)
    check("the new one goes on from the old", status == 200 and continued_from.get("Id", "").lower() == sid, continued_from)
    status, body = action("Records(%s)" % sid, "Continue", {"Task": "Oil change", "Months": 3})
    check("changing the old one again is refused", status == 400 and "changed already" in json.dumps(body), (status, body))
    service, statuses, bodies = oil_change(vehicle, anna, now(2), 159000)
    after = reminder_of(named("next of " + next_id))
    status, of = request("GET", "Records(%s)/Default.Reminder/Schedule" % named("next of " + next_id))
    check("an oil change after closes it there, the next made by the new one: 10000 km on",
          reminder_of(next_id).get("DoneMileageQuantity") == 159000 and after is not None and after.get("DueMileageQuantity") == 169000
          and of.get("Id", "").lower() == new_id, (reminder_of(next_id), after, of))
    check("a kind of expense for a changed schedule",
          request("POST", "CostKinds", {"@odata.type": "#Default.ExpenseKind", "Name": "Oil top-up"})[0] == 201)
    status, again = action("Records(%s)" % new_id, "Continue", {"ExpenseKind": {"@odata.id": "CostKinds('Oil top-up')"}, "Months": 1})
    status2, kind = request("GET", "Records(%s)/Default.Schedule/ExpenseKind" % named("continuation of " + new_id))
    check("Continue again, for a kind of expense given by reference", status == 200 and status2 == 200
          and kind.get("Name") == "Oil top-up", (status, again, kind))


def who_may():
    anna, ben, cid = "anna@example.org", "ben@example.org", "cid@example.org"
    status, body = request("GET", "Vehicles")
    check("no one signed in is refused", status == 401, (status, body))
    status, metadata = request("GET", "$metadata")
    check("but reads $metadata, which says where to sign in", status == 200 and ISSUER.url in str(metadata),
          (status, str(metadata)[:300]))
    check("a user adds themselves", request("POST", "Users", {"Email": ben, "PersonName": "Ben"}, user=ben)[0] == 201)
    check("another by their email", request("POST", "Users", {"Email": "dee@example.org"}, user=cid)[0] == 201)
    status, body = request("POST", "Users", {"Email": "eve@example.org", "PersonName": "Eve"}, user=cid)
    check("and nothing else of them", status == 403, (status, body))
    status, body = request("PATCH", "Users('%s')" % ben, {"PersonName": "B."}, user=cid)
    check("nor changes them", status == 403, (status, body))
    # Anna's vehicle, though the request names Ben its owner.
    made = vehicle_body(ben)
    status, body = request("POST", "Vehicles", made, user=anna)
    check("a vehicle is its maker's", status == 201, body)
    vehicle = made["Id"]
    status, owner = request("GET", "Vehicles(%s)/Owner" % vehicle, user=anna)
    check("whatever the request says", status == 200 and owner.get("Email") == anna, (status, owner))

    status, body = request("GET", "Vehicles", user=cid)
    check("Cid sees no vehicle of Anna's", status == 200 and body["value"] == [], (status, body))
    status, body = request("GET", "Vehicles(%s)" % vehicle, user=ben)
    check("nor Ben, before it is shared", status == 404, (status, body))
    sharing = {"Vehicle@odata.bind": "Vehicles(%s)" % vehicle, "User@odata.bind": "Users('%s')" % ben}
    status, body = request("POST", "VehicleDrivers", sharing, user=ben)
    check("Ben shares it with no one", status in (400, 403), (status, body))
    status, body = request("POST", "VehicleDrivers", sharing, user=anna)
    check("Anna shares it with Ben", status == 201, (status, body))
    status, body = request("GET", "Vehicles", user=ben)
    check("Ben sees it", status == 200 and [v["Id"].lower() for v in body["value"]] == [vehicle], (status, body))

    # Ben's record, though the request says Anna entered it.
    his = tyre_set(vehicle, "Ben's set", "Winter", anna)
    status, body = request("POST", "Records", his, user=ben)
    check("Ben adds a record", status == 201, (status, body))
    status, entered = request("GET", "Records(%s)/EnteredBy" % his["Id"], user=anna)
    check("entered by him", status == 200 and entered.get("Email") == ben, (status, entered))
    status, body = request("PATCH", "Records(%s)" % his["Id"], {"Note": "mine"}, user=ben)
    check("he changes none", status == 403, (status, body))
    status, body = request("DELETE", "Records(%s)" % his["Id"], user=ben)
    check("nor removes one", status == 403, (status, body))
    status, body = request("PATCH", "Records(%s)" % his["Id"], {"Note": "seen"}, user=anna)
    check("Anna, the owner, changes his", status in (200, 204), (status, body))
    status, body = request("POST", "Records", tyre_set(vehicle, "Cid's set", "Summer", cid), user=cid)
    check("Cid adds none", status in (400, 403, 404), (status, body))
    status, body = request("POST", "DistanceUnits", {"Code": "nmi", "Factor": 1.852}, user=anna)
    check("the units are the app's", status == 403, (status, body))
    status, body = request("POST", "CostKinds", {"Name": "Parking"}, user=ben)
    check("Ben adds a kind of cost", status == 201, (status, body))
    status, body = request("POST", "CostKinds", {"@odata.type": "#Default.ExpenseKind", "Name": "Tolls"}, user=cid)
    check("Cid a kind of expense", status == 201, (status, body))
    status, body = request("DELETE", "CostKinds('Parking')", user=ben)
    check("which no one removes, nor changes (its name is all it has)", status == 403, (status, body))
    status, body = request("DELETE", "CostKinds('Maintenance')", user=anna)
    check("nor the model's kinds", status == 403, (status, body))
    procedures_who_may(anna, ben, cid, vehicle)
    stock_who_may(anna, ben, cid, "dee@example.org")


def procedures_who_may(anna, ben, cid, vehicle):
    """Who may call each action: whoever drives the vehicle closes and
    moves its reminders; its owner starts, cancels and discards. A driver's
    service closes the owner's reminder all the same."""
    schedule = oil_schedule(vehicle, anna)
    status, body = request("POST", "Records", schedule, user=anna)
    check("Anna's schedule", status == 201, (status, body))
    sid = schedule["Id"]
    status, body = action("Records(%s)" % sid, "Start", user=ben)
    check("Ben starts none of Anna's schedules", status == 403, (status, body))
    status, body = action("Records(%s)" % sid, "Start", user=cid)
    check("nor Cid, who does not see it", status in (403, 404), (status, body))
    status, first = action("Records(%s)" % sid, "Start", {"LastDoneMileage": 140000, "LastDoneMileageUnit": "km"}, user=anna)
    check("Anna starts it", status == 200 and first.get("DueMileageQuantity") == 155000, (status, first))
    first_id = named("start of " + sid)
    service, statuses, bodies = oil_change(vehicle, ben, now(1), 141000, as_user=ben)
    check("Ben's oil change saved", statuses == [201, 201], (statuses, bodies))
    done = reminder_of(first_id, user=anna)
    next_id = named("next of " + first_id)
    check("it closes Anna's reminder, and makes the next", done.get("DoneMileageQuantity") == 141000
          and reminder_of(next_id, user=anna) is not None, done)
    status, moved = action("Records(%s)" % next_id, "Reschedule", {"DueMileage": 160000}, user=ben)
    check("Ben moves the next", status == 200 and moved.get("FromMileageQuantity") == 156000, (status, moved))
    status, by = request("GET", "Reschedulings(%s)/MadeBy" % named(next_id + " rescheduled 1"), user=anna)
    check("moved by him", status == 200 and by.get("Email") == ben, (status, by))
    status, body = action("Records(%s)" % next_id, "Reschedule", {"DueMileage": 161000}, user=cid)
    check("Cid moves none", status in (403, 404), (status, body))
    status, body = action("Records(%s)" % next_id, "Cancel", user=ben)
    check("Ben cancels none", status == 403, (status, body))
    status, body = action("Records(%s)" % service["Id"], "Discard", user=ben)
    check("nor discards his own record", status == 403, (status, body))
    status, body = action("Records(%s)" % service["Id"], "Discard", user=anna)
    check("Anna discards it: refused while its next is moved", status == 409 and body["error"]["code"] == "NextReminderTouched",
          (status, body))
    status, body = action("Records(%s)" % service["Id"], "Discard", {"KeepNextReminder": True}, user=anna)
    check("keeping the next is refused: a reminder is done only by an event", status == 400, (status, body))
    status, body = action("Records(%s)" % service["Id"], "Discard", {"KeepNextReminder": False}, user=anna)
    check("the next deleted too: the first reopened", status == 204 and reminder_of(first_id, user=anna).get("DoneAt") is None
          and reminder_of(next_id, user=anna) is None, (status, body))
    oil_change(vehicle, ben, now(2), 141500, as_user=ben)
    check("Ben's next oil change closes it again", reminder_of(first_id, user=anna).get("DoneMileageQuantity") == 141500)
    status, body = action("Records(%s)" % first_id, "Complete", {"Event": {"@odata.id": "Records(%s)" % service["Id"]}}, user=ben)
    check("Complete of one done is refused", status == 400, (status, body))
    status, body = action("Records(%s)" % first_id, "Cancel", user=anna)
    check("a done one is not cancelled", status == 400, (status, body))



def stock_who_may(anna, ben, cid, dee):
    """Who may see and write a catalog's stock, and call its actions."""
    catalog = {"Id": str(uuid.uuid4()), "CatalogName": "Workshop", "DocumentPrefix": "GAR", "Currency": "USD"}
    status, body = request("POST", "Catalogs", catalog, user=anna)
    check("a catalog is its maker's", status == 201, (status, body))
    cat = "Catalogs(%s)" % catalog["Id"]
    status, owner = request("GET", cat + "/CatalogOwner", user=anna)
    check("Anna owns it", status == 200 and owner.get("Email") == anna, (status, owner))
    garage = {"Id": str(uuid.uuid4()), "WarehouseName": "Garage", "Catalog@odata.bind": cat}
    check("Anna's garage", request("POST", "Warehouses", garage, user=anna)[0] == 201)
    shelves = []
    for name in ("Shelf A", "Shelf B"):
        shelf = {"Id": str(uuid.uuid4()), "LocationName": name, "Warehouse@odata.bind": "Warehouses(%s)" % garage["Id"]}
        check("its " + name, request("POST", "Locations", shelf, user=anna)[0] == 201)
        shelves.append(shelf["Id"])
    a, b = ("Locations(%s)" % shelf for shelf in shelves)
    for user, role in ((ben, "Keeper"), (dee, "Manager")):
        staff = {"Id": str(uuid.uuid4()), "StaffRole": role, "User@odata.bind": "Users('%s')" % user,
                 "Warehouse@odata.bind": "Warehouses(%s)" % garage["Id"]}
        status, body = request("POST", "WarehouseStaffs", staff, user=anna)
        check("%s works there, %s" % (user, role.lower()), status == 201, (status, body))
    status, body = request("POST", "Warehouses", dict(garage, Id=str(uuid.uuid4())), user=ben)
    check("Ben, of its staff, makes no warehouse of hers", status == 403, (status, body))
    status, body = request("GET", "Catalogs", user=cid)
    check("Cid sees no catalog of Anna's", status == 200 and body["value"] == [], (status, body))
    status, body = request("GET", "Catalogs", user=ben)
    check("Ben, of its staff, sees it", status == 200 and [c["Id"].lower() for c in body["value"]] == [catalog["Id"]],
          (status, body))
    bolt = {"Id": str(uuid.uuid4()), "ItemName": "Bolt", "Created": now(), "Catalog@odata.bind": cat}
    status, body = request("POST", "StockItems", bolt, user=anna)
    check("Anna's bolts, their SKU given: GAR-00001", status == 201 and body.get("SKU", body.get("Sku")) == "GAR-00001", (status, body))
    status, body = request("POST", "StockItems", dict(bolt, Id=str(uuid.uuid4()), ItemName="Nut"), user=ben)
    check("Ben adds no items", status == 403, (status, body))
    item = "StockItems(%s)" % bolt["Id"]

    status, body = action(item, "Adjust", {"Quantity": 20, "At": {"@odata.id": a}, "Reason": "Opening"}, user=ben)
    check("Ben brings 20 bolts in", status == 200 and body.get("Moved") == 20, (status, body))
    status, held = request("GET", "Holdings(%s)" % named("%s at %s" % (bolt["Id"], shelves[0])), user=ben)
    check("their holding, named by item and shelf: 20", status == 200 and held.get("Quantity") == 20, (status, held))
    status, body = action(item, "Adjust", {"Quantity": 1, "At": {"@odata.id": a}, "Reason": "Found"}, user=cid)
    check("Cid adjusts nothing", status in (403, 404), (status, body))
    status, body = action(item, "Transfer", {"Quantity": 25, "From": {"@odata.id": a}, "To": {"@odata.id": b}}, user=ben)
    check("25 bolts of 20 moved is refused, said so", status == 400 and "holds 20" in body["error"]["message"], (status, body))
    status, moved = action(item, "Transfer", {"Quantity": 5, "From": {"@odata.id": a}, "To": {"@odata.id": b}}, user=ben)
    check("Ben moves 5 to B", status == 200, (status, moved))
    status, body = request("PATCH", "Moves(%s)" % moved["Id"], {"Note": "mine"}, user=ben)
    check("and changes no move: a manager's", status == 403, (status, body))
    status, body = request("PATCH", "Moves(%s)" % moved["Id"], {"Note": "checked"}, user=dee)
    check("Dee, managing there, notes it", status in (200, 204), (status, body))

    contact = {"Id": str(uuid.uuid4()), "ContactName": "Bob's Garage", "Catalog@odata.bind": cat}
    check("Anna's contact", request("POST", "Contacts", contact, user=anna)[0] == 201)
    customer = {"Id": str(uuid.uuid4()), "Contact@odata.bind": "Contacts(%s)" % contact["Id"], "Catalog@odata.bind": cat}
    check("a customer of hers", request("POST", "Customers", customer, user=anna)[0] == 201)
    order = {"Id": str(uuid.uuid4()), "SaleOrdered": now(), "OrderState": "Draft", "Catalog@odata.bind": cat,
             "Customer@odata.bind": "Customers(%s)" % customer["Id"]}
    status, body = request("POST", "SaleOrders", order, user=ben)
    check("Ben orders nothing", status == 403, (status, body))
    status, body = request("POST", "SaleOrders", order, user=dee)
    check("Dee does: numbered, given none", status == 201 and body.get("RunningNumber") == 1, (status, body))
    line = {"Id": str(uuid.uuid4()), "Quantity": 3, "LinePriceAmount": 2, "LinePriceCurrency": "USD",
            "SaleOrder@odata.bind": "SaleOrders(%s)" % order["Id"], "StockItem@odata.bind": item}
    check("its line, 3 bolts", request("POST", "SaleLines", line, user=dee)[0] == 201)
    sale = "SaleOrders(%s)" % order["Id"]
    status, body = action(sale, "Confirm", user=ben)
    check("Ben confirms none", status == 403, (status, body))
    status, body = action(sale, "Confirm", user=dee)
    check("Dee confirms it", status == 200 and body.get("OrderState") == "Confirmed", (status, body))
    status, body = action(sale, "Ship", {"Lines": {line["Id"]: 3}, "From": {"@odata.id": b}}, user=ben)
    check("3 from B, of 5: Ben ships them", status == 200 and body.get("RunningNumber") == 1, (status, body))
    status, shipped = request("GET", sale, user=dee)
    check("the order fully shipped", status == 200 and shipped.get("IsFullyShipped") is True, (status, shipped))
    status, body = action(sale, "Ship", {"Lines": {line["Id"]: 1}, "From": {"@odata.id": b}}, user=cid)
    check("Cid ships nothing", status in (403, 404), (status, body))

    found = [{"Item": bolt["Id"], "Location": shelves[0], "Quantity": 14}]
    status, body = action("Warehouses(%s)" % garage["Id"], "Count", {"Location": {"@odata.id": a}, "Found": found}, user=ben)
    check("Ben counts shelf A: 14 of 15", status == 200 and body.get("RunningNumber") == 1, (status, body))
    status, held = request("GET", "Holdings(%s)" % named("%s at %s" % (bolt["Id"], shelves[0])), user=ben)
    check("A holds 14", status == 200 and held.get("Quantity") == 14, (status, held))
    status, body = action("Warehouses(%s)" % garage["Id"], "Reorder", user=ben)
    check("Ben reorders nothing", status == 403, (status, body))
    status, body = action("Warehouses(%s)" % garage["Id"], "Reorder", user=dee)
    check("Dee reorders: nothing due", status == 200 and body.get("value") == [], (status, body))

try:
    server = serve()
    try:
        the_rules()
    finally:
        stop(server)
    if not os.environ.get("LB_SERVICE_ROOT"):
        ISSUER = Issuer()
        server = serve("-JWTIssuer", ISSUER.url, "-AllowAnonymous", "NO")
        try:
            who_may()
        finally:
            stop(server)
            ISSUER.close()
finally:
    if failures:
        for log in logs:
            log.seek(0)
            print(log.read())

sys.exit(1 if failures else 0)
