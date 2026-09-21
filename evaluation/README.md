# Salesforce AI Contract Review

A Salesforce proof of concept that uses **Anthropic Claude** to review contract PDFs and compare contractual terms with structured Salesforce data.

The solution combines **Apex, Lightning Web Components, Salesforce Flow, Salesforce Files, Named Credentials, External Credentials, Custom Metadata, and the Anthropic Messages API** to demonstrate an end-to-end GenAI use case implemented natively on the Salesforce Platform.

> **Project status:** Proof of Concept / Portfolio Project  
> All contract examples and evaluation data are synthetic.

---

## Business Problem

Commercial contract data often exists in two places:

- structured CRM fields in Salesforce,
- unstructured legal documents stored as PDF files.

Differences between these sources can be difficult to identify manually.

For example, Salesforce may contain a contract value, discount, payment terms, notice period, and contract dates while the signed document contains different, missing, or ambiguous terms.

This project demonstrates how an AI-assisted validation process can compare both sources and surface discrepancies directly in Salesforce.

---

## Solution Overview

A Salesforce user starts the analysis from an **Opportunity**.

The application:

1. Retrieves structured data from the Opportunity and its related Contract.
2. Finds PDF files associated with the Contract.
3. Allows the user to select the exact PDF version to analyze.
4. Sends the PDF and structured Salesforce data to Claude.
5. Receives a structured JSON analysis.
6. Validates the AI response in Apex.
7. Deterministically calculates the overall review result.
8. Persists the review and detected discrepancies in Salesforce.
9. Displays the latest analysis directly on the Opportunity record.

The LLM is responsible for interpreting unstructured contract language, while Salesforce remains responsible for validation, deterministic business rules, persistence, security, and user interaction.

---

## Demo

The latest AI review is displayed directly on the Opportunity.

![AI Contract Review - Review Required](docs/screenshots/opportunity-review-required.png)

In this example, the contract does not contain the payment terms stored in Salesforce. The field is classified as `UNKNOWN`, resulting in the deterministic overall status `REVIEW_REQUIRED`.

The same component also supports a clean match state:

![AI Contract Review - Match](docs/screenshots/opportunity-match.png)

---

## Architecture

![Architecture](docs/architecture.png)

```text
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

---

## Technology Stack

| Area | Technology |
| --- | --- |
| CRM Platform | Salesforce |
| Backend | Apex |
| Frontend | Lightning Web Components |
| Orchestration | Salesforce Flow |
| File Storage | Salesforce Files / ContentVersion |
| AI Provider | Anthropic Claude |
| Integration | REST / Anthropic Messages API |
| Authentication | Named Credential + External Credential |
| Configuration | Custom Metadata Types |
| Persistence | Salesforce Custom Objects |
| Security | Sharing + Permission Sets |
| Testing | Apex Tests + HttpCalloutMock |
| Source Control | Git / Salesforce DX |

---

## Data Model

### Opportunity

The Opportunity provides structured commercial terms used during comparison, including:

- `Account`
- `Amount`
- `Discount__c`
- `Payment_Terms__c`
- `Notice_Period_Days__c`
- `ContractId`

### Contract

The standard Salesforce Contract object provides:

- `StartDate`
- `EndDate`
- `ContractTerm`

Contract PDFs are stored using Salesforce Files.

### Contract Review

`Contract_Review__c` represents one analysis execution and stores information such as:

- related Opportunity,
- related Contract,
- analysis date,
- model,
- processing status,
- overall result,
- discrepancy count,
- summary.

### Contract Discrepancy

`Contract_Discrepancy__c` stores individual issues requiring attention, including:

- field,
- Salesforce source and value,
- contract value,
- status,
- severity,
- confidence,
- contract evidence,
- explanation.

`MATCH` comparisons are not persisted as discrepancy records.

---

## AI Classification Model

Each compared field receives one of four statuses:

| Status | Meaning |
| --- | --- |
| `MATCH` | Salesforce and the contract contain equivalent definitive values |
| `MISMATCH` | Salesforce and the contract contain conflicting definitive values |
| `UNKNOWN` | The contract contains no relevant information for the field |
| `AMBIGUOUS` | Relevant information exists, but the contract does not establish one definitive value |

This distinction prevents missing or ambiguous information from automatically being treated as a mismatch.

For example:

```text
Salesforce Discount: 10%

