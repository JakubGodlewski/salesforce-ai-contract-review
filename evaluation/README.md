# LLM Evaluation

This document describes the evaluation methodology used to test the **AI interpretation layer** of the Salesforce AI Contract Review project.

The main project documentation is available in the [root README](../README.md).

The purpose of this evaluation is different from traditional Apex unit testing. Unit tests verify deterministic application behavior using mocked model responses. This evaluation tests how the **real Claude integration interprets synthetic contract documents** and classifies their contents against a controlled Salesforce baseline.

> All contracts and business data used in this evaluation are synthetic.

---

## Purpose

The application uses a large language model to interpret unstructured contractual language.

That introduces behavior that cannot be fully tested with conventional unit tests.

For example, an Apex test can verify that:

```text
status = "UNKNOWN"
```

is parsed and persisted correctly.

It cannot prove that the real model will correctly decide that a missing payment term should be classified as `UNKNOWN`.

The evaluation suite therefore focuses on questions such as:

- Does the model recognize an exact match?
- Does it identify explicit differences?
- Does it distinguish missing information from conflicting information?
- Does it recognize genuinely ambiguous contract language?
- Does it return useful evidence and explanations?
- Does the complete Salesforce-to-Claude-to-Salesforce path behave correctly with real model output?

---

## Evaluation Scope

The evaluation covers the probabilistic part of the system:

```text
Synthetic Contract PDF
        +
Controlled Salesforce Baseline
        |
        v
Real Salesforce Integration
        |
        v
Anthropic Claude
        |
        v
Structured Field-Level Comparisons
        |
        v
Apex Validation
        |
        v
Deterministic Overall Result
```

The suite is intentionally small and targeted. It is designed to exercise the most important semantic categories used by the application rather than to serve as a production-grade legal benchmark.

---

## Evaluation Methodology

Each scenario follows the same process:

1. A controlled set of values is stored in Salesforce.
2. A synthetic contract PDF is attached to the related Contract.
3. The analysis is launched through the normal Salesforce user flow.
4. The selected PDF is sent to Claude together with the Salesforce comparison context.
5. Claude returns structured field-level classifications.
6. Apex validates the returned data.
7. Apex calculates the overall review result deterministically.
8. The result is persisted as `Contract_Review__c` and, where applicable, `Contract_Discrepancy__c` records.
9. Actual results are compared with the expected outcome for the scenario.

The evaluation therefore exercises the real integration path rather than calling the model separately from Salesforce.

---

## Salesforce Baseline

All four scenarios use the same Salesforce baseline.

| Field | Salesforce Value |
| --- | --- |
| Customer | Acme Sp. z o.o. |
| Amount | USD 120,000 |
| Discount | 10% |
| Payment Terms | Net 30 |
| Notice Period | 60 days |
| Contract Start | 2026-11-01 |
| Contract End | 2027-10-31 |
| Contract Term | 12 months |

The comparison fields used by the AI are:

```text
accountName
amount
discount
paymentTerms
noticePeriodDays
contractStartDate
contractEndDate
contractTermMonths
```

Keeping the Salesforce baseline constant makes the contract document the primary variable between scenarios.

---

## Classification Model

Each field is classified independently.

### MATCH

Use `MATCH` when Salesforce and the contract contain equivalent definitive values.

Example:

```text
Salesforce:
Payment Terms = Net 30

Contract:
"All invoices are payable within 30 days."

Result:
MATCH
```

---

### MISMATCH

Use `MISMATCH` when both sources establish definitive values and those values conflict.

Example:

```text
Salesforce:
Notice Period = 60 days

Contract:
"Either party may terminate the agreement with 30 days' written notice."

Result:
MISMATCH
```

---

### UNKNOWN

Use `UNKNOWN` when the contract does not provide sufficient relevant information for the field.

Example:

```text
Salesforce:
Payment Terms = Net 30

Contract:
No payment terms are stated.

Result:
UNKNOWN
```

Missing information is deliberately distinguished from a mismatch.

---

### AMBIGUOUS

Use `AMBIGUOUS` when the contract contains relevant information but does not establish one definitive value.

Example:

```text
Salesforce:
Discount = 10%

Contract:
Section 3.1: Discount = 10%
Section 3.2: Discount = 15%
No precedence rule resolves the conflict.

Result:
AMBIGUOUS
```

This category is intended for situations where relevant contract language exists but the document itself does not provide a single value that can be compared deterministically with Salesforce.

---

## Deterministic Aggregate Classification

Claude is responsible for field-level interpretation.

The overall review result is calculated by Apex:

```text
If any comparison is MISMATCH
    -> MISMATCH

Else if any comparison is UNKNOWN or AMBIGUOUS
    -> REVIEW_REQUIRED

Else
    -> MATCH
```

This rule is intentionally deterministic and order-independent.

The model's aggregate classification is not treated as the source of truth for the final Salesforce review result.

---

# Test Scenarios

## Scenario A - Full Match

