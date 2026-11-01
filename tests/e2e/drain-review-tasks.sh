#!/usr/bin/env bash
# Completes every open Workflow review task the way the Workflow Inbox does, so the
# TriageProcess instances waiting for them can finish.
#
# For each task in the Worklist (namespace IRISAPP): picks the row of the user the task is
# assigned to or, when nobody owns it, the SuperUser row (else any row); takes ownership
# (EnsLib.Workflow.Engine.%TakeOwnershipForTask, the Inbox "Accept") when nobody owns it,
# then runs the action (%ProcessAction, the Inbox button). Waits until the Worklist is
# empty and until data/out/REVIEWED has one more *.review.json per completed task.
#
# WAIT_FOR_TASKS=N first waits until the Worklist has at least N tasks (they are created
# asynchronously, after the .final.json is written).
#
# Needs the "iris" service up with the production running (the Inbox buttons need it too).
# Usage: tests/e2e/drain-review-tasks.sh [ACTION]       (ACTION: Release (default) or KeepOnHold)

set -uo pipefail

cd "$(dirname "$0")/../.." || exit 2

ACTION="${1:-Release}"
WAIT_FOR_TASKS="${WAIT_FOR_TASKS:-0}"
WAIT_SECONDS=60

if [[ ! "$ACTION" =~ ^[A-Za-z]+$ ]]; then
    echo "FAIL: invalid action \"$ACTION\"" >&2
    exit 2
fi

# Runs ObjectScript read from stdin in the IRISAPP namespace.
iris_exec() {
    docker compose exec -T iris iris session IRIS -U IRISAPP
}

# Prints "<rows> <tasks>" of the Worklist (one row per task and user).
worklist_count() {
    iris_exec <<'EOF' | sed -n 's/^WL_COUNT //p'
Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) AS n, COUNT(DISTINCT Task) AS t FROM EnsLib_Workflow.Worklist") Do rs.%Next() Write !,"WL_COUNT ",+rs.n," ",+rs.t,!
Halt
EOF
}

count_reviewed() {
    ls data/out/REVIEWED/*.review.json 2>/dev/null | wc -l
}

# One pass over the Worklist. Prints "DRAIN_FAIL ..." per task it could not complete and
# "DRAIN_RESULT <completed> <failed>".
drain_pass() {
    {
        printf 'Set action="%s"\n' "$ACTION"
        cat <<'EOF'
Kill rows Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT ID, Task, UserName FROM EnsLib_Workflow.Worklist") While rs.%Next() { Set rows(rs.Task,rs.UserName)=rs.ID }
Set (done,failed)=0,t="" For { Set t=$ORDER(rows(t)) Quit:t=""  Set task=##class(EnsLib.Workflow.TaskResponse).%OpenId(t),owner=$SELECT($ISOBJECT(task):task.%TaskStatus.AssignedTo,1:""),who=owner Set:who="" who=$SELECT($DATA(rows(t,"SuperUser")):"SuperUser",1:$ORDER(rows(t,""))) Set item=$GET(rows(t,who)),msg="",sc=1 If '$ISOBJECT(task) { Set msg="task not found" } ElseIf item="" { Set msg="no Worklist row for "_who } ElseIf owner="" { Set sc=##class(EnsLib.Workflow.Engine).%TakeOwnershipForTask(item,who,.msg) } If sc,msg="" { Set sc=##class(EnsLib.Workflow.Engine).%ProcessAction(action,item,who,.msg) } If sc,msg="" { Set done=done+1 } Else { Set failed=failed+1 Write !,"DRAIN_FAIL task ",t," item ",item,": ",$SELECT('sc:$SYSTEM.Status.GetErrorText(sc),1:msg),! } }
Write !,"DRAIN_RESULT ",done," ",failed,!
Halt
EOF
    } | iris_exec | grep -E '^DRAIN_'
}

if ((WAIT_FOR_TASKS > 0)); then
    for ((i = 0; i < WAIT_SECONDS; i++)); do
        read -r rows tasks <<<"$(worklist_count)"
        ((${tasks:-0} >= WAIT_FOR_TASKS)) && break
        sleep 1
    done
    if ((${tasks:-0} < WAIT_FOR_TASKS)); then
        echo "WARNING: the Worklist has ${tasks:-0} tasks after ${WAIT_SECONDS}s, expected $WAIT_FOR_TASKS" >&2
    fi
fi

reviewed_before=$(count_reviewed)
completed=0
failed=0
# A task created during a pass is picked up by the next one.
for pass in 1 2 3; do
    read -r rows tasks <<<"$(worklist_count)"
    if [[ -z "${rows:-}" ]]; then
        echo "FAIL: could not read the Worklist" >&2
        exit 1
    fi
    ((rows == 0)) && break
    out=$(drain_pass)
    grep '^DRAIN_FAIL' <<<"$out" >&2
    read -r pass_done pass_failed <<<"$(sed -n 's/^DRAIN_RESULT //p' <<<"$out")"
    completed=$((completed + ${pass_done:-0}))
    failed=$((failed + ${pass_failed:-0}))
    ((${pass_done:-0} == 0)) && break
done

# CompleteTask deletes the rows right away; the REVIEWED files come later, through the
# TriageProcess and the DecisionFileOperation queue.
read -r rows tasks <<<"$(worklist_count)"
want_reviewed=$((reviewed_before + completed))
for ((i = 0; i < WAIT_SECONDS; i++)); do
    (($(count_reviewed) >= want_reviewed)) && break
    sleep 1
done
reviewed_new=$(($(count_reviewed) - reviewed_before))

echo "Review tasks completed with $ACTION: $completed (failed: $failed, Worklist rows left: ${rows:-?}, new REVIEWED files: $reviewed_new)."
[[ "${rows:-}" == "0" ]] && ((failed == 0 && reviewed_new >= completed))
