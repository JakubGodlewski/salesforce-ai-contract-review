# Salesforce AI Contract Review

A Salesforce proof of concept that uses **Anthropic Claude** to review
contract PDFs and compare contractual terms with structured Salesforce
data.

The solution combines **Apex, Lightning Web Components, Flow, Salesforce
Files, Named Credentials, External Credentials, Custom Metadata, and the
Anthropic Messages API** to demonstrate an end-to-end GenAI use case
implemented natively on the Salesforce Platform.

> **Project status:** Proof of Concept / Portfolio Project\
> All contract examples and evaluation data are synthetic.

------------------------------------------------------------------------

## Business Problem

Commercial contract data often exists in two places:

-   structured CRM fields in Salesforce,
-   unstructured legal documents stored as PDF files.

Differences between these sources can be difficult to identify manually.

For example, Salesforce may contain:

-   Contract Value: **USD 120,000**
-   Discount: **10%**
-   Payment Terms: **Net 30**
-   Notice Period: **60 days**

while the contract document may contain different, missing, or ambiguous
terms.

This project demonstrates how an AI-assisted validation process can
compare both sources and surface discrepancies directly in Salesforce.

------------------------------------------------------------------------

## Solution Overview

A Salesforce user starts the analysis from an **Opportunity**.

The application:

1.  Retrieves structured data from the Opportunity and its related
    Contract.
2.  Finds PDF files associated with the Contract.
3.  Allows the user to select the exact PDF version to analyze.
4.  Sends the PDF and structured Salesforce data to Claude.
5.  Receives a structured JSON analysis.
6.  Validates the AI response in Apex.
7.  Deterministically calculates the overall review result.
8.  Persists the review and detected discrepancies in Salesforce.
9.  Displays the latest analysis directly on the Opportunity record.

The LLM is responsible for interpreting unstructured contract language,
while Salesforce remains responsible for validation, deterministic
business rules, persistence, security, and user interaction.

------------------------------------------------------------------------

## Demo

The latest AI review is displayed directly on the Opportunity record.

![AI Contract Review - Review
Required](docs/screenshots/opportunity-review-required.png)

In this example, the contract does not specify the payment terms stored
in Salesforce. The field is classified as `UNKNOWN`, which results in
the deterministic overall status `REVIEW_REQUIRED`.

The component also supports a clean match state:

![AI Contract Review - Match](docs/screenshots/opportunity-match.png)

------------------------------------------------------------------------

## Architecture

![Architecture](docs/architecture.png)

``` text
Opportunity
    |
    +-- Structured commercial data
    |
    v
Contract
    |
    +-- Start Date / End Date / Contract Term
    |
    v
Salesforce Files / ContentVersion
    |
    v
Screen Flow + Contract PDF Selector LWC
    |
    v
ContractAnalysisAction
    |
    v
ContractAnalysisService
    |
    +-- ContractContextService
    +-- ContractFileService
    +-- ClaudeClient
    |
    v
Named Credential / External Credential
    |
    v
Anthropic Claude Messages API
    |
    v
Structured JSON Response
    |
    v
Apex Validation + Deterministic Aggregation
    |
    v
Contract_Review__c
    |
    +-- Contract_Discrepancy__c
    |
    v
Opportunity LWC / Reporting
```

------------------------------------------------------------------------

## Technology Stack

  Area             Technology
  ---------------- ----------------------------------------
  CRM Platform     Salesforce
  Backend          Apex
  Frontend         Lightning Web Components
  Orchestration    Salesforce Flow
  File Storage     Salesforce Files / ContentVersion
  AI Provider      Anthropic Claude
  Integration      REST / Anthropic Messages API
  Authentication   Named Credential + External Credential
  Configuration    Custom Metadata Types
  Persistence      Salesforce Custom Objects
  Security         Sharing + Permission Sets + CRUD/FLS
  Testing          Apex Tests + HttpCalloutMock
  Source Control   Git / Salesforce DX

------------------------------------------------------------------------

## Data Model

### Opportunity

The Opportunity contains the structured commercial terms used for
comparison.

Relevant fields include:

-   `Account`
-   `Amount`
-   `Discount__c`
-   `Payment_Terms__c`
-   `Notice_Period_Days__c`
-   `ContractId`

### Contract

The standard Salesforce Contract object provides:

-   `StartDate`
-   `EndDate`
-   `ContractTerm`

