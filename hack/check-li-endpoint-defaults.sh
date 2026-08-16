#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Forsway Scandinavia AB
# SPDX-License-Identifier: Apache-2.0
#
# Assert that the two charts' Lawful Interception defaults name the same X1
# endpoint: the host the SMF's CC Triggering Function dials (5g-control-plane's
# upfTriggers[].x1Url) and the name of the Service the UPF's triggering interface
# is fronted by (bess-upf's config.upf.li.x1.serviceName).
#
# They are set in charts that install separately, so nothing at render time can
# check one against the other — and a disagreement is not a visible failure. Both
# charts deploy cleanly, every trigger and every withdrawal the SMF sends fails
# against a name that resolves to nothing, and the only symptom is content
# interception that never starts and, worse, never stops.
#
# Everything else here is chart defaults: the values below enable LI and set only
# what each chart refuses to render without.
set -euo pipefail

cd "$(dirname "$0")/.."
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

cat >"$work/cp.yaml" <<'EOF'
config:
  smf:
    li:
      enabled: true
      mdf2: "10.0.11.12:42069"
      mdf3: "10.0.11.12:42070"
EOF

cat >"$work/upf.yaml" <<'EOF'
config:
  upf:
    cfgFiles:
      upf.jsonc:
        li:
          ne_id: upf-1
          tf_id: smf-1
          x1_listen: "0.0.0.0:8443"
          x3_sockaddr: "127.0.0.1:29001"
          cert: /etc/li/certs/tls.crt
          key: /etc/li/certs/tls.key
          ca_cert: /etc/li/certs/ca.crt
EOF

helm template cp 5g-control-plane -f "$work/cp.yaml" >"$work/cp.rendered"
helm template upf bess-upf -f "$work/upf.yaml" >"$work/upf.rendered"

# The host of every x1Url the SMF is configured to task.
dialled=$(grep -oE 'x1Url: https?://[^:/]+' "$work/cp.rendered" | sed -E 's|.*//||' | sort -u)
# The Service that fronts the UPF's X1 listener, by the port it publishes.
fronted=$(awk '/^  name: /{n=$2} /- name: x1$/{print n}' "$work/upf.rendered" | sort -u)

if [ -z "$dialled" ] || [ -z "$fronted" ]; then
	echo "check-li-endpoint-defaults: nothing to compare (dialled=[$dialled] fronted=[$fronted])" >&2
	echo "The LI-enabled render produced no trigger endpoint on one side or the other." >&2
	exit 1
fi

if [ "$dialled" != "$fronted" ]; then
	echo "check-li-endpoint-defaults: the charts' defaults do not compose." >&2
	echo "  5g-control-plane dials: $dialled" >&2
	echo "  bess-upf publishes:     $fronted" >&2
	echo "A deployment taking both charts' defaults would run a CC triggering function" >&2
	echo "that can neither task nor untask its POI." >&2
	exit 1
fi

echo "check-li-endpoint-defaults: both charts name $dialled"
