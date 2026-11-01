#!/usr/bin/env bash
# End-to-end test: the Workflow review of HOLD_FOR_REVIEW messages, with the AgentOperation
# in REPLAY, completing each task the way the Workflow Inbox does.
#
# Sets Mode=REPLAY on the running production (Ens.Director, namespace IRISAPP), completes
# the review tasks left open (drain-review-tasks.sh, action Release) and cleans data/out
# and data/error. Then, for sample 06 (rules only, action Release) and sample 02 (agent,
# action KeepOnHold): drops the sample into data/in and checks the .final.json in
# HOLD_FOR_REVIEW, the new task in the Worklist (one row for SuperUser and one for
# _SYSTEM, subject, actions), Accept (EnsLib.Workflow.Engine.%TakeOwnershipForTask) and
# the action (%ProcessAction) as SuperUser, the REVIEWED/<MSH-10>.review.json and the
# empty Worklist. Also checks that the LabReviewer role has SuperUser and _SYSTEM
# (created by iris.script). At the end, Mode goes back to empty.
#
# Needs the "iris" service up (docker compose up -d) and python3.
# Usage: tests/e2e/workflow.sh

set -uo pipefail

cd "$(dirname "$0")/../.." || exit 2

WAIT_SECONDS=60
DEV="/home/irisowner/dev"
ROLE="LabReviewer"
REVIEWER="SuperUser"

# Sample, MSH-10, OBR-2, agent of the final file (provider/attempts or no-agent), action.
ROUNDS=(
    "06-invalid-value.hl7 SYN-ORU-0006 ORD-1006 no-agent Release"
    "02-abnormal-mild.hl7 SYN-ORU-0002 ORD-1002 replay/1 KeepOnHold"
)

NAMES=()
RESULTS=()

# Records one check: name, PASS or FAIL, detail.
record() {
    NAMES+=("$1")
    RESULTS+=("$2${3:+  ($3)}")
    echo "[$2] $1${3:+ - $3}"
}

# Records PASS when the reasons (one per line) are empty, else FAIL with the reasons.
check() {
    local name="$1" reasons="$2" summary="$3"
    if [[ -z "$reasons" ]]; then
        record "$name" PASS "$summary"
    else
        record "$name" FAIL "$(paste -sd ';' <<<"$reasons" | sed 's/;/; /g')"
    fi
}

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
drop_sample() {
    docker compose exec -T iris sh -c "cp $DEV/data/samples/$1 $DEV/data/in/$1.part && mv $DEV/data/in/$1.part $DEV/data/in/$1"
}

# Prints one line per Worklist row: "WL^<item id>^<task id>^<user>^<role>".
worklist_rows() {
    iris_exec <<'EOF' | grep '^WL\^'
Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT ID, Task, UserName, RoleName FROM EnsLib_Workflow.Worklist ORDER BY Task, UserName") While rs.%Next() { Write !,"WL^",rs.ID,"^",rs.Task,"^",rs.UserName,"^",rs.RoleName }
Write !
Halt
EOF
}

# Prints "TASK^<subject>^<actions>^<assigned to>^<role>^<complete>" of a task.
task_info() {
    {
        printf 'Set id="%s"\n' "$1"
        cat <<'EOF'
Set t=##class(EnsLib.Workflow.TaskResponse).%OpenId(id) If $ISOBJECT(t) { Write !,"TASK^",t.%Subject,"^",t.%Actions,"^",t.%TaskStatus.AssignedTo,"^",$SELECT($ISOBJECT(t.%TaskStatus.Role):t.%TaskStatus.Role.Name,1:""),"^",t.%TaskStatus.IsComplete,! } Else { Write !,"TASK^not found",! }
Halt
EOF
    } | iris_exec | grep '^TASK\^'
}

