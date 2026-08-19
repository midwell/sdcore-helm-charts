{{/*
# SPDX-FileCopyrightText: 2026 Forsway Scandinavia AB
# SPDX-License-Identifier: Apache-2.0
*/}}

{{/*
omec-user-plane.li.checkDuration refuses a Lawful Interception timer that is not a Go
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

Call with a dict of `value` and `key`. An empty value is a stated choice and passes: an
operator who writes nothing has said the timer is off, which is different from one who wrote a
value this element cannot use.
*/}}
{{- define "omec-user-plane.li.checkDuration" -}}
{{- $value := .value | toString -}}
{{- if $value -}}
{{/*
Second-or-larger units only, and no sign. The previous pattern admitted "ns", "us", "ms" and a
leading "+" or "-", and every one of those is a value the element cannot use: it refuses a
non-positive window, and it refuses one below one second because the window is halved to produce
the watchdog's tick interval and integer division reaches zero — which panicked time.NewTicker,
on a goroutine, and took the network function down.

"1ns" is the case that made this worth tightening: it is a well-formed Go duration and it is
positive, so it passed both this regex and the element's own positive test, and then crash-looped
the process. The element refuses it now; this refuses it a deployment earlier, where the mistake
costs neither interception nor service.
*/}}
{{- if not (regexMatch "^([0-9]+(\\.[0-9]+)?[smh])+$" $value) -}}
{{- fail (printf "%s: %q is not a Go duration of at least one second. Use a whole unit of seconds or more — for example \"30s\", \"5m\" or \"1h30m\" — and no sign; \"ns\", \"us\" and \"ms\" are below the floor this timer can hold." .key $value) -}}
{{- end -}}
{{/*
And the numeric floor, which the pattern above cannot express: "0s" and "0.5s" are spelled in
seconds and are still under one. A multi-component value like "0h30m" is not caught here and
does not need to be — it is thirty minutes.
*/}}
{{- if regexMatch "^0+(\\.[0-9]+)?[smh]$" $value -}}
{{- fail (printf "%s: %q is less than one second, which is the shortest window this timer can hold: it is halved to produce the watchdog's tick interval." .key $value) -}}
{{- end -}}
{{- end -}}
{{- end -}}
