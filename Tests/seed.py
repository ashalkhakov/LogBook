#!/usr/bin/env python3
"""What a server for the devices' checks starts with, besides its reference
data: the kinds of cost a service and an expense are of, which the devices
read (they are the server's) and the desktop app adds.

    Tests/seed.py http://127.0.0.1:8080/odata/
"""
import json
import sys
import urllib.request

root = sys.argv[1]
for name, kind in (("Maintenance", "CostKind"), ("Repair", "CostKind"), ("Parking", "ExpenseKind")):
    body = json.dumps({"@odata.type": "#Default." + kind, "Name": name}).encode()
    request = urllib.request.Request(root + "CostKinds", data=body, method="POST",
                                     headers={"Content-Type": "application/json"})
    urllib.request.urlopen(request).read()
print("seeded: Maintenance, Repair, Parking")
