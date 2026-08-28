#!/bin/sh
#
# Applies this repo's JetStream topology to a broker.
#
# WHY THIS EXISTS. Streams used to appear by hand, which meant nobody could answer "what
# streams should exist, with what retention?" without asking the broker — and the broker
# only knows what someone last typed. The .json files next to this script are the answer,
# and this repo owns them because it owns the broker (docker-compose.yml). A consuming repo
# declaring its own stream would put two repos in charge of topology, which is how a stream
# ends up configured differently depending on who booted last.
#
# SAFE BY DESIGN. This script CREATES missing streams and never modifies an existing one.
# If a live stream differs from its file it prints the difference and exits non-zero, so
# drift becomes a conversation rather than an automatic change. Editing a stream can shrink
# limits and silently discard messages, which for an append-only event log is unrecoverable
# — so that stays a deliberate operator action (`nats stream edit`).
#
# Usage:
#   ./streams/apply.sh                              # dev broker on the `jetstream` network
#   NATS_URL=nats://jetstream:4222 NATS_NETWORK=prod ./streams/apply.sh
#
# The nats CLI is deliberately not installed in any project container, so this runs from the
# official nats-box image on the broker's own docker network. jq comes with that image, so
# the script needs nothing on the host but docker.
set -eu

SERVER="${NATS_URL:-nats://jetstream:4222}"
NETWORK="${NATS_NETWORK:-jetstream}"
IMAGE="${NATS_BOX_IMAGE:-natsio/nats-box:latest}"
DIR="$(cd "$(dirname "$0")" && pwd)"

status=0

for file in "$DIR"/*.json; do
  name="$(basename "$file" .json)"

  if docker run --rm --network "$NETWORK" "$IMAGE" \
      nats --server="$SERVER" stream info "$name" --json >/dev/null 2>&1; then

    # Compare only the keys the file declares. The server fills in defaults, metadata and
    # placement fields that are not ours to assert, and diffing those would report drift on
    # every NATS upgrade.
    drift="$(
      docker run --rm --network "$NETWORK" -v "$DIR:/streams:ro" "$IMAGE" sh -c "
        nats --server='$SERVER' stream info '$name' --json \
          | jq -r --slurpfile want /streams/$name.json '
              .config as \$live
              | \$want[0]
              | to_entries
              | map(select(.value != \$live[.key]))
              | .[]
              | \"  \\(.key): file=\\(.value|tojson) live=\\(\$live[.key]|tojson)\"
            '
      " 2>/dev/null
    )"

    if [ -n "$drift" ]; then
      echo "DRIFT   $name differs from streams/$name.json:"
      echo "$drift"
      echo "        Not changed. Reconcile deliberately (nats stream edit), or fix the file."
      status=1
    else
      echo "OK      $name matches streams/$name.json"
    fi
  else
    echo "CREATE  $name"
    docker run --rm --network "$NETWORK" -v "$DIR:/streams:ro" "$IMAGE" \
      nats --server="$SERVER" stream add "$name" --config "/streams/$name.json"
  fi
done

exit "$status"