Contract:
"A discount of up to 15% may be applied subject to management approval."

Classification:
AMBIGUOUS
```

The contract discusses the discount, but it does not establish one definitive contractual value.

---

## Deterministic Overall Result

The LLM does **not** have final authority over the overall review result.

Claude classifies individual fields, while Apex calculates the final result deterministically:

```text
If any comparison is MISMATCH
    -> MISMATCH

Else if any comparison is UNKNOWN or AMBIGUOUS
    -> REVIEW_REQUIRED

Else
    -> MATCH
```

This keeps an important aggregate business decision inside deterministic application logic instead of delegating it entirely to the language model.

---

## Prompt Configuration

AI configuration is stored in the `AI_Prompt_Config__mdt` Custom Metadata Type rather than being hard-coded in Apex.

The configuration includes:

- active status,
- Claude model,
- maximum output tokens,
- prompt,
- prompt version.

The current configuration uses:

```text
claude-sonnet-4-6
```

This allows prompt behavior and model configuration to evolve independently from the integration code.

---

## Structured AI Output

Claude returns structured JSON rather than free-form text.

Example:

```json
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

The response is deserialized into strongly typed Apex DTOs before being used by the rest of the application.

---

## AI Response Validation

LLM output is treated as **untrusted input**.

Before persistence, Apex validates the returned data, including:

- required comparison data,
- supported comparison statuses,
- supported severity values,
- confidence values between `0` and `1`,
- expected response structure.

Malformed or unexpected responses are rejected rather than silently persisted.

```text
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

---

## Salesforce User Experience

### Analyze Contract Flow

The **Analyze Contract with AI** Screen Flow provides the main user interaction.

The user selects the exact contract PDF version to analyze:

![Contract PDF Selection](docs/screenshots/contract-pdf-selection.png)

The selector is implemented as a custom Flow Screen LWC and works with Salesforce `ContentVersion` records.

After analysis, the Flow displays the overall result, discrepancy count, and AI-generated summary:

![Contract Analysis Result](docs/screenshots/analysis-result-match.png)

The Flow also contains a dedicated fault path for analysis failures.

### Latest Contract Review

The `contractReviewPanel` Lightning Web Component displays the latest persisted analysis directly on the Opportunity.

It presents:

- overall result,
- analysis date,
- model,
- discrepancy count,
- AI summary,
- field-level discrepancies,
- Salesforce and contract values,
- confidence,
- contract evidence,
- explanation,
- navigation to the persisted review record.

This keeps the analysis visible after the Flow has finished.

---

## Persistence and Audit Trail

Each successful analysis creates a `Contract_Review__c` record.

Comparisons requiring attention are stored as `Contract_Discrepancy__c` child records, creating a Salesforce-side history of review executions rather than treating the AI response as transient UI output.

The Contract record can expose previous review executions alongside the source PDF files.

---

## Security Design

The project uses Salesforce's security model rather than embedding credentials or bypassing record access in custom code.

### Record-Level Security

Core Apex services use `with sharing`, keeping Salesforce record sharing in the execution model.

### Application Permissions

Dedicated permission sets and permission set groups provide access required by the application, including the relevant Salesforce data, Flow, Apex classes, review records, and External Credential principal.

### API Credentials

The Anthropic API key is **not stored in Apex, Flow, Custom Metadata, or source control**.

Authentication uses:

```text
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

The repository contains credential metadata, but not the actual API secret.

---

## Error Handling

The application handles scenarios including:

- missing Opportunity Id,
- missing related Contract,
- missing or unavailable PDF,
- invalid PDF selection,
- Anthropic authentication failures,
- API rate limiting and server errors,
- malformed API responses,
- malformed model JSON,
- truncated model output,
- unsupported status values,
- unsupported severity values,
- invalid confidence values.

Flow fault handling provides a user-facing failure path instead of silently creating incomplete review records.

