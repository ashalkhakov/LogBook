#!/usr/bin/env python3
"""The server's processes (Server/LBWorkflow.h), run over HTTP as the app
runs them: procure to receipt (Model/ProcureToReceipt.bpmn), order to cash
(Model/OrderToCash.bpmn).

    Tests/process-check.py build/logbook-server

On a server of its own, with no one signed in (its workflow API open to a
trial user): a temporary store, on a free port on loopback, its processes
from Logbook.wfdeployment beside it.

- a purchase order refused (it lacks its number) starts nothing;
- one saved as a draft starts procure to receipt: its first task, Confirm
  the order, is the managers', done with the model's ConfirmPurchaseOrder;
- the order confirmed as the form saves it (its state Confirmed): the task
  still open, the facts alone completing nothing; the form's instance
  submitted (WorkflowKit.SubmitForm): the task completed, its orderState
  the process's; Receive the goods, the keepers', done with ReceiveGoods;
- 3 of its 4 received as ReceiveGoods saves them (a receipt and its moves,
  each move's item, place, moment and maker worked out by the model) and
  the instance submitted: the process finds it not all received and asks
  to receive again;
- the last one received the same way: it finds it all received, closes
  the order (its Close), and ends, no task left;
- another draft cancelled through its form: its process ends;
- a draft sale order starts order to cash: Confirm the order; confirming
  it with no lines refused (as Confirm refuses it); with a line, confirmed
  as ConfirmSaleOrder saves it and submitted: Ship the goods; 2 of its 3
  shipped as ShipGoods saves them (each move's item, place, maker and
  moment worked out as it saves): Ship the goods again; the last one: the
  order closed, no task left.

As the app does them: what a form saves is the logbook's, and its instance
submitted completes the task. The server's engine works after each save
and submission, so each check waits a little for it.
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
    def submit(task, root, values, rows=()):
        """The form's instance, as the app sends it, to the task."""
        def element(name, text):
            return "<%s>%s</%s>" % (name, text, name)
        xml = "".join(element(k, v) for k, v in values.items())
        for name, row in rows:
            xml += element(name, "".join(element(k, v) for k, v in row.items()))
        return request("POST", workflow + "Tasks('%s')/WorkflowKit.SubmitForm" % task, {"Instance": element(root, xml)})

    status, body = request("PATCH", odata + "PurchaseOrders(%s)" % order, {"OrderState": "Confirmed"})
    check("confirmed as its form saves it", status == 204, (status, body))
    time.sleep(0.3)
    confirm = tasks()
    check("the facts alone complete nothing: Confirm the order still open", [n for n, _ in confirm] == ["Confirm the order"], confirm)
    status, body = submit(confirm[0][1], "PurchaseOrder", {"id": order, "orderState": "Confirmed"})
    check("its form submitted to the task", status == 204, (status, body))
    check("Confirm the order completed: then Receive the goods", settled(["Receive the goods"]) == ["Receive the goods"], tasks())

    def receive(number, quantity, task):
        receipt, move = str(uuid.uuid4()), str(uuid.uuid4())
        status, body = request("POST", odata + "Receipts", {
            "Id": receipt, "RunningNumber": number, "Received": "2026-11-12", "Recorded": "2026-11-12T09:00:00Z",
            "PurchaseOrder@odata.bind": "PurchaseOrders(%s)" % order, "ReceivedAt@odata.bind": "Locations(%s)" % shelf,
            "RecordedBy@odata.bind": "Users('anna@example.org')",
            "Moves": [{"Id": move, "Moved": quantity, "PurchaseLine@odata.bind": "PurchaseLines(%s)" % line}]})
        check("%s received as ReceiveGoods saves it" % quantity, status == 201, (status, body))
        status, body = request("GET", odata + "Moves(%s)?$expand=StockItem($select=Id),Destination($select=Id),User($select=Email)" % move)
        check("its move's item, place and maker worked out", status == 200 and body.get("StockItem", {}).get("Id", "").lower() == item
              and body.get("Destination", {}).get("Id", "").lower() == shelf and body.get("User", {}).get("Email") == "anna@example.org"
              and body.get("Moment") == "2026-11-12T09:00:00Z", (status, body))
        status, body = submit(task, "Receipt", {"id": receipt, "purchaseOrder": order, "received": "2026-11-12", "receivedAt": shelf},
                              [("moves", {"id": move, "purchaseLine": line, "moved": str(quantity)})])
        check("its form submitted to the task", status == 204, (status, body))

    first = tasks()[0][1]
    receive(1, 3, first)
    for _ in range(100):
        if [t for _, t in tasks()] != [first]:
            break
        time.sleep(0.05)
    again = tasks()
    check("not all received: Receive the goods again", [n for n, _ in again] == ["Receive the goods"] and again[0][1] != first, again)
    receive(2, 1, again[0][1])
    check("all received: no task left", settled([]) == [], tasks())
    status, body = request("GET", odata + "PurchaseOrders(%s)?$select=OrderState,IsFullyReceived" % order)
    check("the order closed by the process", status == 200 and body.get("OrderState") == "Closed" and body.get("IsFullyReceived"),
          (status, body))

    other = str(uuid.uuid4())
    status, body = request("POST", odata + "PurchaseOrders", dict(draft, Id=other, RunningNumber=2))
    check("another draft saved", status == 201 and settled(["Confirm the order"]) == ["Confirm the order"], (status, body, tasks()))
    status, body = request("PATCH", odata + "PurchaseOrders(%s)" % other, {"OrderState": "Cancelled"})
    check("cancelled as its form saves it", status == 204, (status, body))
    status, body = submit(tasks()[0][1], "PurchaseOrder", {"id": other, "orderState": "Cancelled"})
    check("its form submitted to the task", status == 204, (status, body))
    check("its Confirm the order completed: it ends, no task left", settled([]) == [], tasks())

    # Order to cash: what the shelf holds to begin with, a customer.
    contact, customer, sale, sold = (str(uuid.uuid4()) for _ in range(4))
    for what, path, body in (
            ("10 of the oil on the shelf to begin with", "Moves", {
                "Id": str(uuid.uuid4()), "Moved": 10, "AdjustmentReason": "Opening", "Moment": "2026-11-12T08:00:00Z",
                "StockItem@odata.bind": "StockItems(%s)" % item, "Destination@odata.bind": "Locations(%s)" % shelf,
                "User@odata.bind": "Users('anna@example.org')"}),
            ("a customer's contact", "Contacts", {"Id": contact, "ContactName": "Bob", "Catalog@odata.bind": "Catalogs(%s)" % catalog}),
            ("the customer", "Customers", {"Id": customer, "Catalog@odata.bind": "Catalogs(%s)" % catalog,
                                           "Contact@odata.bind": "Contacts(%s)" % contact})):
        status, body = request("POST", odata + path, body)
        check(what, status == 201, (status, body))
    status, body = request("POST", odata + "SaleOrders", {
        "Id": sale, "SaleOrdered": "2026-11-12", "OrderState": "Draft", "RunningNumber": 1,
        "Catalog@odata.bind": "Catalogs(%s)" % catalog, "Customer@odata.bind": "Customers(%s)" % customer})
    check("a draft sale saved", status == 201, (status, body))
    check("starts order to cash: Confirm the order", settled(["Confirm the order"]) == ["Confirm the order"], tasks())
    status, body = request("PATCH", odata + "SaleOrders(%s)" % sale, {"OrderState": "Confirmed"})
    check("confirmed with no line: refused, as Confirm refuses it", status == 400 and "nothing" in json.dumps(body), (status, body))
    status, body = request("POST", odata + "SaleLines", {"Id": sold, "Quantity": 3, "LinePriceAmount": 2, "LinePriceCurrency": "USD",
                                                        "SaleOrder@odata.bind": "SaleOrders(%s)" % sale,
                                                        "StockItem@odata.bind": "StockItems(%s)" % item})
    check("its line, of 3", status == 201, (status, body))
    status, body = request("PATCH", odata + "SaleOrders(%s)" % sale, {"OrderState": "Confirmed"})
    check("confirmed as ConfirmSaleOrder saves it", status == 204, (status, body))
    status, body = submit(tasks()[0][1], "SaleOrder", {"id": sale, "orderState": "Confirmed"})
    check("its form submitted to the task", status == 204, (status, body))
    check("then Ship the goods", settled(["Ship the goods"]) == ["Ship the goods"], tasks())

    def ship(number, quantity, task):
        shipment, move = str(uuid.uuid4()), str(uuid.uuid4())
        status, body = request("POST", odata + "Shipments", {
            "Id": shipment, "RunningNumber": number, "Shipped": "2026-11-13", "ShipmentRecorded": "2026-11-13T09:00:00Z",
            "SaleOrder@odata.bind": "SaleOrders(%s)" % sale, "ShippedFrom@odata.bind": "Locations(%s)" % shelf,
            "ShippedBy@odata.bind": "Users('anna@example.org')",
            "Moves": [{"Id": move, "Moved": quantity, "SaleLine@odata.bind": "SaleLines(%s)" % sold}]})
        check("%s shipped as ShipGoods saves it" % quantity, status == 201, (status, body))
        status, body = request("GET", odata + "Moves(%s)?$expand=StockItem($select=Id),Source($select=Id),User($select=Email)" % move)
        check("its move's item, place, maker and moment worked out", status == 200 and body.get("StockItem", {}).get("Id", "").lower() == item
              and body.get("Source", {}).get("Id", "").lower() == shelf and body.get("User", {}).get("Email") == "anna@example.org"
              and body.get("Moment") == "2026-11-13T09:00:00Z", (status, body))
        status, body = submit(task, "Shipment", {"id": shipment, "saleOrder": sale, "shipped": "2026-11-13", "shippedFrom": shelf},
                              [("moves", {"id": move, "saleLine": sold, "moved": str(quantity)})])
        check("its form submitted to the task", status == 204, (status, body))

    first = tasks()[0][1]
    ship(1, 2, first)
    for _ in range(100):
        if [t for _, t in tasks()] != [first]:
            break
        time.sleep(0.05)
    again = tasks()
    check("not all shipped: Ship the goods again", [n for n, _ in again] == ["Ship the goods"] and again[0][1] != first, again)
    ship(2, 1, again[0][1])
    check("all shipped: no task left", settled([]) == [], tasks())
    status, body = request("GET", odata + "SaleOrders(%s)?$select=OrderState,IsFullyShipped" % sale)
    check("the sale closed by the process", status == 200 and body.get("OrderState") == "Closed" and body.get("IsFullyShipped"),
          (status, body))


if __name__ == "__main__":
    main()
