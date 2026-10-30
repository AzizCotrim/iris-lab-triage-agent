Class LabTriage.Msg.ExamDecision Extends (%SerialObject, %XML.Adaptor)
{
    Property LoincCode As %String;
    
    Property ExamName As %String;
    
    /// Who decided where this exam goes: the deterministic rule, the agent,
    /// or the fallback after an agent failure.
    Property DecidedBy As %String(VALUELIST = ",RULE,AGENT,FALLBACK");

    /// Why the exam is in this list (NORMAL, CRITICAL_HIGH, AGENT_FLAGGED, ...).
    /// Same vocabulary as ExamResult.ReasonCode: when an exam cannot be evaluated,
    /// the Process copies that code here.
    Property ReasonCode As %String;

    /// Human-readable reason, from the rule or from the agent.
    /// MAXLEN follows the Process validation limit for the agent reason (500).
    Property Reason As %String(MAXLEN = 500);

    /// Whether the laboratory corrected this result (OBX-11 = C). A corrected result is triaged as final.
    Property Corrected As %Boolean [ InitialExpression = 0 ];

Storage Default
{
<Data name="ExamDecisionState">
<Value name="1">
<Value>LoincCode</Value>
</Value>
<Value name="2">
<Value>ExamName</Value>
</Value>
<Value name="3">
<Value>DecidedBy</Value>
</Value>
<Value name="4">
<Value>ReasonCode</Value>
</Value>
<Value name="5">
<Value>Reason</Value>
</Value>
<Value name="6">
<Value>Corrected</Value>
</Value>
</Data>
<State>ExamDecisionState</State>
<StreamLocation>^LabTriage.Msg.ExamDecisionS</StreamLocation>
<Type>%Storage.Serial</Type>
}

}
