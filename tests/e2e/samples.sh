#!/usr/bin/env bash
# End-to-end test: the 20 files of data/samples through the running production, with the
# AgentOperation in REPLAY, checked against the expected outcome of each sample.
#
# Sets Mode=REPLAY on the running production (Ens.Director, namespace IRISAPP), cleans
# data/out and data/error, drops every sample into data/in and, once all of them are
# processed, checks for each sample: the folder of the final file, decision, agent,
# reasonCode of every exam, the critical alert (CRITICAL samples), the corrected flag
# (0021) and the error files of the malformed samples (09 and 10). At the end, Mode goes
# back to empty.
#
# Needs the "iris" service up (docker compose up -d) and python3.
# Usage: tests/e2e/samples.sh

set -uo pipefail

cd "$(dirname "$0")/../.." || exit 2

WAIT_SECONDS=180
EXPECTED_FINALS=18
DEV="/home/irisowner/dev"

# Sample, MSH-10, decision, agent (provider/attempts or no-agent), "code=reasonCode" of
# every exam, extra check ("corrected" = every exam has "corrected": true, "-" = none).
SAMPLES=(
    "01-normal.hl7               SYN-ORU-0001 RELEASE         no-agent 718-7=NORMAL,2345-7=NORMAL,2823-3=NORMAL,2160-0=NORMAL,2951-2=NORMAL -"
    "02-abnormal-mild.hl7        SYN-ORU-0002 HOLD_FOR_REVIEW replay/1 2345-7=AGENT_FLAGGED,718-7=NORMAL,2823-3=NORMAL,2160-0=NORMAL,2951-2=NORMAL -"
    "03-abnormal-combo.hl7       SYN-ORU-0003 HOLD_FOR_REVIEW replay/1 2823-3=AGENT_FLAGGED,2160-0=AGENT_FLAGGED -"
    "04-critical.hl7             SYN-ORU-0004 CRITICAL        no-agent 2823-3=CRITICAL_HIGH,2160-0=NORMAL -"
    "05-critical-and-invalid.hl7 SYN-ORU-0005 CRITICAL        no-agent 718-7=CRITICAL_LOW,2951-2=INVALID_VALUE -"
    "06-invalid-value.hl7        SYN-ORU-0006 HOLD_FOR_REVIEW no-agent 718-7=NORMAL,2951-2=INVALID_VALUE -"
    "07-unexpected-unit.hl7      SYN-ORU-0007 HOLD_FOR_REVIEW no-agent 2345-7=UNEXPECTED_UNIT -"
    "08-preliminary.hl7          SYN-ORU-0008 HOLD_FOR_REVIEW no-agent 718-7=NOT_FINAL,2345-7=NOT_FINAL,2823-3=NOT_FINAL,2160-0=NOT_FINAL,2951-2=NOT_FINAL -"
    "11-prompt-injection.hl7     SYN-ORU-0011 HOLD_FOR_REVIEW replay/1 2823-3=AGENT_FLAGGED,2160-0=AGENT_FLAGGED -"
    "13-critical-and-abnormal.hl7 SYN-ORU-0013 CRITICAL       replay/1 2823-3=CRITICAL_HIGH,2345-7=AGENT_FLAGGED,2160-0=NORMAL -"
    "14-unsupported-exam.hl7     SYN-ORU-0014 HOLD_FOR_REVIEW no-agent 3016-3=UNSUPPORTED_EXAM,718-7=NORMAL,2345-7=NORMAL -"
    "15-lab-critical-flag.hl7    SYN-ORU-0015 CRITICAL        no-agent 2823-3=CRITICAL_LAB_FLAG -"
    "16-boundary.hl7             SYN-ORU-0016 HOLD_FOR_REVIEW replay/1 2823-3=AGENT_FLAGGED -"
    "17-blank-flags.hl7          SYN-ORU-0017 RELEASE         no-agent 718-7=NORMAL,2345-7=NORMAL,2823-3=NORMAL,2160-0=NORMAL,2951-2=NORMAL -"
    "18-unknown-flag.hl7         SYN-ORU-0018 HOLD_FOR_REVIEW no-agent 2345-7=UNKNOWN_FLAG -"
    "19-unparseable-range.hl7    SYN-ORU-0019 HOLD_FOR_REVIEW no-agent 2951-2=UNPARSEABLE_RANGE -"
    "20-duplicate-exam.hl7       SYN-ORU-0020 CRITICAL        no-agent 2823-3=CRITICAL_HIGH -"
    "21-corrected.hl7            SYN-ORU-0021 RELEASE         no-agent 718-7=NORMAL,2345-7=NORMAL,2823-3=NORMAL,2160-0=NORMAL,2951-2=NORMAL corrected"
)

