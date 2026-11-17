# Story 28.2, Task 0: duplicate thresholds for the nightly merge (R-28.2-3 hard gate)

Measured 2026-11-16 on one lane-C warm throwaway (run tag `e28s2t0w`, `ci/warm.sh up` then `ci/warm.sh down`; slot C was not used), built from `OCT-epic28` at `7424f2fd0`: IRIS for UNIX (Ubuntu Server LTS for ARM64 Containers) 2026.3.0AI (Build 154U), aarch64, the image built from this worktree, namespace `OCUTALON`. Nothing was added to the repository except this file.

## Method

- **Embedder.** Every text was embedded with the product's own `##class(OcuTalon.Memory.Embedding).Embed(text, .vector, .job)` (the FastEmbed AllMiniLM-L6-v2 model baked into the image, 384 DOUBLE values; every call returned OK, one worker job). The harness was a scratch routine loaded into the throwaway only (`docker exec ... iris session`), reading the pairs from a JSON file copied into the container; it was never in the repository and went with the stack.
- **Cosine.** `SELECT VECTOR_COSINE(TO_VECTOR(?, DOUBLE, 384), TO_VECTOR(?, DOUBLE, 384))` with each vector written as `Memory.ToText` writes it, so the score is the one the product's SQL computes. Cross-check: a cosine recomputed outside IRIS from the same 384 values differs by at most 2.4e-15; every vector has norm 1 within 1e-8.
- **Keyword Jaccard.** The token rule of the private `OcuTalon.Memory.Words`, reproduced exactly (not called): the distinct runs of `[\p{L}\p{N}]+` found with `$Locate`, folded with `$ZConvert(word, "L")`; Jaccard = |A ∩ B| / |A ∪ B| of the two token sets. `Words` stops at `MAXWORDS` (32) tokens; no text here has more than 20 (one has 20), so the cap never applies (the future shared `Tokens(text)` should keep or drop the cap on purpose: a cap would make two long texts that differ after token 32 look identical). Cross-check: the same rule in Python (`[^\W_]+`, lower case) gave identical values for all 72 pairs.
- **The set.** 72 invented pairs (no real person or partner): 30 `dup` (3 exact, 6 case/punctuation, 8 word order, 13 light rephrasing) and 42 `distinct` (8 different value, 5 different date or day, 7 negation, 22 different entity). The last 10 `distinct` pairs (all `kind: "entity"`) are role or value swaps: the same words in a different order with a different meaning ("Dana Lee reports to Alex Chen" / "Alex Chen reports to Dana Lee", "Use port 6661 for ADT and port 6662 for lab results" / the ports swapped). They were added after the first 62 pairs showed that only an identical token set separates the distinct pairs, because a swap is exactly what an identical token set cannot see.

## Results

The full table of the rule `cosine >= DUPCOSINE AND jaccard >= DUPKEYWORDS` (TP = dup pairs merged, FP = distinct pairs merged):

| DUPCOSINE | DUPKEYWORDS | true merges | false merges | merged kinds |
|---|---|---|---|---|
| 0.85 / 0.90 | 0.75 | 20/30 | 31/42 / 28/42 | exact, case, order, rephrase |
| 0.90 | 0.90 | 17/30 | 12/42 | exact, case, order |
| 0.90 / 0.91 | 0.95 or 1.0 | 17/30 | 10/42 (the 10 swaps) | exact, case, order |
| 0.95 | 1.0 | 16/30 | 10/42 | exact, case, order |
| 0.99 | 1.0 | 6/30 | 7/42 | exact, case, order |
| **0.9994** | **1.0** (any value ≥ 0.75 gives the same) | **3/30 (10 %)** | **0/42** | exact only |

What the numbers say:

