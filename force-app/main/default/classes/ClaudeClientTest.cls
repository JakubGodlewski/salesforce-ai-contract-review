@IsTest
private class ClaudeClientTest {

    @IsTest
    static void sendMessageDeserializesSuccessfulResponse() {
        ClaudeHttpCalloutMock mock = ClaudeHttpCalloutMock.success();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        ClaudeClient.ClaudeResponse response =
            ClaudeClient.sendMessage('Test prompt');
        Test.stopTest();

        Assert.areEqual('msg_test', response.id);
        Assert.areEqual('end_turn', response.stop_reason);
        Assert.isTrue(response.getText().contains('Three contractual values'));
        Assert.areEqual('POST', mock.lastRequest.getMethod());
        Assert.areEqual(
            'callout:Anthropic/v1/messages',
            mock.lastRequest.getEndpoint()
        );
        Map<String, Object> requestBody = requestBody(mock);
        Assert.areEqual('claude-sonnet-4-6', requestBody.get('model'));
        Assert.areEqual(4096, requestBody.get('max_tokens'));
        List<Object> messages = (List<Object>) requestBody.get('messages');
        Map<String, Object> message = (Map<String, Object>) messages[0];
        Assert.areEqual('user', message.get('role'));
        Assert.areEqual('Test prompt', message.get('content'));
    }

    @IsTest
    static void analyzeContractDeserializesExpectedComparisonsAndRequest() {
        ContractContext context = buildContext();
        Blob pdfBlob = Blob.valueOf('Synthetic contract PDF content');
        ClaudeHttpCalloutMock mock = ClaudeHttpCalloutMock.success();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        ContractAnalysisResult result = ClaudeClient.analyzeContract(
            pdfBlob,
            context
        );
        Test.stopTest();

        Assert.areEqual('MISMATCH', result.overallStatus);
        Assert.areEqual(8, result.comparisons.size());
        ContractAnalysisResult.Comparison amount =
            findComparison(result, 'amount');
        Assert.areEqual('115000', amount.contractValue);
        Assert.areEqual('MISMATCH', amount.status);
        Assert.areEqual(0.99, amount.confidence);

        Map<String, Object> requestBody = requestBody(mock);
        List<Object> messages = (List<Object>) requestBody.get('messages');
        Map<String, Object> message = (Map<String, Object>) messages[0];
        List<Object> content = (List<Object>) message.get('content');
        Map<String, Object> document = (Map<String, Object>) content[0];
        Map<String, Object> source = (Map<String, Object>) document.get('source');
        Assert.areEqual('document', document.get('type'));
        Assert.areEqual('base64', source.get('type'));
        Assert.areEqual('application/pdf', source.get('media_type'));
        Assert.isTrue(String.isNotBlank((String) source.get('data')));
        Map<String, Object> promptBlock = (Map<String, Object>) content[1];
        Assert.areEqual('text', promptBlock.get('type'));

        Map<String, Object> salesforceData = extractSalesforceData(
            (String) promptBlock.get('text')
        );
        Map<String, Object> opportunityData =
            (Map<String, Object>) salesforceData.get('Opportunity');
        Map<String, Object> contractData =
            (Map<String, Object>) salesforceData.get('Contract');
        Assert.areEqual(
            new Set<String>{
                'accountName', 'amount', 'discount',
                'paymentTerms', 'noticePeriodDays'
            },
            opportunityData.keySet()
        );
        Assert.areEqual(
            new Set<String>{
                'contractStartDate', 'contractEndDate', 'contractTermMonths'
            },
            contractData.keySet()
        );
        Assert.isFalse(opportunityData.containsKey('opportunityId'));
        Assert.isFalse(contractData.containsKey('contractId'));
    }

    @IsTest
    static void rejectsEmptyPromptAndNullPdf() {
        try {
            ClaudeClient.sendMessage('');
            Assert.fail('Expected ClaudeClientException.');
        } catch (ClaudeClient.ClaudeClientException caughtException) {
            Assert.areEqual('Prompt cannot be empty.', caughtException.getMessage());
        }

        try {
            ClaudeClient.analyzePdf(null, 'prompt');
            Assert.fail('Expected ClaudeClientException.');
        } catch (ClaudeClient.ClaudeClientException caughtException) {
            Assert.areEqual('PDF cannot be null.', caughtException.getMessage());
        }
    }

    @IsTest
    static void reportsUnauthorized() {
        assertHttpFailure(401);
    }

    @IsTest
    static void reportsRateLimit() {
        assertHttpFailure(429);
    }

