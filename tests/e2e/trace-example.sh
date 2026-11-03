#!/usr/bin/env bash
# Reproducible example: the LLM calls of the production and their metadata in Visual Trace.
# Runs in REPLAY, so no API key is needed, and creates or changes no recording.
#
# Sends the 3 messages of data/trace-example through the running production:
#   a) SYN-TRACE-0001  critical potassium: CRITICAL by the rule alone, the agent is not called;
#   b) SYN-TRACE-0002  abnormal potassium with a recording in data/replay: one AgentRequest and
#                      one AgentResponse with PromptVersion, InputTokens, OutputTokens, LatencyMs;
#   c) SYN-TRACE-0003  abnormal glucose with no recording: REPLAY answers NO_KEY and the
#                      TriageProcess sends the exam to review (FALLBACK, AGENT_FALLBACK).
# For each case it reads Ens.MessageHeader and the message bodies of that session, checks the
# behavior above and prints the SessionId, the final decision and the Visual Trace URL.
#
# Sets Mode=REPLAY on the AgentOperation (Ens.Director, namespace IRISAPP) and sets the previous
# Mode back at the end. Does not clean data/out. Cases b and c are HOLD_FOR_REVIEW, so each run
# leaves two open review tasks in the Workflow Inbox (samples.sh and workflow.sh complete them).
#
# Needs the "iris" service up (docker compose up -d) and python3.
# Usage: tests/e2e/trace-example.sh
# PORTAL_URL changes the Management Portal address (default http://localhost:52773).

set -uo pipefail

cd "$(dirname "$0")/../.." || exit 2

WAIT_SECONDS=60
DEV="/home/irisowner/dev"
PORTAL_URL="${PORTAL_URL:-http://localhost:52773}"
TRACE_URL="$PORTAL_URL/csp/healthshare/irisapp/EnsPortal.VisualTrace.zen?SESSIONID="
MSH10S=(SYN-TRACE-0001 SYN-TRACE-0002 SYN-TRACE-0003)

# Runs ObjectScript read from stdin in the IRISAPP namespace.
iris_exec() {
    docker compose exec -T iris iris session IRIS -U IRISAPP
}

