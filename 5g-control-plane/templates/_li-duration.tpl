{{/*
# SPDX-FileCopyrightText: 2026 Forsway Scandinavia AB
# SPDX-License-Identifier: Apache-2.0
*/}}

{{/*
5g-control-plane.li.checkDuration refuses a Lawful Interception timer that is not a Go
duration, at render time, naming the values key.

Why here and not in the network function's own configuration validation: an unusable LI
value must stop interception and nothing else, so the element declines to start LI and
reports it to the ADMF. That is the right answer at runtime and a poor one at deploy
time, where the mistake can still be caught for free — `helm upgrade` refuses, nothing
is applied, and whatever is currently running is undisturbed. It is the only place a bad
value costs neither interception nor service.

The check is a regex because sprig has no duration parser, so it is approximate: it will
not reject a pathological but well-formed string. That is acceptable — the element is
authoritative and this fires earlier, for the mistakes anyone actually makes ("30" for
"30s", "5min" for "5m", "30 s").

Call with a dict of `value` and `key`. An empty value is a stated choice and passes.
*/}}
{{- define "5g-control-plane.li.checkDuration" -}}
{{- $value := .value | toString -}}
{{- if $value -}}
{{- if not (regexMatch "^[+-]?([0-9]+(\\.[0-9]+)?(ns|us|µs|μs|ms|s|m|h))+$" $value) -}}
{{- fail (printf "%s: %q is not a Go duration. Use a unit — for example \"30s\", \"5m\" or \"1h30m\"." .key $value) -}}
{{- end -}}
{{- end -}}
{{- end -}}