    @IsTest
    static void reportsServerError() {
        assertHttpFailure(500);
    }

    private static void assertHttpFailure(Integer statusCode) {
        Test.setMock(
            HttpCalloutMock.class,
            ClaudeHttpCalloutMock.apiError(statusCode)
        );

        try {
            Test.startTest();
            ClaudeClient.sendMessage('prompt');
            Assert.fail('Expected HTTP error.');
        } catch (ClaudeClient.ClaudeClientException caughtException) {
            Assert.isTrue(caughtException.getMessage().contains('HTTP ' + statusCode));
        } finally {
            Test.stopTest();
        }
    }

    @IsTest
    static void reportsMalformedAnthropicResponse() {
        Test.setMock(HttpCalloutMock.class, ClaudeHttpCalloutMock.malformedJson());

        try {
            Test.startTest();
            ClaudeClient.sendMessage('prompt');
            Test.stopTest();
            Assert.fail('Expected deserialization error.');
        } catch (ClaudeClient.ClaudeClientException caughtException) {
            Assert.isTrue(caughtException.getMessage().contains('Unable to deserialize'));
        }
    }

    @IsTest
    static void reportsMalformedJsonInsideClaudeContent() {
        ContractContext context = buildContext();
        Blob pdfBlob = Blob.valueOf('Synthetic contract PDF content');
        Test.setMock(
            HttpCalloutMock.class,
            ClaudeHttpCalloutMock.malformedContentJson()
        );

        try {
            Test.startTest();
            ClaudeClient.analyzeContract(
                pdfBlob,
                context
            );
            Test.stopTest();
            Assert.fail('Expected invalid JSON error.');
        } catch (ClaudeClient.ClaudeClientException caughtException) {
            Assert.isTrue(caughtException.getMessage().contains('invalid JSON'));
        }
    }

    @IsTest
    static void reportsMaxTokens() {
        ContractContext context = buildContext();
        Blob pdfBlob = Blob.valueOf('Synthetic contract PDF content');

        Test.setMock(HttpCalloutMock.class, ClaudeHttpCalloutMock.maxTokens());
        try {
            Test.startTest();
            ClaudeClient.analyzeContract(
                pdfBlob,
                context
            );
            Assert.fail('Expected max_tokens error.');
        } catch (ClaudeClient.ClaudeClientException caughtException) {
            Assert.isTrue(caughtException.getMessage().contains('truncated'));
        } finally {
            Test.stopTest();
        }
    }

    @IsTest
    static void reportsEmptyContent() {
        ContractContext context = buildContext();
        Blob pdfBlob = Blob.valueOf('Synthetic contract PDF content');
        Test.setMock(HttpCalloutMock.class, ClaudeHttpCalloutMock.emptyContent());
        try {
            Test.startTest();
            ClaudeClient.analyzeContract(
                pdfBlob,
                context
            );
            Assert.fail('Expected empty response error.');
        } catch (ClaudeClient.ClaudeClientException caughtException) {
            Assert.isTrue(caughtException.getMessage().contains('empty response'));
        } finally {
            Test.stopTest();
        }
    }

    private static ContractContext buildContext() {
        ContractContext context = new ContractContext();
        context.accountName = 'Acme Sp. z o.o.';
        context.amount = 120000;
        context.discount = 10;
        context.paymentTerms = 'Net 30';
        context.noticePeriodDays = 60;
        context.contractStartDate = Date.newInstance(2026, 11, 1);
        context.contractEndDate = Date.newInstance(2027, 10, 31);
        context.contractTermMonths = 12;
        return context;
    }

    private static Map<String, Object> requestBody(
        ClaudeHttpCalloutMock mock
    ) {
        return (Map<String, Object>) JSON.deserializeUntyped(
            mock.lastRequest.getBody()
        );
    }

    private static Map<String, Object> extractSalesforceData(String prompt) {
        String startMarker = 'SALESFORCE DATA:\n';
        String endMarker = '\n\nCompare every relevant contractual field';
        Integer start = prompt.indexOf(startMarker) + startMarker.length();
        Integer endIndex = prompt.indexOf(endMarker);
        return (Map<String, Object>) JSON.deserializeUntyped(
            prompt.substring(start, endIndex)
        );
    }

    private static ContractAnalysisResult.Comparison findComparison(
        ContractAnalysisResult result,
        String fieldName
    ) {
        for (ContractAnalysisResult.Comparison comparison : result.comparisons) {
            if (comparison.field == fieldName) {
                return comparison;
            }
        }
        Assert.fail('Missing comparison for field: ' + fieldName);
        return null;
    }
}
