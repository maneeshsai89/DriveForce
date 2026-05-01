/**
 * WC — Tests for WC_SuggestPartLlmParser (no Einstein LLM calls).
 */
@isTest
private class WC_SuggestPartLlmParserTest {
    @isTest
    static void parse_plain_json() {
        WC_SuggestPartLlmParser.ParsedSuggestion p = WC_SuggestPartLlmParser.parse(
            '{"matchFound":true,"productId":"01t000000000000AAA","productCode":"SKU-1"}'
        );
        System.assertEquals(true, p.matchFound);
        System.assertEquals('01t000000000000AAA', p.productId);
        System.assertEquals('SKU-1', p.productCode);
    }

    @isTest
    static void parse_json_in_markdown_fence() {
        WC_SuggestPartLlmParser.ParsedSuggestion p = WC_SuggestPartLlmParser.parse(
            'Here is the result:\n```json\n{"matchFound":false}\n```\n'
        );
        System.assertEquals(false, p.matchFound);
    }

    @isTest
    static void parse_invalid_returns_no_match() {
        WC_SuggestPartLlmParser.ParsedSuggestion p = WC_SuggestPartLlmParser.parse('not json at all');
        System.assertEquals(false, p.matchFound);
    }
}
