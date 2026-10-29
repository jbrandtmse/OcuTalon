/// Tests of the cross-lane table contracts (Story 0.4): every OcuTalon.Data and OcuTalon.Bridge.Data table, and the live
/// event table, has exactly its contract, its default global is its registry row's and resolves to the private
/// database, and no persistent class projects an SQL reserved word. The tests create no rows, but for the fixture mark of
/// TestStatusMarkRecord, which the test removes.
Class OcuTalon.Test.Data.Tables Extends OcuTalon.Test.Contract
{

/// Every table has its superclass, properties, types, SQL field names and indexes, and an approval request names the
/// keys of its stored dry run.
Method TestContracts()
{
	Do ..AssertContract("Contracts")
	Do $$$AssertEquals($Parameter("OcuTalon.Bridge.Data.ApprovalRequest", "DRYRUNKEYS"), "affected,resend,leftOut,field,before,after,itemNoun", "the dry run keys")
}

/// Each registry class sets the row's DEFAULTGLOBAL, stores its data in the global plus D, and has its globals in the
/// private database: they resolve where the private mapping sample resolves, not where the data database is.
/// PrivateData.Run() passes with them, and StorageGlobals lists the data and index global of each.
Method TestPrivateRecords()
{
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.PrivateData).Run(), "the private-data check passes")
	Do $$$AssertStatusOK(##class(OcuTalon.Install.Step.PrivateData).StorageGlobals(.storage), "the storage globals are read")
	Set private = ##class(%SYS.Namespace).GetGlobalDest($Namespace, "^OcuTalonP.Zz")
	Set data = ##class(%SYS.Namespace).GetGlobalDest($Namespace, "^OcuTalonZzUnmapped")
	Do $$$AssertTrue(private '= data, "the private and data databases differ")
	Set rows = ..Registry()
	Set iterator = rows.%GetIterator()
	While iterator.%GetNext(.key, .row) {
		Set class = row.class
		Set global = row.global
		Set name = $Extract(global, 2, *)
		Do $$$AssertEquals($Parameter(class, "DEFAULTGLOBAL"), global, class_" sets DEFAULTGLOBAL "_global)
		Set compiled = ##class(%Dictionary.CompiledStorage).%OpenId(class_"||Default")
		Set dataLocation = $Select($IsObject(compiled): compiled.DataLocation, 1: "")
		Set indexLocation = $Select($IsObject(compiled): compiled.IndexLocation, 1: "")
		Do $$$AssertEquals(dataLocation, global_"D", class_" stores its data in "_global_"D")
		Do $$$AssertEquals(##class(%SYS.Namespace).GetGlobalDest($Namespace, dataLocation), private, class_" data global "_dataLocation_" resolves to the private database")
		Do $$$AssertEquals(##class(%SYS.Namespace).GetGlobalDest($Namespace, indexLocation), private, class_" index global "_indexLocation_" resolves to the private database")
		Do $$$AssertTrue($Data(storage(name_"D")), "StorageGlobals lists "_name_"D")
		Do $$$AssertTrue($Data(storage(name_"I")), "StorageGlobals lists "_name_"I")
	}
	Do $$$AssertTrue(rows.%Size() >= 23, "the registry holds at least the 23 rows of the contracts so far")
}

/// Every persistent class in OcuTalon.Data, OcuTalon.Live and OcuTalon.Bridge.Data has a registry row.
Method TestEveryTableIsRegistered()
{
	Kill registered
	Set iterator = ..Registry().%GetIterator()
	While iterator.%GetNext(.key, .row) {
		Set registered(row.class) = row.global
	}
	Set statement = ##class(%SQL.Statement).%New()
	Do $$$AssertStatusOK(statement.%Prepare("SELECT ID FROM %Dictionary.CompiledClass WHERE (ID %STARTSWITH 'OcuTalon.Data.' OR ID %STARTSWITH 'OcuTalon.Live.' OR ID %STARTSWITH 'OcuTalon.Bridge.Data.') AND ClassType = 'persistent'"), "the query is prepared")
	Set result = statement.%Execute()
	Set count = 0
	While result.%Next() {
		Set class = result.%GetData(1)
		Set count = count + 1
		Do $$$AssertTrue($Data(registered(class)), class_" has a registry row")
	}
	Do $$$AssertTrue(count >= 23, "OcuTalon.Data, OcuTalon.Live and OcuTalon.Bridge.Data hold at least the 23 tables of the contracts so far")
}

/// No persistent OcuTalon class outside OcuTalon.Test projects an SQL reserved word as its table or a field. The classes
/// that the compiler generates (GeneratedBy set, such as a business process's MessagesSent and MessagesReceived tables)
/// are not opened by name and are left out; the class that generates them is checked.
Method TestSqlNames()
{
	Set statement = ##class(%SQL.Statement).%New()
	Do $$$AssertStatusOK(statement.%Prepare("SELECT ID FROM %Dictionary.CompiledClass WHERE ID %STARTSWITH 'OcuTalon.' AND NOT ID %STARTSWITH 'OcuTalon.Test.' AND ClassType = 'persistent' AND (GeneratedBy IS NULL OR GeneratedBy = '')"), "the query is prepared")
	Set result = statement.%Execute()
	Set count = 0
	While result.%Next() {
		Set count = count + 1
		Set checked(result.%GetData(1)) = 1
		Do ..AssertSqlNames(result.%GetData(1))
	}
	Do $$$AssertTrue(count >= 45, "at least the 45 persistent classes of the first contracts are checked")
	For process = "OcuTalon.Bridge.Process.Decide", "OcuTalon.Bridge.Process.ApprovalHold", "OcuTalon.Watch.IncidentManager", "OcuTalon.Checks.Process", "OcuTalon.Core.Conversation", "OcuTalon.Core.Intake", "OcuTalon.Schedule.ReminderTimer" {
		Do $$$AssertTrue($Data(checked(process)), process_" is among the checked classes")
	}
}

/// Record creates or replaces the row of a mark with RecordedAt in UTC to the second, Get reads the value ("" with no row),
/// an empty value deletes the row, and an empty mark is an error status that names it. The fixture mark is ZzStatusMark<n>, with
/// n from ^OcuTalonTest("StatusMark","n"), which is never reset; the rows of every ZzStatusMark mark are removed first, and the
/// test's own at the end.
Method TestStatusMarkRecord()
{
	Set class = "OcuTalon.Data.StatusMark"
	Set mark = "ZzStatusMark"_$Increment(^OcuTalonTest("StatusMark", "n"))
	Do ..RemoveStatusMarks()
	Do $$$AssertEquals($ClassMethod(class, "Get", mark), "", "a mark with no row reads as empty")
	Set before = ##class(OcuTalon.Data.Time).NowUtc()
	Do $$$AssertStatusOK($ClassMethod(class, "Record", mark, "v"), "Record creates the row")
	Do $$$AssertEquals($ClassMethod(class, "Get", mark), "v", "Get reads the value")
	Set row = $ClassMethod(class, "MarkIndexOpen", mark)
	If $IsObject(row) {
		Set row.RecordedAt = "2000-01-01T00:00:00Z"
		Do $$$AssertStatusOK(row.%Save(), "the row's RecordedAt is set back to 2000, so the replace below must stamp it again")
	}
	Kill row
	Do $$$AssertStatusOK($ClassMethod(class, "Record", mark, "w"), "Record replaces the value")
	Set after = ##class(OcuTalon.Data.Time).NowUtc()
	Do $$$AssertEquals($ClassMethod(class, "Get", mark), "w", "Get reads the new value")
	Do $$$AssertEquals(..StatusMarkRows(mark), 1, "one row holds the mark")
	Set row = $ClassMethod(class, "MarkIndexOpen", mark)
	Set recorded = $Select($IsObject(row): row.RecordedAt, 1: "")
	Set shaped = (recorded ? 4N1"-"2N1"-"2N1"T"2N1":"2N1":"2N1"Z")
	Do $$$AssertTrue(shaped, "RecordedAt is UTC to the second: "_recorded)
	Do $$$AssertTrue(((recorded = before) || (recorded ] before)) && ((recorded = after) || (after ] recorded)), "RecordedAt is the time of the last call, a replace included: "_recorded)
	Kill row
	Do $$$AssertStatusOK($ClassMethod(class, "Record", mark, ""), "Record with an empty value succeeds")
	Do $$$AssertEquals($ClassMethod(class, "Get", mark), "", "Get is empty after an empty value")
	Do $$$AssertEquals(..StatusMarkRows(mark), 0, "an empty value deletes the row")
	Do $$$AssertStatusOK($ClassMethod(class, "Record", mark, ""), "an empty value for a mark with no row succeeds")
	Set sc = $ClassMethod(class, "Record", "", "v")
	Do $$$AssertStatusNotOK(sc, "an empty mark is an error")
	Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "mark is empty", "the error names the empty mark")
	Do $$$AssertEquals($ClassMethod(class, "Get", ""), "", "Get of an empty mark is empty")
	Do ..RemoveStatusMarks()
}

