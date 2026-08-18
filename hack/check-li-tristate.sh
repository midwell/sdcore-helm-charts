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

echo "check-li-tristate: the LI tri-state booleans render as booleans, non-booleans are refused, and two points of interception cannot share an neId"
