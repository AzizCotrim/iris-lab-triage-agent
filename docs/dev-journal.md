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