/// The number of rows of a mark.
ClassMethod StatusMarkRows(mark As %String) As %Integer [ Private ]
{
	Set result = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM OcuTalon_Data.StatusMark WHERE Mark = ?", mark)
	Do result.%Next()
	Quit result.%GetData(1)
}

/// Deletes the rows of every fixture mark, ZzStatusMark and a number.
ClassMethod RemoveStatusMarks() [ Private ]
{
	Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM OcuTalon_Data.StatusMark WHERE Mark %STARTSWITH 'ZzStatusMark'")
}

/// The registry rows of src/short-names.tsv that the tests check, as a dynamic array of {"short","global","class"}.
ClassMethod Registry() As %DynamicArray [ Private ]
{
	Quit ..Read("Registry")
}

XData Contracts [ MimeType = application/json ]
{
{
 "OcuTalon.Bridge.Data.Decision": {
  "super": "%Persistent",
  "props": {
   "Ref": "%String(MAXLEN=22)",
   "Kind": "%String(MAXLEN=32)",
   "ItemId": "%String(MAXLEN=22)",
   "OwnerRef": "%String(MAXLEN=22)",
   "Summary": "%String(MAXLEN=80)",
   "Outcome": "%String(MAXLEN=32)",
   "Reasons": "%String(MAXLEN=)",
   "Confidence": "%Numeric(MAXVAL=1,MINVAL=0,SCALE=2)",
   "Fallback": "%Boolean",
   "FallbackReason": "%String(MAXLEN=32)",
   "Payload": "%String(MAXLEN=)",
   "InputTokens": "%Integer",
   "OutputTokens": "%Integer",
   "CacheReadTokens": "%Integer",
   "CacheWriteTokens": "%Integer",
   "AgentStepCount": "%Integer",
   "DurationMs": "%Integer",
   "CostUSD": "%Numeric(SCALE=6)",
   "Model": "%String(MAXLEN=128)",
   "TraceSessionId": "%Integer",
   "RecordedAt": "%String(MAXLEN=20)"
  },
  "indexes": {
   "RefIndex": "Ref unique",
   "ItemIdKindIndex": "ItemId,Kind unique",
   "OwnerRefIndex": "OwnerRef"
  }
 },
 "OcuTalon.Bridge.Data.ApprovalRequest": {
  "super": "%Persistent",
  "props": {
   "Ref": "%String(MAXLEN=22)",
   "Kind": "%String(MAXLEN=32)",
   "IncidentRef": "%String(MAXLEN=22)",
   "OwnerRef": "%String(MAXLEN=22)",
   "State": "%String(MAXLEN=32)",
   "DryRun": "%String(MAXLEN=)",
   "ToolName": "%String(MAXLEN=128)",
   "ToolArguments": "%String(MAXLEN=)",
   "RequiredRole": "%String(MAXLEN=128)",
   "ResultTarget": "%String(MAXLEN=128)",
   "TraceRef": "%String(MAXLEN=22)",
   "RaisedAt": "%String(MAXLEN=20)",
   "ExpiresAt": "%String(MAXLEN=20)",
   "AnsweredAction": "%String(MAXLEN=32)",
   "AnsweredChannel": "%String(MAXLEN=32)",
   "AnsweredBy": "%String(MAXLEN=128)",
   "AnsweredAt": "%String(MAXLEN=20)",
   "Result": "%String(MAXLEN=32)",
   "FinishedAt": "%String(MAXLEN=20)"
  },
  "indexes": {
   "RefIndex": "Ref unique",
   "IncidentRefIndex": "IncidentRef",
   "OwnerRefIndex": "OwnerRef"
  }
 },
 "OcuTalon.Bridge.Data.Usage": {
  "super": "%Persistent",
  "props": {
   "DecisionRef": "%String(MAXLEN=22)",
   "ItemId": "%String(MAXLEN=22)",
   "Kind": "%String(MAXLEN=32)",
   "Agent": "%String(MAXLEN=32)",
   "Channel": "%String(MAXLEN=32)",
   "OwnerRef": "%String(MAXLEN=22)",
   "Model": "%String(MAXLEN=128)",
   "RequestCount": "%Integer",
   "InputTokens": "%Integer",
   "OutputTokens": "%Integer",
   "CacheReadTokens": "%Integer",
   "CacheWriteTokens": "%Integer",
   "LargestRequestTokens": "%Integer",
   "CostUSD": "%Numeric(SCALE=6)",
   "Estimated": "%Boolean",
   "RecordedAt": "%String(MAXLEN=20)"
  },
  "indexes": {
   "DecisionRefIndex": "DecisionRef",
   "OwnerRefIndex": "OwnerRef"
  }
 },
 "OcuTalon.Bridge.Data.Price": {
  "super": "%Persistent",
  "props": {
   "Model": "%String(MAXLEN=128)",
   "InputPerMTok": "%Numeric(SCALE=4)",
   "OutputPerMTok": "%Numeric(SCALE=4)",
   "CacheReadPerMTok": "%Numeric(SCALE=4)",
   "CacheWritePerMTok": "%Numeric(SCALE=4)",
   "LongThresholdTokens": "%Integer",
   "LongInputPerMTok": "%Numeric(SCALE=4)",
   "LongOutputPerMTok": "%Numeric(SCALE=4)"
  },
  "indexes": {
   "ModelIndex": "Model unique"
  }
 },
 "OcuTalon.Bridge.Data.ConversationLink": {
  "super": "%Persistent",
  "props": {
   "OwnerRef": "%String(MAXLEN=22)",
   "Agent": "%String(MAXLEN=32)",
   "SessionId": "%String(MAXLEN=128)"
  },
  "indexes": {
   "OwnerRefAgentIndex": "OwnerRef,Agent unique"
  }
 },
 "OcuTalon.Bridge.Data.ModelFamily": {
  "super": "%Persistent",
  "props": {
   "Family": "%String(MAXLEN=32)",
   "ModelPrefix": "%String(MAXLEN=128)",
   "CapKey": "%String(MAXLEN=128)",
   "EffortKey": "%String(MAXLEN=128)"
  },
  "indexes": {
   "FamilyIndex": "Family unique"
  }
 },
 "OcuTalon.Data.Session": {
  "super": "%Persistent",
  "props": {
   "Ref": "%String(MAXLEN=22)",
   "TraceRef": "%String(MAXLEN=22)",
   "IrisUser": "%String(MAXLEN=128)",
   "CreatedAt": "%String(MAXLEN=20)",
   "Epoch": "%String(MAXLEN=22)",
   "ThreadSessionId": "%Integer",
   "ThreadDay": "%String(MAXLEN=10)"
  },
  "indexes": {
   "RefIndex": "Ref unique",
   "TraceRefIndex": "TraceRef unique",
   "IrisUserIndex": "IrisUser"
  }
 },
 "OcuTalon.Live.Event": {
  "super": "%Persistent",
  "props": {
   "Seq": "%Integer",
   "Stream": "%String(MAXLEN=22)",
   "Ts": "%String(MAXLEN=20)",
   "Type": "%String(MAXLEN=32)",
   "Payload": "%String(MAXLEN=)"
  },
  "indexes": {
   "StreamSeqIndex": "Stream,Seq unique"
  }
 },
 "OcuTalon.Data.AddressCounter": {
  "super": "%Persistent",
  "props": {
   "AddressHash": "%String(MAXLEN=128)",
   "CreatedAt": "%String(MAXLEN=20)"
  },
  "indexes": {
   "AddressHashIndex": "AddressHash"
  }
 },
 "OcuTalon.Data.StatusMark": {
  "super": "%Persistent",
  "props": {
   "Mark": "%String(MAXLEN=128)",
   "Value": "%String(MAXLEN=1000)",
   "RecordedAt": "%String(MAXLEN=20)"
  },
  "indexes": {
   "MarkIndex": "Mark unique"
  }
 },
 "OcuTalon.Data.GuideState": {
  "super": "%Persistent",
  "props": {
   "SessionRef": "%String(MAXLEN=22)",
   "RunEpoch": "%Integer",
   "TraceOpened": "%Boolean",
   "RunStartedAt": "%String(MAXLEN=20)"
  },
  "indexes": {
   "SessionRefIndex": "SessionRef unique"
  }
 },
 "OcuTalon.Data.BreakFeedRun": {
  "super": "%Persistent",
  "props": {
   "SessionRef": "%String(MAXLEN=22)",
   "State": "%String(MAXLEN=32)",
   "StartedAt": "%String(MAXLEN=20)"
  },
  "indexes": {
   "SessionRefIndex": "SessionRef"
  }
 },
 "OcuTalon.Data.Pairing": {
  "super": "%Persistent",
  "props": {
   "Ref": "%String(MAXLEN=22)",
   "SessionRef": "%String(MAXLEN=22)",
   "ChatId": "%String(MAXLEN=32)",
   "DisplayName": "%String(MAXLEN=128)",
   "CreatedAt": "%String(MAXLEN=20)",
   "CodeSessionRef": "%String(COLLATION=EXACT,MAXLEN=22)",
   "CodeHash": "%String(COLLATION=EXACT,MAXLEN=64)",
   "CodeExpiresAt": "%String(COLLATION=EXACT,MAXLEN=20)",
   "CodeUsedAt": "%String(COLLATION=EXACT,MAXLEN=20)",
   "ReplySlotAt": "%String(COLLATION=EXACT,MAXLEN=20)",
   "SeenAt": "%String(COLLATION=EXACT,MAXLEN=20)"
  },
  "indexes": {
   "RefIndex": "Ref unique",
   "SessionRefIndex": "SessionRef",
   "ChatIdIndex": "ChatId",
   "CodeSessionRefIndex": "CodeSessionRef unique",
   "CodeHashIndex": "CodeHash unique"
  }
 },
 "OcuTalon.Data.Turn": {
  "super": "%Persistent",
  "props": {
   "Ref": "%String(MAXLEN=22)",
   "SessionRef": "%String(MAXLEN=22)",
   "State": "%String(MAXLEN=32)",
   "Channel": "%String(MAXLEN=32)",
   "FromGuide": "%Boolean",
   "TriageDecisionRef": "%String(MAXLEN=22)",
   "TurnDecisionRef": "%String(MAXLEN=22)",
   "CreatedAt": "%String(MAXLEN=20)",
   "ItemId": "%String(MAXLEN=22)",
   "ClientId": "%String(COLLATION=EXACT,MAXLEN=128)",
   "Text": "%String(MAXLEN=)",
   "ReplyText": "%String(MAXLEN=)",
   "ReplyCatalogKey": "%String(MAXLEN=128)",
   "FallbackReason": "%String(MAXLEN=32)",
   "TraceHeaderId": "%Integer",
   "TraceItemIndex": "%Integer",
   "TraceItemIndexNoEvents": "%Integer",
   "Tainted": "%Boolean",
   "Attempt": "%Integer",
   "CheckKey": "%String(MAXLEN=128)",
   "CheckRows": "%String(MAXLEN=)"
  },
  "indexes": {
   "RefIndex": "Ref unique",
   "SessionRefIndex": "SessionRef",
   "ItemIdIndex": "ItemId unique",
   "ClientIdIndex": "SessionRef,ClientId"
  }
 },
 "OcuTalon.Data.SimMessage": {
  "super": "%Persistent",
  "props": {
   "Ref": "%String(MAXLEN=22)",
   "SessionRef": "%String(MAXLEN=22)",
   "Kind": "%String(MAXLEN=32)",
   "Direction": "%String(MAXLEN=32)",
   "ItemId": "%String(MAXLEN=22)",
   "CreatedAt": "%String(MAXLEN=20)",
   "Text": "%String(MAXLEN=)",
   "Sender": "%String(MAXLEN=1000)",
   "Subject": "%String(MAXLEN=1000)",
   "ApprovalRef": "%String(MAXLEN=22)",
   "Answer": "%String(MAXLEN=1000)"
  },
  "indexes": {
   "RefIndex": "Ref unique",
   "SessionRefIndex": "SessionRef",
   "ItemIdIndex": "ItemId"
  }
 },
 "OcuTalon.Data.Delivery": {
  "super": "%Persistent",
  "props": {
   "OwnerRef": "%String(MAXLEN=22)",
   "Channel": "%String(MAXLEN=32)",
   "ChannelMessageId": "%String(MAXLEN=128)",
   "ApprovalRef": "%String(MAXLEN=22)",
   "RecordedAt": "%String(MAXLEN=20)",
   "Kind": "%String(MAXLEN=32)",
   "Text": "%String(MAXLEN=)",
   "DecisionRef": "%String(MAXLEN=22)",
   "DueAt": "%String(MAXLEN=20)",
   "FallbackReason": "%String(MAXLEN=32)"
  },
  "indexes": {
   "ApprovalRefChannelOwnerRefIndex": "ApprovalRef,Channel,OwnerRef",
   "OwnerRefChannelIndex": "OwnerRef,Channel"
  }
 },
 "OcuTalon.Data.Reminder": {
  "super": "%Persistent",
  "props": {
   "Ref": "%String(MAXLEN=22)",
   "SessionRef": "%String(MAXLEN=22)",
   "Text": "%String(MAXLEN=1000)",
   "DueAt": "%String(MAXLEN=20)",
   "State": "%String(MAXLEN=32)",
   "Late": "%Boolean",
   "CreatedAt": "%String(MAXLEN=20)",
   "TraceHeaderId": "%Integer",
   "IdempotencyKey": "%String(MAXLEN=128)",
   "CancelKey": "%String(MAXLEN=128)"
  },
  "indexes": {
   "RefIndex": "Ref unique",
   "SessionRefIndex": "SessionRef"
  }
 },
 "OcuTalon.Data.Setting": {
  "super": "%Persistent",
  "props": {
   "Key": "%String(MAXLEN=128)",
   "Value": "%String(MAXLEN=1000)",
   "UpdatedAt": "%String(MAXLEN=20)"
  },
  "indexes": {
   "KeyIndex": "Key unique"
  }
 },
 "OcuTalon.Data.BackgroundCheck": {
  "super": "%Persistent",
  "props": {
   "Ref": "%String(MAXLEN=22)",
   "SessionRef": "%String(MAXLEN=22)",
   "Kind": "%String(MAXLEN=32)",
   "Namespace": "%String(MAXLEN=128)",
   "Production": "%String(MAXLEN=128)",
   "DisplayName": "%String(MAXLEN=128)",
   "AskedBy": "%String(MAXLEN=128)",
   "CreatedAt": "%String(MAXLEN=20)",
   "NextDueAt": "%String(MAXLEN=20)",
   "LastRunAt": "%String(MAXLEN=20)",
   "Result": "%String(MAXLEN=32)",
   "Finding": "%String(MAXLEN=1000)",
   "LastRunHeaderId": "%Integer"
  },
  "indexes": {
   "RefIndex": "Ref unique",
   "SessionRefIndex": "SessionRef",
   "NamespaceProductionIndex": "Namespace,Production"
  }
 },
 "OcuTalon.Data.WatchMark": {
  "super": "%Persistent",
  "props": {
   "Namespace": "%String(MAXLEN=128)",
   "Production": "%String(MAXLEN=128)",
   "MarkAt": "%String(MAXLEN=23)",
   "Seen": "%String(MAXLEN=)"
  },
  "indexes": {
   "NamespaceProductionIndex": "Namespace,Production unique"
  }
 },
 "OcuTalon.Data.Incident": {
  "super": "%Persistent",
  "props": {
   "Ref": "%String(MAXLEN=22)",
   "OwnerRef": "%String(MAXLEN=22)",
   "Namespace": "%String(MAXLEN=128)",
   "Production": "%String(MAXLEN=128)",
   "State": "%String(MAXLEN=32)",
   "OpenVariant": "%String(MAXLEN=32)",
   "NoticedAt": "%String(MAXLEN=20)",
   "Count": "%Integer",
   "NoticeCount": "%Integer",
   "FirstAt": "%String(MAXLEN=20)",
   "LastAt": "%String(MAXLEN=20)",
   "ItemNoun": "%String(MAXLEN=)",
   "Cause": "%String(MAXLEN=1000)",
   "CauseCategory": "%String(MAXLEN=32)",
   "Element": "%String(MAXLEN=128)",
   "FixSummary": "%String(MAXLEN=1000)",
   "Fallback": "%Boolean",
   "FallbackReason": "%String(MAXLEN=32)",
   "DecisionRef": "%String(MAXLEN=22)",
   "TraceHeaderId": "%Integer",
   "ClosedAt": "%String(MAXLEN=20)",
   "FirstHeaderId": "%Integer",
   "SampleHeaderId": "%Integer",
   "SampleError": "%String(MAXLEN=1000)",
   "RequestRefs": "%String(MAXLEN=)"
  },
  "indexes": {
   "RefIndex": "Ref unique",
   "OwnerRefIndex": "OwnerRef"
  },
  "sql": {
   "Count": "FailureCount"
  }
 },
 "OcuTalon.Data.FailureGroup": {
  "super": "%Persistent",
  "props": {
   "IncidentRef": "%String(MAXLEN=22)",
   "ItemName": "%String(MAXLEN=128)",
   "ErrorPattern": "%String(MAXLEN=1000)",
   "Seen": "%String(MAXLEN=)",
   "Seq": "%Integer",
   "Count": "%Integer",
   "FirstAt": "%String(MAXLEN=20)",
   "LastAt": "%String(MAXLEN=20)",
   "NoticeCount": "%Integer",
   "ErrorSummary": "%String(MAXLEN=1000)"
  },
  "indexes": {
   "IncidentRefIndex": "IncidentRef",
   "SeqIndex": "IncidentRef,Seq unique"
  },
  "sql": {
   "Count": "FailureCount"
  }
 },
 "OcuTalon.Data.FixRun": {
  "super": "%Persistent",
  "props": {
   "ApprovalRef": "%String(MAXLEN=22)",
   "IncidentRef": "%String(MAXLEN=22)",
   "StartedAt": "%String(MAXLEN=20)"
  },
  "indexes": {
   "ApprovalRefIndex": "ApprovalRef",
   "IncidentRefIndex": "IncidentRef"
  }
 }
}
}

