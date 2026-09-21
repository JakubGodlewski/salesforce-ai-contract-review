# Salesforce AI Contract Review

A Salesforce proof of concept that uses **Anthropic Claude** to review contract PDFs and compare contractual terms with structured Salesforce data.

The solution combines **Apex, Lightning Web Components, Flow, Salesforce Files, Named Credentials, Custom Metadata, and the Anthropic Messages API** to demonstrate an end-to-end GenAI use case implemented natively on the Salesforce Platform.

> **Project status:** Proof of Concept / Portfolio Project  
> The project uses synthetic contract data and was created to explore the architecture, security, testing, and evaluation of a Salesforce + GenAI integration.

---

## Business Problem

Commercial contract data often exists in two places:

- structured CRM fields in Salesforce,
- unstructured legal documents stored as PDF files.

Differences between these sources can be difficult to identify manually.

For example, Salesforce may contain:

- Contract Value: **USD 120,000**
- Discount: **10%**
- Payment Terms: **Net 30**
- Notice Period: **60 days**

while the signed contract may contain different or incomplete terms.

This project demonstrates how an AI-assisted validation process can compare both sources and surface discrepancies directly in Salesforce.

---

## Solution Overview

A Salesforce user starts the analysis from an **Opportunity**.

The application:

1. Retrieves structured data from the Opportunity and its related Contract.
2. Finds PDF files associated with the Contract.
3. Allows the user to select the contract version to analyze.
4. Sends the PDF and structured Salesforce data to Claude.
5. Receives a structured JSON analysis.
6. Validates the AI response in Apex.
7. Deterministically calculates the overall review result.
8. Persists the review and detected discrepancies in Salesforce.
9. Displays the latest analysis directly on the Opportunity record.

The LLM is responsible for interpreting unstructured contract language, while Salesforce remains responsible for validation, business rules, persistence, and access control.

---

## Architecture

```text
┌──────────────────────┐
│     Opportunity      │
│                      │
│ Amount               │
│ Discount             │
│ Payment Terms        │
│ Notice Period        │
└──────────┬───────────┘
           │
           │ ContractId
           ▼
┌──────────────────────┐
│       Contract       │
│                      │
│ Start Date           │
│ End Date             │
│ Contract Term        │
└──────────┬───────────┘
           │
           │ Salesforce Files
           ▼
┌──────────────────────┐
│     Contract PDF     │
│   ContentVersion     │
└──────────┬───────────┘
           │
           │
           ▼
┌─────────────────────────────┐
│        Screen Flow          │
│ Analyze Contract with AI    │
│                             │
│ + Contract PDF Selector LWC │
└─────────────┬───────────────┘
              │
              ▼
┌─────────────────────────────┐
│          Apex Layer         │
│                             │
│ ContractAnalysisAction      │
│ ContractAnalysisService     │
│ ContractContextService      │
│ ContractFileService         │
└─────────────┬───────────────┘
              │
              ▼
┌─────────────────────────────┐
│        ClaudeClient         │
│                             │
│ Named Credential            │
│ External Credential         │
└─────────────┬───────────────┘
              │ HTTPS
              ▼
┌─────────────────────────────┐
│      Anthropic Claude       │
│       Messages API          │
└─────────────┬───────────────┘
              │
              │ Structured JSON
              ▼
┌─────────────────────────────┐
│    Response Validation      │
│                             │
│ Allowed fields/statuses     │
│ Severity validation         │
│ Confidence validation       │
│ Deterministic aggregation   │
└─────────────┬───────────────┘
              │
              ▼
┌─────────────────────────────┐
│       Persistence           │
│                             │
│ Contract_Review__c          │
│ Contract_Discrepancy__c     │
└─────────────┬───────────────┘
              │
              ▼
┌─────────────────────────────┐
│     Opportunity LWC         │
│                             │
│ Latest AI Contract Review   │
└─────────────────────────────┘
```

---

## Technology Stack

| Area | Technology |
|---|---|
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
| Security | Sharing + Permission Sets + CRUD/FLS |
| Testing | Apex Tests + HttpCalloutMock |
| Source Control | Git / Salesforce DX |

---

## Data Model

### Opportunity

The Opportunity contains the structured commercial terms used for comparison.

Relevant fields include:

- `Account`
- `Amount`
- `Discount__c`
- `Payment_Terms__c`
- `Notice_Period_Days__c`
- `ContractId`