1. **No distinct pair is separated by the keyword axis below 1.0 with any margin.** Without the swaps the highest distinct Jaccard is 0.9412 (a 16-token sentence with "not" inserted). It grows with length: one changed word in an n-token sentence gives (n−1)/(n+1), one inserted word n/(n+1), so any DUPKEYWORDS below 1.0 is passed by a long enough memory that differs in one name, number, date or "not". DUPKEYWORDS must be 1.0 (identical token sets).
2. **Identical token sets do not mean the same fact.** The 10 swaps all have Jaccard 1.0 and cosine 0.9745 to 0.9993, while the true word-order duplicates have cosine 0.9119 to 0.9927 and the case/punctuation duplicates 0.9537 to 0.9931. The ranges overlap completely, so no DUPCOSINE separates swaps from re-ordered or re-punctuated duplicates. The embedder is nearly blind to order: the swap "Use port 6661 for ADT and port 6662 for lab results" / ports swapped scores 0.99929, higher than every non-identical duplicate.
3. **Zero false merges with cosine + Jaccard alone is reachable only at DUPCOSINE ≥ 0.9994, which merges exact repeats only** (identical texts give cosine exactly 1: identical vectors). True-merge rate 3/30 (10 %). Closest distinct pair: cosine 0.99929, Jaccard 1.0 (the port swap), margin 0.0001 on the cosine axis and 0 on the keyword axis. That is no safety margin; it is "identical text" in disguise.
4. Rephrases (13/30 of the duplicates) have Jaccard 0.33 to 0.78 and cosine as low as 0.4733 ("Keep answers brief" / "Please keep answers brief"), inside the distinct pairs' ranges (Jaccard 0.56 to 0.94, cosine 0.5970 to 0.9993). No threshold pair merges any rephrase without false merges.

## Proposed extra rules (proposals; the Planner decides)

- **P-a: same token sequence.** A duplicate when the two texts' token lists (the `Words` rule, in order, case-folded, punctuation dropped) are equal; the cosine is then redundant (those pairs score 0.9537 to 1.0, so a `DUPCOSINE` of 0.95 changes nothing on this set). Effect: **9/30 true merges (30 %: 3 exact + 6 case/punctuation), 0/42 false merges**, and zero false merges by construction for any pair whose words differ in any token or in order (every distinct pair here). It needs no vector at all: it is "the same text up to case and punctuation", so the vector only narrows the candidates. It loses the 8 word-order duplicates, which cannot be told from swaps by tokens or by this embedder.
- **"No differing number token" / "no negation word on one side only" / "the token sets differ only in stop words":** no effect on the result. At DUPKEYWORDS 1.0 the token sets are identical, so none of them can fire; the false merges at 1.0 are the swaps, which have the same numbers, the same negations and the same words on both sides. Below 1.0 they would block the value, date and negation pairs but not the entity pairs (Lee/Kim, Riverside/Lakeside, ORM/ORU), which would need a "no differing token at all" rule, which is DUPKEYWORDS 1.0 again.

## Verdict

**Fallback: ship fading only (ACs 1-3) and move the nightly merge to Story 28.4** (the pre-approved split under R-28.2-3). With the specified rule (cosine ≥ DUPCOSINE AND Jaccard ≥ DUPKEYWORDS), zero false merges is reachable only for exact repeats (3/30, 10 %, margin 0.0001). The best zero-false-merge variant found, proposal P-a, merges exact and case/punctuation repeats (9/30, 30 %), still below the ~40 % usefulness line and not a vector-plus-keyword similarity merge in the sense the spec describes. If 28.4 takes P-a, the thresholds for the implement stage would be: token sequence equal (DUPKEYWORDS effectively 1.0 on the ordered token list), DUPCOSINE 0.95 as a candidate filter, measured on this set at 9/30 true, 0/42 false.

## The labelled set

72 pairs, in the order measured (cosine and Jaccard rounded to 4 places; raw values: the exact pairs 1 exactly, the closest distinct pair 0.99929034266503236061). The texts are invented test data. A fixture should assert: no `distinct` pair is merged; every `exact` and `case` pair is merged under P-a.