get_agent_mode() {
    iris_exec <<'EOF' | sed -n 's/^MODE_NOW \[\(.*\)\]\r\{0,1\}$/\1/p'
Write !,"MODE_NOW [",##class(Ens.Director).GetHostSettingValue("AgentOperation","Mode"),"]",!
Halt
EOF
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

# Highest Ens.MessageHeader ID before the run: only messages after it belong to this run.
last_header_id() {
    iris_exec <<'EOF' | sed -n 's/^MAXID \([0-9]*\).*/\1/p'
Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT MAX(ID) AS M FROM Ens.MessageHeader") Do rs.%Next() Write !,"MAXID ",+rs.M,!
Halt
EOF
}

# Copies under a name the FileSpec (*.hl7) ignores, then renames, so the adapter never sees half a file.
drop_messages() {
    docker compose exec -T iris sh -c "cd $DEV/data/trace-example && for f in *.hl7; do cp \"\$f\" ../in/\"\$f\".part && mv ../in/\"\$f\".part ../in/\"\$f\" || exit 1; done"
}

# Number of SYN-TRACE-* messages with a FINAL output sent after header pBase.
count_finals() {
    iris_exec <<EOF | sed -n 's/^FINALS \([0-9]*\).*/\1/p'
Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(DISTINCT t.MessageControlId) AS N FROM LabTriage_Msg.TriageResponse t JOIN Ens.MessageHeader h ON h.MessageBodyId = t.ID AND h.MessageBodyClassName = 'LabTriage.Msg.TriageResponse' WHERE t.MessageControlId %STARTSWITH 'SYN-TRACE-' AND t.OutputType = 'FINAL' AND h.ID > ?",$1) Do rs.%Next() Write !,"FINALS ",+rs.N,!
Halt
EOF
}

wait_processed() {
    local base="$1"
    for ((i = 0; i < WAIT_SECONDS; i++)); do
        (($(count_finals "$base") == ${#MSH10S[@]})) && return 0
        sleep 1
    done
    return 1
}

# One CASEJSON line per MSH-10: session, final output, agent messages and alerts of the session.
inspect() {
    local base="$1" msh10
    {
        echo "Set tBase=$base"
        for msh10 in "${MSH10S[@]}"; do
            echo "Set msh=\"$msh10\""
            cat <<'EOF'
Set sess="", j={"msh":(msh),"session":"","decision":"","agentCalled":0,"agentAttempts":0,"agentStatus":"","exams":[],"agentRequests":0,"agentResponses":[],"alerts":0}
Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT TOP 1 t.ID AS TID, h.SessionId AS SID FROM LabTriage_Msg.TriageResponse t JOIN Ens.MessageHeader h ON h.MessageBodyId = t.ID AND h.MessageBodyClassName = 'LabTriage.Msg.TriageResponse' WHERE t.MessageControlId = ? AND t.OutputType = 'FINAL' AND h.ID > ? ORDER BY h.ID DESC",msh,tBase) If rs.%Next() { Set sess=rs.SID, o=##class(LabTriage.Msg.TriageResponse).%OpenId(rs.TID), j.session=sess, j.decision=o.Decision, j.agentCalled=+o.AgentCalled, j.agentAttempts=+o.AgentAttempts, j.agentStatus=o.AgentStatus For l=o.Critical,o.Review,o.Released { For i=1:1:l.Count() { Set d=l.GetAt(i) Do j.exams.%Push(d.LoincCode_"="_d.ReasonCode_"/"_d.DecidedBy) } } }
If sess'="" { Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) AS N FROM Ens.MessageHeader WHERE SessionId = ? AND MessageBodyClassName = 'LabTriage.Msg.AgentRequest'",sess) Do rs.%Next() Set j.agentRequests=+rs.N }
If sess'="" { Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) AS N FROM Ens.MessageHeader h JOIN LabTriage_Msg.TriageResponse t ON t.ID = h.MessageBodyId WHERE h.SessionId = ? AND h.MessageBodyClassName = 'LabTriage.Msg.TriageResponse' AND t.OutputType = 'CRITICAL_ALERT'",sess) Do rs.%Next() Set j.alerts=+rs.N }
If sess'="" { Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT h.SourceConfigName AS ASrc, h.TargetConfigName AS ATgt, r.Status AS AStatus, r.Provider AS AProvider, r.PromptVersion AS APrompt, r.InputTokens AS AIn, r.OutputTokens AS AOut, r.LatencyMs AS ALatency, r.ErrorText AS AError FROM Ens.MessageHeader h JOIN LabTriage_Msg.AgentResponse r ON r.ID = h.MessageBodyId WHERE h.SessionId = ? AND h.MessageBodyClassName = 'LabTriage.Msg.AgentResponse' ORDER BY h.ID",sess) While rs.%Next() { Do j.agentResponses.%Push({"from":(rs.ASrc),"to":(rs.ATgt),"status":(rs.AStatus),"provider":(rs.AProvider),"promptVersion":(rs.APrompt),"inputTokens":(rs.AIn),"outputTokens":(rs.AOut),"latencyMs":(rs.ALatency),"errorText":(rs.AError)}) } }
Write !,"CASEJSON ",j.%ToJSON(),!
EOF
        done
        echo "Halt"
    } | iris_exec | sed -n 's/^CASEJSON //p'
}

# Checks each case and prints SessionId, decision, the agent messages and the Visual Trace URL.
report() {
    python3 -I -c '
import json, sys

trace_url = sys.argv[1]
cases = {c["msh"]: c for c in (json.loads(line) for line in sys.stdin if line.strip())}

def agent_line(r):
    return "AgentResponse %s -> %s: Status=%s Provider=%s PromptVersion=%s InputTokens=%s OutputTokens=%s LatencyMs=%s%s" % (
        r["from"], r["to"], r["status"], r["provider"], r["promptVersion"] or "(empty)", r["inputTokens"] or "(empty)",
        r["outputTokens"] or "(empty)", r["latencyMs"], (" ErrorText=\"%s\"" % r["errorText"]) if r["errorText"] else "")

def check_a(c):
    problems = []
    if c["decision"] != "CRITICAL": problems.append("decision %s, expected CRITICAL" % c["decision"])
    if c["agentCalled"] or c["agentRequests"] or c["agentResponses"]: problems.append("the agent was called")
    if c["alerts"] != 1: problems.append("%d CRITICAL_ALERT messages, expected 1" % c["alerts"])
    if "2823-3=CRITICAL_HIGH/RULE" not in c["exams"]: problems.append("no 2823-3=CRITICAL_HIGH/RULE")
    return problems

def check_b(c):
    problems = []
    if c["decision"] != "HOLD_FOR_REVIEW": problems.append("decision %s, expected HOLD_FOR_REVIEW" % c["decision"])
    if c["agentRequests"] != 1 or len(c["agentResponses"]) != 1: problems.append("%d AgentRequest / %d AgentResponse, expected 1 / 1" % (c["agentRequests"], len(c["agentResponses"])))
    for r in c["agentResponses"]:
        if (r["status"], r["provider"]) != ("OK", "replay"): problems.append("AgentResponse %s/%s, expected OK/replay" % (r["status"], r["provider"]))
        for field in ("promptVersion", "inputTokens", "outputTokens"):
            if r[field] in ("", None): problems.append(field + " empty")
        if not r["latencyMs"]: problems.append("latencyMs empty or 0")
    if "2823-3=AGENT_FLAGGED/AGENT" not in c["exams"]: problems.append("no 2823-3=AGENT_FLAGGED/AGENT")
    return problems

def check_c(c):
    problems = []
    if c["decision"] != "HOLD_FOR_REVIEW": problems.append("decision %s, expected HOLD_FOR_REVIEW" % c["decision"])
    if c["agentRequests"] != 1 or len(c["agentResponses"]) != 1: problems.append("%d AgentRequest / %d AgentResponse, expected 1 / 1" % (c["agentRequests"], len(c["agentResponses"])))
    for r in c["agentResponses"]:
        if (r["status"], r["provider"]) != ("NO_KEY", "replay"): problems.append("AgentResponse %s/%s, expected NO_KEY/replay" % (r["status"], r["provider"]))
    if c["agentStatus"] != "NO_KEY": problems.append("AgentStatus %s, expected NO_KEY" % c["agentStatus"])
    if "2345-7=AGENT_FALLBACK/FALLBACK" not in c["exams"]: problems.append("no 2345-7=AGENT_FALLBACK/FALLBACK")
    return problems

CASES = [
    ("a", "SYN-TRACE-0001", "CRITICAL by the rule alone, no agent call", check_a),
    ("b", "SYN-TRACE-0002", "agent call answered from a recording", check_b),
    ("c", "SYN-TRACE-0003", "agent call with no recording: NO_KEY, then fallback", check_c),
]

failures = 0
for key, msh, title, check in CASES:
    c = cases.get(msh)
    print()
    if not c or not c["session"]:
        print("(%s) %s  %s\n    FAIL: no FINAL output found for this run" % (key, msh, title))
        failures += 1
        continue
    problems = check(c)
    failures += bool(problems)
    print("(%s) %s  %s" % (key, msh, title))
    print("    Result:       " + ("PASS" if not problems else "FAIL: " + "; ".join(problems)))
    print("    SessionId:    %s" % c["session"])
    print("    Decision:     %s" % c["decision"])
    print("    Exams:        %s" % ", ".join(c["exams"]))
    if c["agentResponses"]:
        print("    Agent:        %d call(s), final AgentStatus=%s" % (c["agentRequests"], c["agentStatus"]))
        for r in c["agentResponses"]:
            print("    " + agent_line(r))
    else:
        print("    Agent:        not called; CRITICAL_ALERT messages: %d" % c["alerts"])
    print("    Visual Trace: %s%s" % (trace_url, c["session"]))

print()
print("%d/%d cases behaved as described." % (len(CASES) - failures, len(CASES)))
sys.exit(1 if failures else 0)
' "$TRACE_URL"
}

PREVIOUS_MODE=$(get_agent_mode)

restore_mode() {
    echo
    if set_agent_mode "$PREVIOUS_MODE"; then
        echo "AgentOperation restored: Mode [${PREVIOUS_MODE}]."
    else
        echo "WARNING: could not restore the AgentOperation Mode [${PREVIOUS_MODE}]." >&2
    fi
}
trap restore_mode EXIT

if ! set_agent_mode "REPLAY"; then
    echo "FAIL: could not set Mode=REPLAY"
    exit 1
fi

BASE=$(last_header_id)
if [[ -z "$BASE" ]]; then
    echo "FAIL: could not read Ens.MessageHeader"
    exit 1
fi
if ! drop_messages; then
    echo "FAIL: could not drop the messages into data/in"
    exit 1
fi
echo "Sent ${#MSH10S[@]} messages from data/trace-example (Mode=REPLAY). Waiting for the FINAL outputs..."
if ! wait_processed "$BASE"; then
    echo "WARNING: after ${WAIT_SECONDS}s, only $(count_finals "$BASE")/${#MSH10S[@]} messages have a FINAL output"
fi

inspect "$BASE" | report