**Document:** `Contract_Eval_A_Full_Match.pdf`

### Objective

Verify that Claude recognizes a contract whose relevant business terms are consistent with the Salesforce baseline.

### Contract Data

```text
Customer: Acme Sp. z o.o.
Amount: USD 120,000
Discount: 10%
Payment Terms: Net 30
Notice Period: 60 days
Contract Start: 2026-11-01
Contract End: 2027-10-31
Contract Term: 12 months
```

### Expected Result

```text
Overall Result: MATCH
Persisted Discrepancies: 0
```

All eight comparison fields should be classified as `MATCH`.

### Actual Result

```text
Overall Result: MATCH
Persisted Discrepancies: 0
```

**Result: PASS**

This scenario confirms the basic happy path and verifies that equivalent values do not create false discrepancies.

---

## Scenario B - Explicit Mismatches

**Document:** `Contract_Eval_B_Explicit_Mismatches.pdf`

### Objective

Verify that Claude identifies explicit, definitive differences between Salesforce and the contract.

### Intentional Differences

| Field | Salesforce | Contract | Expected Classification |
| --- | --- | --- | --- |
| Amount | USD 120,000 | USD 115,000 | `MISMATCH` |
| Discount | 10% | 15% | `MISMATCH` |
| Notice Period | 60 days | 30 days | `MISMATCH` |

The remaining comparison fields match the Salesforce baseline.

### Expected Result

```text
Overall Result: MISMATCH
Persisted Discrepancies: 3
```

Expected discrepancy fields:

```text
amount
discount
noticePeriodDays
```

### Actual Result

```text
Overall Result: MISMATCH
Persisted Discrepancies: 3

Fields:
amount
discount
noticePeriodDays
```

**Result: PASS**

This scenario confirms that explicit contractual differences are detected and persisted as discrepancies.

---

## Scenario C - Missing Information

**Document:** `Contract_Eval_C_Missing_Information.pdf`

### Objective

Verify that missing information is classified as `UNKNOWN` rather than `MISMATCH`.

### Contract Difference

The contract intentionally omits payment terms.

Salesforce still contains:

```text
Payment Terms: Net 30
```

The contract provides no definitive payment term to compare against that value.

### Expected Field Result

```text
Field: paymentTerms
Status: UNKNOWN
```

### Expected Overall Result

```text
Overall Result: REVIEW_REQUIRED
Persisted Discrepancies: 1
```

### Actual Field Result

```text
Field: paymentTerms
Status: UNKNOWN
```

After the deterministic aggregate logic was introduced:

```text
Overall Result: REVIEW_REQUIRED
Persisted Discrepancies: 1
```

**Final Result: PASS**

### Important Finding

This scenario exposed an architectural weakness during evaluation.

Claude correctly identified the missing payment terms as:

```text
UNKNOWN
```

but its aggregate result was inconsistent with the field-level classifications.

The field-level interpretation was useful, but the aggregate business decision was not reliable enough to delegate to the model.

This directly led to an architectural change:

```text
Before

Claude
    -> field classifications
    -> overall classification


After

Claude
    -> field classifications

Apex
    -> validates classifications
    -> calculates overall result
```

The final Salesforce status is now derived deterministically from the individual comparisons.

This was one of the most important findings of the evaluation.

---

## Scenario D - Conflicting Terms

**Document:** `Contract_Eval_D_Conflicting_Terms.pdf`

### Objective

Verify that Claude can distinguish conflicting contractual provisions from a straightforward mismatch.

### Contract Structure

The synthetic contract contains two definitive but conflicting discount provisions:

```text
Section 3.1:
Discount = 10%

Section 3.2:
Discount = 15%

Section 3.3:
No precedence rule resolves the conflict.
```

Salesforce contains:

```text
Discount = 10%
```

Although one clause matches Salesforce, the contract as a whole does not establish a single definitive discount.

### Expected Field Result

```text
Field: discount
Status: AMBIGUOUS
```

### Expected Overall Result

```text
Overall Result: REVIEW_REQUIRED
Persisted Discrepancies: 1
```

### Actual Result

```text
Field: discount
Status: AMBIGUOUS

Overall Result: REVIEW_REQUIRED
Persisted Discrepancies: 1
```

**Result: PASS**

This scenario verifies that the classification model can represent uncertainty originating from the contract itself rather than forcing every case into `MATCH` or `MISMATCH`.

---

## Final Regression Results

After the evaluation-driven changes, all four scenarios passed.

| Scenario | Expected Overall Result | Expected Discrepancies | Final Result |
| --- | --- | ---: | --- |
| A - Full Match | `MATCH` | 0 | PASS |
| B - Explicit Mismatches | `MISMATCH` | 3 | PASS |
| C - Missing Information | `REVIEW_REQUIRED` | 1 (`UNKNOWN`) | PASS |
| D - Conflicting Terms | `REVIEW_REQUIRED` | 1 (`AMBIGUOUS`) | PASS |

The suite exercises all four field-level classifications:

