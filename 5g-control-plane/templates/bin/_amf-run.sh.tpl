#!/bin/sh

# Copyright 2024-present Intel Corporation
# Copyright 2020-present Open Networking Foundation
#
# SPDX-License-Identifier: Apache-2.0

set -xe

{{- if .Values.config.coreDump.enabled }}
cp /usr/local/bin/amf /tmp/coredump/
{{- end }}

CFGPATH=/home
FILENAME=amfcfg.yaml
# copy config file from configmap (/opt) to a general directory (/home)
cp /opt/$FILENAME $CFGPATH/$FILENAME
# Print the configuration for operator visibility, with the lawful-interception
# section withheld. This log is readable by anyone who can reach the pod, and the
# mere presence of that section discloses that this network function is an
# interception point — which TS 33.127 undetectability does not permit. The filter
# is unconditional so that the script is byte-identical on every deployment:
# shipping a different one where LI is enabled would leak the same fact.
awk '/^  li:/ {skip=1; next} skip && /^  [^ ]/ {skip=0} !skip' $CFGPATH/$FILENAME
echo ""

GOTRACEBACK=crash amf -cfg $CFGPATH/$FILENAME
