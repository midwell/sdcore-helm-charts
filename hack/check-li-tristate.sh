#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Forsway Scandinavia AB
# SPDX-License-Identifier: Apache-2.0
#
# Assert that the three tri-state Lawful Interception booleans render as real YAML
# booleans however an operator spells them, and that anything which is not a boolean is
# refused at render time, naming the values key.
#
# The check exists because these keys are tri-state — unset means "the specification's
# default" — so the element declares them *bool and the chart defaults them to the empty
# string. That default is what invites a quoted replacement, and --set-string is the
# documented way to set a value Helm would otherwise coerce. The result is
# `x2x3KeepaliveEnabled: "false"`: a YAML string where a bool is declared, which fails
# the *whole* configuration load. The network function then crashloops over a lawful
# interception key — the one cost an LI configuration mistake may never have, and one the
# element cannot apply its own policy to, because it never parsed the file.
#
# smf/factory's TestAQuotedTriStateBooleanIsRefusedByTheConfigLoader pins the other half:
# that a quoted value really is refused by the loader. The two together are the reason
# this guard is not decoration.
set -euo pipefail

cd "$(dirname "$0")/.."

fail() { echo "check-li-tristate: $*" >&2; exit 1; }

ensure_deps() {
	local chart=$1
	helm template preflight "$chart" >/dev/null 2>&1 && return 0
	helm dependency build "$chart" >/dev/null 2>&1 || true
	local out
	out=$(helm template preflight "$chart" 2>&1) && return 0
	fail "$chart does not render even untouched, so nothing below would be testing the LI booleans: $out"
}

ensure_deps 5g-control-plane

render() {
	local nf=$1
	shift
	helm template cp 5g-control-plane \
		--set "config.$nf.li.enabled=true" \
		--set "config.$nf.li.mdf2=10.0.0.1:9000" \
		--set "config.$nf.li.mdf3=10.0.0.1:9001" \
		"$@" 2>&1
}

for nf in amf smf; do
	for key in x2x3KeepaliveEnabled deactivateAllTasks removeAllDestinations; do
		# A quoted spelling renders a real bool. Asserted on the rendered line, because
		# what broke the element was the quoting and not the value.
		out=$(render "$nf" --set-string "config.$nf.li.$key=false") ||
			fail "a quoted \"false\" for config.$nf.li.$key was refused: $out"
		grep -qE "^ +$key: false$" <<<"$out" ||
			fail "config.$nf.li.$key did not render as a YAML boolean; the element's config load would fail:
$(grep -E "$key" <<<"$out" || echo '  (the key did not render at all)')"

		out=$(render "$nf" --set-string "config.$nf.li.$key=true") ||
			fail "a quoted \"true\" for config.$nf.li.$key was refused: $out"
		grep -qE "^ +$key: true$" <<<"$out" ||
			fail "config.$nf.li.$key did not render as a YAML boolean for a quoted \"true\""

		# And the real thing still works.
		out=$(render "$nf" --set "config.$nf.li.$key=true") ||
			fail "a YAML boolean for config.$nf.li.$key was refused: $out"
		grep -qE "^ +$key: true$" <<<"$out" ||
			fail "config.$nf.li.$key did not render for an unquoted true"

		# Anything else fails the render, naming the key. Guessing is what a chart must
		# not do here: the answer decides whether an interception behaves as tasked.
		out=$(render "$nf" --set-string "config.$nf.li.$key=maybe" || true)
		grep -q "config.$nf.li.$key" <<<"$out" ||
			fail "config.$nf.li.$key accepted a value that is not a boolean, or failed without naming the key: $out"

		# Unset stays unset: the element takes the specification's default, and a chart
		# that emitted false here would silently disable a mechanism nobody turned off.
		out=$(render "$nf")
		grep -qE "^ +$key:" <<<"$out" &&
			fail "config.$nf.li.$key rendered while unset; the element can no longer tell \"default\" from \"off\""
	done
done

# LI off must be unaffected: the block is not rendered at all.
helm template cp 5g-control-plane --set-string config.amf.li.x2x3KeepaliveEnabled=maybe >/dev/null 2>&1 ||
	fail "an unusable boolean blocked a render with LI disabled"

