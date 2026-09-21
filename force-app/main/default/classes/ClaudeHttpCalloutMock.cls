@IsTest
public class ClaudeHttpCalloutMock implements HttpCalloutMock {

    private Integer statusCode;
    private String responseBody;
    public HttpRequest lastRequest;

    public ClaudeHttpCalloutMock(Integer statusCode, String responseBody) {
        this.statusCode = statusCode;
        this.responseBody = responseBody;
    }

    public HttpResponse respond(HttpRequest request) {
        lastRequest = request;
        HttpResponse response = new HttpResponse();
        response.setStatusCode(statusCode);
        response.setHeader('Content-Type', 'application/json');
        response.setBody(responseBody);
        return response;
    }

    public static ClaudeHttpCalloutMock success() {
        return new ClaudeHttpCalloutMock(200, successResponseBody());
    }

    public static ClaudeHttpCalloutMock apiError(Integer statusCode) {
        Map<String, Object> error = new Map<String, Object>{
            'type' => 'api_error',
            'message' => 'Test API error'
        };
        Map<String, Object> body = new Map<String, Object>{
            'type' => 'error',
            'error' => error
        };
        return new ClaudeHttpCalloutMock(
            statusCode,
            JSON.serialize(body)
        );
    }

    public static ClaudeHttpCalloutMock malformedJson() {
        return new ClaudeHttpCalloutMock(200, '{"content":');
    }

    public static ClaudeHttpCalloutMock malformedContentJson() {
        return new ClaudeHttpCalloutMock(
            200,
            anthropicResponse('{"overallStatus":')
        );
    }

    public static ClaudeHttpCalloutMock maxTokens() {
        String body = successResponseBody();
        Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(body);
        payload.put('stop_reason', 'max_tokens');
        return new ClaudeHttpCalloutMock(200, JSON.serialize(payload));
    }

    public static ClaudeHttpCalloutMock emptyContent() {
        return new ClaudeHttpCalloutMock(200, JSON.serialize(
            new Map<String, Object>{
                'id' => 'msg_test',
                'type' => 'message',
                'role' => 'assistant',
                'model' => 'claude-sonnet-4-6',
                'content' => new List<Object>(),
                'stop_reason' => 'end_turn'
            }
        ));
    }

    public static String successResponseBody() {
        return anthropicResponse(contractAnalysisJson());
    }

    public static String responseWithAnalysis(String analysisJson) {
        return anthropicResponse(analysisJson);
    }

    public static String contractAnalysisJson() {
        List<Object> comparisons = new List<Object>{
            comparison('amount', 'Opportunity', '120000', '115000', 'MISMATCH', 'HIGH', '0.99', 'The contract states 115000.', 'Amount differs.'),
            comparison('discount', 'Opportunity', '10', '15', 'MISMATCH', 'MEDIUM', '0.95', 'The contract states 15%.', 'Discount differs.'),
            comparison('noticePeriodDays', 'Opportunity', '60', '30', 'MISMATCH', 'MEDIUM', '0.93', 'The contract states 30 days.', 'Notice period differs.'),
            comparison('accountName', 'Opportunity', 'Acme Sp. z o.o.', 'Acme Sp. z o.o.', 'MATCH', 'NONE', '0.99', 'The contract names Acme Sp. z o.o.', 'Values match.'),
            comparison('paymentTerms', 'Opportunity', 'Net 30', 'Net 30', 'MATCH', 'NONE', '0.98', 'The contract states Net 30.', 'Values match.'),
            comparison('contractStartDate', 'Contract', '2026-11-01', '2026-11-01', 'MATCH', 'NONE', '0.98', 'The contract starts on 2026-11-01.', 'Values match.'),
            comparison('contractEndDate', 'Contract', '2027-10-31', '2027-10-31', 'MATCH', 'NONE', '0.98', 'The contract ends on 2027-10-31.', 'Values match.'),
            comparison('contractTermMonths', 'Contract', '12', '12', 'MATCH', 'NONE', '0.98', 'The contract term is 12 months.', 'Values match.')
        };
        return JSON.serialize(new Map<String, Object>{
            'overallStatus' => 'MISMATCH',
            'summary' => 'Three contractual values differ from Salesforce.',
            'comparisons' => comparisons
        });
    }

    private static Map<String, Object> comparison(
        String field,
        String source,
        String salesforceValue,
        String contractValue,
        String status,
        String severity,
        String confidence,
        String evidence,
        String explanation
    ) {
        return new Map<String, Object>{
            'field' => field,
            'salesforceSource' => source,
            'salesforceValue' => salesforceValue,
            'contractValue' => contractValue,
            'status' => status,
            'severity' => severity,
            'confidence' => Decimal.valueOf(confidence),
            'contractEvidence' => evidence,
            'explanation' => explanation
        };
    }

    private static String anthropicResponse(String text) {
        Map<String, Object> contentBlock = new Map<String, Object>{
            'type' => 'text',
            'text' => text
        };
        Map<String, Object> usage = new Map<String, Object>{
            'input_tokens' => 10,
            'output_tokens' => 20
        };
        return JSON.serialize(new Map<String, Object>{
            'id' => 'msg_test',
            'type' => 'message',
            'role' => 'assistant',
            'model' => 'claude-sonnet-4-6',
            'content' => new List<Object>{contentBlock},
            'stop_reason' => 'end_turn',
            'usage' => usage
        });
    }
}
