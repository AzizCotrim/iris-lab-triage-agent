Class LabTriage.Msg.ExamResult Extends (%SerialObject, %XML.Adaptor)
{

    /// LOINC code of the exam, from OBX-3.1. Key used to look up the exam catalog.
    Property LoincCode As %String;

    /// Canonical name from the internal exam catalog, looked up by LOINC code.
    /// Never taken from OBX-3.2, which is free text from the file.
    Property ExamName As %String;

    /// Result value exactly as received in OBX-5, kept for audit.
    /// May be non-numeric (e.g. QNS, <0.5, 13,5).
    Property RawValue As %String (MAXLEN = 255);

    /// RawValue as a number. Set only when the whole RawValue is a valid number
    /// ($ISVALIDNUM). Empty when ReasonCode is set.
    Property NumericValue As %Decimal (SCALE = 5);

    /// Unit of measure from OBX-6 (e.g. mg/dL). Compared with the catalog unit.
    Property Unit As %String;

    /// Reference range as received in OBX-7 (e.g. 3.5-5.1). Bounds are inclusive.
    Property ReferenceRange As %String;

    /// Abnormal flag from the laboratory, OBX-8 (N, H, L, HH, LL, A, AA).
    /// An empty flag in the file is stored as N.
    Property AbnormalFlag As %String;

    /// Result status from OBX-11 (F final, P preliminary, C corrected).
    /// C is triaged as final.
    Property ResultStatus As %String;

    /// Observation date and time as received in OBX-14, HL7 format
    /// (e.g. 20261027071500). Not converted.
    Property ObsDateTime As %String;
    
    /// Why this exam cannot be evaluated (INVALID_VALUE, UNEXPECTED_UNIT, NOT_FINAL, UNSUPPORTED_EXAM, ...).
    /// Empty means the exam is valid. When not empty, the numeric value must not be used.
    Property ReasonCode As %String;

Storage Default
{
<Data name="ExamResultState">
<Value name="1">
<Value>LoincCode</Value>
</Value>
<Value name="2">
<Value>ExamName</Value>
</Value>
<Value name="3">
<Value>RawValue</Value>
</Value>
<Value name="4">
<Value>NumericValue</Value>
</Value>
<Value name="5">
<Value>Unit</Value>
</Value>
<Value name="6">
<Value>ReferenceRange</Value>
</Value>
<Value name="7">
<Value>AbnormalFlag</Value>
</Value>
<Value name="8">
<Value>ResultStatus</Value>
</Value>
<Value name="9">
<Value>ObsDateTime</Value>
</Value>
<Value name="10">
<Value>ReasonCode</Value>
</Value>
</Data>
<State>ExamResultState</State>
<StreamLocation>^LabTriage.Msg.ExamResultS</StreamLocation>
<Type>%Storage.Serial</Type>
}

}