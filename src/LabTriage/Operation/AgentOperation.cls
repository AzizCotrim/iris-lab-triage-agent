/// Only boundary with the LLM provider. One call to the triage agent per AgentRequest.
/// Never retries on its own and never lets an SDK exception escape: every failure becomes
/// an AgentResponse.Status, and the TriageProcess decides what to do.
Class LabTriage.Operation.AgentOperation Extends Ens.BusinessOperation
{

    Parameter INVOCATION = "Queue";

    Parameter SETTINGS = "TimeoutSeconds:Basic";

    /// Wall-clock budget for one call, in seconds (sent to the SDK session as timeout_ms).
    /// The SDK checks it once per iteration: an in-flight HTTP call still runs to completion.
    Property TimeoutSeconds As %Integer [ InitialExpression = 30 ];

    /// Checks the configuration when the production starts and says in the Event Log what is missing.
    Method OnInit() As %Status
    {
        If ($SYSTEM.Util.GetEnviron("GOOGLE_API_KEY") = "")
        {
            $$$LOGWARNING("GOOGLE_API_KEY is not set: every agent call will fall back to HOLD_FOR_REVIEW. Set it in .env.")
        } Else
        {
            Set tModel = $SYSTEM.Util.GetEnviron("LABTRIAGE_MODEL")
            $$$LOGINFO("Agent provider gemini, model "_$SELECT(tModel '= "": tModel, 1: ##class(LabTriage.Agent.TriageAgent).#MODEL)_", timeout "_..TimeoutSeconds_" s")
        }
        Return $$$OK
    }

    Method OnMessage(pRequest As LabTriage.Msg.AgentRequest, Output pResponse As %Library.Persistent) As %Status
    {
        Set pResponse = ##class(LabTriage.Msg.AgentResponse).%New()
        Set pResponse.Provider = "gemini"
        Set tStart = $ZHOROLOG

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
                Set tAnswer = tAgent.Chat(tSession, pRequest.Payload)

                Set tContent = tAnswer.Content
                If ($ZSTRIP(tContent, "<>W") = "")
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

        // When the call failed before the SDK measured it, use the wall-clock time.
        If (pResponse.LatencyMs = "")
        {
            Set pResponse.LatencyMs = ($ZHOROLOG - tStart) * 1000 \ 1
        }

        $$$LOGINFO("Agent call attempt "_pRequest.Attempt_": status="_pResponse.Status_" model="_pResponse.Model_" latencyMs="_pResponse.LatencyMs)
        Return $$$OK
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