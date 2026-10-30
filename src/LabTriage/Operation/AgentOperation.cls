/// Only boundary with the LLM provider. One call to the triage agent per AgentRequest.
/// Three modes: REAL calls the provider; SIMULATION returns a configured outcome without
/// calling it; REPLAY returns an answer recorded earlier in REAL mode (no API key needed).
/// Never retries on its own and never lets an SDK exception escape: every failure becomes
/// an AgentResponse.Status, and the TriageProcess decides what to do.
Class LabTriage.Operation.AgentOperation Extends Ens.BusinessOperation
{

    Parameter INVOCATION = "Queue";

    Parameter SETTINGS = "Mode:Basic,SimulatedOutcome:Basic,TimeoutSeconds:Basic,ReplayPath:Basic";

    /// REAL, SIMULATION or REPLAY. Empty: the LABTRIAGE_AGENT_MODE environment variable decides,
    /// and REPLAY is used when it is empty too, so judges can run without an API key.
    Property Mode As %String(VALUELIST = ",REAL,SIMULATION,REPLAY");

    /// SIMULATION mode only: what the fake agent returns. *_THEN_VALID fails on attempt 1 only.
    Property SimulatedOutcome As %String(VALUELIST = ",HOLD_ALL,HOLD_FIRST,RELEASE_ALL,FENCED,INVALID,INVALID_THEN_VALID,TIMEOUT,TIMEOUT_THEN_VALID,RATE_LIMIT,NO_KEY,PROVIDER_ERROR,EMPTY") [ InitialExpression = "HOLD_ALL" ];

    /// Wall-clock budget for one REAL call, in seconds (sent to the SDK session as timeout_ms).
    /// The SDK checks it once per iteration: an in-flight HTTP call still runs to completion.
    Property TimeoutSeconds As %Integer [ InitialExpression = 30 ];

    /// Folder of recorded answers, as seen inside the container. Must end with "/".
    Property ReplayPath As %String(MAXLEN = 255) [ InitialExpression = "/home/irisowner/dev/data/replay/" ];

    /// Says in the Event Log which mode is active and what it needs.
    Method OnInit() As %Status
    {
        Set tMode = ..EffectiveMode()
        If (tMode = "REAL")
        {
            If ($SYSTEM.Util.GetEnviron("GOOGLE_API_KEY") = "")
            {
                $$$LOGWARNING("Agent mode REAL, but GOOGLE_API_KEY is not set: every agent call will fall back to HOLD_FOR_REVIEW. Set it in .env, or use LABTRIAGE_AGENT_MODE=REPLAY.")
            } Else
            {
                Set tModel = $SYSTEM.Util.GetEnviron("LABTRIAGE_MODEL")
                $$$LOGINFO("Agent mode REAL: provider gemini, model "_$SELECT(tModel '= "": tModel, 1: ##class(LabTriage.Agent.TriageAgent).#MODEL)_", timeout "_..TimeoutSeconds_" s")
            }
        } ElseIf (tMode = "REPLAY")
        {
            $$$LOGINFO("Agent mode REPLAY: answers come from "_..ReplayPath_" (no API key needed). Inputs without a recording fall back to HOLD_FOR_REVIEW.")
        } Else
        {
            $$$LOGINFO("Agent mode SIMULATION: outcome "_..SimulatedOutcome_" (the provider is never called).")
        }
        Return $$$OK
    }

    Method OnMessage(pRequest As LabTriage.Msg.AgentRequest, Output pResponse As %Library.Persistent) As %Status
    {
        Set pResponse = ##class(LabTriage.Msg.AgentResponse).%New()
        Set tStart = $ZHOROLOG
        Set tMode = ..EffectiveMode()
        Set tInput = ..BuildInput(pRequest)

        If (tMode = "SIMULATION")
        {
            Do ..Simulate(pRequest, pResponse)
        } ElseIf (tMode = "REPLAY")
        {
            Do ..Replay(tInput, pResponse)
        } Else
        {
            Do ..CallAgent(tInput, pResponse)
            If (pResponse.Status = "OK")
            {
                Do ..Record(tInput, pResponse)
            }
        }

        // When the SDK did not measure the call, use the wall-clock time.
        If (pResponse.LatencyMs = "")
        {
            Set pResponse.LatencyMs = ($ZHOROLOG - tStart) * 1000 \ 1
        }

        $$$LOGINFO("Agent call attempt "_pRequest.Attempt_" ("_tMode_"): status="_pResponse.Status_" model="_pResponse.Model_" latencyMs="_pResponse.LatencyMs)
        Return $$$OK
    }

    /// The mode in use: the Mode setting, else LABTRIAGE_AGENT_MODE, else REPLAY.
    Method EffectiveMode() As %String
    {
        If (..Mode '= "")
        {
            Return ..Mode
        }
        Set tEnvMode = $ZCONVERT($SYSTEM.Util.GetEnviron("LABTRIAGE_AGENT_MODE"), "U")
        If ((tEnvMode = "REAL") || (tEnvMode = "SIMULATION") || (tEnvMode = "REPLAY"))
        {
            Return tEnvMode
        }
        Return "REPLAY"
    }

    /// The exact text sent to the model: the payload, plus the correction message on a retry
    /// after a contract violation. Replay recordings are keyed by this text.
    ClassMethod BuildInput(pRequest As LabTriage.Msg.AgentRequest) As %String
    {
        If (pRequest.Violation = "")
        {
            Return pRequest.Payload
        }
        Return pRequest.Payload_$CHAR(10,10)_"Your previous answer was:"_$CHAR(10)_pRequest.PreviousAnswer_$CHAR(10,10)_"Your previous answer was rejected: "_pRequest.Violation_" Answer again following the OUTPUT rules."
    }

    /// REAL mode: one call to the provider through the AI Hub SDK.
    Method CallAgent(pInput As %String, pResponse As LabTriage.Msg.AgentResponse)
    {
        Set pResponse.Provider = "gemini"
        Try
        {
            Set tAgent = ##class(LabTriage.Agent.TriageAgent).%New()
            Set tSC = tAgent.%Init()
            If $$$ISERR(tSC)
            {
                Set tText = $SYSTEM.Status.GetErrorText(tSC)
                Set pResponse.Status = $SELECT(tText [ "GOOGLE_API_KEY": "NO_KEY", 1: "PROVIDER_ERROR")
                Set pResponse.ErrorText = $EXTRACT(tText, 1, 500)
            } Else
            {
                Set pResponse.Model = tAgent.Model
                Set tSession = tAgent.CreateSession({"timeout_ms": (..TimeoutSeconds * 1000)})
                Set tAnswer = tAgent.Chat(tSession, pInput)

                Set tContent = tAnswer.Content
                If ($ZSTRIP(tContent, "<>WC") = "")
                {
                    Set pResponse.Status = "EMPTY"
                } Else
                {
                    Set pResponse.Status = "OK"
                    Set pResponse.RawText = tContent
                }
                Set pResponse.LatencyMs = tSession.GetStats().%Get("total_llm_duration_ms")
            }
        } Catch tEx
        {
            Set pResponse.Status = ..ClassifyError(tEx)
            Set pResponse.ErrorText = $EXTRACT($SYSTEM.Status.GetErrorText(tEx.AsStatus()), 1, 500)
        }
    }

    /// SIMULATION mode: returns the configured outcome without calling the provider.
    Method Simulate(pRequest As LabTriage.Msg.AgentRequest, pResponse As LabTriage.Msg.AgentResponse)
    {
        Set pResponse.Provider = "simulation"
        Set pResponse.Model = ..SimulatedOutcome
        Set pResponse.LatencyMs = 0

        // *_THEN_VALID: the first attempt fails as configured, the retry gets a valid answer.
        Set tOutcome = ..SimulatedOutcome
        If (tOutcome [ "_THEN_VALID")
        {
            Set tOutcome = $SELECT(pRequest.Attempt = 1: $PIECE(tOutcome, "_THEN_VALID", 1), 1: "HOLD_ALL")
        }

        // Technical failures: a status and no answer text.
        If ((tOutcome = "TIMEOUT") || (tOutcome = "RATE_LIMIT") || (tOutcome = "NO_KEY") || (tOutcome = "PROVIDER_ERROR") || (tOutcome = "EMPTY"))
        {
            Set pResponse.Status = tOutcome
            Set pResponse.ErrorText = "Simulated "_tOutcome_"."
            Return
        }

        // Codes of the exams in the payload, so the answers only use codes that were sent.
        Set tCodes = []
        Set tIterator = ##class(%DynamicAbstractObject).%FromJSON(pRequest.Payload).exams.%GetIterator()
        While tIterator.%GetNext(.tKey, .tExam)
        {
            Do tCodes.%Push(tExam.code)
        }

        Set pResponse.Status = "OK"
        If (tOutcome = "INVALID")
        {
            Set pResponse.RawText = {"decision": "CRITICAL", "reason": "Simulated answer outside the contract.", "flaggedExams": []}.%ToJSON()
        } ElseIf (tOutcome = "RELEASE_ALL")
        {
            Set pResponse.RawText = {"decision": "RELEASE", "reason": "Simulated answer: nothing needs review.", "flaggedExams": []}.%ToJSON()
        } ElseIf (tOutcome = "HOLD_FIRST")
        {
            Set pResponse.RawText = {"decision": "HOLD_FOR_REVIEW", "reason": "Simulated answer: only the first exam needs review.", "flaggedExams": [(tCodes.%Get(0))]}.%ToJSON()
        } Else
        {
            // HOLD_ALL and FENCED
            Set tAnswer = {"decision": "HOLD_FOR_REVIEW", "reason": "Simulated answer: every exam needs review.", "flaggedExams": (tCodes)}.%ToJSON()
            Set pResponse.RawText = $SELECT(tOutcome = "FENCED": "```json"_$CHAR(10)_tAnswer_$CHAR(10)_"```", 1: tAnswer)
        }
    }

    /// REPLAY mode: returns the answer recorded for this exact input (written in block 4).
    Method Replay(pInput As %String, pResponse As LabTriage.Msg.AgentResponse)
    {
        // TODO (block 4): read the recording from ReplayPath.
        Set pResponse.Provider = "replay"
        Set pResponse.Status = "NO_KEY"
        Set pResponse.ErrorText = "Replay is not implemented yet."
    }

    /// REAL mode: records an answer so REPLAY can return it later (written in block 4).
    Method Record(pInput As %String, pResponse As LabTriage.Msg.AgentResponse)
    {
        // TODO (block 4): write the recording to ReplayPath.
    }

    /// Maps an SDK exception to an AgentResponse.Status.
    /// Observed on build 154: an unknown model raises <%AICore>ProviderError (not ModelNotFound),
    /// and a request that timed out raised <%AICore>InternalError (dev journal, 10-23).
    ClassMethod ClassifyError(pEx As %Exception.AbstractException) As %String
    {
        Set tName = pEx.Name
        Set tText = $SYSTEM.Status.GetErrorText(pEx.AsStatus())

        If ((tName = "<%AICore>Timeout") || (tName = "<%AICore>InternalError"))
        {
            Return "TIMEOUT"
        }
        If (tText [ "HTTP 429")
        {
            Return "RATE_LIMIT"
        }
        If ((tText [ "HTTP 401") || (tText [ "HTTP 403") || (tText [ "API key"))
        {
            Return "NO_KEY"
        }
        Return "PROVIDER_ERROR"
    }

}