### Contract

The standard Salesforce Contract object contains:

- `StartDate`
- `EndDate`
- `ContractTerm`

Contract PDFs are stored using Salesforce Files.

### Contract Review

`Contract_Review__c` represents one AI analysis execution.

It stores information such as:

- related Opportunity,
- related Contract,
- analysis date,
- model,
- processing status,
- overall result,
- discrepancy count,
- summary.

### Contract Discrepancy

`Contract_Discrepancy__c` stores individual issues identified during a review.

Each discrepancy can contain:

- field,
- Salesforce source,
- Salesforce value,
- contract value,
- status,
- severity,
- confidence,
- contract evidence,
- explanation.

Only results requiring attention are persisted as discrepancy records.

---

## AI Classification Model

Each compared field receives one of four statuses:

| Status | Meaning |
|---|---|
| `MATCH` | Salesforce and the contract contain equivalent definitive values |
| `MISMATCH` | Salesforce and the contract contain conflicting definitive values |
| `UNKNOWN` | The contract does not contain relevant information |
| `AMBIGUOUS` | Relevant contract information exists but does not establish one definitive value |

This distinction is important because missing or ambiguous information should not automatically be interpreted as a mismatch.

For example:

```text
Salesforce Discount: 10%

Contract:
"A discount of up to 15% may be applied subject to management approval."

Result:
AMBIGUOUS
```

The contract discusses the discount but does not establish a definitive contractual value.

---

## Deterministic Overall Result

The LLM does **not** have final authority over the overall review result.

Claude classifies individual fields, but Apex calculates the final status deterministically:

```text
If any comparison is MISMATCH
    → MISMATCH

Else if any comparison is UNKNOWN or AMBIGUOUS
    → REVIEW_REQUIRED

Else
    → MATCH
```

This prevents inconsistencies such as an AI response containing an `UNKNOWN` field while incorrectly reporting the entire contract as `MATCH` or `MISMATCH`.

It also keeps an important business decision inside deterministic application logic rather than delegating it entirely to the language model.

---

## Prompt Configuration

AI configuration is stored in the `AI_Prompt_Config__mdt` Custom Metadata Type.

The configuration contains:

- active status,
- Claude model,
- maximum output tokens,
- prompt,
- prompt version.

This allows prompt behavior and model configuration to be changed without modifying Apex code.

The current implementation uses:

```text
claude-sonnet-4-6
```

with a structured contract-validation prompt.

---

## Structured AI Output

Claude is instructed to return JSON rather than free-form text.

A comparison follows this structure:

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

The response is deserialized into strongly typed Apex DTOs before it can be used by the rest of the application.

---

## AI Response Validation

LLM output is treated as **untrusted input**.

Before persistence, Apex validates the returned structure and values.

Validation includes:

- allowed comparison statuses,
- allowed severity values,
- confidence range between `0` and `1`,
- required comparison data,
- expected field names,
- valid response structure.

Malformed or unexpected AI responses are rejected instead of being silently persisted.

This creates a clear trust boundary:

```text
LLM output
    ↓
Untrusted data
    ↓
Apex validation
    ↓
Deterministic business logic
    ↓
Salesforce persistence
```

---

## Salesforce User Experience

### Analyze Contract Flow

The **Analyze Contract with AI** Screen Flow provides the main user interaction.

The flow:

1. receives the Opportunity Id,
2. confirms the analysis,
3. loads available contract PDFs,
4. allows the user to select a PDF,
5. invokes the Apex analysis action,
6. displays the result,
7. handles failures through a dedicated error path.

A custom Flow Screen LWC is used to select the exact `ContentVersion` that should be analyzed.

### Latest Contract Review

The `contractReviewPanel` Lightning Web Component displays the latest analysis directly on the Opportunity record.

It includes:

- overall result,
- analysis date,
- model,
- discrepancy count,
- AI summary,
- discrepancies sorted by severity,
- Salesforce and contract values,
- confidence,
- contract evidence,
- explanation,
- navigation to the persisted review record.

---

## Security Design

The project follows Salesforce's layered security model.

### Record-Level Security

Core services use `with sharing`, ensuring that Salesforce sharing rules remain part of the execution model.

The design assumes private access to business records where appropriate and does not rely on the Opportunity-to-Contract lookup to provide implicit record access.

### CRUD and Field-Level Security

