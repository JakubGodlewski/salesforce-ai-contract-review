public with sharing class ClaudeClient {

    private static final String NAMED_CREDENTIAL = 'callout:Anthropic';
    private static final String MESSAGES_ENDPOINT = '/v1/messages';

    private static final Integer TIMEOUT_MS = 120000;

    /**
     * Sends a simple text prompt to Claude.
     */
    public static ClaudeResponse sendMessage(String prompt) {
        if (String.isBlank(prompt)) {
            throw new ClaudeClientException('Prompt cannot be empty.');
        }

        PromptConfig config = getActivePromptConfig();
        ClaudeRequest request = new ClaudeRequest();
        request.model = config.model;
        request.max_tokens = config.maxTokens;
        request.messages = new List<ClaudeMessage>{
            new ClaudeMessage('user', prompt)
        };

        return sendRequest(request);
    }

    /**
     * Performs the actual HTTP callout to Anthropic.
     */
    private static ClaudeResponse sendRequest(ClaudeRequest claudeRequest) {

        HttpRequest request = new HttpRequest();
        request.setEndpoint(NAMED_CREDENTIAL + MESSAGES_ENDPOINT);
        request.setMethod('POST');
        request.setHeader('Content-Type', 'application/json');
        request.setTimeout(TIMEOUT_MS);
        request.setBody(JSON.serialize(claudeRequest));

        Http http = new Http();
        HttpResponse response;

        try {
            response = http.send(request);
        } catch (System.CalloutException e) {
            throw new ClaudeClientException(
                'Anthropic callout failed: ' + e.getMessage()
            );
        }

        if (response.getStatusCode() < 200 ||
            response.getStatusCode() >= 300) {

            throw new ClaudeClientException(
                'Anthropic API returned HTTP ' +
                response.getStatusCode() +
                ': ' +
                response.getBody()
            );
        }

        try {
            return (ClaudeResponse) JSON.deserialize(
                response.getBody(),
                ClaudeResponse.class
            );
        } catch (System.JSONException e) {
            throw new ClaudeClientException(
                'Unable to deserialize Anthropic response: ' +
                e.getMessage()
            );
        }
    }

    public static ClaudeResponse analyzePdf(
        Blob pdfBlob,
        String prompt
    ) {
        if (pdfBlob == null) {
            throw new ClaudeClientException('PDF cannot be null.');
        }

        if (String.isBlank(prompt)) {
            throw new ClaudeClientException('Prompt cannot be empty.');
        }

        PromptConfig config = getActivePromptConfig();
        return analyzePdf(pdfBlob, prompt, config);
    }

    private static ClaudeResponse analyzePdf(
        Blob pdfBlob,
        String prompt,
        PromptConfig config
    ) {

        HttpRequest request = new HttpRequest();
        request.setEndpoint(NAMED_CREDENTIAL + MESSAGES_ENDPOINT);
        request.setMethod('POST');
        request.setHeader('Content-Type', 'application/json');
        request.setTimeout(TIMEOUT_MS);

        Map<String, Object> documentSource = new Map<String, Object>{
            'type' => 'base64',
            'media_type' => 'application/pdf',
            'data' => EncodingUtil.base64Encode(pdfBlob)
        };

        Map<String, Object> documentBlock = new Map<String, Object>{
            'type' => 'document',
            'source' => documentSource
        };

        Map<String, Object> textBlock = new Map<String, Object>{
            'type' => 'text',
            'text' => prompt
        };

        Map<String, Object> message = new Map<String, Object>{
            'role' => 'user',
            'content' => new List<Object>{
                documentBlock,
                textBlock
            }
        };

        Map<String, Object> requestBody = new Map<String, Object>{
            'model' => config.model,
            'max_tokens' => config.maxTokens,
            'messages' => new List<Object>{
                message
            }
        };

        request.setBody(JSON.serialize(requestBody));

        Http http = new Http();
        HttpResponse response;

        try {
            response = http.send(request);
        } catch (System.CalloutException e) {
            throw new ClaudeClientException(
                'Anthropic callout failed: ' + e.getMessage()
            );
        }

        if (response.getStatusCode() < 200 ||
            response.getStatusCode() >= 300) {

            throw new ClaudeClientException(
                'Anthropic API returned HTTP ' +
                response.getStatusCode() +
                ': ' +
                response.getBody()
            );
        }

        try {
            return (ClaudeResponse) JSON.deserialize(
                response.getBody(),
                ClaudeResponse.class
            );
        } catch (System.JSONException e) {
            throw new ClaudeClientException(
                'Unable to deserialize Anthropic response: ' +
                e.getMessage()
            );
        }
    }

    public static ContractAnalysisResult analyzeContract(
        Blob pdfBlob,
        ContractContext context
    ) {
        PromptConfig config = getActivePromptConfig();
        String prompt = buildContractAnalysisPrompt(context, config);

        ClaudeResponse response = analyzePdf(
            pdfBlob,
            prompt,
            config
        );

        if (response.stop_reason == 'max_tokens') {
            throw new ClaudeClientException(
                'Claude response was truncated because the maximum output token limit was reached.'
            );
        }

        String responseText = response.getText();

        if (String.isBlank(responseText)) {
            throw new ClaudeClientException(
                'Claude returned an empty response.'
            );
        }

        try {
            return (ContractAnalysisResult) JSON.deserialize(
                responseText,
                ContractAnalysisResult.class
            );
        } catch (System.JSONException e) {
            throw new ClaudeClientException(
                'Claude returned invalid JSON: ' +
                e.getMessage() +
                '. Response: ' +
                responseText
            );
        }
    }

    private static String buildContractAnalysisPrompt(
        ContractContext context,
        PromptConfig config
    ) {

        Map<String, Object> comparisonData = new Map<String, Object>{
            'Opportunity' => new Map<String, Object>{
                'accountName' => context.accountName,
                'amount' => context.amount,
                'discount' => context.discount,
                'paymentTerms' => context.paymentTerms,
                'noticePeriodDays' => context.noticePeriodDays
            },
            'Contract' => new Map<String, Object>{
                'contractStartDate' => context.contractStartDate,
                'contractEndDate' => context.contractEndDate,
                'contractTermMonths' => context.contractTermMonths
            }
        };

        String salesforceData = JSON.serializePretty(comparisonData);

        if (String.isBlank(config.prompt) ||
            !config.prompt.contains('{SALESFORCE_DATA}')) {
            throw new ClaudeClientException(
                'Active AI prompt configuration is missing the {SALESFORCE_DATA} placeholder.'
            );
        }

        return config.prompt.replace(
            '{SALESFORCE_DATA}',
            salesforceData
        );
    }

    private class PromptConfig {
        String prompt;
        String model;
        Integer maxTokens;
    }

    private static PromptConfig getActivePromptConfig() {
        List<SObject> configs = Database.query(
            'SELECT Prompt__c, Model__c, Max_Tokens__c ' +
            'FROM AI_Prompt_Config__mdt ' +
            'WHERE Active__c = true ' +
            'ORDER BY Version__c DESC NULLS LAST, DeveloperName ASC ' +
            'LIMIT 1'
        );

        if (configs.isEmpty()) {
            throw new ClaudeClientException(
                'No active AI prompt configuration was found.'
            );
        }

        SObject configRecord = configs[0];
        PromptConfig config = new PromptConfig();
        config.prompt = (String) configRecord.get('Prompt__c');
        config.model = (String) configRecord.get('Model__c');
        config.maxTokens = Integer.valueOf(
            String.valueOf(configRecord.get('Max_Tokens__c'))
        );
        return config;
    }

    // =========================================================
    // REQUEST DTOs
    // =========================================================

    public class ClaudeRequest {

        public String model;

        public Integer max_tokens;

        public List<ClaudeMessage> messages;
    }


    public class ClaudeMessage {

        public String role;

        public String content;

        public ClaudeMessage(String role, String content) {
            this.role = role;
            this.content = content;
        }
    }


    // =========================================================
    // RESPONSE DTOs
    // =========================================================

    public class ClaudeResponse {

        public String id;

        public String type;

        public String role;

        public String model;

        public List<ContentBlock> content;

        public String stop_reason;

        public Usage usage;


        /**
         * Convenience method.
         *
         * For now we expect text responses from Claude.
         */
        public String getText() {

            if (content == null) {
                return null;
            }

            List<String> texts = new List<String>();

            for (ContentBlock block : content) {

                if (block.type == 'text' &&
                    String.isNotBlank(block.text)) {

                    texts.add(block.text);
                }
            }

            return String.join(texts, '\n');
        }
    }


    public class ContentBlock {

        public String type;

        public String text;
    }


    public class Usage {

        public Integer input_tokens;

        public Integer output_tokens;
    }


    // =========================================================
    // EXCEPTION
    // =========================================================

    public class ClaudeClientException extends Exception {}
}