# Malformed samples: sample|messageControlId|patientId|reason ("null" = JSON null, empty reason = not checked).
ERRORS=(
    "09-malformed-no-msh.hl7|null|null|"
    "10-malformed-no-obx.hl7|SYN-ORU-0010|SYN-000110|The message has no OBX segment."
)

# Runs ObjectScript read from stdin in the IRISAPP namespace.
iris_exec() {
    docker compose exec -T iris iris session IRIS -U IRISAPP
}

# Sets Mode of the AgentOperation and applies it to the running production.
set_agent_mode() {
    local mode="$1" out
    out=$(iris_exec <<EOF
Set tSC=##class(Ens.Director).SetHostSettingValue("AgentOperation","Mode","$mode") If tSC Set tSC=##class(Ens.Director).UpdateProduction(30)
Write !,\$SELECT(tSC:"SETTINGS_OK",1:"SETTINGS_ERROR "_\$SYSTEM.Status.GetErrorText(tSC)),!
Write "SETTINGS_NOW Mode=[",##class(Ens.Director).GetHostSettingValue("AgentOperation","Mode"),"]",!
Halt
EOF
)
    if ! grep -q '^SETTINGS_OK' <<<"$out" || ! grep -qF "SETTINGS_NOW Mode=[$mode]" <<<"$out"; then
        grep -E '^SETTINGS_' <<<"$out" >&2
        return 1
    fi
}

# The output files belong to the container user, so they are removed from inside it.
# The shell glob skips dot files, so .gitkeep stays.
clean_outputs() {
    docker compose exec -T iris sh -c "rm -f $DEV/data/out/*/*.json $DEV/data/error/*"
}

# Copies under a name the FileSpec (*.hl7) ignores, then renames, so the adapter never sees half a file.
drop_samples() {
    docker compose exec -T iris sh -c "cd $DEV/data/samples && for f in *.hl7; do cp \"\$f\" ../in/\"\$f\".part && mv ../in/\"\$f\".part ../in/\"\$f\" || exit 1; done"
}

count_finals() {
    ls data/out/*/*.final.json 2>/dev/null | wc -l
}

# Waits until data/in has no *.hl7 left and data/out has EXPECTED_FINALS final files.
wait_processed() {
    for ((i = 0; i < WAIT_SECONDS; i++)); do
        if ! compgen -G "data/in/*.hl7" >/dev/null && (($(count_finals) == EXPECTED_FINALS)); then
            return 0
        fi
        sleep 1
    done
    return 1
}

# Prints one reason per line for every failed check of a sample with a final file; nothing means pass.
check_final() {
    python3 -I -c '
import collections, datetime, glob, json, sys

msh10, want_decision, want_agent, want_exams, extra = sys.argv[1:]

def ts(value):
    return datetime.datetime.fromisoformat(value.replace("Z", "+00:00"))

files = glob.glob("data/out/*/" + msh10 + "*.final.json")
if len(files) != 1:
    print("%d final files for %s, expected 1" % (len(files), msh10))
    sys.exit()
path = files[0]
d = json.load(open(path))

if not path.startswith("data/out/" + want_decision + "/"):
    print("file in %s, expected data/out/%s" % (path.rsplit("/", 1)[0], want_decision))
if d["decision"] != want_decision:
    print("decision %s, expected %s" % (d["decision"], want_decision))

a = d["agent"]
agent = a["provider"] + "/" + str(a["attempts"]) if a["called"] else "no-agent"
if agent != want_agent:
    print("agent %s, expected %s" % (agent, want_agent))

exams = d["released"] + d["review"] + d["critical"]
counts = collections.Counter(e["code"] for e in exams)
repeated = sorted(c + "x" + str(n) for c, n in counts.items() if n != 1)
if repeated:
    print("exam codes not unique: " + ",".join(repeated))
got = ",".join(sorted(e["code"] + "=" + e["reasonCode"] for e in exams))
want = ",".join(sorted(want_exams.split(",")))
if got != want:
    print("exams %s, expected %s" % (got, want))
errors = sorted(e["code"] for e in exams if e["reasonCode"] == "PROCESSING_ERROR")
if errors:
    print("PROCESSING_ERROR in " + ",".join(errors))

if extra == "corrected":
    missing = sorted(e["code"] for e in exams if e.get("corrected") is not True)
    if missing:
        print("not corrected: " + ",".join(missing))

if want_decision == "CRITICAL":
    alert_path = "data/out/ALERTS/" + msh10 + ".critical.json"
    try:
        alert = json.load(open(alert_path))
    except OSError:
        print("no " + alert_path)
        sys.exit()
    alert_codes = sorted(e["code"] for e in alert["released"] + alert["review"] + alert["critical"])
    critical_codes = sorted(e["code"] for e in d["critical"])
    if alert["released"] or alert["review"] or alert_codes != critical_codes:
        print("alert exams %s, expected only the critical ones %s" % (",".join(alert_codes), ",".join(critical_codes)))
    if ts(alert["emittedAt"]) > ts(d["emittedAt"]):
        print("alert emittedAt %s after final emittedAt %s" % (alert["emittedAt"], d["emittedAt"]))
' "$@"
}

