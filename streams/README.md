# JetStream topology

This repo owns the broker (`docker-compose.yml`), so it owns the **streams**. Each
`*.json` here is the declared configuration of one stream; `apply.sh` creates any that are
missing and reports — without changing anything — any that have drifted.

Why it lives here and not in the services: a consuming repo declaring its own stream would
put two repos in charge of topology, and the stream would end up configured differently
depending on which one booted last. Consumers publish and subscribe; they do not create.

```sh
./streams/apply.sh                                   # dev broker, `jetstream` network
NATS_URL=nats://jetstream:4222 NATS_NETWORK=prod ./streams/apply.sh
```

Needs nothing on the host but docker — the `nats` CLI is deliberately absent from every
project container, so the script runs the official `nats-box` image on the broker's network.

## Streams

### `NATHEJK` — the domain event log

`NATHEJK.>`, file storage, unlimited retention. Every service's domain events. Projections
replay it **from sequence zero on every boot**, which is the constraint that shapes
everything below.

### `TELEMETRY` — high-volume measurements

`TELEMETRY.>`, file storage, unlimited retention.

**Subject shape:** `TELEMETRY.<year>.track.<personId>.reported`

Carries the year, like every other subject in the org, and identifies the person. Chosen
with the `hej` repo (its task 081, PRD 002 §11.1).

**Why this is a separate stream and not `NATHEJK.>`.** Measured, so the decision is
reviewable. One 12-hour race, 827 participants, position batched every 2 minutes:

| sampling | MB per event | vs. all of `NATHEJK` |
|---|---|---|
| 10 s | 330 MB | 18× |
| 30 s | 157 MB | 9× |

`NATHEJK` is 18 MiB / ~29,000 messages today — the entire domain history of the event since
2025. Telemetry in `NATHEJK` would mean every future boot dragging hundreds of megabytes
past every projector, to rebuild read models that do not want it. The volume is not the
problem; **coupling that volume to replay** is.

**Per-person subjects are the erasure mechanism**, not a convenience. A participant (or a
parent) asking for a route to be deleted is answered with:

```sh
nats stream purge TELEMETRY --subject 'TELEMETRY.2026.track.<personId>.reported'
```

Verified: purging one person's subject left the other person's messages untouched.

**Retention is indefinite for now**, deliberately (PRD 002 §11.1) — 2026 is the first year
tracks are recorded and there is no basis yet for choosing a cap. To add one later:

```sh
nats stream edit TELEMETRY --max-age=8760h        # one year, for example
```

That is an **operator action, not a code change**: the stream library used by the services
exposes `Create(name)` with no retention options, so nothing in a service can set it. Worth
knowing before someone goes looking for a config value that does not exist. Update the JSON
here at the same time, or `apply.sh` will report the drift — which is the point of it.

**Duplicate window is 2 minutes** (matching `NATHEJK`), and is *not* the deduplication
guarantee for tracks. A phone that has been offline for hours ships its backlog on
reconnect, long past any window, so duplicate suppression is the consumer's job: a point is
identified by `(person, timestamp)`, which makes a replayed batch idempotent by
construction rather than by luck.
