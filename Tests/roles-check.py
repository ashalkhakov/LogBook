#!/usr/bin/env python3
"""Who works a process's tasks: as the logbook's permissions say
(Logbook.permissions.plist; Server/LBWorkflow.h).

    Tests/roles-check.py build/logbook-server

On a server of its own, signed in by a proxy's header (TrustedUserHeader
X-User: whoever it names is asking), a temporary store, on a free port on
loopback. Anna owns a catalog; Dave manages its warehouse, Bob keeps it,
Carl is no one of it.

- a draft purchase order of the catalog starts procure to receipt: Confirm
  the order is offered to its managers, Anna and Dave, not Bob or Carl;
  Bob cannot submit its form;
- confirmed (its form submitted, by Dave): Receive the goods is offered to
  its keepers, Anna, Dave and Bob, not Carl;
- each signed-in user works their task list without the identity
  provider's saying so (Tasks.Work): which tasks are theirs is the
  logbook's.
"""
import json
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

ANNA, BOB, CARL, DAVE = "anna@example.org", "bob@example.org", "carl@example.org", "dave@example.org"


def check(what, ok, detail=""):
    print(("ok   " if ok else "FAIL ") + what + ("" if ok else ": " + str(detail)))
    if not ok:
        failures.append(what)


def free_port():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def request(method, url, body=None, user=ANNA):
    data = json.dumps(body).encode() if body is not None else None
    r = urllib.request.Request(url, data=data, method=method,
                               headers={"Content-Type": "application/json", "Accept": "application/json", "X-User": user})
    try:
        with urllib.request.urlopen(r, timeout=30) as response:
            text = response.read().decode()
            return response.status, json.loads(text) if text else None
    except urllib.error.HTTPError as e:
        text = e.read().decode()
        try:
            return e.code, json.loads(text) if text else None
        except ValueError:
            return e.code, text


def main():
    port = free_port()
    odata, workflow = "http://127.0.0.1:%d/odata/" % port, "http://127.0.0.1:%d/workflow/" % port
    log = tempfile.TemporaryFile(mode="w+")
    server = subprocess.Popen([SERVER, "-StoreURL", "Temporary", "-Port", str(port), "-Localhost", "YES", "-TrustedUserHeader", "X-User"],
                              stdout=log, stderr=subprocess.STDOUT, text=True)
    try:
        for _ in range(600):
            try:
                urllib.request.urlopen(urllib.request.Request(odata, headers={"X-User": ANNA}), timeout=1).read()
                break
            except Exception:
                if server.poll() is not None:
                    log.seek(0)
                    sys.exit("the server stopped: " + log.read())
                time.sleep(0.1)
        walk(odata, workflow)
    finally:
        server.terminate()
        server.wait()
        if failures:
            log.seek(0)
            print("the server's log:\n" + log.read())
    print("roles: %d failed" % len(failures))
    sys.exit(1 if failures else 0)