---

## Testing Strategy

The Apex test suite covers the main application layers.

### Integration Client

Tests cover request construction, PDF payloads, successful API responses, HTTP errors, malformed responses, malformed model JSON, and truncated output.

### Contract Context

Tests cover Opportunity and Contract retrieval, field mapping, and missing related data.

### Salesforce Files

Tests cover contract file discovery, PDF selection, `ContentVersion` handling, and invalid file scenarios.

### Analysis Service

Tests cover response validation and deterministic overall-result calculation.

### Persistence

Tests cover Contract Review creation, discrepancy creation, relationship integrity, and exclusion of `MATCH` comparisons from discrepancy records.

### Security

Tests include execution under restricted users to verify record-level access behavior.

HTTP integrations use `HttpCalloutMock`, keeping unit tests deterministic and independent of external API availability.

---

## LLM Evaluation

Traditional unit tests validate deterministic application behavior, but they cannot prove that a language model interprets contract language correctly.

The project therefore also includes a controlled **LLM evaluation suite** using synthetic contracts executed against the real Anthropic API.

### Evaluation Baseline

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

### Evaluation Scenarios

| Scenario | Expected Result | Expected Issue | Final Result |
| --- | --- | --- | --- |
| A - Full Match | `MATCH` | 0 discrepancies | PASS |
| B - Explicit Mismatches | `MISMATCH` | Amount, Discount, Notice Period | PASS |
| C - Missing Information | `REVIEW_REQUIRED` | Payment Terms -> `UNKNOWN` | PASS |
| D - Conflicting Terms | `REVIEW_REQUIRED` | Discount -> `AMBIGUOUS` | PASS |

### Evaluation-Driven Architecture Change

Scenario C exposed an important design issue.

Claude correctly classified the missing payment term as `UNKNOWN`, but the aggregate result returned by the model was inconsistent with the field-level classifications.

The overall review status was therefore moved to deterministic Apex logic.

This created a clearer responsibility boundary:

```text
Claude
    -> interprets individual contract terms

Apex
    -> validates the response
    -> calculates the overall result
    -> persists the result
```

The final A-D regression suite passed after the architecture and prompt behavior were refined.

Detailed evaluation methodology and the synthetic test documents are available in:

**[LLM Evaluation](evaluation/README.md)**

The evaluation contracts are stored in:

```text
evaluation/synthetic-contracts/
```

---

## Unit Tests vs LLM Evaluation

The project deliberately separates deterministic software testing from probabilistic model evaluation.

### Apex Unit Tests

Validate:

```text
Apex logic
API request construction
JSON parsing
response validation
persistence
security behavior
error handling
```

### LLM Evaluation

Evaluates:

```text
contract interpretation
missing information
conflicting provisions
semantic comparison
classification quality
```

A mocked HTTP unit test cannot prove that the real model correctly interprets a contract.

Conversely, a successful LLM evaluation does not replace deterministic Apex unit tests.

Both layers are required.

---

## Reporting and Dashboard

Persisted review data is designed to support native Salesforce reporting, including:

- reviews by overall result,
- discrepancies by field,
- discrepancies by severity.

When dashboard metadata and its screenshot are included in the repository, the dashboard can be displayed here:

```markdown
![AI Contract Review Dashboard](docs/screenshots/dashboard.png)
```

---

## What the LLM Does - and Does Not Do

### Claude is responsible for

- reading unstructured contract content,
- extracting relevant contractual information,
- interpreting whether contract language is definitive or ambiguous,
- comparing contract information with provided Salesforce values,
- producing evidence and explanations,
- returning structured classifications.

### Salesforce is responsible for

- record and file access,
- structured data retrieval,
- authentication,
- response validation,
- deterministic aggregation,
- persistence,
- authorization,
- user interaction,
- reporting.

This separation keeps probabilistic document interpretation in the AI layer while retaining deterministic business controls inside Salesforce.

---

## Repository Structure

