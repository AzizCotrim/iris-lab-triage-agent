/// What the TriageProcess sends to the DecisionFileOperation when a reviewer acts on the
/// Workflow task of a HOLD_FOR_REVIEW message. Written to REVIEWED/<MSH-10>.review.json.
Class LabTriage.Msg.ReviewResult Extends Ens.Request
{

    /// MSH-10. Links the review to the final output of the same message.
    Property MessageControlId As %String(MAXLEN = 255);

    /// OBR-2.
    Property OrderId As %String(MAXLEN = 255);

    /// PID-3.1.
    Property PatientId As %String(MAXLEN = 255);

    /// Action chosen in the Workflow Inbox (Release or KeepOnHold), or the Workflow cancel value.
    Property Action As %String(MAXLEN = 128);

    /// Workflow user that completed the task (the IRIS login of the reviewer).
    Property Reviewer As %String(MAXLEN = 128);

    /// Workflow role that received the task.
    Property Role As %String(MAXLEN = 128);

    /// When the Workflow Engine created the task, in UTC.
    Property TaskCreatedAt As %TimeStamp;

    /// When the reviewer completed the task, in UTC.
    Property TaskCompletedAt As %TimeStamp;

    /// When the Process emitted this output, in UTC.
    Property EmittedAt As %TimeStamp [ InitialExpression = {$ZDATETIME($ZTIMESTAMP, 3)} ];

Storage Default
{
<Data name="ReviewResultDefaultData">
<Subscript>"ReviewResult"</Subscript>
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
<Value>Action</Value>
</Value>
<Value name="5">
<Value>Reviewer</Value>
</Value>
<Value name="6">
<Value>Role</Value>
</Value>
<Value name="7">
<Value>TaskCreatedAt</Value>
</Value>
<Value name="8">
<Value>TaskCompletedAt</Value>
</Value>
<Value name="9">
<Value>EmittedAt</Value>
</Value>
</Data>
<DefaultData>ReviewResultDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}