def walk(odata, workflow):
    def tasks(user):
        status, body = request("GET", workflow + "Tasks", user=user)
        return [(t["Name"], t["TaskId"]) for t in (body or {}).get("value", [])] if status == 200 else [("?", status, str(body))]

    def names(user):
        return [t[0] for t in tasks(user)]

    def settled(user, expected):
        """The user's open tasks' names, once they are as expected, or 5s on."""
        found = None
        for _ in range(100):
            found = names(user)
            if found == expected:
                break
            time.sleep(0.05)
        return found

    catalog, supplier, warehouse, shelf, item, order, line = (str(uuid.uuid4()) for _ in range(7))
    for what, path, body in (
            ("Anna's catalog", "Catalogs", {"Id": catalog, "CatalogName": "Workshop", "DocumentPrefix": "GAR", "Currency": "USD"}),
            ("Bob, by his email", "Users", {"Email": BOB}),
            ("Carl", "Users", {"Email": CARL}),
            ("Dave", "Users", {"Email": DAVE}),
            ("a supplier", "Suppliers", {"Id": supplier, "Catalog@odata.bind": "Catalogs(%s)" % catalog}),
            ("a warehouse", "Warehouses", {"Id": warehouse, "WarehouseName": "Garage", "Catalog@odata.bind": "Catalogs(%s)" % catalog}),
            ("its shelf", "Locations", {"Id": shelf, "LocationName": "Shelf", "Warehouse@odata.bind": "Warehouses(%s)" % warehouse}),
            ("Dave its manager", "WarehouseStaffs", {"Id": str(uuid.uuid4()), "StaffRole": "Manager", "User@odata.bind": "Users('%s')" % DAVE,
                                                     "Warehouse@odata.bind": "Warehouses(%s)" % warehouse}),
            ("Bob its keeper", "WarehouseStaffs", {"Id": str(uuid.uuid4()), "StaffRole": "Keeper", "User@odata.bind": "Users('%s')" % BOB,
                                                   "Warehouse@odata.bind": "Warehouses(%s)" % warehouse}),
            ("an item", "StockItems", {"Id": item, "ItemName": "Oil", "Sku": "GAR-1", "Created": "2026-11-10T10:00:00Z",
                                       "Catalog@odata.bind": "Catalogs(%s)" % catalog})):
        status, body = request("POST", odata + path, body)
        check(what, status == 201, (status, body))
    for user in (ANNA, BOB, CARL, DAVE):
        check("%s works a task list, no task yet" % user, names(user) == [], tasks(user))

    status, body = request("POST", odata + "PurchaseOrders", {
        "Id": order, "Ordered": "2026-11-10T10:00:00Z", "OrderState": "Draft", "RunningNumber": 1,
        "Catalog@odata.bind": "Catalogs(%s)" % catalog, "Supplier@odata.bind": "Suppliers(%s)" % supplier})
    check("a draft order saved", status == 201, (status, body))
    status, body = request("POST", odata + "PurchaseLines", {"Id": line, "Quantity": 4, "LineUnitCostAmount": 5, "LineUnitCostCurrency": "USD",
                                                            "PurchaseOrder@odata.bind": "PurchaseOrders(%s)" % order,
                                                            "StockItem@odata.bind": "StockItems(%s)" % item})
    check("its line", status == 201, (status, body))
    check("Confirm the order: Anna's, the catalog's owner", settled(ANNA, ["Confirm the order"]) == ["Confirm the order"], tasks(ANNA))
    check("and Dave's, its warehouse's manager", settled(DAVE, ["Confirm the order"]) == ["Confirm the order"], tasks(DAVE))
    check("not Bob's, a keeper", names(BOB) == [], tasks(BOB))
    check("nor Carl's", names(CARL) == [], tasks(CARL))
    confirm = tasks(DAVE)[0][1]

    def submit(task, user):
        instance = "<PurchaseOrder><id>%s</id><orderState>Confirmed</orderState></PurchaseOrder>" % order
        return request("POST", workflow + "Tasks('%s')/WorkflowKit.SubmitForm" % task, {"Instance": instance}, user=user)

    status, body = submit(confirm, BOB)
    check("Bob cannot submit its form", status in (403, 404), (status, body))
    status, body = request("PATCH", odata + "PurchaseOrders(%s)" % order, {"OrderState": "Confirmed"}, user=DAVE)
    check("Dave confirms it, as its form saves it", status == 204, (status, body))
    status, body = submit(confirm, DAVE)
    check("and submits its form", status == 204, (status, body))
    check("Receive the goods: Bob's, its keeper", settled(BOB, ["Receive the goods"]) == ["Receive the goods"], tasks(BOB))
    check("Dave's and Anna's, who keep what they manage",
          names(DAVE) == ["Receive the goods"] and names(ANNA) == ["Receive the goods"], (tasks(DAVE), tasks(ANNA)))
    check("not Carl's", names(CARL) == [], tasks(CARL))


if __name__ == "__main__":
    main()
