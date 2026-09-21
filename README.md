# Salesforce AI Contract Review

A Salesforce proof of concept that uses **Anthropic Claude** to review
contract PDFs and compare contractual terms with structured Salesforce
data.

The solution combines **Apex, Lightning Web Components, Flow, Salesforce
Files, Named Credentials, Custom Metadata, and the Anthropic Messages
API** to demonstrate an end-to-end GenAI use case implemented natively
on the Salesforce Platform.

> **Project status:** Proof of Concept / Portfolio Project\
> All example contracts and evaluation data are synthetic.

------------------------------------------------------------------------

## Business Problem

Commercial contract data often exists in two places:

-   structured CRM fields in Salesforce,
-   unstructured legal documents stored as PDF files.

Differences between these sources can be difficult to identify manually.
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

## Architecture

![Architecture](docs/architecture.png)

``` text
Opportunity
    |
    +-- Structured commercial data
    v
Contract
    |
    +-- Start Date / End Date / Contract Term
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
comparison:

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

`Contract_Review__c` represents one AI analysis execution and stores the
related Opportunity and Contract, analysis date, model, processing
status, overall result, discrepancy count, and summary.

### Contract Discrepancy

`Contract_Discrepancy__c` stores individual issues identified during a
review, including the field, Salesforce source/value, contract value,
status, severity, confidence, contract evidence, and explanation.

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
                                      sufficient relevant information

  `AMBIGUOUS`                         Relevant information exists, but
                                      the contract does not establish one
                                      definitive value
  -----------------------------------------------------------------------

This distinction prevents missing or ambiguous information from
automatically being treated as a mismatch.

------------------------------------------------------------------------

## Deterministic Overall Result

The LLM does **not** have final authority over the overall review
result. Claude interprets individual contract terms, but Apex calculates
the final result deterministically:

``` text
If any comparison is MISMATCH
    -> MISMATCH

Else if any comparison is UNKNOWN or AMBIGUOUS
    -> REVIEW_REQUIRED

Else
    -> MATCH
