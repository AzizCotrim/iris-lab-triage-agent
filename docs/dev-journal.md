# Dev journal — LabTriage Agent

## 2026-10-23 — Environment setup (build 154)

### Image
- Downloaded irishealth-community-2026.3.0AI.154.0-docker.tar.gz (x64) from the EAP portal.
- Loaded image name: docker.iscinternal.com/docker-intersystems/intersystems/irishealth-community:2026.3.0AI.154.0
  Retagged to irishealth-community:2026.3.0AI.154.0 (as the organizers instructed).
- The portal README still references build 136 and the name intersystems/iris-community.
- Version: IRIS for UNIX (Ubuntu Server LTS for x86-64 Containers) 2026.3.0AI (Build 154U) Thu Sep 24 2026.

### Template (ai-hub-dev-template)
- Works with build 154 after changing line 1 of the Dockerfile.
- Kept merge.cpf unchanged (IRISAPP namespace with Interop=1). Dockerfile, docker-compose.yml and iris.script
  adapted from the template; removed MCP, Python venv, ZPM, Sample and port 8080.
- Template build log: zpm "enable -community" succeeds, but the next step in IRISAPP
  (zpm "install vscode-per-namespace-settings") prints "ERROR! No repositories are configured and enabled
  in this namespace" and the build continues. Not relevant to this project (step removed).
- First build takes about 5 minutes: the merge loads the FHIR resources into IRISAPP.

### Volume permissions
- Container restart loop: "Unable to find/open file iris-main.log in current directory /home/irisowner/dev".
- Cause: the repo is mounted at /home/irisowner/dev and irisowner (uid 51773) cannot write to a folder owned by the host user.
- Dev workaround: create iris-main.log, chmod a+rwx on the repo root, ACL for uid 51773 on data/in, out, error, archive.
- Git does not store permissions or ACLs: a clean clone hits the same problem. To fix before 01/11.
- Fixed on 10-31 (part 2): WORKDIR outside the bind mount and the init-perms service.

### Compose
- env_file: .env is required; docker compose fails if the file does not exist. Judges need to create it
  from .env.example, even in replay mode without an API key.
- Fixed on 10-31 (part 2): env_file is optional (required: false); with no .env the agent runs REPLAY.
- Changed restart policy from the template's "always" to "unless-stopped": during the iris-main.log
  permission loop the container restarted 9 times on its own.

### Gemini provider
- %AI.Provider.%GetProviders() confirms: provider "gemini", config "api_key", env var GOOGLE_API_KEY.
- The template docs and skills/ do not mention Gemini; confirmed only via %GetProviders() and the %AI.Provider source.
- SDK default model: gemini-3.1-pro-preview (not tested: Pro model).
- ListModels() also lists models that did not work with this key:
  - gemini-2.5-flash -> HTTP 404 "no longer available to new users"; the error message recommended gemini-3.8-flash
  - gemini-3.8-flash -> timeout (2 attempts, cause unknown)
  - gemini-3.5-flash-lite -> works
- Model id works without the "models/" prefix.
- Errors surface as %Exception.StatusException with <%AICore>ModelNotFound or <%AICore>InternalError (timeout).
- Latency (one-sentence prompt, gemini-3.5-flash-lite): 0.6-1.0 s in 5 of 6 calls; one outlier of 13.5 s
  (first call of the day). A first call in a new session took 0.8 s, so it is not a per-session startup cost.
- Timeout of 30 s per call kept; re-measure with the real triage prompt.

## 2026-10-24 — Tool calling test (template clone, not this repo)

- Switched Sample.Agent to provider "gemini", GOOGLE_API_KEY and gemini-3.5-flash-lite; enabled the ConsoleAudit policy in Sample.ToolSet.
- Tools declared only with /// comments and plain method/query signatures (as in Sample.Tools, no [ WebMethod ] or
  Parameter DESCRIPTION as shown in the toolsets reference) are discovered and called in build 154.
- The model listed only the 2 ObjectScript tools; the Python MCP server declared in Sample.ToolSet did not show up (cause unknown).
- One Chat() requested both tools in a single response (AddPerson and GetPeopleYoungerThan), before seeing the first result.
- ConsoleAudit prints each call with status, result and duration (5 ms and 62 ms).
- session.GetStats(): total_interactions 3, total_tool_calls 2, total_tool_duration_ms 69, total_llm_duration_ms 14608,
  total_prompt_tokens 809, total_completion_tokens 211. Latency is available in the stats (accumulated per session).
- With tools and a longer prompt, each LLM interaction took about 5 s (vs about 0.7 s for a one-sentence prompt).
- Each tool use adds one extra LLM interaction; the full history and tool list are resent on every interaction.
- The final answer matched the SQL result exactly (checked with SELECT on Sample.Person).
- Not tested yet: registering a tool instance with per-run state (needed to keep the patient key out of the LLM input).

## 2026-10-26 — Service design and message classes

### Service design
- Own Business Service with EnsLib.File.InboundAdapter, using EnsLib.HL7.Message only to parse.
  Not EnsLib.HL7.Service.FileService: it sends the EnsLib.HL7.Message itself to the target,
  so the Process would have to know HL7.
- Fields read by position (segment:field, loop over segments, check for OBX), no DocType.
  Validating against the 2.5.1 schema is optional.