# Users of the LabReviewer role, sorted, comma-separated.
role_users() {
    {
        printf 'Set role="%s"\n' "$ROLE"
        cat <<'EOF'
Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT ID FROM EnsLib_Workflow.RoleMembership WHERE ID %STARTSWITH ?",role_"||") While rs.%Next() { Write !,"RM|",$PIECE(rs.ID,"||",2) }
Write !
Halt
EOF
    } | iris_exec | sed -n 's/^RM|//p' | sort | paste -sd ','
}

# What the Inbox does: Accept (%TakeOwnershipForTask), then the action button (%ProcessAction).
# Prints "TAKE^<status ok>^<status text>^<msg>^<assigned to>" and "ACTION^<status ok>^<status text>^<msg>".
complete_task() {
    local item="$1" user="$2" action="$3"
    {
        printf 'Set item="%s",user="%s",action="%s"\n' "$item" "$user" "$action"
        cat <<'EOF'
Set msg="",sc=##class(EnsLib.Workflow.Engine).%TakeOwnershipForTask(item,user,.msg),t=##class(EnsLib.Workflow.TaskResponse).%OpenId($PIECE(item,"||",1)) Write !,"TAKE^",+sc,"^",$SELECT(sc:"",1:$SYSTEM.Status.GetErrorText(sc)),"^",msg,"^",$SELECT($ISOBJECT(t):t.%TaskStatus.AssignedTo,1:""),!
Set msg="",sc=##class(EnsLib.Workflow.Engine).%ProcessAction(action,item,user,.msg) Write !,"ACTION^",+sc,"^",$SELECT(sc:"",1:$SYSTEM.Status.GetErrorText(sc)),"^",msg,!
Halt
EOF
    } | iris_exec | grep -E '^(TAKE|ACTION)\^'
}