Contract PDFs are stored using Salesforce Files.

### Contract Review

`Contract_Review__c` represents one AI analysis execution.

It stores information such as:

-   related Opportunity,
-   related Contract,
-   analysis date,
-   model,
-   processing status,
-   overall result,
-   discrepancy count,
-   summary.

### Contract Discrepancy

`Contract_Discrepancy__c` stores individual issues identified during a
review.

Each discrepancy can contain:

-   field,
-   Salesforce source,
-   Salesforce value,
-   contract value,
-   status,
-   severity,
-   confidence,
-   contract evidence,
-   explanation.

Only comparisons requiring attention are persisted as discrepancy
records.

------------------------------------------------------------------------

## AI Classification Model

Each compared field receives one of four statuses:

  -----------------------------------------------------------------------
  Status                              Meaning
  ----------------------------------- -----------------------------------
  `MATCH`                             Salesforce and the contract contain
                                      equivalent definitive values

  `MISMATCH`                          Salesforce and the contract contain
                                      conflicting definitive values

  `UNKNOWN`                           The contract does not contain
                                      relevant information

  `AMBIGUOUS`                         Relevant contract information
                                      exists but does not establish one
                                      definitive value
  -----------------------------------------------------------------------

This distinction is important because missing or ambiguous information
should not automatically be interpreted as a mismatch.

For example:

``` text
Salesforce Discount: 10%

Contract:
"A discount of up to 15% may be applied subject to management approval."

Result:
AMBIGUOUS
```

The contract discusses the discount but does not establish one
definitive contractual value.

------------------------------------------------------------------------

## Deterministic Overall Result

The LLM does **not** have final authority over the overall review
result.

Claude classifies individual fields, while Apex calculates the final
result deterministically:

``` text
If any comparison is MISMATCH
    -> MISMATCH

Else if any comparison is UNKNOWN or AMBIGUOUS
    -> REVIEW_REQUIRED

Else
    -> MATCH
```

This prevents inconsistent aggregate classifications from becoming the
system result.

It also keeps an important business decision inside deterministic
application logic rather than delegating it entirely to the language
model.

------------------------------------------------------------------------

## Prompt Configuration

AI configuration is stored in the `AI_Prompt_Config__mdt` Custom
Metadata Type instead of being hard-coded in Apex.

The configuration includes:

-   active status,
-   Claude model,
-   maximum output tokens,
-   prompt,
-   prompt version.

The current configuration uses:

``` text
claude-sonnet-4-6
```

This allows prompt behavior and model configuration to evolve
independently from the integration code.

------------------------------------------------------------------------

## Structured AI Output

Claude is instructed to return structured JSON rather than free-form
text.

Example comparison:

``` json
{
  "field": "discount",
  "salesforceSource": "Opportunity",
  "salesforceValue": "10%",
  "contractValue": "15%",
  "status": "MISMATCH",
  "severity": "MEDIUM",
  "confidence": 0.99,
  "contractEvidence": "The Customer receives a discount of 15%.",
  "explanation": "The contract establishes a 15% discount while Salesforce records 10%."
}
```

The response is deserialized into strongly typed Apex DTOs before it can
be used by the rest of the application.

------------------------------------------------------------------------

## AI Response Validation

LLM output is treated as **untrusted input**.

Before persistence, Apex validates the returned structure and values,
including:

-   required comparison data,
-   allowed comparison statuses,
-   allowed severity values,
-   confidence range between `0` and `1`,
-   valid response structure.

Malformed or unexpected AI responses are rejected rather than silently
persisted.

``` text
LLM Output
    |
    v
Untrusted Data
    |
    v
Apex Validation
    |
    v
Deterministic Business Rules
    |
    v
Salesforce Persistence
```

------------------------------------------------------------------------

## Salesforce User Experience

### Analyze Contract Flow

The **Analyze Contract with AI** Screen Flow provides the main user
interaction.

The user selects the exact contract PDF version that should be analyzed:

![Contract PDF Selection](docs/screenshots/contract-pdf-selection.png)

The selector is implemented as a custom Flow Screen LWC and works with
Salesforce `ContentVersion` records.

After the API analysis completes, the Flow displays the overall result,
discrepancy count, and AI-generated summary:

![Contract Analysis Result](docs/screenshots/analysis-result-match.png)