# ── Two triggering endpoints may not share an neId ──
#
# The consequence is invisible from either UPF — each numbers its own product correctly —
# and lands at the mediation function as duplicated sequence numbers and apparent gaps,
# which is how loss is signalled on that interface. The SMF refuses such a configuration
# at startup; refusing it here catches it while nothing is deployed.
trigger_args() {
	local a_ne=$1 b_ne=$2
	echo "--set config.smf.li.upfTriggers[0].nodeId=upf-a --set config.smf.li.upfTriggers[0].neId=${a_ne} --set config.smf.li.upfTriggers[0].x1Url=https://a:8443/X1/NE --set config.smf.li.upfTriggers[1].nodeId=upf-b --set config.smf.li.upfTriggers[1].neId=${b_ne} --set config.smf.li.upfTriggers[1].x1Url=https://b:8443/X1/NE"
}

# shellcheck disable=SC2046 # the args are deliberately word-split
out=$(render smf $(trigger_args upf-1 upf-1) || true)
grep -q "share neId" <<<"$out" ||
	fail "two triggering endpoints sharing an neId were accepted: $out"

# shellcheck disable=SC2046
out=$(render smf $(trigger_args upf-1 upf-2)) ||
	fail "two properly distinguished triggering endpoints were refused: $out"
grep -q "neId: upf-2" <<<"$out" ||
	fail "a valid two-UPF trigger list did not render"

# ── bess-upf: the same four keys on the user plane ──
#
# A separate chart with a separate template, and the failure it prevents is worse: the UPF's
# configuration is JSON, so a quoted boolean is not merely the wrong type — `encoding/json`
# refuses the whole document, and the user plane does not start. x3_rcvbuf is here for the
# same reason in the other direction: it is an int, and the same --set-string that protects a
# boolean from Helm's coercion turns a buffer size into a string.
#
# The block is hand-written in values rather than assembled from typed keys, which is why
# these are checked at all: an operator writing the block gets it passed through, so the
# chart is the only place a spelling mistake can be caught before the element refuses to
# start over it.
ensure_deps bess-upf

upfbase=$(mktemp -d)/upf.yaml
cat >"$upfbase" <<'YAML'
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

renderupf() {
	helm template upf bess-upf -f "$upfbase" "$@" 2>&1
}

# The rendered upf.jsonc is a JSON string inside YAML, so the assertions read the escaped
# form: \"key\":value. Reading the JSON as JSON would need a parser the other checks do not
# use, and the escaping is itself part of what must be right.
rendered() {
	grep -o "\\\\\"$1\\\\\":[^,}]*" <<<"$2" | head -1 | sed 's/.*://'
}

for key in x2x3_keepalive_enabled deactivate_all_tasks remove_all_destinations; do
	for value in false true; do
		out=$(renderupf --set-string "config.upf.cfgFiles.upf\.jsonc.li.$key=$value") ||
			fail "a quoted \"$value\" for the UPF's li.$key was refused: $out"
		[ "$(rendered "$key" "$out")" = "$value" ] ||
			fail "the UPF's li.$key did not render as a JSON boolean for a quoted \"$value\"; the element's config decode would refuse the whole file:
$(rendered "$key" "$out")"
	done

	out=$(renderupf --set-string "config.upf.cfgFiles.upf\.jsonc.li.$key=maybe" || true)
	grep -q "li.$key" <<<"$out" ||
		fail "the UPF's li.$key accepted a value that is not a boolean, or failed without naming the key: $out"
done

# x3_rcvbuf: a whole number of bytes, and an int in the rendered JSON.
out=$(renderupf --set-string 'config.upf.cfgFiles.upf\.jsonc.li.x3_rcvbuf=8388608') ||
	fail "a quoted x3_rcvbuf was refused: $out"
[ "$(rendered x3_rcvbuf "$out")" = 8388608 ] ||
	fail "the UPF's li.x3_rcvbuf did not render as a JSON number: $(rendered x3_rcvbuf "$out")"

out=$(renderupf --set-string 'config.upf.cfgFiles.upf\.jsonc.li.x3_rcvbuf=lots' || true)
grep -q "li.x3_rcvbuf" <<<"$out" ||
	fail "a non-numeric x3_rcvbuf rendered without complaint, or failed without naming the key: $out"

