#!/bin/sh
# Auth is opt-in: a token on the server makes it required, no token leaves the
# server open so a client needs only the URL. Two static configs rather than one
# clever matcher — Caddyfile placeholders are substituted at parse time and
# cannot express "only if this is non-empty", and an unset token in the gated
# config would leave it matching a bare "Bearer " and refusing everything.
set -e

if [ -n "${DS_TOKEN}" ]; then
	echo "durable-streams: DS_TOKEN set — requiring Authorization: Bearer"
	CONFIG=/etc/caddy/Caddyfile.auth
else
	echo "durable-streams: no DS_TOKEN — serving unauthenticated"
	CONFIG=/etc/caddy/Caddyfile
fi

exec durable-streams-server run --config "${CONFIG}"