# Waits for the .final.json of an MSH-10 and prints its path.
wait_final() {
    local file
    for ((i = 0; i < WAIT_SECONDS; i++)); do
        file=$(ls data/out/*/"$1"*.final.json 2>/dev/null | head -n 1)
        if [[ -n "$file" ]]; then
            echo "$file"
            return 0
        fi
        sleep 1
    done
    return 1
}

# Waits until the Worklist has exactly N rows and prints them (the task is created after the final file).
wait_worklist_rows() {
    local want="$1" rows=""
    for ((i = 0; i < WAIT_SECONDS; i++)); do
        rows=$(worklist_rows)
        (($(grep -c '^WL\^' <<<"$rows") == want)) && break
        sleep 1
    done
    echo "$rows"
}

# Prints one reason per line for every failed check of the final file; nothing means pass.
check_final() {
    python3 -I -c '
import glob, json, sys

msh10, want_agent = sys.argv[1:]
files = glob.glob("data/out/*/" + msh10 + "*.final.json")
if len(files) != 1:
    print("%d final files for %s, expected 1" % (len(files), msh10))
    sys.exit()
path = files[0]
if not path.startswith("data/out/HOLD_FOR_REVIEW/"):
    print("file in %s, expected data/out/HOLD_FOR_REVIEW" % path.rsplit("/", 1)[0])
d = json.load(open(path))
if d["decision"] != "HOLD_FOR_REVIEW":
    print("decision %s, expected HOLD_FOR_REVIEW" % d["decision"])
a = d["agent"]
agent = a["provider"] + "/" + str(a["attempts"]) if a["called"] else "no-agent"
if agent != want_agent:
    print("agent %s, expected %s" % (agent, want_agent))
' "$@"
}

# Prints one reason per line for every failed check of the review file; nothing means pass.
check_review() {
    python3 -I -c '
import datetime, glob, json, re, sys

msh10, order, want_action, want_reviewer, want_role = sys.argv[1:]

def ts(value):
    # ISO UTC with "T" and "Z", 0 to 6 fraction digits.
    m = re.fullmatch(r"(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d)(?:\.(\d{1,6}))?Z", value or "")
    if not m:
        raise ValueError("not ISO UTC: %r" % value)
    base = datetime.datetime.strptime(m.group(1), "%Y-%m-%dT%H:%M:%S")
    return base + datetime.timedelta(microseconds=int((m.group(2) or "0").ljust(6, "0")))

files = glob.glob("data/out/*/" + msh10 + "*.review.json")
if files != ["data/out/REVIEWED/" + msh10 + ".review.json"]:
    print("review files %s, expected data/out/REVIEWED/%s.review.json" % (files, msh10))
    sys.exit()
d = json.load(open(files[0]))
final = json.load(open(glob.glob("data/out/*/" + msh10 + "*.final.json")[0]))

want = {"messageControlId": msh10, "outputType": "REVIEW", "orderId": order,
        "patientId": final["patientId"], "action": want_action,
        "reviewer": want_reviewer, "role": want_role}
for key, value in want.items():
    if d.get(key) != value:
        print("%s %r, expected %r" % (key, d.get(key), value))
try:
    created, completed, emitted = (ts(d.get(k)) for k in ("taskCreatedAt", "taskCompletedAt", "emittedAt"))
    if not created <= completed <= emitted:
        print("expected taskCreatedAt <= taskCompletedAt <= emittedAt: %s, %s, %s"
              % (d["taskCreatedAt"], d["taskCompletedAt"], d["emittedAt"]))
except ValueError as e:
    print(e)
' "$@"
}

# Waits for the review file of an MSH-10 (written after the action, through the process).
wait_review() {
    for ((i = 0; i < WAIT_SECONDS; i++)); do
        compgen -G "data/out/REVIEWED/$1*.review.json" >/dev/null && return 0
        sleep 1
    done
    return 1
}

print_summary() {
    local i failures=0
    echo
    echo "==== workflow check summary ===="
    for i in "${!NAMES[@]}"; do
        printf '%-45s %s\n' "${NAMES[$i]}" "${RESULTS[$i]}"
        [[ "${RESULTS[$i]}" == FAIL* ]] && failures=$((failures + 1))
    done
    echo "$(( ${#NAMES[@]} - failures ))/${#NAMES[@]} checks passed."
    ((failures == 0))
}

restore_mode() {
    echo
    if set_agent_mode ""; then
        echo "AgentOperation restored: Mode empty."
    else
        echo "WARNING: could not restore the AgentOperation Mode." >&2
    fi
}

finish() {
    local rc=$?
    restore_mode
    exit "$rc"
}
trap finish EXIT

if ! set_agent_mode "REPLAY"; then
    echo "FAIL: could not set Mode=REPLAY"
    exit 1
fi

# a. Open tasks keep TriageProcess instances waiting and would be counted below.
if drain_out=$(tests/e2e/drain-review-tasks.sh Release 2>&1); then
    record "open review tasks drained" PASS "$(tail -n 1 <<<"$drain_out")"
else
    record "open review tasks drained" FAIL "$(paste -sd ';' <<<"$drain_out")"
fi

# b.
clean_outputs

role_checked=0
for line in "${ROUNDS[@]}"; do
    read -r sample msh10 order agent action <<<"$line"
    tag="${sample%%-*} $action"

    # c. Final file first, then the task (sent after it), one Worklist row per role user.
    if ! drop_sample "$sample"; then
        record "$tag: sample dropped into data/in" FAIL
        continue
    fi
    if wait_final "$msh10" >/dev/null; then
        check "$tag: final file in HOLD_FOR_REVIEW" "$(check_final "$msh10" "$agent" 2>&1)" "$agent"
    else
        record "$tag: final file in HOLD_FOR_REVIEW" FAIL "no $msh10.final.json after ${WAIT_SECONDS}s"
    fi

    rows=$(wait_worklist_rows 2)
    task_ids=$(cut -d'^' -f3 <<<"$rows" | sed '/^$/d' | sort -u)
    users=$(cut -d'^' -f4 <<<"$rows" | sed '/^$/d' | sort | paste -sd ',')
    roles=$(cut -d'^' -f5 <<<"$rows" | sed '/^$/d' | sort -u | paste -sd ',')
    reasons=""
    if (($(grep -c '^WL\^' <<<"$rows") != 2 || $(sed '/^$/d' <<<"$task_ids" | wc -l) != 1)); then
        reasons="Worklist rows: $(paste -sd ' ' <<<"$rows"), expected 2 rows of one task"
    else
        [[ "$users" == "SuperUser,_SYSTEM" ]] || reasons+="users $users, expected SuperUser,_SYSTEM"$'\n'
        [[ "$roles" == "$ROLE" ]] || reasons+="role $roles, expected $ROLE"$'\n'
        IFS='^' read -r _ subject actions assigned task_role complete <<<"$(task_info "$task_ids")"
        want_subject="Lab results held for review: MSH-10 $msh10, order $order"
        [[ "$subject" == "$want_subject" ]] || reasons+="subject \"$subject\", expected \"$want_subject\""$'\n'
        [[ "$actions" == "Release,KeepOnHold" ]] || reasons+="actions \"$actions\", expected Release,KeepOnHold"$'\n'
        [[ -z "$assigned" && "$complete" == "0" ]] || reasons+="task already assigned to \"$assigned\" or complete ($complete)"$'\n'
    fi
    check "$tag: review task in the Worklist" "$(sed '/^$/d' <<<"$reasons")" "task $task_ids, users $users"

    # d. Once: the users the role was given by iris.script.
    if ((role_checked == 0)); then
        role_checked=1
        members=$(role_users)
        if [[ "$members" == "SuperUser,_SYSTEM" ]]; then
            record "role $ROLE has SuperUser and _SYSTEM" PASS
        else
            record "role $ROLE has SuperUser and _SYSTEM" FAIL "members: ${members:-none}"
        fi
    fi

    # e. Accept, then the action button, as SuperUser.
    item="$(head -n 1 <<<"$task_ids")||$REVIEWER"
    if ! grep -qF "WL^$item^" <<<"$rows"; then
        record "$tag: Accept as $REVIEWER" FAIL "no Worklist row $item"
        record "$tag: $action as $REVIEWER" FAIL "no Worklist row $item"
    else
        out=$(complete_task "$item" "$REVIEWER" "$action")
        IFS='^' read -r _ take_ok take_err take_msg take_owner <<<"$(grep '^TAKE\^' <<<"$out")"
        IFS='^' read -r _ act_ok act_err act_msg <<<"$(grep '^ACTION\^' <<<"$out")"
        if [[ "$take_ok" == "1" && -z "$take_msg" && "$take_owner" == "$REVIEWER" ]]; then
            record "$tag: Accept as $REVIEWER" PASS "%TakeOwnershipForTask $item"
        else
            record "$tag: Accept as $REVIEWER" FAIL "status ${take_ok:-?} ${take_err} msg \"$take_msg\" assigned to \"$take_owner\""
        fi
        if [[ "$act_ok" == "1" && -z "$act_msg" ]]; then
            record "$tag: $action as $REVIEWER" PASS "%ProcessAction $action"
        else
            record "$tag: $action as $REVIEWER" FAIL "status ${act_ok:-?} ${act_err} msg \"$act_msg\""
        fi
    fi

    # f. Review file, written after the TaskResponse reaches the process.
    if wait_review "$msh10"; then
        check "$tag: review file" "$(check_review "$msh10" "$order" "$action" "$REVIEWER" "$ROLE" 2>&1)" "REVIEWED/$msh10.review.json"
    else
        record "$tag: review file" FAIL "no data/out/REVIEWED/$msh10.review.json after ${WAIT_SECONDS}s"
    fi
    left=$(worklist_rows)
    if [[ -z "$left" ]]; then
        record "$tag: Worklist empty" PASS
    else
        record "$tag: Worklist empty" FAIL "$(paste -sd ' ' <<<"$left")"
    fi
done

print_summary