The Flow also contains a dedicated fault path for analysis failures.

### Latest Contract Review

The `contractReviewPanel` Lightning Web Component displays the latest
persisted analysis directly on the Opportunity.

It includes:

-   overall result,
-   analysis date,
-   model,
-   discrepancy count,
-   AI summary,
-   field-level discrepancies,
-   Salesforce and contract values,
-   confidence,
-   contract evidence,
-   explanation,
-   navigation to the persisted review record.

This allows the result to remain visible after the analysis Flow has
finished.

------------------------------------------------------------------------

## Persistence

Each analysis creates a `Contract_Review__c` record.

Only comparisons requiring attention are persisted as
`Contract_Discrepancy__c` child records.

This creates an auditable Salesforce-side history of contract analyses
rather than treating the AI response as transient UI output.

The related Contract can therefore expose previous review executions
alongside the source PDF files.

Additional screenshots are available in:

``` text
docs/screenshots/contract-files-and-reviews.png
docs/screenshots/contract-review-record.png
```

------------------------------------------------------------------------

## Security Design

The project follows Salesforce's layered security model.

### Record-Level Security

Core services use `with sharing`, keeping Salesforce record sharing
rules in the execution model.

The AI integration therefore does not intentionally provide a mechanism
for bypassing record-level access to the underlying Salesforce records.

### CRUD and Field-Level Security

Dedicated permission configuration grants the access required by the
application.

The intended application user can:

-   read the required Opportunity data,
-   read the required Account data,
-   read the related Contract,
-   access the required Salesforce Files,
-   execute the analysis Flow,
-   use the configured External Credential principal,
-   create and read Contract Reviews,
-   create and read Contract Discrepancies.

The application does not require users to modify the source commercial
data as part of the analysis process.

### API Credentials

The Anthropic API key is **not stored in Apex, Flow, Custom Metadata, or
source control**.

Authentication uses:

``` text
Named Credential
    |
    v
External Credential
    |
    v
Named Principal
    |
    v
Secret configured in Salesforce
```

The repository contains the credential configuration but not the actual
API secret.

------------------------------------------------------------------------

## Error Handling

The integration handles both Salesforce-side and external API failures.

Examples include:

-   missing Opportunity Id,
-   missing related Contract,
-   unavailable contract PDF,
-   invalid PDF selection,
-   Anthropic authentication failures,
-   API rate limiting,
-   server errors,
-   malformed Anthropic responses,
-   malformed model JSON,
-   incomplete or truncated model output,
-   invalid status values,
-   invalid severity values,
-   invalid confidence values.

Errors are surfaced through the application flow rather than silently
creating incomplete analysis records.

------------------------------------------------------------------------

## Testing Strategy

The project contains Apex tests covering the major application layers.

### Integration Client

Tests cover:

-   request construction,
-   Named Credential endpoint usage,
-   PDF payload construction,
-   successful responses,
-   HTTP error responses,
-   malformed Anthropic responses,
-   malformed model JSON,
-   incomplete output.

### Contract Context

Tests cover:

-   Opportunity data retrieval,
-   Contract data retrieval,
-   missing related records,
-   expected field mapping.

### Salesforce Files

Tests cover:

-   contract file discovery,
-   PDF selection,
-   `ContentVersion` handling,
-   invalid file scenarios.

### Analysis Service

Tests cover:

-   response validation,
-   supported statuses,
-   supported severities,
-   confidence validation,
-   deterministic overall-status calculation.

### Persistence

Tests cover:

-   Contract Review creation,
-   discrepancy creation,
-   exclusion of `MATCH` results from discrepancy records,
-   relationship integrity.

### Security

Tests include execution under restricted users to verify record-level
access behavior.

HTTP integrations are isolated using `HttpCalloutMock`, allowing the
unit test suite to execute without calling the real Anthropic API.

------------------------------------------------------------------------

## LLM Evaluation

Traditional unit tests validate deterministic application behavior, but
they cannot prove that a language model interprets contract language
correctly.

The project therefore also uses a controlled **LLM evaluation suite**
with synthetic contracts.

### Evaluation Baseline

The Salesforce baseline used during evaluation is:

``` text
Customer: Acme Sp. z o.o.
Amount: USD 120,000
Discount: 10%
Payment Terms: Net 30
Notice Period: 60 days
Contract Start: 2026-11-01
Contract End: 2027-10-31
Contract Term: 12 months
```

