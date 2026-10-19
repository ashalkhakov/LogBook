#!/usr/bin/env python3
"""The server run, and asked over HTTP as a device would.

    Tests/serve-and-check.py build/logbook-server

Each part on a server of its own: a temporary store, on a free port on
loopback.

The rules, with no one signed in:
- the units every store starts with are there;
- a change set (a $batch atomicity group) of a vehicle's tyre sets and two
  tyre changes is saved whole, and the second change's removed set is the
  one the change before it fitted (derived and stored, at the end of the
  change set);
- a change set whose change fits the set the change before it fitted (so
  removes the set it fits) breaks a rule: refused, 400, and none of it
  saved; the same alone, as one request.

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
  no one removes.

LB_SERVICE_ROOT, when set, is a server already running (a store it can
fill), asked instead of one started here: the first part only.

LB_FRAMEWORK_PATH, when set, is the server's DYLD_FRAMEWORK_PATH: frameworks
built from an unreleased fix tried in place of the released ones. (macOS
drops DYLD_ variables on the way through a protected binary such as
/usr/bin/python3, so they are passed under another name.)
"""
import base64
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


def batch(group, requests):
    """One atomicity group: its responses' statuses and bodies."""
    status, answer = request("POST", "$batch", {"requests": [
        dict(id=str(i), atomicityGroup=group, method=method, url=url, body=body)
        for i, (method, url, body) in enumerate(requests)]})
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
