#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Forsway Scandinavia AB
# SPDX-License-Identifier: Apache-2.0
#
# Assert that an unusable Lawful Interception timer is refused at render time, and that a
# usable one — and an absent one — render as before.
#
# The check exists because the element's own answer to such a value is deliberately quiet:
# it declines to start interception and tells the ADMF, leaving the network function
# serving. That is right at runtime and useless to an operator who has just mistyped a
# duration in values.yaml, so the render refuses it while nothing is deployed yet.
set -euo pipefail

cd "$(dirname "$0")/.."
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

fail() { echo "check-li-durations: $*" >&2; exit 1; }

# refused reports whether a failed render failed because *this* guard refused the value,
# rather than for some unrelated reason. Without it every render failure is attributed to
# the duration check, which is how a fresh checkout — where the subcharts have not been
# fetched yet — reads as "a valid duration was refused" and sends the reader to the wrong
# file entirely.
refused() { grep -q "$1" <<<"$2"; }

# ensure_deps renders a chart untouched, and fetches its subcharts if that is what is
# missing. `helm template` refuses to render at all while a dependency named in Chart.yaml
# is absent from charts/, and charts/ is not in the repository — so on a clean clone, which
# is what CI has, every check below would fail before reaching the templates it is testing.
ensure_deps() {
	local chart=$1
	helm template preflight "$chart" >/dev/null 2>&1 && return 0

	helm dependency build "$chart" >/dev/null 2>&1 || true

	local out
	out=$(helm template preflight "$chart" 2>&1) && return 0
	fail "$chart does not render even untouched, so nothing below would be testing the LI timers: $out"
}

ensure_deps 5g-control-plane
ensure_deps bess-upf

# ── 5g-control-plane: the AMF's and SMF's three timers ──
for nf in amf smf; do
	for key in keepaliveTimeout x2x3KeepaliveTimeP1 x2x3KeepaliveTimeP2; do
		if ! out=$(helm template cp 5g-control-plane \
			--set "config.$nf.li.enabled=true" \
			--set "config.$nf.li.mdf2=10.0.0.1:9000" \
			--set "config.$nf.li.mdf3=10.0.0.1:9001" \
			--set "config.$nf.li.$key=30s" 2>&1); then
			if refused "config.$nf.li.$key" "$out"; then
				fail "a valid duration was refused for config.$nf.li.$key"
			fi
			fail "the render failed for a reason other than this guard: $out"
		fi

		out=$(helm template cp 5g-control-plane \
			--set "config.$nf.li.enabled=true" \
			--set "config.$nf.li.mdf2=10.0.0.1:9000" \
			--set "config.$nf.li.mdf3=10.0.0.1:9001" \
			--set "config.$nf.li.$key=30" 2>&1 || true)
		grep -q "config.$nf.li.$key" <<<"$out" ||
			fail "an unusable duration for config.$nf.li.$key rendered without complaint"
	done
done

# LI off must be unaffected: the timers are not read at all.
helm template cp 5g-control-plane --set config.amf.li.keepaliveTimeout=30 >/dev/null 2>&1 ||
	fail "an unusable duration blocked a render with LI disabled"

# ── bess-upf: the UPF's three ──
base=$work/upf.yaml
cat >"$base" <<'YAML'
config:
  upf:
    cfgFiles:
      upf.jsonc:
        li:
          ne_id: upf-1
          tf_id: smf-1
          x1_listen: "0.0.0.0:8443"
          x3_sockaddr: "/pod-share/li_x3"
          cert: /etc/li/certs/tls.crt
          key: /etc/li/certs/tls.key
          ca_cert: /etc/li/certs/ca.crt
YAML

helm template upf bess-upf -f "$base" >/dev/null 2>&1 ||
	fail "an li block with no timers at all was refused"

for key in trigger_keepalive x2x3_keepalive_time_p1 x2x3_keepalive_time_p2; do
	good=$work/good.yaml
	{ cat "$base"; echo "          $key: \"5m\""; } >"$good"
	if ! out=$(helm template upf bess-upf -f "$good" 2>&1); then
		if refused "li.$key" "$out"; then
			fail "a valid duration was refused for li.$key"
		fi
		fail "the render failed for a reason other than this guard: $out"
	fi

	bad=$work/bad.yaml
	{ cat "$base"; echo "          $key: \"5min\""; } >"$bad"
	out=$(helm template upf bess-upf -f "$bad" 2>&1 || true)
	grep -q "li.$key" <<<"$out" ||
		fail "an unusable duration for li.$key rendered without complaint"
done

echo "check-li-durations: unusable LI timers are refused at render time on both charts"
