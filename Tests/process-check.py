#!/usr/bin/env python3
"""The server's processes (Server/LBWorkflow.h), run over HTTP as the app
runs them: procure to receipt (Model/ProcureToReceipt.bpmn).

    Tests/process-check.py build/logbook-server

On a server of its own, with no one signed in (its workflow API open to a
trial user): a temporary store, on a free port on loopback, its processes
from Logbook.wfdeployment beside it.

- a purchase order refused (it lacks its number) starts nothing;
- one saved as a draft starts procure to receipt: its first task, Confirm
  the order, is the managers', done with the model's ConfirmPurchaseOrder;
- the order confirmed (its Confirm): the server completes the task, the
  order's state given; Receive the goods, the keepers', done with
  ReceiveGoods;
- 3 of its 4 received (its Receive): the task completed, the process finds
  it not all received and asks to receive again;
- the last one received: it finds it all received, closes the order (its
  Close), and ends, no task left;
- another draft cancelled (its Cancel): its Confirm the order completed,
  and its process ends.

No task is completed through the workflow API: the processes follow the
facts, whoever changes them. The server's engine works after each save,
so each check waits a little for it.
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


def request(method, url, body=None):
    data = json.dumps(body).encode() if body is not None else None
    r = urllib.request.Request(url, data=data, method=method,
                               headers={"Content-Type": "application/json", "Accept": "application/json"})
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
    server = subprocess.Popen([SERVER, "-StoreURL", "Temporary", "-Port", str(port), "-Localhost", "YES"],
                              stdout=log, stderr=subprocess.STDOUT, text=True)
    try:
        for _ in range(600):
            try:
                urllib.request.urlopen(odata, timeout=1).read()
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
    print("processes: %d failed" % len(failures))
    sys.exit(1 if failures else 0)


def walk(odata, workflow):
    def tasks():
        status, body = request("GET", workflow + "Tasks")
        return [(t["Name"], t["TaskId"]) for t in (body or {}).get("value", [])] if status == 200 else [("?", str(body))]

    def settled(expected):
        """The open tasks' names, once they are as expected, or 5s on."""
        names = None
        for _ in range(100):
            names = [n for n, _ in tasks()]
            if names == expected:
                break
            time.sleep(0.05)
        return names

    catalog, supplier, warehouse, shelf, item, order, line = (str(uuid.uuid4()) for _ in range(7))
    for what, path, body in (
            ("a catalog", "Catalogs", {"Id": catalog, "CatalogName": "Workshop", "DocumentPrefix": "GAR", "Currency": "USD"}),
            ("its owner", "Users", {"Email": "anna@example.org"}),
            ("a supplier", "Suppliers", {"Id": supplier, "Catalog@odata.bind": "Catalogs(%s)" % catalog}),
            ("a warehouse", "Warehouses", {"Id": warehouse, "WarehouseName": "Garage", "Catalog@odata.bind": "Catalogs(%s)" % catalog}),
            ("its shelf", "Locations", {"Id": shelf, "LocationName": "Shelf", "Warehouse@odata.bind": "Warehouses(%s)" % warehouse}),
            ("an item", "StockItems", {"Id": item, "ItemName": "Oil", "Sku": "GAR-1", "Created": "2026-11-10T10:00:00Z",
                                       "Catalog@odata.bind": "Catalogs(%s)" % catalog})):
        status, body = request("POST", odata + path, body)
        check(what, status == 201, (status, body))
        if path == "Users":
            status, body = request("PATCH", odata + "Catalogs(%s)" % catalog, {"CatalogOwner@odata.bind": "Users('anna@example.org')"})
            check("its owner the catalog's", status == 204, (status, body))
    check("the workflow API answers, no task yet", tasks() == [], tasks())

    draft = {"Id": order, "Ordered": "2026-11-10T10:00:00Z", "OrderState": "Draft", "Catalog@odata.bind": "Catalogs(%s)" % catalog,
             "Supplier@odata.bind": "Suppliers(%s)" % supplier}
    status, body = request("POST", odata + "PurchaseOrders", draft)
    check("an order without its number refused", status == 400, (status, body))
    check("and starts nothing", settled(["?"]) == [], tasks())
    status, body = request("POST", odata + "PurchaseOrders", dict(draft, RunningNumber=1))
    check("a draft order saved", status == 201, (status, body))
    check("starts procure to receipt: Confirm the order", settled(["Confirm the order"]) == ["Confirm the order"], tasks())
    status, body = request("POST", odata + "PurchaseLines", {"Id": line, "Quantity": 4, "LineUnitCostAmount": 5, "LineUnitCostCurrency": "USD",
                                                            "PurchaseOrder@odata.bind": "PurchaseOrders(%s)" % order,
                                                            "StockItem@odata.bind": "StockItems(%s)" % item})
    check("its line, of 4", status == 201, (status, body))
    status, body = request("POST", odata + "PurchaseOrders(%s)/Default.Confirm" % order, {})
    check("confirmed", status == 200, (status, body))
    check("Confirm the order completed: then Receive the goods", settled(["Receive the goods"]) == ["Receive the goods"], tasks())

    first = tasks()[0][1]
    at = {"@odata.id": "Locations(%s)" % shelf}
    status, body = request("POST", odata + "PurchaseOrders(%s)/Default.Receive" % order, {"Lines": {line: 3}, "At": at})
    check("3 of 4 received", status == 200, (status, body))
    for _ in range(100):
        if [t for _, t in tasks()] != [first]:
            break
        time.sleep(0.05)
    again = tasks()
    check("not all received: Receive the goods again", [n for n, _ in again] == ["Receive the goods"] and again[0][1] != first, again)
    status, body = request("POST", odata + "PurchaseOrders(%s)/Default.Receive" % order, {"Lines": {line: 1}, "At": at})
    check("the last one received", status == 200, (status, body))
    check("all received: no task left", settled([]) == [], tasks())
    status, body = request("GET", odata + "PurchaseOrders(%s)?$select=OrderState,IsFullyReceived" % order)
    check("the order closed by the process", status == 200 and body.get("OrderState") == "Closed" and body.get("IsFullyReceived"),
          (status, body))


    other = str(uuid.uuid4())
    status, body = request("POST", odata + "PurchaseOrders", dict(draft, Id=other, RunningNumber=2))
    check("another draft saved", status == 201 and settled(["Confirm the order"]) == ["Confirm the order"], (status, body, tasks()))
    status, body = request("POST", odata + "PurchaseOrders(%s)/Default.Cancel" % other, {})
    check("cancelled", status == 200, (status, body))
    check("its Confirm the order completed: it ends, no task left", settled([]) == [], tasks())


if __name__ == "__main__":
    main()