### Evaluation Scenarios

  -------------------------------------------------------------------------
  Scenario          Expected Result     Expected          Result
                                        Discrepancy       
  ----------------- ------------------- ----------------- -----------------
  A - Full Match    `MATCH`             0                 PASS

  B - Explicit      `MISMATCH`          Amount, Discount, PASS
  Mismatches                            Notice Period     

  C - Missing       `REVIEW_REQUIRED`   Payment Terms -\> PASS
  Information                           `UNKNOWN`         

  D - Conflicting   `REVIEW_REQUIRED`   Discount -\>      PASS
  Terms                                 `AMBIGUOUS`       
  -------------------------------------------------------------------------

### Scenario A - Full Match

All contractual values match the Salesforce baseline.

Expected:

``` text
MATCH
0 discrepancies
```

### Scenario B - Explicit Mismatches

The synthetic contract contains:

``` text
Amount: USD 115,000
Discount: 15%
Notice Period: 30 days
```

while the remaining values match Salesforce.

Expected:

``` text
MISMATCH
3 discrepancies
```

### Scenario C - Missing Information

The contract matches the Salesforce baseline but contains no payment
terms.

Expected:

``` text
REVIEW_REQUIRED

paymentTerms -> UNKNOWN
```

This scenario exposed an important architecture issue during evaluation.

Claude correctly classified the missing payment term as `UNKNOWN`, but
the model-level aggregate result was inconsistent with the field-level
classifications.

The overall result was therefore moved to deterministic Apex logic
instead of trusting the LLM's aggregate decision.

### Scenario D - Conflicting Terms

The contract contains conflicting definitive provisions:

``` text
Section 3.1: Discount = 10%
Section 3.2: Discount = 15%
```

with no precedence rule establishing which provision controls.

Expected:

``` text
REVIEW_REQUIRED

discount -> AMBIGUOUS
```

All four final evaluation scenarios passed after the architecture and
prompt behavior were refined.

Detailed evaluation methodology and synthetic test documents are
maintained under:

**[`evaluation/README.md`](evaluation/README.md)**

------------------------------------------------------------------------

## Unit Tests vs LLM Evaluation

The project deliberately separates two types of testing.

### Apex Unit Tests

Verify deterministic software behavior:

``` text
Apex logic
API request construction
JSON parsing
validation
persistence
security behavior
error handling
```

### LLM Evaluation

Verifies probabilistic model behavior:

``` text
contract interpretation
missing information
conflicting provisions
semantic comparison
classification quality
```

A mocked HTTP unit test cannot prove that the real model will correctly
understand a contract.

Conversely, a successful LLM evaluation does not replace deterministic
Apex unit tests.

Both layers are therefore required.

------------------------------------------------------------------------

## Reporting and Dashboard

Persisted review data can be analyzed through native Salesforce
reporting.

The reporting model is designed around:

-   reviews by overall result,
-   discrepancies by field,
-   discrepancies by severity.

The dashboard provides an aggregated view of AI contract-review
activity.

![AI Contract Review Dashboard](docs/screenshots/dashboard.png)

------------------------------------------------------------------------

## What the LLM Does - and Does Not Do

The architecture deliberately limits the responsibilities of the
language model.

### Claude is responsible for

-   reading unstructured contract content,
-   extracting relevant contractual information,
-   interpreting whether language is definitive or ambiguous,
-   comparing contract information with provided Salesforce values,
-   producing evidence and explanations,
-   returning structured classifications.

### Salesforce is responsible for

-   record access,
-   structured data retrieval,
-   file access,
-   authentication,
-   response validation,
-   deterministic aggregation,
-   persistence,
-   authorization,
-   user interaction,
-   reporting.

This separation keeps probabilistic document interpretation in the AI
layer while retaining deterministic business controls inside Salesforce.

------------------------------------------------------------------------

## Repository Structure