```json
[
{"a": "My manager is Dana Lee", "b": "My manager is Dana Lee", "label": "dup", "kind": "exact", "cosine": 1.0, "jaccard": 1.0},
{"a": "The ADT feed from Riverside Clinic retries every 5 minutes", "b": "The ADT feed from Riverside Clinic retries every 5 minutes", "label": "dup", "kind": "exact", "cosine": 1.0, "jaccard": 1.0},
{"a": "Priya prefers alerts by Telegram, not email", "b": "Priya prefers alerts by Telegram, not email", "label": "dup", "kind": "exact", "cosine": 1.0, "jaccard": 1.0},
{"a": "My manager is Dana Lee", "b": "my manager is Dana Lee.", "label": "dup", "kind": "case", "cosine": 0.9885, "jaccard": 1.0},
{"a": "The Lab results interface uses MLLP port 6661", "b": "the lab results interface uses MLLP port 6661.", "label": "dup", "kind": "case", "cosine": 0.9903, "jaccard": 1.0},
{"a": "Marco Ruiz is the contact at Northside Labs", "b": "marco ruiz is the contact at northside labs!", "label": "dup", "kind": "case", "cosine": 0.9683, "jaccard": 1.0},
{"a": "Production OCUHL7 must be stopped before the Sunday patch window.", "b": "Production OCUHL7 must be stopped before the Sunday patch window", "label": "dup", "kind": "case", "cosine": 0.9775, "jaccard": 1.0},
{"a": "Remind me: the HL7 schema upgrade is due Friday", "b": "Remind me - the HL7 schema upgrade is due Friday.", "label": "dup", "kind": "case", "cosine": 0.9931, "jaccard": 1.0},
{"a": "I prefer short answers with code examples", "b": "I prefer short answers, with code examples.", "label": "dup", "kind": "case", "cosine": 0.9537, "jaccard": 1.0},
{"a": "Dana Lee is my manager", "b": "My manager is Dana Lee", "label": "dup", "kind": "order", "cosine": 0.9606, "jaccard": 1.0},
{"a": "Every 5 minutes the ADT feed retries", "b": "The ADT feed retries every 5 minutes", "label": "dup", "kind": "order", "cosine": 0.9654, "jaccard": 1.0},
{"a": "On call this weekend is Alex Chen", "b": "Alex Chen is on call this weekend", "label": "dup", "kind": "order", "cosine": 0.9758, "jaccard": 1.0},
{"a": "For alerts, use Telegram", "b": "Use Telegram for alerts", "label": "dup", "kind": "order", "cosine": 0.9119, "jaccard": 1.0},
{"a": "The PharmaLink partner sends RDE messages over SFTP", "b": "Over SFTP, the PharmaLink partner sends RDE messages", "label": "dup", "kind": "order", "cosine": 0.9927, "jaccard": 1.0},
{"a": "The deadline for the FHIR migration is March 3", "b": "March 3 is the deadline for the FHIR migration", "label": "dup", "kind": "order", "cosine": 0.9829, "jaccard": 1.0},
{"a": "Always restart the OCUHL7 production after a config change", "b": "After a config change, always restart the OCUHL7 production", "label": "dup", "kind": "order", "cosine": 0.9731, "jaccard": 1.0},
{"a": "The test namespace is HSTEST", "b": "HSTEST is the test namespace", "label": "dup", "kind": "order", "cosine": 0.9816, "jaccard": 1.0},
{"a": "My manager is Dana Lee", "b": "Dana Lee is my boss", "label": "dup", "kind": "rephrase", "cosine": 0.8521, "jaccard": 0.6667},
{"a": "The ADT feed retries every 5 minutes", "b": "The ADT feed does a retry every 5 minutes", "label": "dup", "kind": "rephrase", "cosine": 0.8585, "jaccard": 0.6},
{"a": "Alex Chen is on call this weekend", "b": "Alex Chen is the on-call person this weekend", "label": "dup", "kind": "rephrase", "cosine": 0.9575, "jaccard": 0.7778},
{"a": "I prefer Telegram for alerts", "b": "I like to get alerts on Telegram", "label": "dup", "kind": "rephrase", "cosine": 0.921, "jaccard": 0.3333},
{"a": "The Riverside lab feed uses port 6661", "b": "Riverside's lab feed runs on port 6661", "label": "dup", "kind": "rephrase", "cosine": 0.9677, "jaccard": 0.5},
{"a": "Northside Labs' contact is Marco Ruiz", "b": "The contact at Northside Labs is Marco Ruiz", "label": "dup", "kind": "rephrase", "cosine": 0.9803, "jaccard": 0.75},
{"a": "The FHIR migration deadline is March 3", "b": "The FHIR migration is due on March 3", "label": "dup", "kind": "rephrase", "cosine": 0.9188, "jaccard": 0.6667},
{"a": "Keep answers brief", "b": "Please keep answers brief", "label": "dup", "kind": "rephrase", "cosine": 0.4733, "jaccard": 0.75},
{"a": "The orders router sends ORM messages to PharmaLink", "b": "The orders router forwards ORM messages to PharmaLink", "label": "dup", "kind": "rephrase", "cosine": 0.9634, "jaccard": 0.7778},
{"a": "Purge Ens messages older than 30 days", "b": "Ens messages older than 30 days should be purged", "label": "dup", "kind": "rephrase", "cosine": 0.9762, "jaccard": 0.6},
{"a": "Sam Okafor owns the billing interface", "b": "The billing interface is owned by Sam Okafor", "label": "dup", "kind": "rephrase", "cosine": 0.9768, "jaccard": 0.5556},
{"a": "I work in the UTC+1 time zone", "b": "My time zone is UTC+1", "label": "dup", "kind": "rephrase", "cosine": 0.8585, "jaccard": 0.4},
{"a": "The EpicBridge partner needs ACKs within 30 seconds", "b": "EpicBridge expects ACKs within 30 seconds", "label": "dup", "kind": "rephrase", "cosine": 0.9039, "jaccard": 0.5556},
{"a": "The ADT feed retries every 5 minutes", "b": "The ADT feed retries every 15 minutes", "label": "distinct", "kind": "value", "cosine": 0.9781, "jaccard": 0.75},
{"a": "The Lab results interface uses MLLP port 6661", "b": "The Lab results interface uses MLLP port 6662", "label": "distinct", "kind": "value", "cosine": 0.997, "jaccard": 0.7778},
{"a": "Purge Ens messages older than 30 days", "b": "Purge Ens messages older than 90 days", "label": "distinct", "kind": "value", "cosine": 0.9773, "jaccard": 0.75},
{"a": "The EpicBridge partner needs ACKs within 30 seconds", "b": "The EpicBridge partner needs ACKs within 60 seconds", "label": "distinct", "kind": "value", "cosine": 0.9921, "jaccard": 0.7778},
{"a": "The orders router pool size is 2", "b": "The orders router pool size is 4", "label": "distinct", "kind": "value", "cosine": 0.9442, "jaccard": 0.75},
{"a": "Priya prefers alerts by Telegram", "b": "Priya prefers alerts by email", "label": "distinct", "kind": "value", "cosine": 0.7837, "jaccard": 0.6667},
{"a": "The PharmaLink partner sends RDE messages over SFTP", "b": "The PharmaLink partner sends RDE messages over HTTPS", "label": "distinct", "kind": "value", "cosine": 0.7806, "jaccard": 0.7778},
{"a": "The test namespace is HSTEST", "b": "The test namespace is HSDEV", "label": "distinct", "kind": "value", "cosine": 0.8832, "jaccard": 0.6667},
{"a": "The FHIR migration deadline is March 3", "b": "The FHIR migration deadline is March 13", "label": "distinct", "kind": "date", "cosine": 0.9867, "jaccard": 0.75},
{"a": "The HL7 schema upgrade is due Friday", "b": "The HL7 schema upgrade is due Monday", "label": "distinct", "kind": "date", "cosine": 0.9905, "jaccard": 0.75},
{"a": "The TLS certificate for the Riverside Clinic ADT feed expires on June 30, 2027", "b": "The TLS certificate for the Riverside Clinic ADT feed expires on June 30, 2026", "label": "distinct", "kind": "date", "cosine": 0.9992, "jaccard": 0.8571},
{"a": "Production OCUHL7 must be stopped before the Sunday patch window", "b": "Production OCUHL7 must be stopped before the Saturday patch window", "label": "distinct", "kind": "date", "cosine": 0.9791, "jaccard": 0.8182},
{"a": "Alex Chen is on call this weekend", "b": "Alex Chen is on call next weekend", "label": "distinct", "kind": "date", "cosine": 0.9909, "jaccard": 0.75},
{"a": "Alex Chen is on call this weekend", "b": "Alex Chen is not on call this weekend", "label": "distinct", "kind": "negation", "cosine": 0.945, "jaccard": 0.875},
{"a": "The ADT feed retries on timeout", "b": "The ADT feed does not retry on timeout", "label": "distinct", "kind": "negation", "cosine": 0.8818, "jaccard": 0.5556},
{"a": "I want code examples in answers", "b": "I don't want code examples in answers", "label": "distinct", "kind": "negation", "cosine": 0.8593, "jaccard": 0.75},
{"a": "The billing interface is enabled in the production", "b": "The billing interface is disabled in the production", "label": "distinct", "kind": "negation", "cosine": 0.9036, "jaccard": 0.75},
{"a": "Northside Labs accepts batch files", "b": "Northside Labs no longer accepts batch files", "label": "distinct", "kind": "negation", "cosine": 0.9102, "jaccard": 0.7143},
{"a": "Restart OCUHL7 after a config change", "b": "Never restart OCUHL7 after a config change", "label": "distinct", "kind": "negation", "cosine": 0.9744, "jaccard": 0.8571},
{"a": "The Riverside Clinic ADT feed must send ACKs back to the sender within 30 seconds of receipt", "b": "The Riverside Clinic ADT feed must not send ACKs back to the sender within 30 seconds of receipt", "label": "distinct", "kind": "negation", "cosine": 0.9737, "jaccard": 0.9412},
{"a": "My manager is Dana Lee", "b": "My manager is Dana Kim", "label": "distinct", "kind": "entity", "cosine": 0.9013, "jaccard": 0.6667},
{"a": "Marco Ruiz is the contact at Northside Labs", "b": "Marco Ruiz is the contact at Southside Labs", "label": "distinct", "kind": "entity", "cosine": 0.9172, "jaccard": 0.7778},
{"a": "Sam Okafor owns the billing interface", "b": "Sam Okafor owns the scheduling interface", "label": "distinct", "kind": "entity", "cosine": 0.7023, "jaccard": 0.7143},
{"a": "Alex Chen is on call this weekend", "b": "Jordan Chen is on call this weekend", "label": "distinct", "kind": "entity", "cosine": 0.9237, "jaccard": 0.75},
{"a": "The ADT feed from Riverside Clinic retries every 5 minutes", "b": "The ADT feed from Lakeside Clinic retries every 5 minutes", "label": "distinct", "kind": "entity", "cosine": 0.8586, "jaccard": 0.8182},
{"a": "The orders router sends ORM messages to PharmaLink", "b": "The orders router sends ORU messages to PharmaLink", "label": "distinct", "kind": "entity", "cosine": 0.9555, "jaccard": 0.7778},
{"a": "Priya Nair is the contact for the Riverside feed", "b": "Priya Nair is the contact for the Lakeside feed", "label": "distinct", "kind": "entity", "cosine": 0.8249, "jaccard": 0.7778},
{"a": "My manager is Dana Lee", "b": "My mentor is Dana Lee", "label": "distinct", "kind": "entity", "cosine": 0.7724, "jaccard": 0.6667},
{"a": "The Riverside ADT feed uses port 6661", "b": "The Riverside lab feed uses port 6661", "label": "distinct", "kind": "entity", "cosine": 0.8558, "jaccard": 0.75},
{"a": "Use the HSTEST namespace for testing", "b": "Use the HSPROD namespace for testing", "label": "distinct", "kind": "entity", "cosine": 0.8669, "jaccard": 0.7143},
{"a": "Ping Dana before restarting the production", "b": "Ping Alex before restarting the production", "label": "distinct", "kind": "entity", "cosine": 0.597, "jaccard": 0.7143},
{"a": "Before the quarterly release, the integration team at Riverside Clinic must review every HL7 routing rule change with Dana Lee", "b": "Before the quarterly release, the integration team at Riverside Clinic must review every HL7 routing rule change with Dana Kim", "label": "distinct", "kind": "entity", "cosine": 0.9729, "jaccard": 0.9},
{"a": "Dana Lee reports to Alex Chen", "b": "Alex Chen reports to Dana Lee", "label": "distinct", "kind": "entity", "cosine": 0.9929, "jaccard": 1.0},
{"a": "The Riverside feed forwards ADT messages to Lakeside", "b": "The Lakeside feed forwards ADT messages to Riverside", "label": "distinct", "kind": "entity", "cosine": 0.9923, "jaccard": 1.0},
{"a": "Alex Chen is on call this weekend, not Dana Lee", "b": "Dana Lee is on call this weekend, not Alex Chen", "label": "distinct", "kind": "entity", "cosine": 0.9957, "jaccard": 1.0},
{"a": "Retry every 5 minutes and give up after 30 minutes", "b": "Retry every 30 minutes and give up after 5 minutes", "label": "distinct", "kind": "entity", "cosine": 0.9979, "jaccard": 1.0},
{"a": "Route ORM messages to the lab, not to billing", "b": "Route ORM messages to billing, not to the lab", "label": "distinct", "kind": "entity", "cosine": 0.9846, "jaccard": 1.0},
{"a": "Stop OCUHL7 before OCUFHIR during the patch window", "b": "Stop OCUFHIR before OCUHL7 during the patch window", "label": "distinct", "kind": "entity", "cosine": 0.9937, "jaccard": 1.0},
{"a": "Priya Nair backs up Sam Okafor on the billing interface", "b": "Sam Okafor backs up Priya Nair on the billing interface", "label": "distinct", "kind": "entity", "cosine": 0.9879, "jaccard": 1.0},
{"a": "Use port 6661 for ADT and port 6662 for lab results", "b": "Use port 6662 for ADT and port 6661 for lab results", "label": "distinct", "kind": "entity", "cosine": 0.9993, "jaccard": 1.0},
{"a": "Telegram for urgent alerts, email for the daily digest", "b": "Email for urgent alerts, Telegram for the daily digest", "label": "distinct", "kind": "entity", "cosine": 0.9745, "jaccard": 1.0},
{"a": "The test namespace is HSTEST and the production namespace is HSPROD", "b": "The test namespace is HSPROD and the production namespace is HSTEST", "label": "distinct", "kind": "entity", "cosine": 0.9981, "jaccard": 1.0}
]
```
