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

    /// TriageAgent PROMPTVERSION that produced the answer. REAL: the compiled prompt;
    /// REPLAY: the version stored in the recording; SIMULATION: empty (no prompt is used).
    Property PromptVersion As %String(MAXLEN = 50);

    /// Prompt (input) tokens of this call, from the SDK session stats. REPLAY: from the
    /// recording (empty for recordings made before tokens were recorded); SIMULATION: empty.
    Property InputTokens As %Integer;

    /// Completion (output) tokens of this call, from the SDK session stats. Same sources as InputTokens.
    Property OutputTokens As %Integer;

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
<Value name="7">
<Value>PromptVersion</Value>
</Value>
<Value name="8">
<Value>InputTokens</Value>
</Value>
<Value name="9">
<Value>OutputTokens</Value>
</Value>
</Data>
<DefaultData>AgentResponseDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}