```

This keeps an important business decision inside deterministic
application logic rather than delegating it entirely to the language
model.

------------------------------------------------------------------------

## Prompt Configuration

AI configuration is stored in the `AI_Prompt_Config__mdt` Custom
Metadata Type rather than hard-coded in Apex.

The configuration includes the active status, Claude model, maximum
output tokens, prompt, and prompt version.

The current configuration uses:

``` text
claude-sonnet-4-6
```

------------------------------------------------------------------------

## Structured AI Output

Claude returns structured JSON rather than free-form text.

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

LLM output is treated as **untrusted input**. Before persistence, Apex
validates the returned structure and values, including:

-   allowed comparison fields,
-   allowed comparison statuses,
-   allowed severity values,
-   confidence range,
-   expected response structure.

Malformed or unexpected responses are rejected rather than silently
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

## User Experience

### Analyze Contract Flow

The **Analyze Contract with AI** Screen Flow receives the Opportunity
Id, confirms the analysis, loads available contract PDFs, allows the
user to select a PDF, invokes the Apex analysis action, and handles
failures through a dedicated error path.

A custom Flow Screen LWC is used to select the exact `ContentVersion` to
analyze.

![Analyze Contract Flow](docs/screenshots/analyze-contract-flow.png)

### Latest Contract Review

The `contractReviewPanel` Lightning Web Component displays the latest
analysis directly on the Opportunity, including the overall result,
analysis date, model, discrepancy count, AI summary, field-level
discrepancies, Salesforce and contract values, confidence, contract
evidence, and explanation.

![Latest Contract Review](docs/screenshots/contract-review-panel.png)

------------------------------------------------------------------------

## Security Design

The project follows Salesforce's layered security model.

Core services respect Salesforce record sharing, so the AI integration
does not become a mechanism for bypassing access to business records.

Dedicated permission configuration grants only the access required by
the application. The intended user can read the required Opportunity,
Account, Contract, and Salesforce Files data; execute the analysis Flow;
use the configured External Credential principal; and create/read
Contract Reviews and Contract Discrepancies.

The Anthropic API key is **not stored in Apex, Flow, Custom Metadata, or
source control**.

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

The repository contains the credential metadata but not the actual API
secret.

------------------------------------------------------------------------

## Error Handling

The application handles scenarios including:

-   missing Opportunity,
-   missing related Contract,
-   missing or unavailable PDF,
-   invalid PDF selection,
-   Anthropic authentication errors,
-   API rate limiting and server errors,
-   malformed API responses,
-   malformed model JSON,
-   truncated model output,
-   unsupported status values,
-   unsupported severity values,
-   invalid confidence values.

Flow fault handling provides a user-facing error path instead of
silently creating incomplete review records.

------------------------------------------------------------------------

## Testing Strategy

The Apex test suite covers:

-   contract context retrieval,
-   Salesforce File retrieval,
-   request payload construction,
-   Anthropic HTTP callouts,
-   successful and failed HTTP responses,
-   malformed responses and model JSON,
-   truncated output,
-   field/status/severity/confidence validation,
-   deterministic overall-result calculation,
-   review and discrepancy persistence,
-   restricted-user record access.

Anthropic HTTP responses are mocked using `HttpCalloutMock`, keeping
unit tests deterministic and independent of external API availability.

------------------------------------------------------------------------

## LLM Evaluation

Traditional unit tests validate application behavior, but they cannot
prove that a language model interprets contract language correctly.

The project therefore also uses a controlled **LLM evaluation suite**
with synthetic contracts executed against the real Anthropic API.

  Scenario              Expected Result                   Final Result
  --------------------- --------------------------------- --------------
  Full Match            `MATCH` / 0 discrepancies         PASS
  Explicit Mismatches   `MISMATCH` / 3 discrepancies      PASS
  Missing Information   `REVIEW_REQUIRED` / `UNKNOWN`     PASS
  Conflicting Terms     `REVIEW_REQUIRED` / `AMBIGUOUS`   PASS

The evaluation exposed an important design issue: aggregate business
decisions should not depend on the LLM. During testing, the model
correctly classified missing field information as `UNKNOWN` but produced
an inconsistent overall classification. Overall status calculation was
therefore moved to deterministic Apex logic.

Detailed methodology, scenarios, findings, and synthetic test documents
are documented separately in
**[`evaluation/README.md`](evaluation/README.md)**.

------------------------------------------------------------------------

## Reporting and Dashboard

Persisted review data can be analyzed through native Salesforce
reporting, including:

-   reviews by overall result,
-   discrepancies by field,
-   discrepancies by severity.

![AI Contract Review Dashboard](docs/screenshots/dashboard.png)

------------------------------------------------------------------------

## What the LLM Does --- and Does Not Do

### Claude is responsible for

-   reading unstructured contract content,
-   extracting relevant contractual information,
-   interpreting whether contract language is definitive or ambiguous,
-   comparing contract information with provided Salesforce values,
-   producing evidence and explanations,
-   returning structured classifications.

### Salesforce is responsible for

-   record and file access,
-   data retrieval,
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
|-- docs/
|   |-- architecture.png
|   `-- screenshots/
|       |-- analyze-contract-flow.png
|       |-- contract-review-panel.png
|       `-- dashboard.png
|-- evaluation/
|   |-- README.md
|   `-- synthetic-contracts/
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
|           `-- quickActions/
|-- config/
|-- scripts/
|-- package.json
`-- sfdx-project.json
```

------------------------------------------------------------------------

## Setup

### Prerequisites

-   Salesforce CLI
-   access to a Salesforce org
-   an Anthropic API key
-   permissions to deploy Salesforce metadata

### 1. Authenticate to Salesforce

``` bash
sf org login web --alias contract-review
```

### 2. Deploy the Metadata

``` bash
sf project deploy start --source-dir force-app --target-org contract-review
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
comparison fields, then upload at least one PDF to the Contract using
Salesforce Files.

### 6. Run the Analysis

Open the Opportunity, launch **Analyze Contract with AI**, select a
contract PDF, and start the analysis.

------------------------------------------------------------------------

## Running Apex Tests

``` bash
sf apex run test   --test-level RunLocalTests   --target-org contract-review   --wait 20   --code-coverage
```

The Apex unit tests use mocked HTTP responses and do not require live
Anthropic API calls.

------------------------------------------------------------------------

## Production Considerations

This project is intentionally a proof of concept. A production
implementation would require additional decisions depending on
organizational requirements, including:

-   legal and compliance review,
-   data residency and confidentiality requirements,
-   AI provider data-processing policies,
-   observability and operational monitoring,
-   API usage and cost monitoring,
-   retry and rate-limit strategies,
-   asynchronous processing for larger workloads,
-   prompt and model lifecycle management,
-   prompt version auditing,
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