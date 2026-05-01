/**
 * WC — Parses JSON from Einstein Prompt Builder output for part suggestion.
 */
public with sharing class WC_SuggestPartLlmParser {
    public class ParsedSuggestion {
        public Boolean matchFound;
        public String productId;
        public String productCode;
        public String productName;
    }

    public static ParsedSuggestion parse(String raw) {
        ParsedSuggestion p = new ParsedSuggestion();
        p.matchFound = false;
        if (String.isBlank(raw)) {
            return p;
        }
        String text = raw.trim();
        text = stripMarkdownFences(text);
        Integer start = text.indexOf('{');
        Integer endIdx = text.lastIndexOf('}');
        if (start < 0 || endIdx <= start) {
            return p;
        }
        String jsonSlice = text.substring(start, endIdx + 1);
        try {
            Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(jsonSlice);
            Object mf = root.get('matchFound');
            if (mf instanceof Boolean) {
                p.matchFound = (Boolean) mf;
            } else if (mf != null) {
                p.matchFound = Boolean.valueOf(String.valueOf(mf));
            }
            if (root.containsKey('productId') && root.get('productId') != null) {
                p.productId = String.valueOf(root.get('productId')).trim();
            }
            if (root.containsKey('productCode') && root.get('productCode') != null) {
                p.productCode = String.valueOf(root.get('productCode')).trim();
            }
            if (root.containsKey('productName') && root.get('productName') != null) {
                p.productName = String.valueOf(root.get('productName')).trim();
            }
        } catch (Exception e) {
            p.matchFound = false;
        }
        return p;
    }

    private static String stripMarkdownFences(String s) {
        if (s.startsWith('```')) {
            Integer nl = s.indexOf('\n');
            if (nl > 0) {
                s = s.substring(nl + 1);
            }
            Integer close = s.lastIndexOf('```');
            if (close > 0) {
                s = s.substring(0, close);
            }
        }
        return s.trim();
    }
}
