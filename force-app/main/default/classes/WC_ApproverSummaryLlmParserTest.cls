/**
 * WC — Tests for WC_ApproverSummaryLlmParser.
 */
@isTest
private class WC_ApproverSummaryLlmParserTest {
    @isTest
    static void parse_full_json() {
        WC_ApproverSummaryLlmParser.ParsedSummary p = WC_ApproverSummaryLlmParser.parse(
            '{"summary":"Line one.","recommendedAction":"Approve","confidenceNote":"ok","riskScore":72}'
        );
        System.assertEquals('Line one.', p.summary);
        System.assertEquals('Approve', p.recommendedAction);
        System.assertEquals('ok', p.confidenceNote);
        System.assertEquals(72, p.riskScore);
    }

    @isTest
    static void parse_with_fences() {
        WC_ApproverSummaryLlmParser.ParsedSummary p = WC_ApproverSummaryLlmParser.parse(
            '```json\n{"summary":"x","recommendedAction":"Review","confidenceNote":""}\n```'
        );
        System.assertEquals('x', p.summary);
        System.assertEquals('Review', p.recommendedAction);
    }

    @isTest
    static void parse_blank() {
        WC_ApproverSummaryLlmParser.ParsedSummary p = WC_ApproverSummaryLlmParser.parse('');
        System.assertEquals(null, p.summary);
    }

    @isTest
    static void parse_risk_score_clamped() {
        WC_ApproverSummaryLlmParser.ParsedSummary hi = WC_ApproverSummaryLlmParser.parse(
            '{"summary":"x","recommendedAction":"Review","confidenceNote":"","riskScore":150}'
        );
        System.assertEquals(100, hi.riskScore);
        WC_ApproverSummaryLlmParser.ParsedSummary lo = WC_ApproverSummaryLlmParser.parse(
            '{"summary":"x","recommendedAction":"Review","confidenceNote":"","riskScore":-5}'
        );
        System.assertEquals(0, lo.riskScore);
    }
}
