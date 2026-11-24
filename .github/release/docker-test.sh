#!/bin/bash
# The server's image as a user runs it, for gnustep-release-actions'
# docker.yml (given the target and the image built and loaded), as
# SimpleNotes' is (TopoText's .github/release/docker-test.sh):
#
# - SQLite in its volume by default: started, a user and her vehicle made
#   over OData, then Drivvo's export imported into it by logbook-import
#   from the same image (Tests/drivvo-export.csv), and read back;
# - PostgreSQL by its settings (FreeCoreData's store, loaded by name):
#   started, its health asked, a user made and read back;
# - signed in through an identity provider: a token it cannot check is
#   refused (401), which needs the image's CA certificates to fetch the
#   provider's keys.
#
# Its containers, volume and network are its own, removed at the end.
#
#   .github/release/docker-test.sh '' logbook-server
set -euo pipefail
image=$2
names="logbook-db logbook-sqlite logbook-postgres logbook-oidc"
trap 'docker rm -f $names > /dev/null 2>&1 || true
      docker volume rm logbook-test-data > /dev/null 2>&1 || true
      docker network rm logbook-test > /dev/null 2>&1 || true' EXIT
docker network create logbook-test > /dev/null
docker run -d --name logbook-db --network logbook-test -e POSTGRES_PASSWORD=logbook -e POSTGRES_DB=logbook postgres:16 > /dev/null
docker run -d --name logbook-sqlite --network logbook-test -p 18090:8080 -v logbook-test-data:/data \
  -e LB_SERVICE_ROOT=http://logbook-sqlite:8080/odata/ "$image" > /dev/null

up() {
  for _ in $(seq 1 90); do curl -sf -o /dev/null "http://127.0.0.1:$1/health" && return 0; sleep 1; done
  echo "the server on $1 did not answer /health"; docker logs "$2"; exit 1
}
post() {
  code=$(curl -s -o /dev/null -w '%{http_code}' -X POST -H 'Content-Type: application/json' "http://127.0.0.1:$1/odata/$2" -d "$3")
  [ "$code" = 201 ] || { echo "$2 not made on $1: $code"; docker logs "$4"; exit 1; }
}
count() {
  curl -sf "http://127.0.0.1:$1/odata/$2/\$count"
}

up 18090 logbook-sqlite
golf=$(python3 -c 'import uuid; print(uuid.uuid4())')
post 18090 Users '{"Email":"anna@example.org","PersonName":"Anna Driver","Currency":"EUR","TimeZone":"Europe/Berlin"}' logbook-sqlite
post 18090 Users '{"Email":"ben@example.org","PersonName":"Ben Driver"}' logbook-sqlite
post 18090 Vehicles "{\"Id\":\"$golf\",\"VehicleName\":\"Golf\",\"Make\":\"Volkswagen\",\"CarModel\":\"Golf\",\"ManufactureYear\":2016,\"Fuel\":\"Petrol\",\"Owner@odata.bind\":\"Users('anna@example.org')\"}" logbook-sqlite
post 18090 VehicleDrivers "{\"Id\":\"$(python3 -c 'import uuid; print(uuid.uuid4())')\",\"Vehicle@odata.bind\":\"Vehicles($golf)\",\"User@odata.bind\":\"Users('ben@example.org')\"}" logbook-sqlite
docker run --rm --network logbook-test -v "$PWD/Tests":/in:ro --entrypoint /app/logbook-import "$image" \
  -Server http://logbook-sqlite:8080/ -Email anna@example.org -Vehicle Golf -LeaveOut YES /in/drivvo-export.csv
items=$(count 18090 ServiceItems)
echo "SQLite: Drivvo's export imported, $items service items"
[ "$items" = 2 ] || { docker logs logbook-sqlite; exit 1; }
# Kept in the volume: started again, the same.
docker rm -f logbook-sqlite > /dev/null
docker run -d --name logbook-sqlite --network logbook-test -p 18090:8080 -v logbook-test-data:/data "$image" > /dev/null
up 18090 logbook-sqlite
[ "$(count 18090 ServiceItems)" = 2 ] || { echo "the volume's store not kept"; docker logs logbook-sqlite; exit 1; }
echo "SQLite: kept in the volume across a restart"

for _ in $(seq 1 60); do docker exec logbook-db pg_isready -h 127.0.0.1 -U postgres > /dev/null 2>&1 && break; sleep 1; done
docker run -d --name logbook-postgres --network logbook-test -p 18091:8080 \
  -e LB_STORE_TYPE=PostgreSQL -e LB_STORE_URL=postgresql://postgres:logbook@logbook-db:5432/logbook \
  -e LB_WORKFLOW=/data/Workflow.sqlite "$image" > /dev/null
up 18091 logbook-postgres
post 18091 Users '{"Email":"anna@example.org"}' logbook-postgres
users=$(count 18091 Users)
echo "PostgreSQL: $users user"
[ "$users" -ge 1 ] || { docker logs logbook-postgres; exit 1; }

docker run -d --name logbook-oidc -p 18092:8080 \
  -e LB_JWT_ISSUER=https://accounts.google.com -e LB_ALLOW_ANONYMOUS=NO "$image" > /dev/null
up 18092 logbook-oidc
b64() { base64 -w0 | tr '+/' '-_' | tr -d '='; }
header=$(printf '{"alg":"RS256","typ":"JWT","kid":"none"}' | b64)
claims=$(printf '{"iss":"https://accounts.google.com","sub":"x","exp":9999999999}' | b64)
answer=$(mktemp)
status=$(curl -s -o "$answer" -w '%{http_code}' -H "Authorization: Bearer $header.$claims.c2ln" http://127.0.0.1:18092/odata/Vehicles)
echo "signed in, a token it cannot check: $status $(cat "$answer")"
[ "$status" = 401 ] || { docker logs logbook-oidc; exit 1; }
