# Durable Streams server — the Caddy plugin build, which is the upstream's
# production implementation. Nothing is compiled here: the project publishes
# static linux binaries per release, so this image only fetches and verifies one.
#
# Chosen over the Node package (@durable-streams/server) on the upstream's own
# guidance — that one calls itself development-and-testing and exports a class
# named DurableStreamTestServer. Measured, both survive a restart and a SIGKILL
# with their records intact; the Node one is not broken, it is just not the
# implementation its authors point production at.
#
# Both share one operational trap: the port accepts, and answers 200, BEFORE the
# store has finished loading. A read in that window returns no data and a write
# can be reset. Give the pod a readiness probe that proves the STORE answers,
# not just that the socket is up.
#
# Auth is opt-in — see entrypoint.sh. DS_TOKEN set requires it, unset serves
# openly, so a client can get by with only a URL.
FROM debian:12-slim

# Supplied by buildx per platform — `amd64` / `arm64`, which is exactly how the
# release assets are named. Declared after FROM so it is in scope for RUN.
ARG TARGETARCH
ARG DS_VERSION=v0.3.0

RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl \
 && rm -rf /var/lib/apt/lists/*

# Verified against the release's own checksums.txt. The binary arrives over the
# network at build time; a corrupted or substituted tarball should fail the
# build rather than reach production.
RUN set -eux; \
    base="https://github.com/durable-streams/durable-streams/releases/download/${DS_VERSION}"; \
    file="durable-streams-server_${DS_VERSION#v}_linux_${TARGETARCH}.tar.gz"; \
    curl -fsSL -o "/tmp/${file}" "${base}/${file}"; \
    curl -fsSL -o /tmp/checksums.txt "${base}/checksums.txt"; \
    (cd /tmp && grep " ${file}\$" checksums.txt | sha256sum -c -); \
    tar xzf "/tmp/${file}" -C /usr/local/bin durable-streams-server; \
    chmod +x /usr/local/bin/durable-streams-server; \
    rm -f "/tmp/${file}" /tmp/checksums.txt; \
    durable-streams-server version

# Two configs, and an entrypoint that picks one: DS_TOKEN set means auth is
# required, unset means the server is open and a client needs only the URL.
COPY Caddyfile Caddyfile.auth /etc/caddy/
COPY entrypoint.sh /entrypoint.sh

# Streams live here. Mount a volume or the data is only as durable as the
# container, which defeats the point of running this at all.
VOLUME ["/data"]

EXPOSE 4437

ENTRYPOINT ["/entrypoint.sh"]
