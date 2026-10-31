/// A file the FileInbound service could not accept as an ORU^R01 message.
/// The ErrorFileOperation writes a copy of it and an .error.json to data/error.
Class LabTriage.Msg.RejectedFile Extends Ens.Request
{

    /// Name of the input file, from the adapter (not part of the HL7 message).
    Property SourceFileName As %String(MAXLEN = 255);

    /// Why the file was rejected, in one English sentence.
    Property Reason As %String(MAXLEN = 500);

    /// MSH-10, when the file has one. Truncated to 255: file data can be anything.
    Property MessageControlId As %String(MAXLEN = 255);

    /// PID-3.1, when the file has one. Truncated to 255: file data can be anything.
    Property PatientId As %String(MAXLEN = 255);

    /// When the Service received the file, in UTC (system clock).
    Property ReceivedAt As %TimeStamp [ InitialExpression = {$ZDATETIME($ZTIMESTAMP, 3)} ];

    /// Copy of the file content, written to data/error as received.
    Property Content As %Stream.GlobalCharacter;

Storage Default
{
<Data name="RejectedFileDefaultData">
<Subscript>"RejectedFile"</Subscript>
<Value name="1">
<Value>SourceFileName</Value>
</Value>
<Value name="2">
<Value>Reason</Value>
</Value>
<Value name="3">
<Value>MessageControlId</Value>
</Value>
<Value name="4">
<Value>PatientId</Value>
</Value>
<Value name="5">
<Value>ReceivedAt</Value>
</Value>
<Value name="6">
<Value>Content</Value>
</Value>
</Data>
<DefaultData>RejectedFileDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}