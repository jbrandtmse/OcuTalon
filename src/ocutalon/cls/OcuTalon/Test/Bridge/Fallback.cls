/// Tests of the one classification, Decide.Classify, and of the way Lane B's catalog words its reasons (Story 1.6; AD-8, NFR-5): pure,
/// with no production, no mock and no row. Classify reads the facts of one request and nothing else; the catalog is read through
/// OcuTalon.Msg.Catalog.Render and Entry only.
///   - TestEachFactAlone: each fact gives its own reason, and no facts, and a request or reply that is usable, give "";
///   - TestOrder: the earlier rule wins when two facts hold: the prechecks, then the text of a failure, then the finish reason, then an
///     empty text, then invalid;
///   - TestFailureOrder (QA): when the text of a failure holds the words of two rules, the earlier rule wins, for every pair of the five
///     rules and with the words in either order in the text: daily_cap, then no_key, then timeout, then rate_limited, then unusable;
///   - TestMeasuredTexts: the failure texts that AI Hub raised on build 154 and that earlier stories and this one measured: the gateway's
///     403, the missing key, the 529, the 400, 401 and 500, a timeout, and the two errors of a loop that does not end;
///   - TestEmptyText: an empty text is empty when the provider reported a finish reason and unusable when it reported none, and a
///     finish reason that is empty never gives refusal or cut_off;
///   - TestTextMatching: the failure literals are matched without regard to case, the missing-key text needs both of its pieces, and
///     Invalid input is an error until a later story gives it a reason of its own;
///   - TestPure: facts that are not an object, a missing fact and a fact that Classify does not read change nothing, and the facts are
///     not changed; every answer is "" or a value of Msg.Enum FALLBACKREASON, and too_large is never one of them yet;
///   - TestCatalogMap (AC5): each of the 12 reasons rendered through "conversation.turnFallback" gives exactly one of the 11
///     fallbackReason.* texts, invalid and unusable give the generic one, refusal and cut_off their own, and all 11 are reached.
/// Added by Story 1.7 (AD-8, FR-4):
///   - TestTimedOut: a timer that fired (timedOut) gives timeout, and rate_limited once Decide has re-sent (resends above 0); the precheck
///     reasons win over it, and it wins over the text of a failure, the finish reason, an empty text and invalid; resends without timedOut
///     gives nothing, and a missing fact counts as false or 0.
Class OcuTalon.Test.Bridge.Fallback Extends %UnitTest.TestCase
{

/// The class under test.
Parameter DECIDE = "OcuTalon.Bridge.Process.Decide";

/// The gateway's 403 as AI Hub raised it (Story 1.6, Task 0 (b), measured on build 154).
Parameter DAILYCAP = "ERROR <%AICore>ProviderError: Provider 'anthropic' error: API error: Authentication failed: daily cost cap reached";

/// The error of a runner request with no key (Story 1.2, measured on build 154).
Parameter NOKEY = "ERROR <%AICore>ProviderCreateFailed: Failed to create provider 'anthropic'    > ERROR <%AICore>InternalError: Internal AI-Core error: @{env:ANTHROPIC_API_KEY} has no value and no :-fallback was given";

/// The error for HTTP 529 (Story 0.11, measured on build 154).
Parameter OVERLOADED = "ERROR <%AICore>ProviderError: Provider 'anthropic' error: Rate limit exceeded: CI mock: overloaded.";

/// The error of a loop that stalls on a tool that does not exist (Story 1.6, Task 0 (a)).
Parameter LOOP = "ERROR <%AICore>LoopDetected: Agentic loop stalled: no new evidence from tool results after 4 assessment(s)";

/// The error of a loop that reaches the agent's maximum of iterations (Story 1.6, Task 0 (a)).
Parameter MAXITERATIONS = "ERROR <%AICore>MaxIterationsReached: Max iterations (4) reached without a final response";

/// Each fact alone gives its own reason; no facts, and a usable request and reply, give "".
Method TestEachFactAlone()
{
	Do ..AssertReason({}, "", "no facts")
	Do ..AssertReason({"noKey": true}, "no_key", "noKey")
	Do ..AssertReason({"capped": true}, "daily_cap", "capped")
	Do ..AssertReason({"overBudget": true}, "budget", "overBudget")
	Do ..AssertReason({"failure": "something failed"}, "error", "a failure with no known text")
	Do ..AssertReason({"finishReason": "refusal"}, "refusal", "the finish reason refusal")
	Do ..AssertReason({"finishReason": "max_tokens"}, "cut_off", "the finish reason max_tokens")
	Do ..AssertReason({"finishReason": "end_turn", "text": ""}, "empty", "an empty text with a finish reason")
	Do ..AssertReason({"text": ""}, "unusable", "an empty text with none")
	Do ..AssertReason({"text": "A reply.", "invalid": true}, "invalid", "invalid")
	Do ..AssertReason({"noKey": false, "capped": false, "overBudget": false, "failure": "", "finishReason": "", "text": "A reply.", "invalid": false}, "", "every fact false or empty")
	Do ..AssertReason({"finishReason": "end_turn", "text": "A reply."}, "", "a usable reply")
	Do ..AssertReason({"finishReason": "", "text": "A reply."}, "", "a usable reply from a provider that reports no finish reason")
	Do ..AssertReason({"text": "A reply."}, "", "a text alone")
	Do ..AssertReason({"finishReason": "tool_use", "text": "A reply."}, "", "another finish reason with a text")
}

/// The first rule that holds wins: noKey, capped, overBudget; then the failure; then refusal and cut_off; then an empty text; then invalid.
Method TestOrder()
{
	Do ..AssertReason({"noKey": true, "capped": true, "overBudget": true}, "no_key", "no_key before daily_cap and budget")
	Do ..AssertReason({"capped": true, "overBudget": true}, "daily_cap", "daily_cap before budget")
	Do ..AssertReason({"noKey": true, "failure": "x"}, "no_key", "a precheck before a failure")
	Do ..AssertReason({"overBudget": true, "failure": "x", "finishReason": "refusal", "text": "", "invalid": true}, "budget", "a precheck before everything after it")
	Do ..AssertReason({"failure": "x", "finishReason": "refusal"}, "error", "a failure before the finish reason")
	Do ..AssertReason({"failure": (..#DAILYCAP), "finishReason": "refusal", "text": ""}, "daily_cap", "the failure's own reason before the finish reason")
	Do ..AssertReason({"failure": "x", "text": "", "invalid": true}, "error", "a failure before an empty text and invalid")
	Do ..AssertReason({"finishReason": "refusal", "text": ""}, "refusal", "refusal before an empty text")
	Do ..AssertReason({"finishReason": "max_tokens", "text": ""}, "cut_off", "cut_off before an empty text")
	Do ..AssertReason({"finishReason": "max_tokens", "invalid": true, "text": "A cut"}, "cut_off", "cut_off before invalid")
	Do ..AssertReason({"finishReason": "refusal", "invalid": true, "text": "A refusal"}, "refusal", "refusal before invalid")
	Do ..AssertReason({"finishReason": "end_turn", "text": "  ", "invalid": true}, "empty", "an empty text before invalid")
	Do ..AssertReason({"finishReason": "", "text": "", "invalid": true}, "unusable", "and so is the unusable one")
}

/// The rule for a timer that fired comes after the prechecks and before the failure text (AD-8): timedOut gives timeout, or rate_limited when
/// resends is above 0, because the retries then ran out (FR-4). resends alone, and resends with a timedOut that is false, give nothing.
Method TestTimedOut()
{
	Do ..AssertReason({"timedOut": true}, "timeout", "timedOut alone")
	Do ..AssertReason({"timedOut": true, "resends": 0}, "timeout", "timedOut with no re-send")
	Do ..AssertReason({"timedOut": true, "resends": 1}, "rate_limited", "timedOut after one re-send")
	Do ..AssertReason({"timedOut": true, "resends": 4}, "rate_limited", "timedOut after four re-sends")
	Do ..AssertReason({"timedOut": true, "resends": "x"}, "timeout", "timedOut with resends that is not a number")
	Do ..AssertReason({"resends": 3}, "", "resends without timedOut")
	Do ..AssertReason({"timedOut": false, "resends": 3}, "", "resends with timedOut false")
	Do ..AssertReason({"timedOut": false}, "", "timedOut false")
	// the prechecks win, with and without a re-send
	Set reasons = $ListBuild("no_key", "daily_cap", "budget")
	Set facts = $ListBuild("noKey", "capped", "overBudget")
	For i = 1:1:3 {
		For resends = 0, 2 {
			Set one = {"timedOut": true}
			Do one.%Set("resends", resends, "number")
			Do one.%Set($List(facts, i), 1, "boolean")
			Do ..AssertReason(one, $List(reasons, i), $List(facts, i)_" with timedOut and "_resends_" re-sends")
		}
	}
	// and it wins over everything after them
	Do ..AssertReason({"timedOut": true, "failure": (..#DAILYCAP)}, "timeout", "timedOut before the text of a failure")
	Do ..AssertReason({"timedOut": true, "failure": (..#OVERLOADED)}, "timeout", "and before a rate limit")
	Do ..AssertReason({"timedOut": true, "resends": 1, "failure": (..#NOKEY)}, "rate_limited", "after a re-send, before a missing key found by the runner")
	Do ..AssertReason({"timedOut": true, "finishReason": "refusal", "text": "", "invalid": true}, "timeout", "timedOut before the finish reason, an empty text and invalid")
}

/// The failure rules are applied in one order, whatever the order of the words in the text: daily_cap, no_key, timeout, rate_limited, unusable
/// (the agent's iteration errors), and error for a text that none of them finds. A text that holds the words of two rules gives the reason of
/// the earlier one, for every pair and with the words in either order, so that no rule can move up or down the list unseen.
Method TestFailureOrder()
{
	Set pieces = $ListBuild("daily cost cap reached", "@{env:ANTHROPIC_API_KEY} has no value", "operation timed out", "Rate limit exceeded", "<%AICore>MaxIterationsReached")
	Set reasons = $ListBuild("daily_cap", "no_key", "timeout", "rate_limited", "unusable")
	For i = 1:1:$ListLength(pieces) {
		Do ..AssertReason({"failure": ("ERROR x "_$List(pieces, i)_" y")}, $List(reasons, i), "the words of "_$List(reasons, i)_" alone")
	}
	Do ..AssertReason({"failure": "ERROR x words that no rule finds y"}, "error", "words that no rule finds")
	For i = 1:1:$ListLength(pieces) - 1 {
		For j = i + 1:1:$ListLength(pieces) {
			Do ..AssertReason({"failure": ($List(pieces, i)_" | "_$List(pieces, j))}, $List(reasons, i), "the words of "_$List(reasons, i)_" then "_$List(reasons, j)_" give "_$List(reasons, i))
			Do ..AssertReason({"failure": ($List(pieces, j)_" | "_$List(pieces, i))}, $List(reasons, i), "the words of "_$List(reasons, j)_" then "_$List(reasons, i)_" give "_$List(reasons, i)_" too")
		}
	}
	// all five at once, then each winner taken out in turn: the next rule wins
	For first = 1:1:$ListLength(pieces) {
		Set text = "ERROR"
		For k = $ListLength(pieces):-1:first {
			Set text = text_" | "_$List(pieces, k)
		}
		Do ..AssertReason({"failure": (text)}, $List(reasons, first), "with the words of every rule from "_$List(reasons, first)_" on, "_$List(reasons, first)_" wins")
	}
	// and a precheck still wins over every one of them, and the failure over the finish reason and the text
	For i = 1:1:$ListLength(pieces) {
		Do ..AssertReason({"noKey": true, "failure": ($List(pieces, i))}, "no_key", "noKey before the words of "_$List(reasons, i))
		Do ..AssertReason({"capped": true, "failure": ($List(pieces, i))}, "daily_cap", "capped before the words of "_$List(reasons, i))
		Do ..AssertReason({"overBudget": true, "failure": ($List(pieces, i))}, "budget", "overBudget before the words of "_$List(reasons, i))
		Do ..AssertReason({"failure": ($List(pieces, i)), "finishReason": "refusal", "text": "", "invalid": true}, $List(reasons, i), "the words of "_$List(reasons, i)_" before the finish reason, an empty text and invalid")
	}
}

/// The failure texts that were measured.
Method TestMeasuredTexts()
{
	Do ..AssertReason({"failure": (..#DAILYCAP)}, "daily_cap", "the gateway's 403")
	Do ..AssertReason({"failure": (..#NOKEY)}, "no_key", "the missing key")
	Do ..AssertReason({"failure": (..#OVERLOADED)}, "rate_limited", "the 529")
	Do ..AssertReason({"failure": "ERROR <%AICore>ProviderError: Provider 'anthropic' error: Rate limit exceeded: CI mock: rate limited."}, "rate_limited", "and a 429")
	Do ..AssertReason({"failure": "ERROR <%AICore>ProviderError: Provider 'anthropic' error: operation timed out"}, "timeout", "a provider timeout")
	Do ..AssertReason({"failure": (..#MAXITERATIONS)}, "unusable", "the agent's maximum iterations")
	Do ..AssertReason({"failure": (..#LOOP)}, "unusable", "a loop that stalls")
	Do ..AssertReason({"failure": "ERROR <%AICore>ProviderError: Provider 'anthropic' error: Invalid input: CI mock: sampling parameters are not allowed (NFR-1): temperature"}, "error", "the 400")
	Do ..AssertReason({"failure": "ERROR <%AICore>ProviderError: Provider 'anthropic' error: API error: Authentication failed: CI mock: the request has no x-api-key header"}, "error", "the 401")
	Do ..AssertReason({"failure": "ERROR <%AICore>ProviderError: Provider 'anthropic' error: API error: [api_error] CI mock: the provider failed."}, "error", "the 500")
	Do ..AssertReason({"failure": "The runner gave no Reply"}, "error", "the failure that Decide gives a reply that is not a Reply")
	Do ..AssertReason({"failure": "ERROR <%AICore>InternalError: Internal AI-Core error: the compaction failed"}, "error", "an internal error")
}

/// An empty text is empty when the provider reported a finish reason, and unusable when it reported none: a provider that gives no
/// stop reason cannot tell an empty reply from a refusal or a cut-off. A finish reason that is empty never gives refusal or cut_off.
Method TestEmptyText()
{
	For text = "", " ", $Char(9, 10, 13, 32), $Char(0, 7, 27, 127) {
		Set label = "the text of "_$Length(text)_" characters of white space and controls"
		Do ..AssertReason({"finishReason": "end_turn", "text": (text)}, "empty", label_" with end_turn is empty")
		Do ..AssertReason({"finishReason": "", "text": (text)}, "unusable", label_" with no finish reason is unusable")
		Do ..AssertReason({"text": (text)}, "unusable", label_" with the finish reason missing is unusable")
	}
	Do ..AssertReason({"finishReason": "stop", "text": ""}, "empty", "an empty text with a finish reason that is another word is empty")
	Do ..AssertReason({"finishReason": "", "text": "x"}, "", "an empty finish reason with a text is usable")
	Do ..AssertNotIn(..Classify({"finishReason": "", "text": "", "invalid": true}), "refusal,cut_off", "an empty finish reason never gives refusal or cut_off")
	Do ..AssertNotIn(..Classify({"finishReason": "", "text": "x", "invalid": true}), "refusal,cut_off", "not with a text either")
}

/// The failure literals are matched without regard to case; the missing-key text needs both pieces; Invalid input is an error.
Method TestTextMatching()
{
	Do ..AssertReason({"failure": "DAILY COST CAP REACHED"}, "daily_cap", "the daily cap text in capitals")
	Do ..AssertReason({"failure": "x Daily Cost Cap Reached x"}, "daily_cap", "in the middle of a text")
	Do ..AssertReason({"failure": "Operation Timed Out"}, "timeout", "the timeout text in capitals")
	Do ..AssertReason({"failure": "RATE LIMIT EXCEEDED"}, "rate_limited", "the rate limit text in capitals")
	Do ..AssertReason({"failure": "rate limit exceeded"}, "rate_limited", "and in small letters")
	Do ..AssertReason({"failure": "<%aicore>maxiterationsreached"}, "unusable", "the maximum iterations code in small letters")
	Do ..AssertReason({"failure": "<%AICORE>LOOPDETECTED"}, "unusable", "the loop code in capitals")
	Do ..AssertReason({"failure": "@{ENV:ANTHROPIC_API_KEY} HAS NO VALUE"}, "no_key", "the missing key in capitals")
	Do ..AssertReason({"failure": "@{env:ANTHROPIC_API_KEY} was found"}, "error", "a placeholder alone is not the missing key")
	Do ..AssertReason({"failure": "the value has no value"}, "error", "and neither are the words alone")
	Do ..AssertReason({"failure": "ERROR <%AICore>ProviderError: Provider 'anthropic' error: Invalid input: x"}, "error", "Invalid input is an error until Story 1.8")
	Do ..AssertReason({"failure": "The daily cap was reached"}, "error", "a text that only resembles the daily cap text is an error")
	Do ..AssertReason({"failure": "daily cost cap reached and rate limit exceeded"}, "daily_cap", "the daily cap text wins over the rate limit text")
	Do ..AssertReason({"failure": "operation timed out after a Rate limit exceeded"}, "timeout", "and the timeout text wins over the rate limit text")
}

/// Classify is pure and total.
Method TestPure()
{
	Do $$$AssertEquals(..Classify(""), "", "facts that are an empty string give no reason")
	Do $$$AssertEquals(..Classify("noKey"), "", "facts that are a string give none")
	Do $$$AssertEquals(..Classify([]), "", "facts that are an array give none")
	Do ..AssertReason({"unknown": true, "failure": "", "other": "x"}, "", "facts that Classify does not read change nothing")
	Set facts = {"failure": (..#DAILYCAP), "finishReason": "refusal", "text": "t", "invalid": true, "noKey": false}
	Set before = facts.%ToJSON()
	Set first = ..Classify(facts)
	Do $$$AssertEquals(facts.%ToJSON(), before, "the facts are not changed")
	Do $$$AssertEquals(..Classify(facts), first, "and the same facts give the same reason again")

	// every combination of the facts gives "" or a value of FALLBACKREASON, and never too_large
	Set allowed = ##class(OcuTalon.Bridge.Msg.Enum).#FALLBACKREASON
	Set bad = ""
	Set seen = ""
	For noKey = 0, 1 {
		For capped = 0, 1 {
			For over = 0, 1 {
				For failure = "", "x", ..#DAILYCAP, ..#NOKEY, ..#OVERLOADED, ..#MAXITERATIONS, "operation timed out" {
					For finish = "", "end_turn", "refusal", "max_tokens" {
						For text = "", "t" {
							For invalid = 0, 1 {
								Set facts = {"noKey": (noKey), "capped": (capped), "overBudget": (over), "failure": (failure), "finishReason": (finish), "text": (text), "invalid": (invalid)}
								Set reason = ..Classify(facts)
								If (reason '= "") && '$ListFind($ListFromString(allowed), reason) Set bad = bad _ $ListBuild(reason)
								Set seen("r:"_reason) = 1
							}
						}
					}
				}
			}
		}
	}
	Do $$$AssertEquals($ListToString(bad), "", "no combination gives a word that is not a FALLBACKREASON")
	Do $$$AssertEquals($Data(seen("r:too_large")), 0, "none gives too_large, which Story 1.9 adds")
	Do $$$AssertEquals($Data(seen("r:")), 1, "and some combinations are usable")
	Set reached = ""
	Set reason = ""
	For {
		Set reason = $Order(seen(reason))
		Quit:reason=""
		Set reached = reached _ $ListBuild(reason)
	}
	Do $$$AssertEquals($ListLength(reached), 12, "the 12 values less too_large, and the empty answer, are all reached: "_$ListToString(reached, ","))
}

/// AC5: the 12 values of FallbackReason through Lane B's renderer give 11 distinct wordings, one for each reason except that invalid and
/// unusable share the generic one, and all 11 fallbackReason.* texts are reached.
Method TestCatalogMap()
{
	Set reasons = $ListFromString(##class(OcuTalon.Bridge.Msg.Enum).#FALLBACKREASON)
	Do $$$AssertEquals($ListLength(reasons), 12, "the bridge has 12 FallbackReason values")
	Set keys = $ListFromString("noKey,dailyCap,budget,tooLarge,timeout,rateLimited,error,refusal,cutOff,empty,generic")
	Set texts = ""
	Set position = 0
	While $ListNext(keys, position, key) {
		Set entry = ##class(OcuTalon.Msg.Catalog).Entry("fallbackReason."_key, .sc)
		Do $$$AssertStatusOK(sc, "the catalog has fallbackReason."_key)
		Set texts = texts _ $ListBuild($Select($IsObject(entry): entry.text, 1: ""))
	}
	Set mapping = "no_key=noKey,daily_cap=dailyCap,budget=budget,too_large=tooLarge,timeout=timeout,rate_limited=rateLimited,error=error,refusal=refusal,cut_off=cutOff,empty=empty,invalid=generic,unusable=generic"
	Set reached = ""
	Set position = 0
	While $ListNext(reasons, position, reason) {
		Set text = ##class(OcuTalon.Msg.Catalog).Render("conversation.turnFallback", {"fallbackReason": (reason)}.%ToJSON(), "web", .sc)
		Do $$$AssertStatusOK(sc, reason_" renders")
		Set found = ""
		For i = 1:1:$ListLength(texts) {
			If (text '= "") && (text [ $List(texts, i)) Set found = found _ $ListBuild($List(keys, i))
		}
		Do $$$AssertEquals($ListLength(found), 1, reason_" renders exactly one of the 11 reasons: "_text)
		Set expected = ..Lookup(mapping, reason)
		Do $$$AssertEquals($ListToString(found), expected, reason_" gives the reason "_expected)
		Set reached = reached _ found
	}
	Set distinct = ""
	Set position = 0
	While $ListNext(reached, position, key) {
		If '$ListFind(distinct, key) Set distinct = distinct _ $ListBuild(key)
	}
	Do $$$AssertEquals($ListLength(distinct), 11, "all 11 are reached")
	Set refusal = ##class(OcuTalon.Msg.Catalog).Render("conversation.turnFallback", "{""fallbackReason"":""refusal""}", "web")
	Set cutoff = ##class(OcuTalon.Msg.Catalog).Render("conversation.turnFallback", "{""fallbackReason"":""cut_off""}", "web")
	Set generic = ##class(OcuTalon.Msg.Catalog).Render("conversation.turnFallback", "{""fallbackReason"":""unusable""}", "web")
	Do $$$AssertTrue((refusal '= generic) && (cutoff '= generic) && (refusal '= cutoff), "refusal and cut_off have wordings of their own, apart from the generic one")
	Do $$$AssertTrue(generic [ "couldn't be used", "the generic wording says the reply couldn't be used: "_generic)
}

/// --- helpers ---
/// Classify of the facts.
ClassMethod Classify(facts) As %String [ Private ]
{
	Quit $ClassMethod(..#DECIDE, "Classify", facts)
}

/// Asserts the reason that Classify gives for the facts.
Method AssertReason(facts As %DynamicObject, expected As %String, label As %String) [ Private ]
{
	Do $$$AssertEquals(..Classify(facts), expected, label_" gives '"_expected_"': "_facts.%ToJSON())
}

/// Asserts that the answer is none of the words (a comma-separated list).
Method AssertNotIn(answer As %String, words As %String, label As %String) [ Private ]
{
	Do $$$AssertNotTrue($ListFind($ListFromString(words), answer), label_" (it gave '"_answer_"')")
}

/// The value of name in a list of name=value pairs, comma-separated.
ClassMethod Lookup(map As %String, name As %String) As %String [ Private ]
{
	Set value = ""
	For i = 1:1:$Length(map, ",") {
		If $Piece($Piece(map, ",", i), "=", 1) = name Set value = $Piece($Piece(map, ",", i), "=", 2)
	}
	Quit value
}

}
