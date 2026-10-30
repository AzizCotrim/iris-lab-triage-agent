/// Triages each exam of a TriageRequest and sends the TriageResponse to the DecisionFileOperation.
/// Critical exams: the alert goes out first. Abnormal exams: one call to the agent;
/// any agent failure or invalid answer sends those exams to review (FALLBACK).
Class LabTriage.Process.TriageProcess Extends Ens.BusinessProcess
{

    Method OnRequest(pRequest As LabTriage.Msg.TriageRequest, Output pResponse As %Library.Persistent) As %Status
    {
        Set tTriageResponse = ##class(LabTriage.Msg.TriageResponse).%New()

        Set tTriageResponse.MessageControlId = pRequest.MessageControlId
        Set tTriageResponse.OrderId = pRequest.OrderId
        Set tTriageResponse.PatientId = pRequest.PatientId
        Set tTriageResponse.OutputType = "FINAL"

        // AGENT: valid, non-critical exams outside their reference range wait here for the agent.
        Set tForAgent = ##class(%ListOfObjects).%New()

        Set tExamCount = pRequest.Exams.Count()
        For tExamIndex = 1:1:tExamCount
        {
            Set tExamResult = pRequest.Exams.GetAt(tExamIndex)

            Set tExamDecision = ##class(LabTriage.Msg.ExamDecision).%New()
            Set tExamDecision.LoincCode = tExamResult.LoincCode
            Set tExamDecision.ExamName = tExamResult.ExamName
            Set tExamDecision.DecidedBy = "RULE"

            If (tExamResult.ReasonCode '= "")
            {
                Set tExamDecision.ReasonCode = tExamResult.ReasonCode
                Set tExamDecision.Reason = "Exam cannot be evaluated: "_tExamResult.ReasonCode_"."
                Do tTriageResponse.Review.Insert(tExamDecision)
            } Else
            {
                // Every valid exam goes through the critical rule first.
                Set tRuleResult = ##class(LabTriage.Rules.CriticalLimits).Check(tExamResult, .tCode, .tReason)

                If (tRuleResult = "CRITICAL")
                {
                    Set tExamDecision.ReasonCode = tCode
                    Set tExamDecision.Reason = tReason
                    Do tTriageResponse.Critical.Insert(tExamDecision)
                } ElseIf (tRuleResult = "NOT_EVALUABLE")
                {
                    // Defensive: the Service already marks unsupported exams, wrong units and
                    // invalid values, so the rule should never refuse a valid exam here.
                    Set tExamDecision.ReasonCode = "UNEXPECTED_UNIT"
                    Set tExamDecision.Reason = "Unit "_tExamResult.Unit_" is not the unit expected by the exam catalog."
                    Do tTriageResponse.Review.Insert(tExamDecision)
                } Else
                {
                    // AGENT: not critical; the reference range decides between the agent and the rule.
                    Set tRangeResult = ##class(LabTriage.Util.ReferenceRange).Classify(tExamResult)

                    If (tRangeResult = "ABNORMAL")
                    {
                        Do tForAgent.Insert(tExamResult)
                    } ElseIf (tRangeResult = "UNPARSEABLE")
                    {
                        Set tExamDecision.ReasonCode = "UNPARSEABLE_RANGE"
                        Set tExamDecision.Reason = "Reference range '"_tExamResult.ReferenceRange_"' cannot be read."
                        Do tTriageResponse.Review.Insert(tExamDecision)
                    } Else
                    {
                        Set tExamDecision.ReasonCode = "NORMAL"
                        Set tExamDecision.Reason = "Within reference range."
                        Do tTriageResponse.Released.Insert(tExamDecision)
                    }
                }
            }
        }

        // Critical results do not wait. The alert goes out before the agent is called.
        If (tTriageResponse.Critical.Count() > 0)
        {
            Set tAlert = ##class(LabTriage.Msg.TriageResponse).%New()
            Set tAlert.MessageControlId = pRequest.MessageControlId
            Set tAlert.OrderId = pRequest.OrderId
            Set tAlert.PatientId = pRequest.PatientId
            Set tAlert.OutputType = "CRITICAL_ALERT"
            Set tAlert.Decision = "CRITICAL"

            // The alert carries only the critical list.
            For tCriticalIndex = 1:1:tTriageResponse.Critical.Count()
            {
                Do tAlert.Critical.Insert(tTriageResponse.Critical.GetAt(tCriticalIndex))
            }

            Set tAlert.EmittedAt = $ZDATETIME($ZTIMESTAMP, 3, 1, 3)
            Set tSC = ..SendRequestAsync("DecisionFileOperation", tAlert, 0) // 0 = no response expected.
            If $$$ISERR(tSC)
            {
                Return tSC
            }
        }

        // AGENT: one call for all abnormal exams of this message.
        If (tForAgent.Count() > 0)
        {
            Do ..TriageWithAgent(tForAgent, tTriageResponse)
        }

        // The message decision is the most severe one among the lists.
        Set tTriageResponse.Decision = $SELECT(tTriageResponse.Critical.Count() > 0: "CRITICAL", tTriageResponse.Review.Count() > 0: "HOLD_FOR_REVIEW", 1: "RELEASE")

        // Overwrites the InitialExpression with the time right before sending, in milliseconds.
        // Set after the alert, so the final output is always later than the alert.
        Set tTriageResponse.EmittedAt = $ZDATETIME($ZTIMESTAMP, 3, 1, 3)

        Return ..SendRequestAsync("DecisionFileOperation", tTriageResponse, 0) // 0 = no response expected.
    }

    /// Sends the abnormal exams to the agent and fills the lists from its answer.
    /// At most 2 calls per message: a contract violation, a timeout, a provider error or an
    /// empty answer gets one corrective retry; a rate limit or a missing/invalid key falls back
    /// at once. Anything that is still not a valid answer sends the exams to review (FALLBACK).
    Method TriageWithAgent(pExams As %ListOfObjects, pTriageResponse As LabTriage.Msg.TriageResponse)
    {
        // Codes sent to the agent: flaggedExams may only use these.
        Set tSentCodes = []
        For tIndex = 1:1:pExams.Count()
        {
            Do tSentCodes.%Push(pExams.GetAt(tIndex).LoincCode)
        }

        Set tPayload = ##class(LabTriage.Util.Sanitizer).BuildPayload(pExams)
        Set pTriageResponse.AgentCalled = 1
        Set pTriageResponse.AgentLatencyMs = 0

        Set tPreviousAnswer = ""
        Set tViolation = ""
        Set tWhy = ""

        For tAttempt = 1:1:2
        {
            Set tAgentRequest = ##class(LabTriage.Msg.AgentRequest).%New()
            Set tAgentRequest.Payload = tPayload
            Set tAgentRequest.Attempt = tAttempt
            Set tAgentRequest.PreviousAnswer = tPreviousAnswer
            Set tAgentRequest.Violation = tViolation

            // Kill: on a failed call the response variable must not keep the previous answer.
            Kill tAgentResponse
            Set pTriageResponse.AgentAttempts = tAttempt

            // Waits up to 70 s: longer than the AgentOperation timeout (30 s), as the spec asks.
            Set tSC = ..SendRequestSync("AgentOperation", tAgentRequest, .tAgentResponse, 70)

            // No answer at all within the wait time: treated as a timeout (one retry).
            If (($$$ISERR(tSC)) || ('$ISOBJECT($GET(tAgentResponse))))
            {
                Set pTriageResponse.AgentStatus = "TIMEOUT"
                Set tWhy = "the agent call failed ("_$SYSTEM.Status.GetErrorText(tSC)_")"
                Set tPreviousAnswer = ""
                Set tViolation = ""
                Continue
            }

            Set pTriageResponse.AgentStatus = tAgentResponse.Status
            Set pTriageResponse.AgentProvider = tAgentResponse.Provider
            Set pTriageResponse.AgentModel = tAgentResponse.Model
            Set pTriageResponse.AgentLatencyMs = pTriageResponse.AgentLatencyMs + tAgentResponse.LatencyMs
            Set pTriageResponse.AgentRawExcerpt = $EXTRACT(tAgentResponse.RawText, 1, 500)

            If (tAgentResponse.Status '= "OK")
            {
                Set tWhy = "agent status "_tAgentResponse.Status_" ("_tAgentResponse.ErrorText_")"
                // Rate limit and missing or invalid key: repeating would not help.
                If ((tAgentResponse.Status = "RATE_LIMIT") || (tAgentResponse.Status = "NO_KEY"))
                {
                    Quit
                }
                // Timeout, provider error, empty answer: the retry resends the same payload.
                Set tPreviousAnswer = ""
                Set tViolation = ""
                Continue
            }

            If (##class(LabTriage.Util.AgentContract).Validate(tAgentResponse.RawText, tSentCodes, .tDecision, .tReason, .tFlagged, .tNewViolation))
            {
                Do ..ApplyAgentDecision(pExams, pTriageResponse, tReason, tFlagged)
                Return
            }

            // Contract violation: the retry tells the agent what was wrong.
            $$$LOGWARNING("Agent answer rejected for MSH-10="_pTriageResponse.MessageControlId_" (attempt "_tAttempt_"): "_tNewViolation)
            Set pTriageResponse.AgentStatus = "INVALID_ANSWER"
            Set tWhy = "the agent answer was rejected ("_tNewViolation_")"
            Set tPreviousAnswer = tAgentResponse.RawText
            Set tViolation = tNewViolation
        }

        Do ..AddFallback(pExams, pTriageResponse, tWhy)
    }

    /// Valid answer: flagged exams go to review, the others are released, all decided by the agent.
    Method ApplyAgentDecision(pExams As %ListOfObjects, pTriageResponse As LabTriage.Msg.TriageResponse, pReason As %String, pFlagged As %DynamicArray)
    {
        Set tFlaggedList = ""
        For tIndex = 0:1:(pFlagged.%Size() - 1)
        {
            Set tFlaggedList = tFlaggedList_$LISTBUILD(pFlagged.%Get(tIndex))
        }

        For tIndex = 1:1:pExams.Count()
        {
            Set tExamResult = pExams.GetAt(tIndex)

            Set tExamDecision = ##class(LabTriage.Msg.ExamDecision).%New()
            Set tExamDecision.LoincCode = tExamResult.LoincCode
            Set tExamDecision.ExamName = tExamResult.ExamName
            Set tExamDecision.DecidedBy = "AGENT"
            Set tExamDecision.Reason = pReason

            If ($LISTFIND(tFlaggedList, tExamResult.LoincCode))
            {
                Set tExamDecision.ReasonCode = "AGENT_FLAGGED"
                Do pTriageResponse.Review.Insert(tExamDecision)
            } Else
            {
                Set tExamDecision.ReasonCode = "AGENT_RELEASED"
                Do pTriageResponse.Released.Insert(tExamDecision)
            }
        }
    }

    /// Fail-safe: every exam that was sent to the agent goes to review, decided by FALLBACK.
    Method AddFallback(pExams As %ListOfObjects, pTriageResponse As LabTriage.Msg.TriageResponse, pWhy As %String)
    {
        $$$LOGWARNING("Agent fallback for MSH-10="_pTriageResponse.MessageControlId_": "_pWhy)

        For tIndex = 1:1:pExams.Count()
        {
            Set tExamResult = pExams.GetAt(tIndex)

            Set tExamDecision = ##class(LabTriage.Msg.ExamDecision).%New()
            Set tExamDecision.LoincCode = tExamResult.LoincCode
            Set tExamDecision.ExamName = tExamResult.ExamName
            Set tExamDecision.DecidedBy = "FALLBACK"
            Set tExamDecision.ReasonCode = "AGENT_FALLBACK"
            // Reason is limited to 500 characters (ExamDecision.Reason MAXLEN).
            Set tExamDecision.Reason = $EXTRACT("Sent to review because "_pWhy_".", 1, 500)
            Do pTriageResponse.Review.Insert(tExamDecision)
        }
    }

Storage Default
{
<Type>%Storage.Persistent</Type>
}

}