Dedicated permission sets grant only the permissions required by the application.

The intended user can:

- read the source Opportunity,
- read the source Account,
- read the related Contract,
- read the required Salesforce Files,
- execute the analysis Flow,
- use the configured External Credential principal,
- create and read Contract Reviews,
- create and read Contract Discrepancies.

The application does not require users to edit source commercial data as part of the analysis process.

### API Credentials

The Anthropic API key is **not stored in Apex, Flow, Custom Metadata, or source control**.

Authentication uses:

```text
Named Credential
      ↓
External Credential
      ↓
Named Principal
      ↓
API secret configured in Salesforce
```

The repository therefore contains the credential configuration but not the actual API secret.

---

## Error Handling

The integration handles both Salesforce-side and external API failures.

Examples include:

- missing Opportunity Id,
- missing related Contract,
- unavailable contract PDF,
- invalid PDF selection,
- Anthropic authentication failure,
- API rate limiting,
- server errors,
- malformed API responses,
- malformed model JSON,
- incomplete model output,
- invalid status values,
- invalid severity values,
- invalid confidence values.

Errors are surfaced to the Flow instead of silently producing incomplete review records.

---

## Testing Strategy

The project contains Apex tests covering the major application layers.

Test coverage includes:

### Integration Client

- request construction,
- Named Credential endpoint usage,
- PDF payload construction,
- successful responses,
- HTTP error responses,
- malformed Anthropic responses,
- malformed model JSON,
- incomplete output.

### Contract Context

- Opportunity data retrieval,
- Contract data retrieval,
- missing related records,
- expected field mapping.

### Salesforce Files

- contract file discovery,
- PDF selection,
- ContentVersion handling,
- invalid file scenarios.

### Analysis Service

- response validation,
- supported statuses,
- supported severities,
- confidence validation,
- deterministic overall status calculation.

### Persistence

- Contract Review creation,
- discrepancy creation,
- exclusion of `MATCH` results from discrepancy records,
- relationship integrity.

### Security

Tests include execution under restricted users to verify record-level access behavior.

HTTP integrations are isolated using `HttpCalloutMock`, allowing the test suite to execute without calling the real Anthropic API.

---

## LLM Evaluation

Unit tests validate deterministic application behavior, but they cannot prove that a language model interprets contract language correctly.

The project therefore also uses a small **LLM evaluation suite** with synthetic contracts.

The scenarios cover four important behaviors:

| Scenario | Expected Result | Purpose |
|---|---|---|
| Full Match | `MATCH` | All contractual values agree with Salesforce |
| Explicit Mismatches | `MISMATCH` | Contract contains definitive conflicting values |
| Missing Information | `REVIEW_REQUIRED` | Contract omits a field available in Salesforce |
| Conflicting Contract Terms | `REVIEW_REQUIRED` | Contract contains conflicting provisions without a precedence rule |

The evaluation verifies not only the final result but also the individual comparison classifications.

### Example Evaluation Dataset

Baseline Salesforce data:

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

#### Scenario A — Full Match

All contract values match Salesforce.

Expected:

```text
MATCH
0 discrepancies
```

#### Scenario B — Explicit Mismatches

The synthetic contract contains:

```text
Amount: USD 115,000
Discount: 15%
Notice Period: 30 days
```

while the remaining values match Salesforce.

Expected:

```text
MISMATCH
3 discrepancies
```

#### Scenario C — Missing Information

The contract matches Salesforce but contains no payment terms.

Expected:

```text
REVIEW_REQUIRED

paymentTerms → UNKNOWN
```

This scenario is also used to verify that the overall result is calculated from field-level classifications in Apex rather than trusted directly from the LLM.

#### Scenario D — Conflicting Contract Terms

The contract contains two definitive but conflicting provisions:

```text
Section 3.1: Discount = 10%
Section 3.2: Discount = 15%
```

and does not specify which provision takes precedence.

Expected:

```text
REVIEW_REQUIRED

discount → AMBIGUOUS
```

The evaluation contracts contain synthetic data and are intended solely for testing the behavior of the proof of concept.

---

## What the LLM Does — and Does Not Do

The architecture deliberately limits the responsibilities of the language model.

### Claude is responsible for

- reading unstructured contract text,
- extracting relevant contractual information,
- interpreting whether language is definitive or ambiguous,
- comparing contractual information with provided Salesforce values,
- producing evidence and explanations,
- returning structured classifications.

