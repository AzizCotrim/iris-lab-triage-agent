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

### Compose
- env_file: .env is required; docker compose fails if the file does not exist. Judges need to create it
  from .env.example, even in replay mode without an API key.
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
- Defaults in config/FlagCategory.xml, to be loaded by iris.script with %Import and the table
  name (replaces the table; without the name it merges); iris.script does not load it yet.
  Kept outside src/, because LoadDir also loads *.xml files.
- An empty key is not allowed (ERROR #5659); the Service turns an empty flag into N first.
  %GetValue with pExists tells an unknown flag from a known one. A missing table makes every
  flag unknown, so every exam goes to review.

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
