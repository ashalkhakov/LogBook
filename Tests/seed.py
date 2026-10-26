#!/usr/bin/env python3
"""What a server for the devices' checks starts with, besides its reference
data (the units, and the kinds of cost the model has: 'Maintenance',
'Repair', 'Fuel', ...): a kind of expense of a user's own, which the
devices read (kinds of cost are the server's) and the desktop app adds.

    Tests/seed.py http://127.0.0.1:8080/odata/ [access token]

A server that asks who is asking is sent the token (as a user's).
"""
import json
import sys
import urllib.request

root = sys.argv[1]
headers = {"Content-Type": "application/json"}
if len(sys.argv) > 2:
    headers["Authorization"] = "Bearer " + sys.argv[2]
for name in ("Parking",):
    body = json.dumps({"@odata.type": "#Default.ExpenseKind", "Name": name}).encode()
    request = urllib.request.Request(root + "CostKinds", data=body, method="POST", headers=headers)
    urllib.request.urlopen(request).read()
print("seeded: Parking")
