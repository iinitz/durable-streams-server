# durable-streams-server

A container image for the [Durable Streams](https://github.com/durable-streams/durable-streams)
server — the Caddy plugin build, which is the upstream's production
implementation. Nothing is compiled here: the project publishes static linux
binaries per release, so the image fetches one and verifies it against the
release's own `checksums.txt`.

Built for Fullfeel's AI chat, where it holds the delivery log for a run so a
reconnecting browser resumes the answer instead of losing it. The API reaches it
through `DURABLE_STREAMS_URL`; unset, the API keeps the log in its own process
and forgets it on restart.

## Image

```
iinitz/durable-streams-server:0.3.0
iinitz/durable-streams-server:0.3.0-<build>
```

No `latest` tag, deliberately: this image holds data, so a rollback has to be
able to name the exact build it is going back to.

## Run it

```bash
docker run -d -p 4437:4437 -v durable-streams:/data \
  iinitz/durable-streams-server:0.3.0
```

Storage is file-backed (LMDB) under `/data`. Mount a volume or the streams are
only as durable as the container, which defeats the point.

## DS_TOKEN — opt-in auth

| server | client |
| --- | --- |
| `DS_TOKEN` set | must send `Authorization: Bearer <token>`, or gets `401` |
| `DS_TOKEN` unset | needs only the URL; any `Authorization` header is ignored |

The client side already matches: the API sends `DURABLE_STREAMS_TOKEN` as a
bearer header only when it is set, so a URL on its own is a complete
configuration against an open server.

This is two static configs and a six-line entrypoint rather than one clever
matcher, because Caddyfile placeholders are substituted at parse time and cannot
express "only when this is non-empty" — an unset token in the gated config
leaves it matching a bare `Bearer ` and refusing everything.

Two Caddy details worth keeping if you edit either config. The plugin is not
part of Caddy's built-in directive order, so it needs the `order` global option
(or a `route` block) or the server will not start at all — it says so plainly on
stderr. And the gate uses `handle`, not a bare `respond`: top-level directives
are sorted by Caddy's order rather than file order, so a bare `respond` runs
*after* the route and lets every request through, silently, with a 200 and no
error anywhere.

## The route is `/streams/*`, not the upstream's `/v1/stream/*`

The plugin takes the stream identity straight from `r.URL.Path` with no prefix
stripping, and `@tanstack/ai-durable-stream` addresses `<server>/streams/<name>`.
The example Caddyfile in the upstream README serves `/v1/stream/*`, which
silently matches nothing. If you change the route, change the client's base URL
to match.

## Give it a readiness probe

The port accepts — and answers `200` — *before* the store has finished loading.
A read in that window comes back with no data, and a write can be reset. A plain
`httpGet` probe does not work, because an unknown stream answers `404` and
Kubernetes scores that as a failure. Prove the store answers instead:

```yaml
readinessProbe:
  exec:
    command: ["sh", "-c", "curl -s -o /dev/null -w '%{http_code}' -H \"Authorization: Bearer $DS_TOKEN\" http://localhost:4437/streams/_probe | grep -q 404"]
  periodSeconds: 5
```

The header matters when a token is set: without it the probe gets `401`, which
proves only that Caddy is up — not that the store has finished loading, which is
the whole point. With no token the header is ignored, so the same command works
either way.

`curl` is in the image for this.

## Single writer

The file-backed store owns its data directory, so this runs at one replica with
a `ReadWriteOnce` volume and `strategy: Recreate` — a rolling update would
deadlock two pods on the same volume.

## Bumping the server version

Edit `DS_VERSION` in `.github/workflows/build.yml`. The image tag follows it.
Upstream tags two independent things: plain `vX.Y.Z` releases carry these Go
binaries, while `@durable-streams/server@X.Y.Z` tags are the separate Node
reference implementation. Only the plain ones are relevant here.

## Verified

Against v0.3.0 (Caddy v2.10.2), file-backed on a mounted volume: records survive
a graceful restart and a `SIGKILL`, and older streams are untouched by either.
With `DS_TOKEN` set the gate answers `401` to a missing or wrong token and
`201`/`200` to writes carrying the right one; with it unset the same requests
succeed with no header at all.
Measure with the server given time to become ready first — reading too early
reports losses that have not happened.
