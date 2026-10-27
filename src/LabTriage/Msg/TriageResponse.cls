Class LabTriage.Msg.TriageResponse Extends Ens.Request
{

    /// MSH-10. Links the alert and the final output.
    Property MessageControlId As %String;
    
    /// OBR-2.
    Property OrderId As %String;
    
    /// PID-3.1. Output only; never sent to the LLM.
    Property PatientId As %String;
    
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
</Data>
<DefaultData>TriageResponseDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