### Salesforce is responsible for

- record access,
- data retrieval,
- file access,
- authentication,
- validation,
- deterministic aggregation,
- persistence,
- authorization,
- user interaction,
- reporting.

This separation keeps probabilistic document interpretation in the AI layer while retaining deterministic business controls inside Salesforce.

---

## Repository Structure

```text
force-app/main/default/
│
├── classes/
│   ├── ClaudeClient.cls
│   ├── ContractAnalysisAction.cls
│   ├── ContractAnalysisService.cls
│   ├── ContractContextService.cls
│   ├── ContractFileService.cls
│   ├── ContractReviewService.cls
│   └── ...
│
├── customMetadata/
│   └── AI_Prompt_Config__mdt.Default.md-meta.xml
│
├── externalCredentials/
│   └── Anthropic_API.externalCredential-meta.xml
│
├── flows/
│   └── Analyze_Contract_with_AI.flow-meta.xml
│
├── lwc/
│   ├── contractPdfSelector/
│   └── contractReviewPanel/
│
├── namedCredentials/
│   └── Anthropic.namedCredential-meta.xml
│
├── objects/
│   ├── AI_Prompt_Config__mdt/
│   ├── Contract_Review__c/
│   ├── Contract_Discrepancy__c/
│   └── Opportunity/
│
├── permissionsets/
├── permissionsetgroups/
├── quickActions/
└── flexipages/
```

---

## Setup

### 1. Deploy Salesforce Metadata

Authenticate to a Salesforce org:

```bash
sf org login web --alias contract-review
```

Deploy the project:

```bash
sf project deploy start --source-dir force-app --target-org contract-review
```

### 2. Configure the Anthropic Credential

The repository intentionally does **not** contain an Anthropic API key.

After deployment:

1. open **Setup → Named Credentials**,
2. locate the Anthropic External Credential,
3. configure the Named Principal authentication parameter with a valid Anthropic API key,
4. ensure the application user has access to the External Credential principal.

### 3. Assign Application Permissions

Assign the relevant permission set or permission set group to the test user.

### 4. Prepare Salesforce Data

Create an Opportunity and related Contract containing the required comparison fields.

Upload at least one PDF to the related Contract using Salesforce Files.

### 5. Run the Analysis

Open the Opportunity and launch:

**Analyze Contract with AI**

Select the contract PDF and start the analysis.

---

## Running Apex Tests

Run the complete local Apex test suite using Salesforce CLI:

```bash
sf apex run test \
  --test-level RunLocalTests \
  --target-org contract-review \
  --wait 20 \
  --code-coverage
```

The test suite uses mocked HTTP responses and does not require live Anthropic API calls.

---

## Production Considerations

This project is intentionally a proof of concept.

A production implementation would require additional decisions depending on the organization's requirements, including:

- formal legal and compliance review,
- data residency requirements,
- AI provider data-processing policies,
- contract confidentiality requirements,
- observability and operational monitoring,
- API usage and cost monitoring,
- retry and rate-limit strategies,
- asynchronous processing for larger workloads,
- model and prompt lifecycle management,
- expanded evaluation datasets,
- regression testing across model versions,
- human review and escalation workflows,
- audit and retention policies.

AI-generated results should be treated as decision support rather than a substitute for legal review.

---

## Design Principles

Several principles guided the implementation:

**AI output is untrusted input.**  
Model responses are validated before they affect Salesforce data.

**Use AI where deterministic code is insufficient.**  
Claude interprets unstructured language; Apex handles deterministic business logic.

**Do not confuse missing information with disagreement.**  
`UNKNOWN`, `AMBIGUOUS`, and `MISMATCH` represent different business situations.

**Keep secrets outside source code.**  
API authentication is handled through Salesforce credentials.

**Respect Salesforce security.**  
AI integration should not become a mechanism for bypassing record access.

**Make AI behavior testable.**  
Traditional unit tests are complemented by document-level LLM evaluation.

---

## Disclaimer

This repository is a technical proof of concept created for demonstration and learning purposes.

All contract examples and evaluation data are synthetic.

The project is not a legal review system and AI-generated analysis should not be treated as legal advice.

---

## Author

**Jakub Godlewski**

Salesforce Developer / Technical Lead

Built as a hands-on exploration of integrating Generative AI with Salesforce using native platform architecture, security controls, and engineering practices.