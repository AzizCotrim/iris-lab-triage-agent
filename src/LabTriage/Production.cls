Class LabTriage.Production Extends Ens.Production
{

XData ProductionDefinition
{
<Production Name="LabTriage.Production" LogGeneralTraceEvents="false">
  <Description>LabTriage Agent: triage of synthetic HL7 v2 ORU^R01 lab results.</Description>
  <ActorPoolSize>2</ActorPoolSize>
  <Item Name="FileInbound" Category="" ClassName="LabTriage.Service.FileInbound" PoolSize="1" Enabled="true" Foreground="false" Comment="" LogTraceEvents="false" Schedule="">
    <Setting Target="Adapter" Name="FilePath">/home/irisowner/dev/data/in/</Setting>
    <Setting Target="Adapter" Name="FileSpec">*.hl7</Setting>
    <Setting Target="Adapter" Name="ArchivePath">/home/irisowner/dev/data/archive/</Setting>
    <Setting Target="Adapter" Name="Charset">UTF-8</Setting>
    <Setting Target="Adapter" Name="ConfirmComplete">1</Setting>
    <Setting Target="Host" Name="TargetConfigName">TriageProcess</Setting>
  </Item>
  <Item Name="TriageProcess" Category="" ClassName="LabTriage.Process.TriageProcess" PoolSize="1" Enabled="true" Foreground="false" Comment="" LogTraceEvents="false" Schedule="">
  </Item>
  <Item Name="DecisionFileOperation" ClassName="LabTriage.Operation.DecisionFileOperation" PoolSize="1" Enabled="true">
    <Setting Target="Host" Name="OutputPath">/home/irisowner/dev/data/out/</Setting>
  </Item>
  <Item Name="AgentOperation" ClassName="LabTriage.Operation.AgentOperation" PoolSize="1" Enabled="true">
    <Setting Target="Host" Name="TimeoutSeconds">30</Setting>
  </Item>
</Production>
}

}
