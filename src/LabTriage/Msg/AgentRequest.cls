/// What the TriageProcess sends to the AgentOperation for one call to the agent.
/// Carries only the sanitized payload: patient identity never travels in this message
/// (the patient reference for the delta check is a differential, in a separate field).
Class LabTriage.Msg.AgentRequest Extends Ens.Request
{

    /// JSON built by the Sanitizer. The only data sent to the LLM.
    Property Payload As %String(MAXLEN = "");

    /// 1 for the first call, 2 for the corrective retry.
    Property Attempt As %Integer [ InitialExpression = 1 ];

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
</Data>
<DefaultData>AgentRequestDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}