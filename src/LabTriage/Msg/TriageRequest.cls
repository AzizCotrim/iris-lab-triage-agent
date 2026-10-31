Class LabTriage.Msg.TriageRequest Extends Ens.Request
{
    /// MSH-10. Also links the critical alert and the final output.
    Property MessageControlId As %String(MAXLEN = 255);

    /// When the Service received the file, in UTC (system clock, not MSH-7).
    Property DateTimeReceived As %TimeStamp [ InitialExpression = {$ZDATETIME($ZTIMESTAMP,3)} ];

    /// Name of the input file, from the adapter (not part of the HL7 message).
    Property SourceFileName As %String(MAXLEN = 255);

    /// PID-3.1. Used in the output and, later, in the history lookup;
    /// never sent to the LLM.
    Property PatientId As %String(MAXLEN = 255);

    /// OBR-2 (placer order number).
    Property OrderId As %String(MAXLEN = 255);

    Property Exams As list Of LabTriage.Msg.ExamResult;

    Property ParsingWarnings As list Of %String(MAXLEN = 255);

Storage Default
{
<Data name="TriageRequestDefaultData">
<Subscript>"TriageRequest"</Subscript>
<Value name="1">
<Value>MessageControlId</Value>
</Value>
<Value name="2">
<Value>DateTimeReceived</Value>
</Value>
<Value name="3">
<Value>SourceFileName</Value>
</Value>
<Value name="4">
<Value>PatientId</Value>
</Value>
<Value name="5">
<Value>OrderId</Value>
</Value>
<Value name="6">
<Value>Exams</Value>
</Value>
<Value name="7">
<Value>ParsingWarnings</Value>
</Value>
</Data>
<DefaultData>TriageRequestDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
