#!/usr/bin/env python3
"""The server run, and asked over HTTP as a device would.

    Tests/serve-and-check.py build/logbook-server

A temporary store, on a free port on loopback. What it checks:
- the units every store starts with are there;
- a change set (a $batch atomicity group) of a vehicle's tyre sets and two
  tyre changes is saved whole, and the second change's removed set is the
  one the change before it fitted (derived and stored, at the end of the
  change set);
- a change set whose change fits the set the change before it fitted (so
  removes the set it fits) breaks a rule: refused, 400, and none of it
  saved; the same alone, as one request.

LB_SERVICE_ROOT, when set, is a server already running (a store it can
fill), asked instead of one started here.

LB_FRAMEWORK_PATH, when set, is the server's DYLD_FRAMEWORK_PATH: frameworks
built from an unreleased fix tried in place of the released ones. (macOS
drops DYLD_ variables on the way through a protected binary such as
/usr/bin/python3, so they are passed under another name.)
"""
import json
import os
import socket
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
import uuid

SERVER = sys.argv[1] if len(sys.argv) > 1 else "build/logbook-server"
failures = []


def check(what, ok, detail=""):
    print(("ok   " if ok else "FAIL ") + what + ("" if ok else ": " + str(detail)))
    if not ok:
        failures.append(what)


def free_port():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def request(method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    r = urllib.request.Request(ROOT + path, data=data, method=method,
                               headers={"Content-Type": "application/json", "Accept": "application/json"})
    try:
        with urllib.request.urlopen(r, timeout=30) as response:
            text = response.read().decode()
            return response.status, json.loads(text) if text.startswith(("{", "[")) else text
    except urllib.error.HTTPError as e:
        text = e.read().decode()
        return e.code, json.loads(text) if text.startswith("{") else text


def batch(group, requests):
    """One atomicity group: its responses' statuses and bodies."""
    status, answer = request("POST", "$batch", {"requests": [
        dict(id=str(i), atomicityGroup=group, method=method, url=url, body=body)
        for i, (method, url, body) in enumerate(requests)]})
    if status != 200:
        return [status], [answer]
    return [r["status"] for r in answer["responses"]], [r.get("body") for r in answer["responses"]]


port = free_port()
ROOT = os.environ.get("LB_SERVICE_ROOT") or "http://127.0.0.1:%d/odata/" % port
environment = dict(os.environ)
if os.environ.get("LB_FRAMEWORK_PATH"):
    environment["DYLD_FRAMEWORK_PATH"] = os.environ["LB_FRAMEWORK_PATH"]
# Its log to a file: a pipe nobody reads would stop it once full.
log = tempfile.TemporaryFile(mode="w+")
server = subprocess.Popen(["true"] if os.environ.get("LB_SERVICE_ROOT") else [SERVER, "-StoreURL", "Temporary", "-Port", str(port), "-Localhost", "YES"],
                          stdout=log, stderr=subprocess.STDOUT, text=True, env=environment)
try:
    for _ in range(100):
        try:
            urllib.request.urlopen(ROOT, timeout=1).read()
            break
        except Exception:
            if server.poll() is not None:
                log.seek(0)
                sys.exit("the server stopped: " + log.read())
            time.sleep(0.1)

    status, units = request("GET", "DistanceUnits")
    check("the units are there", status == 200 and sorted(u["Code"] for u in units["value"]) == ["km", "mi"], units)

    anna = "Users('anna@example.org')"
    check("a user", request("POST", "Users", {"Email": "anna@example.org"})[0] == 201)
    vehicle = str(uuid.uuid4())
    status, body = request("POST", "Vehicles", {
        "Id": vehicle, "VehicleName": "Golf", "Make": "Volkswagen", "CarModel": "Golf VII", "ManufactureYear": 2016,
        "Fuel": "Petrol", "Owner@odata.bind": anna})
    check("a vehicle", status == 201, body)

    def tyre_set(name, season):
        return {"@odata.type": "#Default.TyreSet", "Id": str(uuid.uuid4()), "TyreSetName": name, "Season": season,
                "TyreModel": "Primacy 4", "TyreSize": "205/55 R16", "Vehicle@odata.bind": "Vehicles(%s)" % vehicle,
                "EnteredBy@odata.bind": anna}

    def tyre_change(fits, day, km):
        return {"@odata.type": "#Default.TyreChange", "Id": str(uuid.uuid4()),
                "Timestamp": "2026-%s T09:00:00Z".replace(" ", "") % day, "MileageQuantity": km,
                "MileageDistanceUnit@odata.bind": "DistanceUnits('km')", "Tread": 7,
                "TyreSet@odata.bind": "Records(%s)" % fits["Id"], "Driver@odata.bind": anna,
                "EnteredBy@odata.bind": anna, "Vehicle@odata.bind": "Vehicles(%s)" % vehicle}

    summer, winter = tyre_set("Summer set", "Summer"), tyre_set("Winter set", "Winter")
    april, november = tyre_change(summer, "04-01", 10000), tyre_change(winter, "11-01", 15000)
    statuses, bodies = batch("g1", [("POST", "Records", summer), ("POST", "Records", winter),
                                    ("POST", "Records", april), ("POST", "Records", november)])
    check("a change set of two sets and two changes is saved", statuses == [201] * 4, (statuses, bodies))
    status, removed = request("GET", "Records(%s)/Default.TyreChange/RemovedTyreSet" % november["Id"])
    check("the second change removed the set the first fitted (derived at save)",
          status == 200 and removed.get("Id", "").lower() == summer["Id"], (status, removed))
    status, removed = request("GET", "Records(%s)/Default.TyreChange/RemovedTyreSet" % april["Id"])
    check("the first removed none", status in (204, 404) or removed.get("value") is None, (status, removed))

    status, count = request("GET", "Records/$count")
    again = tyre_change(winter, "12-01", 16000)
    statuses, bodies = batch("g2", [("POST", "Records", again)])
    check("fitting the set fitted before is refused", statuses == [400], (statuses, bodies))
    check("none of it saved", request("GET", "Records/$count")[1] == count)
    status, body = request("POST", "Records", tyre_change(winter, "12-02", 16100))
    check("alone, too", status == 400 and request("GET", "Records/$count")[1] == count, (status, body))
    # A request's answer has each violation a detail; a batch's the message.
    message = json.dumps(body)
    check("the refusal names the rule", "removed the same TyreSet" in message, message)
finally:
    server.terminate()
    try:
        server.wait(timeout=10)
    except subprocess.TimeoutExpired:
        server.kill()
        server.wait()
    if failures:
        log.seek(0)
        print(log.read())

sys.exit(1 if failures else 0)