```text
salesforce-ai-contract-review/
├── README.md
├── docs/
│   ├── architecture.png
│   └── screenshots/
│       ├── opportunity-review-required.png
│       ├── opportunity-match.png
│       ├── contract-pdf-selection.png
│       └── analysis-result-match.png
├── evaluation/
│   ├── README.md
│   └── synthetic-contracts/
│       ├── Contract_Eval_A_Full_Match.pdf
│       ├── Contract_Eval_B_Explicit_Mismatches.pdf
│       ├── Contract_Eval_C_Missing_Information.pdf
│       └── Contract_Eval_D_Conflicting_Terms.pdf
├── force-app/
│   └── main/
│       └── default/
│           ├── classes/
│           ├── customMetadata/
│           ├── externalCredentials/
│           ├── flexipages/
│           ├── flows/
│           ├── lwc/
│           ├── namedCredentials/
│           ├── objects/
│           ├── permissionsets/
│           ├── permissionsetgroups/
│           └── quickActions/
├── config/
├── scripts/
├── package.json
└── sfdx-project.json
```

---

## Setup

### Prerequisites

- Salesforce CLI
- access to a Salesforce org
- an Anthropic API key
- permissions to deploy the required Salesforce metadata

### 1. Authenticate to Salesforce

```bash
sf org login web --alias contract-review
```

### 2. Deploy the Metadata

```bash
sf project deploy start \
  --source-dir force-app \
  --target-org contract-review
```

### 3. Configure the Anthropic Credential

The repository intentionally does **not** contain an Anthropic API key.

After deployment:

1. Open **Setup -> Named Credentials**.
2. Locate the Anthropic External Credential.
3. Configure the Named Principal authentication parameter with a valid Anthropic API key.
4. Ensure the application user has access to the External Credential principal.

### 4. Assign Application Permissions

Assign the relevant permission set or permission set group to the application user.

### 5. Prepare Test Data

Create an Opportunity with a related Contract containing the required comparison data.

Upload at least one PDF to the Contract using Salesforce Files.

### 6. Run the Analysis

Open the Opportunity, launch **Analyze Contract with AI**, select a contract PDF, and start the analysis.

---

## Running Apex Tests

```bash
sf apex run test \
  --test-level RunLocalTests \
  --target-org contract-review \
  --wait 20 \
  --code-coverage
```

The Apex unit tests use mocked HTTP responses and do not require live Anthropic API calls.

---

## Production Considerations

This project is intentionally a proof of concept.

A production implementation would require additional decisions depending on organizational requirements, including:

- legal and compliance review,
- data residency and confidentiality requirements,
- AI provider data-processing policies,
- observability and operational monitoring,
- API usage and cost monitoring,
- retry and rate-limit strategies,
- asynchronous processing for larger workloads,
- prompt and model lifecycle management,
- prompt version auditing,
- expanded evaluation datasets,
- regression testing across model versions,
- human review and escalation workflows,
- audit and retention policies.

AI-generated results should be treated as decision support rather than a substitute for legal review.

---

## Design Principles

**AI output is untrusted input.**  
Model responses are validated before they affect Salesforce data.

**Use AI where deterministic code is insufficient.**  
Claude interprets unstructured language; Apex handles deterministic business logic.

**Do not confuse missing information with disagreement.**  
`UNKNOWN`, `AMBIGUOUS`, and `MISMATCH` represent different business situations.

**Keep secrets outside source code.**  
API authentication is handled through Salesforce credentials.

**Respect Salesforce security.**  
The AI integration should not become a mechanism for bypassing record access.

**Make AI behavior testable.**  
Traditional unit tests are complemented by document-level LLM evaluation.

**Keep aggregate business decisions deterministic.**  
The LLM interprets individual fields; Apex determines the final review status.

---

## Disclaimer

This repository is a technical proof of concept created for demonstration and learning purposes.

All contract examples and evaluation data are synthetic.

The project is not a legal review system, and AI-generated analysis should not be treated as legal advice.

---

## Author

**Jakub Godlewski**

Salesforce Developer / Technical Lead

Built as a hands-on exploration of integrating Generative AI with Salesforce using native platform architecture, security controls, deterministic guardrails, and LLM evaluation.