- File Inbound Adapter docs disagree with each other: the guide shows %FileCharacterStream,
  a community article shows %Stream.FileCharacter, and the Charset default is "Default" on the
  settings page but "Native" in an online Class Reference for another product version.
  To check on build 154: log $classname(pInput).

### Numeric values
- Using text as a number truncates silently, with no error:
  "QNS"+0 = 0, "13,5"+0 = 13, "<0.5"+0 = 0.
  A sodium "QNS" would become 0 (false CRITICAL_LOW); a potassium "6,8" would become 6
  (a real critical missed).
- $ISVALIDNUM: "13.8" = 1; "QNS", "13,5", "<0.5" and "" = 0. The Service converts only after it.

### Time
- The container runs in UTC: $HOROLOG gave 20:53 at 17:53 local time.
- Messages store UTC with $ZTIMESTAMP (UTC by definition, not by container config).
  Conversion to -03:00 happens only in the DecisionFileOperation.

### Message classes
- ExamResult and ExamDecision: %SerialObject + %XML.Adaptor (saved inside the message).
- TriageRequest and TriageResponse: Ens.Request (TriageResponse is sent by the Process
  to the DecisionFileOperation).
- %String default MAXLEN is 50 (confirmed on build 154 with %Dictionary.CompiledProperty
  for ExamResult.Unit); raised to 255 where file data can be long.
- Read-only review by Claude Code: no save failures in the current scenarios;
  contradicting comments fixed in "fix: message comments and parameters".

### Not done
- Day goal (file in data/in, final in data/out) not reached. Per the plan, the delay
  comes out of the differentials.

### Deferred (from the review)
- EmittedAt: the Process sets it right before sending, with milliseconds (Process day).
- Truncated LLM response: with the agent fields (Wed 10-28).
- Status C marked as corrected, discarded duplicate value: with the 5 exams (Fri 10-30);
  adjust the "exactly one list" invariant in the spec.
- OBR-7 field and UTC vs local HL7 dates: with the delta check (Tue 11-03).
- Spec: "Campos usados" table says PID-5/7/8 and OBR-3 go to the output; only PID-3.1
  and OBR-2 do.

## 2026-10-27 — FileInbound service on build 154

### Observed on build 154
- The File Inbound Adapter passes %Library.FileCharacterStream (as in the adapter guide;
  the community article showing %Stream.FileCharacter does not match).
  Attributes("Filename") holds the full path inside the container.
- Ens.BusinessService.OnProcessInput has a third argument (ByRef pHint As %String);
  the example in the adapter guide shows only two.
