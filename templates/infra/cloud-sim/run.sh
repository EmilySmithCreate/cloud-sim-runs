#!/bin/sh
# Run one config through one runner and put what it produced in S3.
#
#   run.sh <runner> <run> [submitting commit]
#
# <runner> is scripts/<runner>.py (or an executable scripts/<runner>), <run> is configs/<run>.json. The runner writes
# its outputs into $SIM_OUTPUT_DIR. This script adds _run.json, a record of what ran, and uploads the folder to
# s3://$RESULTS_BUCKET/runs/<run>/. _run.json is uploaded last, so its presence in the bucket means the upload
# finished. A run that fails or is stopped goes to partial/<run>/ instead, which the bucket expires after 14 days.
set -eu

if [ $# -lt 2 ]; then
    echo "usage: run.sh <runner> <run> [commit]" >&2
    exit 2
fi
RUNNER="$1"
RUN="$2"
COMMIT="${3:-unknown}"

case "$RUNNER$RUN" in
    *[!A-Za-z0-9_-]*) echo "runner and run names may use only letters, digits, - and _" >&2; exit 2 ;;
esac
CONFIG="configs/${RUN}.json"
if [ ! -f "$CONFIG" ]; then
    echo "no such config: $CONFIG" >&2
    exit 2
fi
if [ -f "scripts/${RUNNER}.py" ]; then
    set -- python "scripts/${RUNNER}.py" "$CONFIG"
elif [ -x "scripts/${RUNNER}" ]; then
    set -- "scripts/${RUNNER}" "$CONFIG"
else
    echo "no such runner: scripts/${RUNNER}.py or an executable scripts/${RUNNER}" >&2
    exit 2
fi

OUT="${SIM_OUT_BASE:-/app/out}/${RUN}"
mkdir -p "$OUT"
export SIM_RUN_NAME="$RUN" SIM_OUTPUT_DIR="$OUT"
CONFIG_SHA=$(sha256sum "$CONFIG" | cut -d' ' -f1)
STARTED=$(date -u +%Y-%m-%dT%H:%M:%SZ)
T0=$(date +%s)

record() {
    cat > "$OUT/_run.json" <<EOF
{
  "run": "${RUN}",
  "runner": "${RUNNER}",
  "status": "$1",
  "exit_code": $2,
  "config_sha256": "${CONFIG_SHA}",
  "submitted_commit": "${COMMIT}",
  "image_commit": "${SIM_IMAGE_COMMIT:-unknown}",
  "batch_job_id": "${AWS_BATCH_JOB_ID:-local}",
  "started_utc": "${STARTED}",
  "finished_utc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "seconds": $(( $(date +%s) - T0 )),
  "python": "$(python --version 2>&1 | cut -d' ' -f2)"
}
EOF
}

save_partial() {
    record failed "$1"
    echo "--- run did not finish (exit $1); saving what it wrote to partial/${RUN}/"
    aws s3 cp --recursive --only-show-errors "$OUT" "s3://${RESULTS_BUCKET}/partial/${RUN}/" || true
    exit 1
}

# Batch stops a job by sending TERM to this script, then KILL 30 seconds later. The runner runs in the background so
# that the TERM is caught here at once, passed on, and the scratch saved.
echo "--- ${RUNNER} on ${RUN} (submitted from ${COMMIT}, image from ${SIM_IMAGE_COMMIT:-unknown})"
"$@" &
CHILD=$!
trap 'kill -TERM "$CHILD" 2>/dev/null; save_partial 143' TERM INT
STATUS=0
wait "$CHILD" || STATUS=$?
trap - TERM INT
[ "$STATUS" -eq 0 ] || save_partial "$STATUS"

record succeeded 0
echo "--- uploading to s3://${RESULTS_BUCKET}/runs/${RUN}/"
aws s3 cp --recursive --only-show-errors --exclude _run.json "$OUT" "s3://${RESULTS_BUCKET}/runs/${RUN}/"
aws s3 cp --only-show-errors "$OUT/_run.json" "s3://${RESULTS_BUCKET}/runs/${RUN}/_run.json"
echo "--- done in $(( $(date +%s) - T0 )) s"
