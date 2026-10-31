#!/usr/bin/env bash
# Clean-clone check: what a judge gets from
#   git clone ... && cd iris-lab-triage-agent && docker compose up -d --build
#
# Clones the committed HEAD of this local repo into a temp dir (nothing is pushed), with no
# .env, starts the stack and checks that: the iris service does not crash-loop, the
# production starts by itself, the iris service reaches "healthy" (compose healthcheck),
# irisowner (uid 51773) can write the data folders, /home/irisowner/iris-main.log exists,
# and tests/e2e/samples.sh passes inside the clone.
#
# Stops the stack of this repo first (docker compose down, so the ports are free) and does
# not start it again. The clone runs under its own compose project name, so its image,
# containers and "down -v" never touch the ones of this repo.
#
# Needs git, docker compose and python3 (for samples.sh).
# Usage: tests/e2e/clean-clone-check.sh       (KEEP=1 leaves the clone and its stack up)

set -uo pipefail

REPO_ROOT=$(git -C "$(dirname "$0")" rev-parse --show-toplevel) || exit 2
PROJECT="labtriage-clean-clone"
WAIT_SECONDS=180
HEALTH_WAIT_SECONDS=240
DEV="/home/irisowner/dev"
KEEP="${KEEP:-0}"

TMP_DIR=""
CLONE=""
NAMES=()
RESULTS=()

# Records one check: name, PASS or FAIL, optional detail.
record() {
    NAMES+=("$1")
    RESULTS+=("$2${3:+  ($3)}")
    echo "[$2] $1${3:+ - $3}"
}

# docker compose for the clone's project, run inside the clone.
dc() {
    (cd "$CLONE" && docker compose -p "$PROJECT" "$@")
}

# Prints "<status ok> <production name> <state>" of IRISAPP; state 1 = running.
production_status() {
    dc exec -T iris iris session IRIS -U IRISAPP 2>/dev/null <<'EOF' | sed -n 's/^PRODSTATUS //p'
Set tSC=##class(Ens.Director).GetProductionStatus(.name,.state) Write !,"PRODSTATUS ",+tSC," ",$Get(name)," ",$Get(state),!
Halt
EOF
}

# Prints "<status> <restart count>" of the iris container, empty if there is none.
iris_container_state() {
    local cid
    cid=$(dc ps -aq iris 2>/dev/null | head -n 1)
    [[ -n "$cid" ]] && docker inspect -f '{{.State.Status}} {{.RestartCount}}' "$cid" 2>/dev/null
}

# Prints the health status of the iris container (starting, healthy, unhealthy), empty if none.
iris_health() {
    local cid
    cid=$(dc ps -aq iris 2>/dev/null | head -n 1)
    [[ -n "$cid" ]] && docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{end}}' "$cid" 2>/dev/null
}

print_summary() {
    local i failures=0
    echo
    echo "==== clean-clone check summary ===="
    for i in "${!NAMES[@]}"; do
        printf '%-45s %s\n' "${NAMES[$i]}" "${RESULTS[$i]}"
        [[ "${RESULTS[$i]}" == FAIL* ]] && failures=$((failures + 1))
    done
    echo "$(( ${#NAMES[@]} - failures ))/${#NAMES[@]} checks passed."
    ((failures == 0))
}

# Files written by the container belong to uid 51773, so the host user cannot remove them:
# they are deleted from inside the container (or, if iris is not up, from the one-shot
# init-perms service, which runs as root on ./data).
cleanup() {
    [[ -n "$TMP_DIR" ]] || return
    if [[ "$KEEP" == "1" ]]; then
        echo
        echo "KEEP=1: clone left at $CLONE, stack left up (project $PROJECT)."
        echo "Clean up with: (cd $CLONE && docker compose -p $PROJECT down -v) && rm -rf $TMP_DIR"
        return
    fi
    echo
    echo "Cleaning up..."
    if [[ -d "$CLONE" ]]; then
        if [[ "$(iris_container_state)" == running* ]]; then
            dc exec -T iris find "$DEV" -mindepth 1 -user 51773 -delete
        else
            dc run --rm --no-deps init-perms find /data -mindepth 1 -user 51773 -delete
        fi
        dc down -v --remove-orphans
    fi
    rm -rf "$TMP_DIR" || echo "WARNING: could not remove $TMP_DIR" >&2
}

