/**
 * WC — Parses JSON from Einstein Flex prompt for approver Slack summary.
 */
public with sharing class WC_ApproverSummaryLlmParser {
    public class ParsedSummary {
        public String summary;
        public String recommendedAction;
        public String confidenceNote;
        /** Integer 0–100 from model JSON; null if missing or invalid. */
        public Decimal riskScore;
    }

    public static ParsedSummary parse(String raw) {
        ParsedSummary p = new ParsedSummary();
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
            if (root.containsKey('summary') && root.get('summary') != null) {
                p.summary = String.valueOf(root.get('summary')).trim();
            }
            if (root.containsKey('recommendedAction') && root.get('recommendedAction') != null) {
                p.recommendedAction = String.valueOf(root.get('recommendedAction')).trim();
            }
            if (root.containsKey('confidenceNote') && root.get('confidenceNote') != null) {
                p.confidenceNote = String.valueOf(root.get('confidenceNote')).trim();
            }
            if (root.containsKey('riskScore') && root.get('riskScore') != null) {
                p.riskScore = parseRiskScore(root.get('riskScore'));
            }
        } catch (Exception e) {
            /* leave partial */
        }
        return p;
    }

    private static Decimal parseRiskScore(Object obj) {
        if (obj == null) {
            return null;
        }
        Decimal d;
        try {
            if (obj instanceof Decimal || obj instanceof Integer || obj instanceof Long || obj instanceof Double) {
                d = Decimal.valueOf(String.valueOf(obj));
            } else {
                String s = String.valueOf(obj).trim();
                if (String.isBlank(s)) {
                    return null;
                }
                d = Decimal.valueOf(s);
            }
        } catch (Exception e) {
            return null;
        }
        if (d < 0) {
            return 0;
        }
        if (d > 100) {
            return 100;
        }
        return d;
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
