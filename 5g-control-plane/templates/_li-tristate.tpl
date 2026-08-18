{{/*
# SPDX-FileCopyrightText: 2026 Forsway Scandinavia AB
# SPDX-License-Identifier: Apache-2.0
*/}}

{{/*
5g-control-plane.li.triStateBool renders one of the Lawful Interception tri-state
booleans as "true", "false", or "" for unset, and fails the render — naming the values
key — on anything else.

Why these keys need a guard the other LI values do not: they are *tri-state*. Unset means
"take the specification's default", which is a different instruction from either true or
false, so they are `*bool` in the element's configuration and the chart's own default for
them is the empty string. That empty-string default is precisely what invites an operator
to replace it with a quoted value, and `--set-string` is the documented way to set a value
Helm would otherwise coerce. The result renders `x2x3KeepaliveEnabled: "false"` — a YAML
string where the element declares a bool — and the element's config load fails outright:
not the LI block ignored, the whole network function crashlooping over a lawful
interception key.

That is the one cost an LI configuration mistake may never have. The element's own policy
is to disable interception and tell the ADMF, and it cannot apply that policy to a value
it never managed to parse. So the chart accepts both spellings an operator plausibly
writes, emits a real bool, and refuses anything else while nothing is deployed yet — the
same reasoning, and the same shape, as checkDuration in _li-duration.tpl.

Deliberately narrow: "yes", "1", "False" and the rest are refused rather than guessed at.
The coercion covers exactly the two spellings the empty-string default invites, because a
chart that guesses is a chart that can guess wrong about whether an interception is
running.

Call with a dict of `value` and `key`.
*/}}
{{- define "5g-control-plane.li.triStateBool" -}}
{{- $v := .value -}}
{{- if kindIs "bool" $v -}}
{{- if $v -}}true{{- else -}}false{{- end -}}
{{- else if kindIs "invalid" $v -}}
{{- else -}}
{{- $s := $v | toString -}}
{{- if eq $s "" -}}
{{- else if eq $s "true" -}}true
{{- else if eq $s "false" -}}false
{{- else -}}
{{- fail (printf "%s: %q is not a boolean. Use true or false — unquoted, or as the exact strings \"true\" or \"false\" — or leave it unset to take the specification's default." .key $s) -}}
{{- end -}}
{{- end -}}
{{- end -}}
