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
docker run -d -p 4437:4437 -v durable-streams:/data iinitz/durable-streams-server:0.3.0
```

Storage is file-backed (LMDB) under `/data`. Mount a volume or the streams are
only as durable as the container, which defeats the point.

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
    command: ["sh", "-c", "curl -s -o /dev/null -w '%{http_code}' http://localhost:4437/streams/_probe | grep -q 404"]
  periodSeconds: 5
```

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
Measure with the server given time to become ready first — reading too early
reports losses that have not happened.