finish() {
    local rc=$?
    cleanup
    exit "$rc"
}
trap finish EXIT
trap 'exit 130' INT TERM

if [[ -n "$(git -C "$REPO_ROOT" status --porcelain)" ]]; then
    echo "WARNING: $REPO_ROOT has uncommitted changes. This check only tests committed HEAD ($(git -C "$REPO_ROOT" rev-parse --short HEAD))." >&2
fi

echo "Stopping the stack of $REPO_ROOT (it will not be restarted)..."
(cd "$REPO_ROOT" && docker compose down) || echo "WARNING: docker compose down failed in $REPO_ROOT" >&2

TMP_DIR=$(mktemp -d)
CLONE="$TMP_DIR/iris-lab-triage-agent"
if git clone -q "$REPO_ROOT" "$CLONE"; then
    record "git clone of HEAD" PASS "$CLONE"
else
    record "git clone of HEAD" FAIL
    print_summary
    exit 1
fi

if [[ -e "$CLONE/.env" ]]; then
    record "no .env in the clone" FAIL ".env is committed"
else
    record "no .env in the clone" PASS
fi

if dc up -d --build; then
    up_at=$SECONDS
    record "docker compose up -d --build" PASS
else
    record "docker compose up -d --build" FAIL
    print_summary
    exit 1
fi

# Waits for the production, failing fast if the container crash-loops.
restarting=""
running=""
start=$SECONDS
while ((SECONDS - start < WAIT_SECONDS)); do
    read -r cstatus restarts <<<"$(iris_container_state)"
    if [[ "$cstatus" == "restarting" || "${restarts:-0}" -gt 0 ]]; then
        restarting="status ${cstatus:-none}, ${restarts:-0} restarts"
        break
    fi
    read -r sc_ok pname pstate <<<"$(production_status)"
    if [[ "${sc_ok:-}" == "1" && "${pstate:-}" == "1" ]]; then
        running="$pname after $((SECONDS - start)) s"
        break
    fi
    sleep 3
done

if [[ -n "$restarting" ]]; then
    record "iris service not Restarting" FAIL "$restarting"
    dc logs --tail 30 iris
    print_summary
    exit 1
fi
record "iris service not Restarting" PASS "$(iris_container_state)"

if [[ -n "$running" ]]; then
    record "production running (state 1)" PASS "$running"
else
    record "production running (state 1)" FAIL "not running after ${WAIT_SECONDS}s, last status: $(production_status)"
fi

# Counted from "docker compose up", so start_period (120 s) is inside the budget.
health=""
while ((SECONDS - up_at < HEALTH_WAIT_SECONDS)); do
    health=$(iris_health)
    [[ "$health" == "healthy" ]] && break
    sleep 5
done
if [[ "$health" == "healthy" ]]; then
    record "iris service healthy" PASS "after $((SECONDS - up_at)) s"
else
    record "iris service healthy" FAIL "status ${health:-none} after ${HEALTH_WAIT_SECONDS}s"
fi

for d in in out error archive replay; do
    if dc exec -T -u 51773 iris sh -c "f=$DEV/data/$d/.write-check-\$\$ && touch \"\$f\" && rm -f \"\$f\""; then
        record "data/$d writable by uid 51773" PASS
    else
        record "data/$d writable by uid 51773" FAIL
    fi
done

if dc exec -T iris test -f /home/irisowner/iris-main.log; then
    record "/home/irisowner/iris-main.log exists" PASS
else
    record "/home/irisowner/iris-main.log exists" FAIL
fi

echo
echo "Running tests/e2e/samples.sh in the clone..."
if (cd "$CLONE" && COMPOSE_PROJECT_NAME="$PROJECT" tests/e2e/samples.sh); then
    record "tests/e2e/samples.sh" PASS
else
    record "tests/e2e/samples.sh" FAIL
fi

print_summary
