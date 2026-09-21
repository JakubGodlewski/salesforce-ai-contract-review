public class ContractAnalysisResult {

    public String overallStatus;
    public String summary;
    public List<Comparison> comparisons;

public class Comparison {
    public String field;
    public String salesforceSource;
    public String salesforceValue;

    public String contractValue;
    public String status;
    public String severity;
    public Decimal confidence;

    public String contractEvidence;
    public String explanation;
}
}