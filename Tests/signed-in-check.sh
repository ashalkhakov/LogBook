#!/bin/bash
# The desktop app driven from within (LBSelfTest.h) against a server that
# asks for a sign-in, as a user's does: Keycloak (in Docker) with a realm
# whose client is Logbook's (logbook, public, its Audience mapper: the
# tokens name it), a user self-test@example.org; the server checking the
# realm's tokens (-JWTIssuer, -JWTAudience logbook, -AllowAnonymous NO),
# so every permission (Server/Logbook.permissions.plist) applies; the app
# signed in by the realm's tokens (LB_SIGN_IN_TOKENS, in place of the
# device flow's code typed at a page). Its containers are its own, removed
# at the end.
#
#   Tests/signed-in-check.sh build/logbook-server build/Logbook.app/Contents/MacOS/Logbook
set -euo pipefail
server=$1
app=$2
here=$(cd "$(dirname "$0")" && pwd)
name=logbook-signed-in-check-$$
kc_port=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')
trap 'docker rm -f "$name" > /dev/null 2>&1 || true' EXIT
docker run -d --name "$name" -p "127.0.0.1:$kc_port:8080" -e KC_BOOTSTRAP_ADMIN_USERNAME=admin -e KC_BOOTSTRAP_ADMIN_PASSWORD=admin \
  -e KC_HOSTNAME="http://127.0.0.1:$kc_port" -e KC_HTTP_ENABLED=true quay.io/keycloak/keycloak:26.0.7 start-dev > /dev/null
up=no
for _ in $(seq 1 180); do
  curl -sf -o /dev/null "http://127.0.0.1:$kc_port/realms/master" && { up=yes; break; }
  sleep 1
done
[ $up = yes ] || { echo "signed-in-check: Keycloak did not start"; docker logs "$name" | tail -20; exit 1; }
kc() { docker exec "$name" /opt/keycloak/bin/kcadm.sh "$@"; }
kc config credentials --server http://localhost:8080 --realm master --user admin --password admin > /dev/null
kc create realms -s realm=logbook-check -s enabled=true -s accessTokenLifespan=3600 > /dev/null
client=$(kc create clients -r logbook-check -s clientId=logbook -s publicClient=true -s directAccessGrantsEnabled=true \
  -s 'attributes."oauth2.device.authorization.grant.enabled"=true' -i)
kc create "clients/$client/protocol-mappers/models" -r logbook-check -s name=audience -s protocol=openid-connect \
  -s protocolMapper=oidc-audience-mapper -s 'config."included.client.audience"=logbook' -s 'config."access.token.claim"=true' > /dev/null
kc create users -r logbook-check -s username=self-test -s email=self-test@example.org -s emailVerified=true \
  -s firstName=Self -s lastName=Test -s enabled=true > /dev/null
kc set-password -r logbook-check --username self-test --new-password self-test
issuer="http://127.0.0.1:$kc_port/realms/logbook-check"
LB_SIGN_IN_TOKENS=$(curl -sf "$issuer/protocol/openid-connect/token" -d grant_type=password -d client_id=logbook \
  -d username=self-test -d password=self-test -d scope=openid)
export LB_SIGN_IN_TOKENS
LB_SERVER_ARGS="-JWTIssuer $issuer -JWTAudience logbook -AllowAnonymous NO"
export LB_SERVER_ARGS
echo "signed-in-check: Keycloak at $issuer, the app signed in as self-test@example.org"
"$here/app-check.sh" "$server" "$app"