XData Registry [ MimeType = application/json ]
{
[
 {
  "short": "Decision",
  "global": "^OcuTalonBP.Decision",
  "class": "OcuTalon.Bridge.Data.Decision"
 },
 {
  "short": "Approval",
  "global": "^OcuTalonBP.Approval",
  "class": "OcuTalon.Bridge.Data.ApprovalRequest"
 },
 {
  "short": "Usage",
  "global": "^OcuTalonBP.Usage",
  "class": "OcuTalon.Bridge.Data.Usage"
 },
 {
  "short": "Price",
  "global": "^OcuTalonBP.Price",
  "class": "OcuTalon.Bridge.Data.Price"
 },
 {
  "short": "ConvLink",
  "global": "^OcuTalonBP.ConvLink",
  "class": "OcuTalon.Bridge.Data.ConversationLink"
 },
 {
  "short": "ModelFamily",
  "global": "^OcuTalonBP.ModelFamily",
  "class": "OcuTalon.Bridge.Data.ModelFamily"
 },
 {
  "short": "Session",
  "global": "^OcuTalonP.Session",
  "class": "OcuTalon.Data.Session"
 },
 {
  "short": "AddrCount",
  "global": "^OcuTalonP.AddrCount",
  "class": "OcuTalon.Data.AddressCounter"
 },
 {
  "short": "StatusMark",
  "global": "^OcuTalonP.StatusMark",
  "class": "OcuTalon.Data.StatusMark"
 },
 {
  "short": "Guide",
  "global": "^OcuTalonP.Guide",
  "class": "OcuTalon.Data.GuideState"
 },
 {
  "short": "BreakFeed",
  "global": "^OcuTalonP.BreakFeed",
  "class": "OcuTalon.Data.BreakFeedRun"
 },
 {
  "short": "Pairing",
  "global": "^OcuTalonP.Pairing",
  "class": "OcuTalon.Data.Pairing"
 },
 {
  "short": "Turn",
  "global": "^OcuTalonP.Turn",
  "class": "OcuTalon.Data.Turn"
 },
 {
  "short": "SimMsg",
  "global": "^OcuTalonP.SimMsg",
  "class": "OcuTalon.Data.SimMessage"
 },
 {
  "short": "Delivery",
  "global": "^OcuTalonP.Delivery",
  "class": "OcuTalon.Data.Delivery"
 },
 {
  "short": "Reminder",
  "global": "^OcuTalonP.Reminder",
  "class": "OcuTalon.Data.Reminder"
 },
 {
  "short": "Setting",
  "global": "^OcuTalonP.Setting",
  "class": "OcuTalon.Data.Setting"
 },
 {
  "short": "Check",
  "global": "^OcuTalonP.Check",
  "class": "OcuTalon.Data.BackgroundCheck"
 },
 {
  "short": "WatchMark",
  "global": "^OcuTalonP.WatchMark",
  "class": "OcuTalon.Data.WatchMark"
 },
 {
  "short": "Incident",
  "global": "^OcuTalonP.Incident",
  "class": "OcuTalon.Data.Incident"
 },
 {
  "short": "FailGroup",
  "global": "^OcuTalonP.FailGroup",
  "class": "OcuTalon.Data.FailureGroup"
 },
 {
  "short": "FixRun",
  "global": "^OcuTalonP.FixRun",
  "class": "OcuTalon.Data.FixRun"
 },
 {
  "short": "LiveEvent",
  "global": "^OcuTalonP.LiveEvent",
  "class": "OcuTalon.Live.Event"
 }
]
}

}