```text
MATCH
MISMATCH
UNKNOWN
AMBIGUOUS
```

and all three application-level outcomes:

```text
MATCH
MISMATCH
REVIEW_REQUIRED
```

---

## Key Findings

### 1. Field-Level Interpretation and Aggregate Decisions Are Different Problems

The model can provide useful semantic interpretation at the field level without being the appropriate authority for the final business state.

Scenario C demonstrated this directly.

The resulting architecture deliberately assigns these responsibilities to different layers:

```text
Claude
    -> semantic interpretation

Apex
    -> validation
    -> deterministic aggregation
    -> persistence
```

---

### 2. Missing Information Must Not Be Treated as a Mismatch

A contract that does not mention a field is materially different from a contract that explicitly contains a conflicting value.

The `UNKNOWN` classification preserves this distinction.

Without it, missing information could create misleading discrepancy results.

---

### 3. Contractual Ambiguity Requires Its Own State

Some documents contain relevant language without establishing one definitive value.

Forcing these cases into `MATCH` or `MISMATCH` would lose important information.

The `AMBIGUOUS` state allows the system to route these cases to human review.

---

### 4. Evaluation Should Influence Architecture

The purpose of the evaluation was not only to measure whether the model produced the expected labels.

The evaluation identified a system-design weakness and resulted in moving the aggregate decision into deterministic Apex logic.

This is an example of evaluation being used as part of application engineering rather than as a standalone model demo.

---

## Improvements Introduced During Evaluation

The evaluation process resulted in several design refinements:

- explicit distinction between `MATCH`, `MISMATCH`, `UNKNOWN`, and `AMBIGUOUS`,
- deterministic calculation of the overall result in Apex,
- `REVIEW_REQUIRED` as an application-level state for incomplete or ambiguous information,
- validation of model output before persistence,
- regression scenarios covering all semantic classifications,
- separation between deterministic unit tests and live-model evaluation.

These changes reduce the amount of business authority delegated to the LLM while preserving its value for interpreting unstructured documents.

---

## Unit Tests vs LLM Evaluation

The two testing layers serve different purposes.

### Apex Unit Tests

Apex tests verify deterministic software behavior.

They cover areas such as:

```text
Salesforce data retrieval
Salesforce File handling
request construction
HTTP callout handling
JSON parsing
response validation
deterministic aggregation
persistence
security behavior
error handling
```

HTTP responses are mocked using `HttpCalloutMock`.

This makes the tests repeatable and independent of the external AI service.

### LLM Evaluation

The evaluation suite exercises the real model and focuses on:

```text
semantic interpretation
contract term extraction
missing information
explicit disagreement
conflicting provisions
field-level classification
```

A mocked response cannot demonstrate that Claude will correctly interpret a real document.

Likewise, a successful model evaluation cannot prove that Apex persistence, permissions, error handling, or validation are implemented correctly.

Both testing layers are therefore required.

---

## Synthetic Test Documents

The four evaluation PDFs are stored in:

```text
evaluation/synthetic-contracts/
```

Files:

```text
Contract_Eval_A_Full_Match.pdf
Contract_Eval_B_Explicit_Mismatches.pdf
Contract_Eval_C_Missing_Information.pdf
Contract_Eval_D_Conflicting_Terms.pdf
```

All documents were created specifically for this proof of concept.

They contain no real customer contracts, confidential information, or production business data.

---

## Reproducing the Evaluation

To reproduce the evaluation:

1. Create the Salesforce baseline described in this document.
2. Associate the Opportunity with a Contract.
3. Upload the four synthetic PDFs to the Contract.
4. Ensure the Anthropic External Credential is configured.
5. Run **Analyze Contract with AI** separately for each document.
6. Compare the persisted review and discrepancy records with the expected results above.

Because this evaluation uses a live language model, exact explanatory wording and confidence values may vary between executions.

The important regression targets are the semantic classifications and deterministic application-level outcomes.

---

## Evaluation Limitations

This evaluation is intentionally limited in scope.

The current suite contains four synthetic English-language contracts and a single controlled Salesforce baseline.

It does not establish production-level accuracy across:

- different contract types,
- large or highly complex legal documents,
- scanned or low-quality documents,
- multilingual contracts,
- unusual formatting,
- tables and appendices,
- conflicting definitions across long documents,
- jurisdiction-specific legal interpretation,
- adversarial document content,
- broader real-world contract distributions.

The four scenarios are therefore best understood as a targeted regression suite for this proof of concept, not as a general benchmark of legal-document understanding.

A production implementation would require a substantially larger and representative evaluation dataset, defined acceptance criteria, repeated regression runs, model-version testing, and appropriate human/legal review.

---

## Evaluation Principle

The central design principle established by this evaluation is:

> **Use the LLM for interpretation, not for deterministic business authority.**

Claude interprets the document.

Salesforce validates the output, applies deterministic rules, controls access, and persists the resulting business state.

That boundary is the primary architectural outcome of the evaluation.