- ImportFromLibraryStream on non-HL7 data returns an OK status and no object, with only
  a Warning ("Discarding received non-HL7 data"). The Service checks $ISOBJECT and
  returns its own error (#5001).
- When OnProcessInput returns an error, the adapter leaves the file in FilePath and skips
  it ("Skipping previously errored file"). Archived files get a timestamp suffix.
- After recompiling, a running item keeps the old code ("continuing to run using code
  from previous version"): restart the production.
- Saving in the Management Portal rewrites the production XData (default attributes on
  every item); check git diff on Production.cls before committing.
- EnsLib.HL7.Message: the segment count is SegCount; GetSegmentAt(i).Name gives the
  segment type; GetValueAt("i:field.component") reads a field.
- The Event Log shows times in UTC.

### Decisions
- ConfirmComplete = 1 (Size): on Linux a file can be opened while another process is
  still writing it, so Readable (the default) and Writable confirm nothing.
- SourceFileName keeps only the file name (%File.GetFilename), not the container path.
- Service checks, in order: import status, object returned, first segment is MSH,
  MSH-9.1 = ORU and MSH-9.2 = R01, at least one OBX (counted over the whole message).
- First MVP step reads only hemoglobin (718-7); the other exams come with the catalog.

## 2026-10-28 — First end-to-end flow

- Monday's milestone reached: 01-normal.hl7 in data/in produces
  data/out/RELEASE/SYN-ORU-0001.final.json (hemoglobin released by RULE, agent not called).
- TriageProcess is an ObjectScript class (Ens.BusinessProcess), not BPL: the
  validation, retry and fallback logic is easier to read and to unit test in code.
- Exams the Service marks with a reasonCode go to the review list; nothing invalid
  is released.
- DecisionFileOperation writes to a .tmp file and renames it, so a reader never sees a
  half-written file. PoolSize 1 keeps alert and final in arrival order.
- emittedAt is written in UTC as ISO 8601 with "Z" (e.g. 2026-10-28T19:38:50.244Z)
  instead of -03:00: unambiguous for judges in any time zone. Spec to be updated.
- Temporary: valid exams outside the reference range are still released; they go to
  the agent from the agent day on.

## 2026-10-29 — Critical rule and alert (work of 10-28 evening)

- Tuesday's milestone reached: 04-critical.hl7 produces out/ALERTS/SYN-ORU-0004.critical.json
  (potassium CRITICAL_HIGH) and out/CRITICAL/SYN-ORU-0004.final.json.
- Exam catalog (LabTriage.ExamCatalog) with the 5 exams; every OBX becomes an ExamResult,
  LOINC outside the catalog gets UNSUPPORTED_EXAM and a warning in the Event Log.
- CriticalLimits returns CRITICAL, OK or NOT_EVALUABLE. Empty value or a unit different from
  the catalog unit returns NOT_EVALUABLE. 31 %UnitTest tests (all limits of the 5 exams).
- ObjectScript evaluates operators strictly left to right, with no precedence:
  (a = b && c '= d) is read as ((a = b) && c) '= d. Every comparison needs its own parentheses.
- Unit match is case-sensitive: "mmol/l" is not "mmol/L"; the exam goes to review (fail-safe).
- The numeric literal 0.1 is written as .1; reasons use RawValue (as the laboratory sent it).
- Alert and final can share the same emittedAt (same millisecond) when the agent is not called;
  order is guaranteed by the operation queue (PoolSize 1), not by the timestamp.
- Files created by the container (uid 51773) cannot be deleted by the host user without an ACL.
  A stale final from an earlier run stays in another decision folder: start tests from an
  empty data/out.
- Running %UnitTest loads only the test classes; the class under test must be compiled first.

## 2026-10-29 — Agent in the flow

- Wednesday's milestone reached: 03-abnormal-combo.hl7 goes through the real LLM and ends in
  HOLD_FOR_REVIEW, both exams AGENT_FLAGGED. 13-critical-and-abnormal.hl7 matches the final
  output example of the spec: potassium CRITICAL by RULE (alert first), glucose flagged by
  AGENT, creatinine NORMAL by RULE.
- New classes: AgentRequest/AgentResponse, ReferenceRange, Sanitizer (allowlist payload),
  AgentContract (contract validation), TriageAgent (%AI.Agent subclass), AgentOperation.
- ReferenceRange reads the range before the flag: an unreadable range goes to review
  (UNPARSEABLE_RANGE) even with an abnormal flag, so the agent never gets an exam whose range
  the system cannot read. In a-b the bounds are normal; in <x and >x, x itself is abnormal.
  Known limitation: a negative lower bound (e.g. -1-5) is not read.
- Any agent failure (call error, status not OK, answer outside the contract) sends the exams
  to review as FALLBACK. The corrective retry comes next.
- 85 %UnitTest tests: CriticalLimits (31), ReferenceRange (23), AgentContract (31).
- Synthetic samples 02 to 21 generated by Claude Code from the scenario table (CR only,
  checked with od -c).

### AI Hub SDK on build 154 (checked in the container dictionary)
- Agent: subclass of %AI.Agent; prompt in XData INSTRUCTIONS; %Init() runs %OnInit() last,
  so provider, model and Temperature can be set there. Session: CreateSession(config);
  call: Chat(session, input) returns %AI.LLM.Response, text in .Content.
- GetStats() is on the session, not the agent (total_llm_duration_ms, total_prompt_tokens, ...).
- Errors are thrown as %Exception.StatusException. An unknown model raises
  <%AICore>ProviderError ("Model not found" only inside the text), not <%AICore>ModelNotFound
  as assumed on 10-23.
- timeout_ms exists in the session config, but it is checked once per iteration: an in-flight
  HTTP call is not cut. The Process protects itself with the SendRequestSync timeout (70 s).
- Temperature exists (set before CreateSession). No JSON response format option was found:
  contract validation in the Process is the only guarantee.
- Template docs that do not match build 154: %AI.System.StreamRenderer does not exist
  (%AI.Shell.StreamRenderer does); StreamChat has 3 arguments, not 4.

### Prompt
- With the real MVP prompt (scenario 03 payload), gemini-3.5-flash-lite answered exactly the
  contract (one JSON object, both codes flagged) in 865 ms.
- Before the prompt was loaded, the model answered in Portuguese with its own schema, CRITICAL
  and a treatment suggestion: an example of why the Process validates every answer.

## 2026-10-30 — Agent modes, retry, replay and the remaining MVP rules

- Thursday's and Friday's plans done: simulation, corrective retry, replay, NOT_FINAL /
  UNEXPECTED_UNIT / UNKNOWN_FLAG in the Service, corrected results, duplicate exams and the
  flag Lookup Table. Back on schedule.
- The 20 sample files (01 to 21; 12 is a differential) run in REPLAY mode, which needs no API
  key; python3 tests/e2e/summary.py lists the outputs. The 18 with output match the spec
  scenario table; 09 and 10 stay in data/in instead of going to data/error with an .error.json.

### Agent modes
- AgentOperation has three modes: REAL (Gemini), SIMULATION (configured outcome, provider
  never called) and REPLAY (answers recorded in REAL mode). The Mode setting wins; when empty,
  LABTRIAGE_AGENT_MODE decides; when that is empty too, REPLAY, so judges need no key.
- Corrective retry: at most 2 calls per message. A contract violation, a timeout, a provider
  error or an empty answer gets one retry (after a violation, the retry carries the previous
  answer and the violation). RATE_LIMIT and NO_KEY fall back at once.
- tests/e2e/agent-simulation.sh (written by Claude Code) runs scenario 03 through 8 simulated
  outcomes: all PASS, and no error path ends in RELEASE.
- Ens.Director.SetHostSettingValue + UpdateProduction change a setting on the running
  production without editing the local Production.cls (the class on the server is rewritten).
  Compiling Production.cls instead resets the settings changed in the portal.

### Replay
- Every OK answer in REAL mode is recorded in data/replay/<CRC-32>.json, keyed by the prompt
  version and the exact text sent to the model (payload, plus the correction on a retry).
  Recording every OK answer, not only valid ones, lets replay reproduce a retry path too.
- A missing PROMPTVERSION parameter made ##class(...).#PROMPTVERSION return "" without a
  compile error; recordings were keyed without the version and had to be redone.
- Scenario 11 (prompt injection in OBX-3.2 and NTE) produces exactly the same payload as
  scenario 03, so both use the same recording: the injected text never reaches the LLM.
- No recording for an input: NO_KEY, fallback with one attempt, and an Event Log warning.

### Service and Process
- The Service marks, first problem wins: UNSUPPORTED_EXAM, NOT_FINAL (C counts as final),
  UNEXPECTED_UNIT, INVALID_VALUE, UNKNOWN_FLAG. NumericValue is set only when none applies.
- Corrected results (OBX-11 = C) get "corrected": true in the output.
- Duplicate exam (same LOINC twice): the critical value wins and the discarded values are
  listed in the reason; with no critical value, DUPLICATE_EXAM in review. Each exam code
  appears in exactly one list. Spec invariant to be updated.

### Lookup Table
- Flag categories come from the Lookup Table LabTriage.FlagCategory (Ens.Util.LookupTable),
  editable in the portal: changing H to CRITICAL turned scenario 16 into CRITICAL_LAB_FLAG
  with no recompile and no restart.
- Defaults in config/FlagCategory.xml, loaded by iris.script with %Import and the table
  name (replaces the table; without the name it merges).
  Kept outside src/, because LoadDir also loads *.xml files.
- An empty key is not allowed (ERROR #5659); the Service turns an empty flag into N first.
  %GetValue with pExists tells an unknown flag from a known one. A missing table makes every
  flag unknown, so every exam goes to review.
- Fail-safe review fixes: an OBX with no OBX-3.1 no longer stops the Process (an empty
  subscript raises <SUBSCRIPT>), and a table value other than NORMAL, ABNORMAL or CRITICAL
  (e.g. a typo in the portal) counts as an unknown flag.

### Environment
- After compiling a Business Service, restart the production: the running job keeps the old
  code (scenarios 08 and 18 were released by the old FileInbound until the restart).
- When localhost:52773 does not answer from Windows, the portal works on the WSL IP
  (hostname -I); the IP changes when WSL restarts.
- Recreating the container (after changing .env) drops every class compiled after the image
  build; reload with $system.OBJ.LoadDir, or rebuild with docker compose up -d --build.
- "Import and Compile" on the src folder in VS Code pushes every local file to the server and
  clears the "version on the server is newer" warnings.
- Build 154 logs <METHOD DOES NOT EXIST>Sharding+2^STU at startup; not related to this project.

## 2026-10-31 — Fail-safe on exceptions, rejected files and safe output names

- Saturday's plan done: exception fail-safe, malformed files, safe output file names, style batch
  and the end-to-end test of the 20 samples (tests/e2e/samples.sh, 20/20 in REPLAY, about 50 s).

### Exception fail-safe
- TriageProcess.OnRequest wraps the triage in Try/Catch. Exams whose code is in none of the three
  lists go to review (FALLBACK, PROCESSING_ERROR), once per code; the final output is always emitted.
- A critical alert not sent yet still goes out before the final output (tAlertTried); a failed alert
  send becomes an exception, so the final output is not lost.
- Known limitation: an exam the critical rule had not evaluated yet when the exception happened goes
  to review, not to CRITICAL.
- Tested by hand with a temporary Throw in three places (before the count, before duplicates, before
  the agent) on sample 13.
- Empty LOINC no longer breaks the duplicate count (no empty subscript).

### Rejected files
- FileInbound no longer returns an error for an invalid file: it sends a RejectedFile to the new
  ErrorFileOperation and returns OK, so the adapter archives the input instead of skipping it forever.
- data/error gets a copy of the file (identical, checked with cmp) and <file>.error.json with reason,
  MSH-10 and PID-3 (null when absent) and receivedAt in UTC.
- Sample 09 (no MSH): ImportFromLibraryStream returns no object, so no MSH-10 and no PID-3.

### Output file names
- Only [A-Za-z0-9._-] from MSH-10 go into the file name, no leading dots, max 100, NO-MSH10 when
  empty; the JSON keeps the original MSH-10. A repeated MSH-10 gets a UTC timestamp suffix.
- IDs in TriageRequest and TriageResponse raised from MAXLEN 50 to 255: a longer MSH-10 failed %Save.

### Environment
- Agent mode REAL (from .env) rewrites data/replay on every OK answer (new recordedAt and wording):
  run regressions with Mode=REPLAY and git restore data/replay after a REAL run.
- The file adapter takes about 3 s per file with ConfirmComplete=1: the 20 samples need about a minute.
- Recreating the container drops what was done after the image build: classes compiled since then
  and Lookup Table edits made in the portal. The table itself comes back from the image
  (iris.script imports config/FlagCategory.xml at build time).

## 2026-10-31 (part 2) — Clean clone, healthcheck and README v1

- Sunday's plan (clean clone, as a judge would run it) done on Saturday, plus README v1.
  tests/e2e/clean-clone-check.sh: 13/13 PASS.

### Clean clone
- A fresh clone with no .env reproduced the 10-23 permission problem: a `Restarting (134)` loop
  (iris-main aborts). In the clone the root and data/* are 755 and owned by the host user, so
  uid 51773 can write nowhere. My working repo hid it (root 777, ACLs with defaults on data/*).
- Dockerfile: WORKDIR /home/irisowner after the build step, so iris-main.log is written inside the
  image, not in the bind mount. The repo root no longer needs to be writable.
- docker-compose: one-shot init-perms service (busybox, root): chmod 0777 on data/in, out, error,
  archive and replay, and chmod 0666 on the replay files; iris starts after it
  (service_completed_successfully). chmod, not chown: the host user must still write to data/in.
  No sticky bit: the adapter deletes files created by the host user.
- iris.script: SetAutoStart("LabTriage.Production") with the status checked (a failure fails the
  build). The production now starts on every container start.
- env_file is optional (required: false, needs Compose v2.24+); with no .env the agent runs REPLAY.
- The replay JSONs were committed as 100755 (created under the default ACL). init-perms drops the
  x bit, so git showed a mode change on every start. Recommitted as 100644.
- clean-clone-check.sh clones HEAD of the local repo into a temp dir (nothing is pushed), with no
  .env, runs up --build, waits for the production and for healthy, checks write access as uid
  51773, runs samples.sh and cleans up. It stops this repo's stack first.

### Base image
- iris-2026.3.0AI.154.0-docker.tar.gz (also downloaded on 10-23) is a different image
  (intersystems/iris); the right one is irishealth-community-...-docker.tar.gz. It is a plain tar
  despite the .gz name, and docker image load accepts both.
- The image is linux/amd64 only.

### Healthcheck
- The base image check (/irisHealth.sh) needs the instance status ok or warn. Build 154 leaves it
  in alert: the Sharding+2^STU error (see 10-30) and "System appears to have failed over from node
  buildkitsandbox" (IRIS ran during the build under another hostname).
- Compose healthcheck overridden: healthy means LabTriage.Production is running in IRISAPP
  (GetProductionStatus state 1).

### Measurements
- Full build: about 4 min (233 s). The build step bind-mounts the whole repo, so any change, even
  to the README, rebuilds it.
- Clean clone, REPLAY: production running after 61 to 90 s, healthy after 92 s.
- Working repo, REAL: healthy within about 2 min; one earlier run took 207 s (cause not confirmed).

### README v1
- Base image load and retag, quick start, LLM provider and modes, how to verify, how it works,
  output examples, known limitations, tests, project structure.

### Next
- Choose the differentials for 11-02 to 11-05: review queue (Workflow), delta check or audit policy.
- Update the spec with this week's changes.

## 2026-11-01 — Human review with Workflow

- Differential chosen: review queue. HOLD_FOR_REVIEW messages become Workflow tasks for the
  LabReviewer role; the reviewer's action is written to data/out/REVIEWED/<MSH-10>.review.json.

### Workflow in build 154
- Exported the EnsLib.Workflow classes from the container and read the source, since build 154
  has diverged from the documentation before. Signatures checked in %Dictionary.CompiledMethod.
- ShowActionButtons accepts free action names: %Actions="Release,KeepOnHold" shows those two
  buttons, and the button name comes back as %Action.
- The Inbox (_DeepSee.UserPortal.Workflow.zen) lists only the tasks of $UserName: the login must
  be a Workflow user (UserDefinition) in the role.
- Accept is required before the action: the Inbox calls Engine.%TakeOwnershipForTask on Accept and
  Engine.%ProcessAction on the button. %ProcessAction needs the task assigned to the user of the
  Worklist item. When it is not, it returns $$$OK with pMsg "This task is not assigned to the
  current user.", so the status alone proves nothing: check pMsg.
- A role with no users fails the task: OnNewTask returns EnsWfErrNoUsersFound. AutoCreateRole=1
  on the Workflow Operation creates the role, not its users.
- IdKeys: RoleDefinition and UserDefinition = Name; RoleMembership = "Role||User"; Worklist =
  (Task, User), id "<taskId>||<user>". In SQL the Worklist user column is UserName, not User.
- CompleteTask sets %UserName from %TaskStatus.AssignedTo (not from $UserName), deletes the
  Worklist rows of the task and sends the TaskResponse with SendDeferredResponse. So a script that
  calls the Engine from `iris session` (OS user irisowner) still records the reviewer it passed to
  %TakeOwnershipForTask.
- TaskStatus.TimeCreated and TimeCompleted are UTC with milliseconds (trailing zeros dropped,
  e.g. 12:50:08.82).
- The action buttons are disabled while the production is stopped.
- The Priority column of the Inbox is empty for our tasks (cause not investigated).

### Decisions
- Only the final decision HOLD_FOR_REVIEW becomes a task, agent fallback included. CRITICAL already
  has the alert file; RELEASE needs no human.
- Two actions, Release and KeepOnHold, written as received (the Workflow cancel value too).
- Separate .review.json in data/out/REVIEWED: the .final.json is written right away and never
  changes; the review is one more event, later. Same file name rules as the .final.json.
- SendRequestAsync to LabReviewer with OnResponse/OnError (key "review"): the Workflow Operation
  defers its response (DeferResponse) until a reviewer acts. OnError only logs a warning, so a
  Workflow problem never fails the triage.
- No timeout or expiration in the MVP. Each open task keeps one TriageProcess instance persisted.
- samples.sh leaves its 10 tasks open, so a judge finds them in the Workflow Inbox after the run.
  It completes the tasks still open with Release only at the start, before cleaning data/out
  (workflow.sh does the same).

### Setup (iris.script)
- After LoadDir and before SetAutoStart: CreateUser SuperUser and _SYSTEM, CreateRole LabReviewer,
  AddUserToRole for both, each step guarded by %ExistsId. A failure terminates the build like
  SetAutoStart does.
- Creation path tested in the running container inside a rolled-back transaction (test role),
  then for real by the clean-clone build.

### Tests
- New %UnitTest class LabTriage.Operation.TestDecisionFileOperation (7 tests): path
  <OutputPath>/REVIEWED/<MSH-10>.review.json, fields and key order, outputType REVIEW, ISO UTC
  timestamps, empty timestamp stays empty, unsafe MSH-10, empty MSH-10 (NO-MSH10), repeated
  MSH-10 (timestamp suffix, first file intact).
- The operation runs outside the production: %New(pConfigName) with a name that is not in the
  production gives a shadow instance (Ens.Host.initConfig: no settings, no OnInit). OutputPath
  is set by hand to a temporary folder, removed after each test.
- %File:FileSet returns folders whatever includedirs says (it only adds folders that do not match
  the wildcard); the test filters on Type "F".
- Full suite: 92/92 (85 + 7).
- tests/e2e/drain-review-tasks.sh completes every open task like the Inbox (Accept, then the
  action) and waits for the empty Worklist and the new .review.json files. It closed the 10 tasks
  the previous samples.sh run had left open.
- tests/e2e/samples.sh drains before cleaning data/out (the .review.json of the drained tasks
  arrive asynchronously, so they must land before the clean) and leaves its own 10 tasks open
  for the Inbox. A first version also drained after the checks; removed (see Decisions).
- tests/e2e/workflow.sh: drain, clean, then sample 06 (Release) and sample 02 (agent, KeepOnHold):
  final file, task in the Worklist (2 rows, subject, actions), role users, Accept, action,
  .review.json, empty Worklist. 14/14.
- First workflow.sh run failed on my own parsing: "|" as field separator collides with the "||"
  of the Worklist id. Switched to "^".
- tests/e2e/clean-clone-check.sh runs workflow.sh after samples.sh: 14/14 PASS (13 + workflow.sh).
  The clean build ran the new iris.script steps (role and users created, workflow.sh found them).
  Production running after 70 s, healthy after 72 s. Inside the clone, samples.sh leaves its 10
  tasks open and workflow.sh completes them at the start ("open review tasks drained").
  The clean-clone run itself used the first version of samples.sh, which drained at the end;
  the samples.sh then workflow.sh flow was rerun on the working repo (next item). Run against a
  staging clone holding the uncommitted changes, since the check clones committed HEAD.
- Rerun after removing the final drain: samples.sh 20/20, then 20 Worklist rows and 10 tasks;
  workflow.sh 14/14, with "open review tasks drained" = 10.

### AI Hub bug reports
- For the contest's "Find a bug in AI Hub" bonus. Done outside this repo (~/aihub-bugrepro); nothing in src/ changed.
- The two original candidates were dropped as duplicates: the `Sharding+2^STU` startup error (already #1) and
  timeout_ms not stopping the in-flight HTTP call (already #6).
- Method: a fake OpenAI/Anthropic-style server (Python, inside the container) instead of a real provider; a new
  throwaway container per run, no published ports; each repro run twice from scratch, same result both times. APIs and
  error codes checked in %Dictionary and %AI.Errors.inc, not in the docs. Two real Gemini calls only
  (gemini-3.5-flash-lite, output limit 1 token), key passed as an environment variable.
- The gemini provider rejects base_url (accepts only api_key, http_config, extra_config), so probing it took a hosts
  entry and a test CA in http_config.tls.ca_certificates. The reports use the openai provider with base_url.
- Posted: #9, the OpenAI-compatible providers drop finish_reason (a reply cut at the token limit comes back as a normal
  answer; with real Gemini and max_tokens 1, an empty success); #10, recognised provider errors (model not found,
  billing, timeout) are thrown as <%AICore>ProviderError instead of ModelNotFound, BillingError and Timeout, and a 503
  with a Google-style body is labelled "Rate limit exceeded".
- Effect on this project: a cut answer from Gemini reaches AgentOperation as OK; an empty one becomes EMPTY and a cut
  JSON fails AgentContract, so both still end in retry or fallback. ClassifyError matching on the error text is still
  needed because of #10.
- For later (optional, outside the MVP): http_config, accepted by every provider but not listed by %GetProviders(), has
  an undocumented request_timeout_secs (per-request HTTP timeout) that could bound the in-flight call instead of relying
  on the SendRequestSync timeout. Only its type was checked (u64), not its effect. Without it, a provider that never
  answered failed after about 60 s per attempt, 4 attempts (243.5 s).

## 2026-11-04 — IPM module (ZPM bonus)

### What changed
- New `LabTriage.Installer`, `Setup(pRoot)`: what iris.script did after LoadDir (Lookup Table import from
  `pRoot_"config/FlagCategory.xml"`, CreateUser SuperUser and _SYSTEM, CreateRole LabReviewer, AddUserToRole,
  SetAutoStart), each step guarded so a second run changes nothing. It also creates
  `/home/irisowner/dev/data/{in,out,error,archive,replay}` when missing and, when pRoot is not `/home/irisowner/dev/`,
  copies `data/replay/*.json` and `data/samples/*.hl7` from pRoot without overwriting.
- Second argument `pStartProduction` (default 0). With 1, after SetAutoStart, Setup starts LabTriage.Production
  only if no production is running, suspended or troubled in the namespace; if another one is, nothing is stopped
  and Setup writes which one is running and how to start ours. Inside a transaction (`$TLEVEL > 0`) the start is
  done by a job (`StartAfterCommit`) that waits for the end of the transaction (see below) and logs the outcome to
  messages.log.
- iris.script: LoadDir, then `Setup("/home/irisowner/dev/")`, Terminate if it fails. No setup logic left inline.
  It does not pass pStartProduction: AutoStart starts the production when the container starts.
- `module.xml`: `iris-lab-triage-agent` 1.0.1, `SystemRequirements Version=">=2026.3" Interoperability="enabled"`,
  `LabTriage.PKG`, file resources `/config/FlagCategory.xml`, `/data/replay/`, `/data/samples/` (needed by Setup in a
  registry install), one `<UnitTest Class=...>` per test class, `Invoke LabTriage.Installer.Setup` with `${root}`
  and `1`, `Phase="Activate" When="After"`.
- README: section "Install with IPM" (IPM client and registry commands copied from the IPM README,
  github.com/intersystems/ipm, README.md at commit 5a71f3c), Project structure.

### IPM vs build 154 (checked in the image and in the IPM 0.10.10 sources)
- No IPM client in the image: no `%IPM.Main` in IRISAPP or %SYS, no `zpm` command, and no
  `dist/install/misc/zpm.xml` (the folder has only buildver, hsutil.xml, iboot, iutil.*, update.*).
- `%IPM` classes exist only in HSLIB (module `ZPM` 0.10.5-SNAPSHOT, used by HealthShare for its own modules), not
  mapped to other namespaces. Not used: it is not the client a user installs.
- The current client is the registry installer (`/packages/zpm/latest/installer`, `IPM.Installer`, VERSION 0.10.10).
  Its sources were first read from the installer XML; later it was installed in a throwaway container only.
- IPM 0.9+ installs in the current namespace only; the README installs it in the app's namespace, as the IPM README
  says.
- The IPM README gives two ways to get the community registry: `zpm "enable -community"` (also maps IPM to every
  namespace) and `repo -r -n registry -url https://pm.community.intersystems.com/ -user "" -pass ""` (registry only).
  The README uses the second: `enable -map -globally -preview` showed IPM mappings would be added to HSCUSTOM, HSSYS
  and HSSYSLOCALTEMP, which use HealthShare's own IPM.
- `repo -r ... -pass ""` prints "WARNING: Using -password via the CLI is insecure" (IPM's own warning; the password is
  empty).
- `<UnitTest Package="LabTriage">` does not fit this repo: the Test processor's unique name is `<Package>.PKG`, so it
  would be `LabTriage.PKG`, the same as the app resource (`%IPM.Storage.ResourceReference` has
  `Index ResourceName On UniqueName [ Unique ]`). Also, the test phase does not delete test classes when the package
  already has classes, and a `.PKG` resource takes every class of the package found in the namespace.
  `<UnitTest Class="...">` gives each test class its own unique name (`<Class>.CLS`), and the `.PKG` resource skips
  classes owned by another resource, so the tests stay out of `LabTriage.PKG` without renaming the package. A new
  test class needs its own line in module.xml.
- `Invoke` defaults to `Phase="Configure"`. Configure is not in the phase list of load/install, but the load log
  prints "Configure START/SUCCESS" inside Activate, so the default may also run there; `Phase="Activate" When="After"`
  was kept because it is explicit.
- `load` and `install` (not in developer mode) run Reload, Compile and Activate in one transaction
  (`%IPM.Utils.Module`, TSTART before the phases, TCOMMIT after Activate, TROLLBACK on error). Compiling
  LabTriage.Production saves its configuration, and the transaction keeps the X lock on `^Ens.Config.ItemD(1)` until
  the commit (seen in `^$LOCK`, owner = the installing WorkQueue worker). A StartProduction called from the Invoke then
  failed after 30 s with `<Ens>ErrCanNotAcquireRuntimeLock` (twice, same result), and IPM rolled the whole install
  back (classes, module, Lookup Table, AutoStart; the folders created on disk stayed). A StartProduction inside a
  plain TSTART, with the classes compiled outside it, worked, so the transaction alone is not the cause. Hence the
  job that waits for the commit: Setup locks `^LabTriage.Installer("Start")`, jobs `StartAfterCommit`, and unlocks;
  inside a transaction the unlock only takes effect at TCOMMIT/TROLLBACK, so the job gets the lock right after the
  install ends. After a rollback AutoStart is no longer ours and the job does nothing.
- `zpm "iris-lab-triage-agent package"` exports the classes under `src/cls/LabTriage/...` (Package processor
  directory `cls`), not the repo layout `src/LabTriage/...`.
- Right after `docker run`, `iris qlist` says running while `iris session` still answers
  "Sign-on inhibited: Startup or Installation in progress" (about 20 to 70 s here).
- `${root}` comes from `NormalizeDirectory(Root)`, with a final "/". Setup normalizes it anyway.
- `SystemRequirements Version` is compared with major.minor only (`2026.3` on build 154).
- In the base image, `USER` already has Interoperability and passes `validateNamespace` (what IPM checks); HSCUSTOM,
  HSLIB and HSSYS have it but fail `validateNamespace`.
- `SetAutoStart(pProductionName, pStartupPriority)`: the second argument is a priority, not a disable flag.
- `SYS.Process.Terminate` is an instance method on this build (`<METHOD DOES NOT EXIST>` as a class method).

### Verified (without the IPM client)
- Project container: it was still running classes from the 11-01 image (no `AgentResponse.PromptVersion`), so 4
  TestAgentOperation tests failed with `<PROPERTY DOES NOT EXIST>`. After LoadDir of src: 96/96. Setup run twice:
  OK, 7 Lookup Table entries, role with both users, AutoStart set, production state 1. samples.sh 20/20,
  workflow.sh 14/14.
- Throwaway container from the base image (no compose, no ports), tree copied to `/home/irisowner/labtriage-src`,
  namespace USER: LoadDir, then Setup twice: OK. `/home/irisowner/dev/data/*` created, 4 recordings and 20 samples
  copied; a changed sample was kept and a removed recording was copied again. After a container restart the
  production was running in 12 s (AutoStart). Sample 13 in REPLAY with no key: `out/CRITICAL/SYN-ORU-0013.final.json`
  (agent status OK, provider replay) and `out/ALERTS/SYN-ORU-0013.critical.json`. Unit tests there: 96/96.
- clean-clone-check.sh against a staging clone holding all the uncommitted changes, final versions (the check clones
  committed HEAD): 14/14 PASS. The build compiled the final LabTriage.Installer and ran iris.script with Setup;
  production running after 58 s, healthy after 61 s; samples.sh 20/20, workflow.sh 14/14 (role and users created
  by Setup). An earlier run, before pStartProduction, was also 14/14.

### Verified with IPM 0.10.10 (throwaway container, USER)
- Fresh container from the base image, no compose, no published ports, no `/home/irisowner/dev`. Tree copied without
  .git, the secrets file and data/{in,out,error,archive}. The project container has no IPM.
- README steps 1 and 2 run as written, in USER (the two lines of step 2 piped as typed, plus `quit` to leave the
  shell): install snippet HTTP 200, "Installation succeeded"; `repo -list` before: "No repositories found" (banner:
  "No registry configured"); after: `registry`, https://pm.community.intersystems.com/, Enabled Yes, Available Yes.
- `zpm "version"` in USER: `zpm 0.10.10` (installed in USER), registry `https://pm.community.intersystems.com/ - 1.0.0`.
  `zpm "search iris-lab-triage-agent"`: empty (not published yet).
- `zpm "load /home/irisowner/labtriage-src -v"`: every phase SUCCESS, no ERROR; "LabTriage.Production starts when the
  install transaction commits (job 1191)". Production state 1 two seconds after the load, no restart; messages.log:
  "LabTriage.Installer: start of LabTriage.Production: OK".
- `zpm "list"`: `iris-lab-triage-agent 1.0.1`.
- `zpm "iris-lab-triage-agent test"`: Methods 4 + 7 + 31 + 31 + 23 = 96 passed, 0 failed (one run per UnitTest
  class); production still running afterwards (Setup did nothing, ours was already running).
- `zpm "iris-lab-triage-agent package -v -path /tmp/labtriage-pkg"`, with the 5 test classes compiled in USER at that
  moment: the .tgz has module.xml, README.md, LICENSE, config/FlagCategory.xml, data/replay (4 + .gitkeep),
  data/samples (20) and the 22 app classes; no entry contains "test".
- Sample 13 in REPLAY, no key in the environment: `out/CRITICAL/SYN-ORU-0013.final.json` (agent OK, provider replay)
  and `out/ALERTS/SYN-ORU-0013.critical.json` (CRITICAL_ALERT).
- History: an earlier run had IPM installed in %SYS and mapped with `zpm "enable -map -namespaces USER"`; same results
  for load, list, test, package and sample 13. The check with another production running was done in that run: with
  a throwaway empty `ZCheck.OtherProduction` running, `Setup(root, 1)` wrote the warning, with and without a
  transaction; ZCheck.OtherProduction kept running and ours was not started.
- Project container, after the change (no zpm): Installer recompiled, `Setup(…, 1)` inside TSTART with our production
  running: OK, nothing started. samples.sh 20/20, workflow.sh 14/14.

### Not verified yet
- `zpm "install iris-lab-triage-agent"` from the registry: the module is not published on Open Exchange yet
  (the registry is configured and answers; the search finds nothing).
