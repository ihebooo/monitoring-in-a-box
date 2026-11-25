#!/usr/bin/env bash
# check_targets.sh — wait until every Prometheus scrape target is "up".
#
# Exit codes:
#   0  all active targets are up (and at least --min of them)
#   1  some targets still down when the timeout ran out
#   2  Prometheus not reachable, or a required tool is missing
#   3  usage error
set -euo pipefail

VERSION="0.1.0"
URL="http://localhost:9090"
TIMEOUT=120
INTERVAL=5
MIN_TARGETS=1

usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

Wait until every active Prometheus target reports health "up", then print a table.

Options:
  -u, --url URL        Prometheus base URL (default: $URL)
  -t, --timeout SEC    give up after SEC seconds (default: $TIMEOUT)
  -i, --interval SEC   seconds between checks (default: $INTERVAL)
  -m, --min N          also require at least N active targets (default: $MIN_TARGETS)
  -h, --help           show this help
  -V, --version        show the version

Exit codes: 0 all up, 1 targets down, 2 Prometheus unreachable / tool missing, 3 usage error.
Requires: curl, jq.
EOF
}

die_usage() { echo "error: $*" >&2; echo "Try --help." >&2; exit 3; }

is_uint() { [[ $1 =~ ^[0-9]+$ ]]; }

while [[ $# -gt 0 ]]; do
    case $1 in
        -u|--url)      [[ $# -ge 2 ]] || die_usage "$1 needs a value"; URL=${2%/}; shift 2 ;;
        -t|--timeout)  [[ $# -ge 2 ]] || die_usage "$1 needs a value"; TIMEOUT=$2; shift 2 ;;
        -i|--interval) [[ $# -ge 2 ]] || die_usage "$1 needs a value"; INTERVAL=$2; shift 2 ;;
        -m|--min)      [[ $# -ge 2 ]] || die_usage "$1 needs a value"; MIN_TARGETS=$2; shift 2 ;;
        -h|--help)     usage; exit 0 ;;
        -V|--version)  echo "$(basename "$0") $VERSION"; exit 0 ;;
        *)             die_usage "unknown option: $1" ;;
    esac
done

is_uint "$TIMEOUT"     || die_usage "--timeout must be a whole number of seconds"
if ! is_uint "$INTERVAL" || [[ $INTERVAL -lt 1 ]]; then
    die_usage "--interval must be a whole number >= 1"
fi
is_uint "$MIN_TARGETS" || die_usage "--min must be a whole number"

for tool in curl jq; do
    command -v "$tool" >/dev/null 2>&1 || { echo "error: '$tool' is required" >&2; exit 2; }
done

# job, instance, health, last error — one tab-separated line per active target
fetch_targets() {
    curl -fsS --max-time 10 "$URL/api/v1/targets?state=active" |
        jq -r '.data.activeTargets[] | [.labels.job, .labels.instance, .health, (.lastError // "")] | @tsv'
}

deadline=$(( SECONDS + TIMEOUT ))
reachable=false
while :; do
    if targets=$(fetch_targets 2>/dev/null); then
        reachable=true
        total=$(grep -c . <<<"$targets" || true)
        down=$(awk -F'\t' '$3 != "up"' <<<"$targets" | grep -c . || true)
        if [[ $total -ge $MIN_TARGETS && $down -eq 0 ]]; then
            break
        fi
    fi
    if [[ $SECONDS -ge $deadline ]]; then
        break
    fi
    sleep "$INTERVAL"
done

if [[ $reachable == false ]]; then
    echo "CRIT: Prometheus not reachable at $URL after ${TIMEOUT}s" >&2
    exit 2
fi

printf '%-16s %-28s %-8s %s\n' JOB INSTANCE HEALTH LAST_ERROR
awk -F'\t' '{ printf "%-16s %-28s %-8s %s\n", $1, $2, $3, $4 }' <<<"$targets"
echo

if [[ $down -gt 0 ]]; then
    echo "CRIT: $down of $total targets not up after ${TIMEOUT}s"
    exit 1
fi
if [[ $total -lt $MIN_TARGETS ]]; then
    echo "CRIT: only $total active targets, expected at least $MIN_TARGETS"
    exit 1
fi
echo "OK: all $total targets up"
