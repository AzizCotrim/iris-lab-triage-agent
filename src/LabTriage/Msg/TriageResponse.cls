Class LabTriage.Msg.TriageResponse Extends Ens.Request
{

    /// MSH-10. Links the alert and the final output.
    Property MessageControlId As %String(MAXLEN = 255);
    
    /// OBR-2.
    Property OrderId As %String(MAXLEN = 255);
    
    /// PID-3.1. Output only; never sent to the LLM.
    Property PatientId As %String(MAXLEN = 255);
    
    /// REVIEW_DECISION is added with the review queue.
    Property OutputType As %String(VALUELIST = ",CRITICAL_ALERT,FINAL") [ Required ];
    
    /// Most severe decision among the lists.
    Property Decision As %String(VALUELIST = ",RELEASE,HOLD_FOR_REVIEW,CRITICAL") [ Required ];
    
    
    Property Released As list Of LabTriage.Msg.ExamDecision;
    
    
    Property Review As list Of LabTriage.Msg.ExamDecision;
    
    
    Property Critical As list Of LabTriage.Msg.ExamDecision;
    
    /// Whether the agent was consulted for this message.
    Property AgentCalled As %Boolean [ InitialExpression = 0 ];
    
    /// When the Process emitted this output, in UTC.
    Property EmittedAt As %TimeStamp [ InitialExpression = {$ZDATETIME($ZTIMESTAMP, 3)} ];

    /// Number of calls made to the agent for this message (0, 1 or 2).
    Property AgentAttempts As %Integer [ InitialExpression = 0 ];

    /// Technical status of the last call (OK, TIMEOUT, ...) or INVALID_ANSWER
    /// when the last answer broke the contract.
    Property AgentStatus As %String;

    /// Sum of the LLM time of all calls, in milliseconds.
    Property AgentLatencyMs As %Integer;

    /// Provider of the last call (gemini, simulation or replay).
    Property AgentProvider As %String;

    /// Model of the last call.
    Property AgentModel As %String(MAXLEN = 100);

    /// First 500 characters of the last raw answer, for audit. Never sent to the output file.
    Property AgentRawExcerpt As %String(MAXLEN = 500);

Storage Default
{
<Data name="TriageResponseDefaultData">
<Subscript>"TriageResponse"</Subscript>
<Value name="1">
<Value>MessageControlId</Value>
</Value>
<Value name="2">
<Value>OrderId</Value>
</Value>
<Value name="3">
<Value>PatientId</Value>
</Value>
<Value name="4">
<Value>OutputType</Value>
</Value>
<Value name="5">
<Value>Decision</Value>
</Value>
<Value name="6">
<Value>Released</Value>
</Value>
<Value name="7">
<Value>Review</Value>
</Value>
<Value name="8">
<Value>Critical</Value>
</Value>
<Value name="9">
<Value>AgentCalled</Value>
</Value>
<Value name="10">
<Value>EmittedAt</Value>
</Value>
<Value name="11">
<Value>AgentAttempts</Value>
</Value>
<Value name="12">
<Value>AgentStatus</Value>
</Value>
<Value name="13">
<Value>AgentLatencyMs</Value>
</Value>
<Value name="14">
<Value>AgentProvider</Value>
</Value>
<Value name="15">
<Value>AgentModel</Value>
</Value>
<Value name="16">
<Value>AgentRawExcerpt</Value>
</Value>
</Data>
<DefaultData>TriageResponseDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
