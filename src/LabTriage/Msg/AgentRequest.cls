/// What the TriageProcess sends to the AgentOperation for one call to the agent.
/// Carries only the sanitized payload: patient identity never travels in this message.
Class LabTriage.Msg.AgentRequest Extends Ens.Request
{

    /// JSON built by the Sanitizer. The only data sent to the LLM.
    Property Payload As %String(MAXLEN = "");

    /// 1 for the first call, 2 for the corrective retry.
    Property Attempt As %Integer [ InitialExpression = 1 ];

    /// Retry only: the answer that was rejected, exactly as returned.
    Property PreviousAnswer As %String(MAXLEN = "");

    /// Retry only: which contract rule the previous answer broke (from AgentContract).
    Property Violation As %String(MAXLEN = 500);

Storage Default
{
<Data name="AgentRequestDefaultData">
<Subscript>"AgentRequest"</Subscript>
<Value name="1">
<Value>Payload</Value>
</Value>
<Value name="2">
<Value>Attempt</Value>
</Value>
<Value name="3">
<Value>PreviousAnswer</Value>
</Value>
<Value name="4">
<Value>Violation</Value>
</Value>
</Data>
<DefaultData>AgentRequestDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}