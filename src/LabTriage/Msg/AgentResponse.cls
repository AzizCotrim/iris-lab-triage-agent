/// Technical result of one call to the agent. Not a decision yet:
/// the TriageProcess validates RawText against the contract before using it.
Class LabTriage.Msg.AgentResponse Extends Ens.Response
{

    /// Answer text exactly as returned by the LLM. Validated by the Process before use.
    Property RawText As %String(MAXLEN = "");

    /// Technical status of the call, not a triage decision.
    Property Status As %String(VALUELIST = ",OK,TIMEOUT,NO_KEY,RATE_LIMIT,PROVIDER_ERROR,EMPTY") [ Required ];

    /// Error detail when Status is not OK. Never contains the API key.
    Property ErrorText As %String(MAXLEN = 500);

    /// LLM time for this call, in milliseconds.
    Property LatencyMs As %Integer;

    /// Provider used (e.g. gemini).
    Property Provider As %String;

    /// Model id used.
    Property Model As %String(MAXLEN = 100);

Storage Default
{
<Data name="AgentResponseDefaultData">
<Subscript>"AgentResponse"</Subscript>
<Value name="1">
<Value>RawText</Value>
</Value>
<Value name="2">
<Value>Status</Value>
</Value>
<Value name="3">
<Value>ErrorText</Value>
</Value>
<Value name="4">
<Value>LatencyMs</Value>
</Value>
<Value name="5">
<Value>Provider</Value>
</Value>
<Value name="6">
<Value>Model</Value>
</Value>
</Data>
<DefaultData>AgentResponseDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}