# Same contract as check_final, for a malformed sample that must end up in data/error.
check_error() {
    local sample="$1" want_msh10="$2" want_patient="$3" want_reason="$4"
    if [[ "$want_msh10" != "null" ]]; then
        local out_files
        out_files=$(ls data/out/*/"$want_msh10"* 2>/dev/null)
        [[ -n "$out_files" ]] && echo "files in data/out: $(paste -sd ' ' <<<"$out_files")"
    fi
    if [[ ! -f "data/error/$sample" ]]; then
        echo "no data/error/$sample"
    elif ! cmp -s "data/samples/$sample" "data/error/$sample"; then
        echo "data/error/$sample differs from the sample"
    fi
    python3 -I -c '
import json, sys

path, want_msh10, want_patient, want_reason = sys.argv[1:]
try:
    d = json.load(open(path))
except OSError:
    print("no " + path)
    sys.exit()

def show(value):
    return "null" if value is None else value

if show(d.get("messageControlId")) != want_msh10:
    print("messageControlId %s, expected %s" % (show(d.get("messageControlId")), want_msh10))
if show(d.get("patientId")) != want_patient:
    print("patientId %s, expected %s" % (show(d.get("patientId")), want_patient))
if want_reason and d.get("reason") != want_reason:
    print("reason \"%s\", expected \"%s\"" % (d.get("reason"), want_reason))
' "data/error/$sample.error.json" "$want_msh10" "$want_patient" "$want_reason"
}

# A sample without MSH-10 cannot be matched by name, so any file in data/out besides the
# expected finals and alerts counts against it.
check_no_extra_outputs() {
    local expected=() line sample msh10 decision rest
    for line in "${SAMPLES[@]}"; do
        read -r sample msh10 decision rest <<<"$line"
        expected+=("data/out/$decision/$msh10.final.json")
        [[ "$decision" == "CRITICAL" ]] && expected+=("data/out/ALERTS/$msh10.critical.json")
    done
    local extra=()
    for f in data/out/*/*; do
        [[ -e "$f" ]] || continue
        [[ " ${expected[*]} " == *" $f "* ]] || extra+=("$f")
    done
    ((${#extra[@]} == 0)) || echo "unexpected files in data/out: ${extra[*]}"
}

restore_mode() {
    echo
    if set_agent_mode ""; then
        echo "AgentOperation restored: Mode empty."
    else
        echo "WARNING: could not restore the AgentOperation Mode." >&2
    fi
}
trap restore_mode EXIT

if ! set_agent_mode "REPLAY"; then
    echo "FAIL: could not set Mode=REPLAY"
    exit 1
fi
clean_outputs
if ! drop_samples; then
    echo "FAIL: could not drop the samples into data/in"
    exit 1
fi
if ! wait_processed; then
    echo "WARNING: after ${WAIT_SECONDS}s, data/in still has $(compgen -G 'data/in/*.hl7' | wc -l) *.hl7 and data/out has $(count_finals)/$EXPECTED_FINALS final files"
fi

failures=0
total=0

# Prints PASS or FAIL for a sample, given the reasons (one per line) its checks printed.
report() {
    local sample="$1" reasons="$2" summary="$3"
    total=$((total + 1))
    printf '%-30s ' "$sample"
    if [[ -z "$reasons" ]]; then
        echo "PASS  ($summary)"
    else
        echo "FAIL: $(paste -sd ';' <<<"$reasons" | sed 's/;/; /g')"
        failures=$((failures + 1))
    fi
}

for line in "${SAMPLES[@]}"; do
    read -r sample msh10 decision agent exams extra <<<"$line"
    reasons=$(check_final "$msh10" "$decision" "$agent" "$exams" "$extra" 2>&1)
    report "$sample" "$reasons" "$decision, $agent"
done

for line in "${ERRORS[@]}"; do
    IFS='|' read -r sample msh10 patient reason <<<"$line"
    reasons=$(check_error "$sample" "$msh10" "$patient" "$reason" 2>&1)
    [[ "$msh10" == "null" ]] && reasons=$(printf '%s\n%s' "$reasons" "$(check_no_extra_outputs)" | sed '/^$/d')
    report "$sample" "$reasons" "data/error, messageControlId $msh10"
done

echo
echo "$((total - failures))/$total samples passed."
((failures == 0))