# deactivate_all_tasks is the one key the UPF chart defaults rather than omitting, and the
# default is false — the bulk operation removed from an interface reachable by anyone holding
# an SMF-bound LI certificate, on an element whose peer implements no bulk request at all.
# Asserting it here is what stops the default being lost the next time the block is rebuilt.
out=$(renderupf)
[ "$(rendered deactivate_all_tasks "$out")" = false ] ||
	fail "the UPF no longer defaults li.deactivate_all_tasks to false: $(rendered deactivate_all_tasks "$out")"

# And the two that are genuinely tri-state stay absent, so the element can tell "no agreement
# in advance" from "refused".
for key in x2x3_keepalive_enabled remove_all_destinations; do
	[ -z "$(rendered "$key" "$out")" ] ||
		fail "the UPF rendered li.$key while unset; the element can no longer tell \"default\" from \"off\""
done

# ── One render, two ways ──
#
# --show-only is how an operator inspects one manifest, and how the checks above would be
# written if they were written for convenience. It re-renders the whole chart and filters, so
# a template whose output depended on evaluation order would differ between the two — and the
# LI block is built by mutating a local dict, which is exactly the shape that can.
full=$(renderupf --set-string 'config.upf.cfgFiles.upf\.jsonc.li.x2x3_keepalive_enabled=false')
only=$(renderupf --set-string 'config.upf.cfgFiles.upf\.jsonc.li.x2x3_keepalive_enabled=false' \
	--show-only templates/configmap-upf.yaml)
fullblock=$(grep -o '\\"li\\":{[^}]*}' <<<"$full" | head -1)
onlyblock=$(grep -o '\\"li\\":{[^}]*}' <<<"$only" | head -1)
[ -n "$fullblock" ] || fail "the LI block did not render in the full render"
[ "$fullblock" = "$onlyblock" ] ||
	fail "the LI block differs between a full render and --show-only:
  full: $fullblock
  only: $onlyblock"

cpfull=$(render amf --set-string config.amf.li.x2x3KeepaliveEnabled=false)
cponly=$(helm template cp 5g-control-plane \
	--set config.amf.li.enabled=true \
	--set config.amf.li.mdf2=10.0.0.1:9000 \
	--set config.amf.li.mdf3=10.0.0.1:9001 \
	--set-string config.amf.li.x2x3KeepaliveEnabled=false \
	--show-only templates/configmap-amf.yaml 2>&1)
[ "$(grep -cE '^ +x2x3KeepaliveEnabled: false$' <<<"$cpfull")" = 1 ] ||
	fail "the control plane's rendered boolean is not there to compare"
grep -qE '^ +x2x3KeepaliveEnabled: false$' <<<"$cponly" ||
	fail "the control plane's LI boolean differs between a full render and --show-only:
$(grep -E 'x2x3KeepaliveEnabled' <<<"$cponly" || echo '  (it did not render at all)')"

# ── Each triggering entry names all three of its keys ──
#
# An entry missing one used to fail on `hasKey $seenNEIDs $t.neId` with "wrong type for value;
# expected string; got interface {}", which names neither the key nor the entry — for a
# mistake in the values file the operator has just edited.
for missing in neId nodeId x1Url; do
	args="--set config.smf.li.upfTriggers[0].nodeId=upf --set config.smf.li.upfTriggers[0].neId=upf-1 --set config.smf.li.upfTriggers[0].x1Url=https://upf-1:8443/X1/NE"
	# shellcheck disable=SC2001 # the substitution is over a fixed, known string
	args=$(sed "s#--set config.smf.li.upfTriggers\[0\].$missing=[^ ]*##" <<<"$args")
	# shellcheck disable=SC2086 # the args are deliberately word-split
	out=$(render smf $args || true)
	grep -q "config.smf.li.upfTriggers\[0\].$missing is required" <<<"$out" ||
		fail "a triggering entry with no $missing was accepted, or failed without naming the key: $out"
done

echo "check-li-tristate: both charts coerce the LI tri-states to real booleans, refuse anything else naming the key, render identically under --show-only, and require each triggering entry's three keys"
