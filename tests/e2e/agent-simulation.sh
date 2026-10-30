#!/usr/bin/env bash
# End-to-end test: scenario 03 (potassium 5.6 H + creatinine 2.1 H) through every
# simulated outcome of the AgentOperation, checked against the "03 + simulação" rows
# of the spec's scenario table.
#
# For each case: sets Mode=SIMULATION and SimulatedOutcome on the running production
# (Ens.Director, namespace IRISAPP), drops the sample into data/in and checks the final
# JSON file. At the end, Mode goes back to empty and SimulatedOutcome to HOLD_ALL.
#
# Needs the "iris" service up (docker compose up -d). Uses jq when installed, else python3.
# Usage: tests/e2e/agent-simulation.sh

set -uo pipefail

cd "$(dirname "$0")/../.." || exit 2

SAMPLE="03-abnormal-combo.hl7"
MSH10="SYN-ORU-0003"
EXPECTED_DECISION="HOLD_FOR_REVIEW"
WAIT_SECONDS=60
DEV="/home/irisowner/dev"

# Outcome, expected reasonCode for 2823-3 (potassium), for 2160-0 (creatinine), attempts.
CASES=(
    "HOLD_ALL           AGENT_FLAGGED  AGENT_FLAGGED  1"
    "HOLD_FIRST         AGENT_FLAGGED  AGENT_RELEASED 1"
    "TIMEOUT            AGENT_FALLBACK AGENT_FALLBACK 2"
    "TIMEOUT_THEN_VALID AGENT_FLAGGED  AGENT_FLAGGED  2"
    "RATE_LIMIT         AGENT_FALLBACK AGENT_FALLBACK 1"
    "INVALID            AGENT_FALLBACK AGENT_FALLBACK 2"
    "INVALID_THEN_VALID AGENT_FLAGGED  AGENT_FLAGGED  2"
    "FENCED             AGENT_FLAGGED  AGENT_FLAGGED  1"
)

# Runs ObjectScript read from stdin in the IRISAPP namespace.
iris_exec() {
    docker compose exec -T iris iris session IRIS -U IRISAPP
}

# Sets Mode and SimulatedOutcome of the AgentOperation and applies them to the running production.
set_agent_settings() {
    local mode="$1" outcome="$2" out
    out=$(iris_exec <<EOF
Set tSC=##class(Ens.Director).SetHostSettingValue("AgentOperation","Mode","$mode") If tSC Set tSC=##class(Ens.Director).SetHostSettingValue("AgentOperation","SimulatedOutcome","$outcome") If tSC Set tSC=##class(Ens.Director).UpdateProduction(30)
Write !,\$SELECT(tSC:"SETTINGS_OK",1:"SETTINGS_ERROR "_\$SYSTEM.Status.GetErrorText(tSC)),!
Write "SETTINGS_NOW Mode=[",##class(Ens.Director).GetHostSettingValue("AgentOperation","Mode"),"] SimulatedOutcome=[",##class(Ens.Director).GetHostSettingValue("AgentOperation","SimulatedOutcome"),"]",!
Halt
EOF
)
    if ! grep -q '^SETTINGS_OK' <<<"$out" || ! grep -qF "SETTINGS_NOW Mode=[$mode] SimulatedOutcome=[$outcome]" <<<"$out"; then
        grep -E '^SETTINGS_' <<<"$out" >&2
        return 1
    fi
}

# The output files belong to the container user, so they are removed from inside it.
clean_outputs() {
    docker compose exec -T iris sh -c "rm -f $DEV/data/out/*/$MSH10*.json $DEV/data/out/*/$MSH10*.json.tmp"
}

# Copies under a name the FileSpec (*.hl7) ignores, then renames, so the adapter never sees half a file.
drop_sample() {
    docker compose exec -T iris sh -c "cp $DEV/data/samples/$SAMPLE $DEV/data/in/$SAMPLE.part && mv $DEV/data/in/$SAMPLE.part $DEV/data/in/$SAMPLE"
}

# Prints the path of the final file once it exists, or fails after WAIT_SECONDS.
wait_final() {
    local file
    for ((i = 0; i < WAIT_SECONDS; i++)); do
        file=$(ls data/out/*/"$MSH10"*.final.json 2>/dev/null | head -n 1)
        if [[ -n "$file" ]]; then
            echo "$file"
            return 0
        fi
        sleep 1
    done
    return 1
}

# One line: decision, agent.called, agent.attempts, then "code=reasonCode" of every exam, sorted.
summarize() {
    if command -v jq >/dev/null 2>&1; then
        jq -r '[.decision, (.agent.called | tojson), (.agent.attempts | tojson),
                ([.released[], .review[], .critical[]] | map(.code + "=" + .reasonCode) | sort | join(","))] | join(" ")' "$1"
    else
        python3 -I -c '
import json, sys
d = json.load(open(sys.argv[1]))
exams = sorted(e["code"] + "=" + e["reasonCode"] for e in d["released"] + d["review"] + d["critical"])
print(d["decision"], json.dumps(d["agent"].get("called")), json.dumps(d["agent"].get("attempts")), ",".join(exams))
' "$1"
    fi
}

restore_settings() {
    echo
    if set_agent_settings "" "HOLD_ALL"; then
        echo "AgentOperation restored: Mode empty, SimulatedOutcome HOLD_ALL."
    else
        echo "WARNING: could not restore the AgentOperation settings." >&2
    fi
}
trap restore_settings EXIT

failures=0
for case in "${CASES[@]}"; do
    read -r outcome want_potassium want_creatinine want_attempts <<<"$case"
    printf '%-20s ' "$outcome"

    if ! set_agent_settings "SIMULATION" "$outcome"; then
        echo "FAIL: could not apply the settings"
        failures=$((failures + 1))
        continue
    fi
    clean_outputs
    drop_sample

    if ! file=$(wait_final); then
        echo "FAIL: no final file in data/out after ${WAIT_SECONDS}s"
        failures=$((failures + 1))
        continue
    fi

    read -r decision called attempts exams <<<"$(summarize "$file")"
    want_exams="2160-0=$want_creatinine,2823-3=$want_potassium"
    reasons=()
    [[ "$file" == data/out/$EXPECTED_DECISION/* ]] || reasons+=("file in ${file%/*}, expected data/out/$EXPECTED_DECISION")
    [[ "$decision" == "$EXPECTED_DECISION" ]] || reasons+=("decision $decision, expected $EXPECTED_DECISION")
    [[ "$called" == "true" ]] || reasons+=("agent.called $called, expected true")
    [[ "$attempts" == "$want_attempts" ]] || reasons+=("agent.attempts $attempts, expected $want_attempts")
    [[ "$exams" == "$want_exams" ]] || reasons+=("exams $exams, expected $want_exams")

    if ((${#reasons[@]} == 0)); then
        echo "PASS  (2823-3 $want_potassium, 2160-0 $want_creatinine, attempts $attempts)"
    else
        printf -v reason '%s; ' "${reasons[@]}"
        echo "FAIL: ${reason%; }"
        failures=$((failures + 1))
    fi
done

echo
echo "$(( ${#CASES[@]} - failures ))/${#CASES[@]} cases passed."
((failures == 0))