``` text
salesforce-ai-contract-review/
|
|-- README.md
|
|-- docs/
|   |-- architecture.png
|   `-- screenshots/
|       |-- opportunity-review-required.png
|       |-- opportunity-match.png
|       |-- contract-pdf-selection.png
|       |-- analysis-result-match.png
|       |-- contract-files-and-reviews.png
|       |-- contract-review-record.png
|       `-- dashboard.png
|
|-- evaluation/
|   |-- README.md
|   `-- synthetic-contracts/
|       |-- Contract_Eval_A_Full_Match.pdf
|       |-- Contract_Eval_B_Explicit_Mismatches.pdf
|       |-- Contract_Eval_C_Missing_Information.pdf
|       `-- Contract_Eval_D_Conflicting_Terms.pdf
|
|-- force-app/
|   `-- main/
|       `-- default/
|           |-- classes/
|           |-- customMetadata/
|           |-- externalCredentials/
|           |-- flexipages/
|           |-- flows/
|           |-- lwc/
|           |-- namedCredentials/
|           |-- objects/
|           |-- permissionsets/
|           |-- permissionsetgroups/
|           |-- quickActions/
|           |-- reports/
|           `-- dashboards/
|
|-- config/
|-- scripts/
|-- package.json
`-- sfdx-project.json
```

------------------------------------------------------------------------

## Setup

### Prerequisites

You need:

-   Salesforce CLI,
-   access to a Salesforce org,
-   an Anthropic API key,
-   appropriate permissions to deploy the Salesforce metadata.

### 1. Authenticate to Salesforce

``` bash
sf org login web --alias contract-review
```

### 2. Deploy the Metadata

``` bash
sf project deploy start \
  --source-dir force-app \
  --target-org contract-review
```

### 3. Configure the Anthropic Credential

The repository intentionally does **not** contain an Anthropic API key.

After deployment:

1.  Open **Setup -\> Named Credentials**.
2.  Locate the Anthropic External Credential.
3.  Configure the Named Principal authentication parameter with a valid
    Anthropic API key.
4.  Ensure the application user has access to the External Credential
    principal.

### 4. Assign Application Permissions

Assign the relevant permission set or permission set group to the user.

### 5. Prepare Test Data

Create an Opportunity and related Contract containing the required
comparison fields.

Upload at least one PDF to the related Contract using Salesforce Files.

### 6. Run the Analysis

Open the Opportunity and launch **Analyze Contract with AI**.

Select the contract PDF and start the analysis.

------------------------------------------------------------------------

## Running Apex Tests

Run the Apex test suite using Salesforce CLI:

``` bash
sf apex run test \
  --test-level RunLocalTests \
  --target-org contract-review \
  --wait 20 \
  --code-coverage
```

The Apex unit tests use mocked HTTP responses and do not require live
Anthropic API calls.

------------------------------------------------------------------------

## Production Considerations

This project is intentionally a proof of concept.

A production implementation would require additional decisions depending
on organizational requirements, including:

-   formal legal and compliance review,
-   data residency requirements,
-   AI provider data-processing policies,
-   contract confidentiality requirements,
-   observability and operational monitoring,
-   API usage and cost monitoring,
-   retry and rate-limit strategies,
-   asynchronous processing for larger workloads,
-   prompt and model lifecycle management,
-   expanded evaluation datasets,
-   regression testing across model versions,
-   human review and escalation workflows,
-   audit and retention policies.

AI-generated results should be treated as decision support rather than a
substitute for legal review.

------------------------------------------------------------------------

## Design Principles

**AI output is untrusted input.**\
Model responses are validated before they affect Salesforce data.

**Use AI where deterministic code is insufficient.**\
Claude interprets unstructured language; Apex handles deterministic
business logic.

**Do not confuse missing information with disagreement.**\
`UNKNOWN`, `AMBIGUOUS`, and `MISMATCH` represent different business
situations.

**Keep secrets outside source code.**\
API authentication is handled through Salesforce credentials.

**Respect Salesforce security.**\
The AI integration should not become a mechanism for bypassing record
access.

**Make AI behavior testable.**\
Traditional unit tests are complemented by document-level LLM
evaluation.

**Keep aggregate business decisions deterministic.**\
The LLM interprets fields; Apex determines the final review status.

------------------------------------------------------------------------

## Disclaimer

This repository is a technical proof of concept created for
demonstration and learning purposes.

All contract examples and evaluation data are synthetic.

The project is not a legal review system, and AI-generated analysis
should not be treated as legal advice.

------------------------------------------------------------------------

## Author

**Jakub Godlewski**

Salesforce Developer / Technical Lead

Built as a hands-on exploration of integrating Generative AI with
Salesforce using native platform architecture, security controls,
deterministic guardrails, and LLM evaluation.