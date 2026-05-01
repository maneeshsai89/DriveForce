/**
 * WC — Slack Interactivity (Block Kit buttons) → Salesforce.
 * POST body: application/x-www-form-urlencoded with `payload` (JSON) or JSON url_verification.
 * Verifies X-Slack-Signature using Slack_Signing_Secret__c on WC_Slack_Approval_Config__mdt (Default).
 * For wc_approve_claim / wc_reject_claim calls WC_SlackClaimApprovalService (Guest users cannot Run Flows).
 *
 * Expose via public HTTPS: e.g. Experience / Salesforce Site → add this class to Guest user’s
 * enabled Apex classes; Request URL = https://{site}/services/apexrest/wc/slack/interactivity
 *
 * Legacy Sites / some gateways: application/x-www-form-urlencoded may arrive with an empty
 * requestBody (body parsed into RestRequest.params), or a requestBody that does not match Slack’s
 * raw POST. Signing merges requestBody plus param-derived reconstructions. If {@code payload} is
 * still percent-encoded ({@code %7B...}), it must not be urlEncode’d again. + vs %20 and %-hex
 * case variants are also tried.
 */
@RestResource(urlMapping='/wc/slack/interactivity')
global with sharing class WC_SlackInteractivityRest {
    private static final String CMDT_DEFAULT = 'Default';
    private static final String ACTION_APPROVE = 'wc_approve_claim';
    private static final String ACTION_REJECT = 'wc_reject_claim';
    private static final Integer MAX_TIMESTAMP_SKEW_SEC = 300;

    @HttpPost
    global static void handlePost() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        try {
            res.addHeader('Content-Type', 'application/json; charset=UTF-8');

            String rawBody = getSlackRequestBodyForSigning(req);
        System.debug(
            LoggingLevel.DEBUG,
            'WC_SLACK_INTERACT POST uri=' +
                (req.requestURI == null ? '' : req.requestURI) +
                ' bodyLen=' +
                rawBody.length() +
                ' bodySource=' +
                describeBodySource(req)
        );
        WC_Slack_Approval_Config__mdt slackCfg = getDefaultSlackConfig();
        String signingSecret = slackCfg == null || slackCfg.Slack_Signing_Secret__c == null
            ? null
            : slackCfg.Slack_Signing_Secret__c.trim();
        Boolean skipSignatureVerify = slackCfg != null && slackCfg.Skip_Slack_Signature_Verification__c == true;

        if (!Test.isRunningTest()) {
            if (skipSignatureVerify) {
                System.debug(
                    LoggingLevel.ERROR,
                    'WC_SLACK_INTERACT Skip_Slack_Signature_Verification__c=true — HMAC not checked; use only in sandbox, never production'
                );
            } else {
                if (String.isBlank(signingSecret)) {
                    System.debug(LoggingLevel.ERROR, 'WC_SLACK_INTERACT signing_secret_missing (WC_Slack_Approval_Config__mdt Default)');
                    res.statusCode = 503;
                    res.responseBody = Blob.valueOf(
                        '{"ok":false,"error":"signing_secret_missing","hint":"Set Slack_Signing_Secret__c on WC_Slack_Approval_Config__mdt Default"}'
                    );
                    return;
                }
                if (!verifySlackSignature(req, signingSecret)) {
                    System.debug(
                        LoggingLevel.WARN,
                        'WC_SLACK_INTERACT invalid_signature (Signing Secret + raw body must match Slack; or set Skip_Slack_Signature_Verification__c in sandbox only)'
                    );
                    res.statusCode = 401;
                    res.responseBody = Blob.valueOf('{"ok":false,"error":"invalid_signature"}');
                    return;
                }
                System.debug(LoggingLevel.DEBUG, 'WC_SLACK_INTERACT signature_ok');
            }
        }

        Object parsed = parseIncomingBody(rawBody);
        if (parsed instanceof Map<String, Object>) {
            Map<String, Object> root = (Map<String, Object>) parsed;
            String type = (String) root.get('type');
            if ('url_verification'.equals(type)) {
                String challenge = (String) root.get('challenge');
                if (String.isNotBlank(challenge)) {
                    System.debug(LoggingLevel.DEBUG, 'WC_SLACK_INTERACT url_verification (json body) challenge_len=' + challenge.length());
                    res.statusCode = 200;
                    res.responseBody = Blob.valueOf(JSON.serialize(new Map<String, String>{ 'challenge' => challenge }));
                    return;
                }
            }
        }

        Map<String, Object> payloadMap = extractPayloadMap(parsed, rawBody, req);
        if (payloadMap == null || payloadMap.isEmpty()) {
            System.debug(LoggingLevel.WARN, 'WC_SLACK_INTERACT unrecognized_payload (no payload= or empty)');
            res.statusCode = 400;
            res.responseBody = Blob.valueOf('{"ok":false,"error":"unrecognized_payload"}');
            return;
        }

        String pType = (String) payloadMap.get('type');
        if ('url_verification'.equals(pType)) {
            String challenge = (String) payloadMap.get('challenge');
            if (String.isNotBlank(challenge)) {
                System.debug(LoggingLevel.DEBUG, 'WC_SLACK_INTERACT url_verification (form payload) challenge_len=' + challenge.length());
                res.statusCode = 200;
                res.responseBody = Blob.valueOf(JSON.serialize(new Map<String, String>{ 'challenge' => challenge }));
                return;
            }
        }

        if (!'block_actions'.equals(pType)) {
            System.debug(LoggingLevel.DEBUG, 'WC_SLACK_INTERACT ignore type=' + pType);
            res.statusCode = 200;
            res.responseBody = Blob.valueOf('{"ok":true}');
            return;
        }

            processBlockActions(payloadMap);
            System.debug(LoggingLevel.DEBUG, 'WC_SLACK_INTERACT response 200 ok');
            res.statusCode = 200;
            res.responseBody = Blob.valueOf('{"ok":true}');
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'WC_SLACK_INTERACT handlePost: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, e);
            res.statusCode = 200;
            res.responseBody = Blob.valueOf('{"ok":true}');
        }
    }

    private static Object parseIncomingBody(String rawBody) {
        if (String.isBlank(rawBody)) {
            return null;
        }
        String trimmed = rawBody.trim();
        if (trimmed.startsWith('{')) {
            try {
                return JSON.deserializeUntyped(trimmed);
            } catch (Exception e) {
                return null;
            }
        }
        return null;
    }

    /**
     * Best-effort body string for parsing/logging when requestBody is empty (use params in extractPayloadMap too).
     */
    private static String getSlackRequestBodyForSigning(RestRequest req) {
        if (req.requestBody != null && req.requestBody.size() > 0) {
            return req.requestBody.toString();
        }
        String payloadParam = getPayloadParam(req);
        if (String.isNotBlank(payloadParam)) {
            return buildPayloadFormBodyFromParam(payloadParam);
        }
        return '';
    }

    /**
     * Form body Slack signed: {@code payload=<url-encoded-json>}.
     * If the gateway still has percent-encoded JSON ({@code %7B...}), do not urlEncode again (would turn {@code %} into {@code %25}).
     */
    private static String buildPayloadFormBodyFromParam(String payloadParam) {
        if (String.isBlank(payloadParam)) {
            return '';
        }
        String t = stripBom(payloadParam.trim());
        if (t.startsWith('{')) {
            return 'payload=' + EncodingUtil.urlEncode(t, 'UTF-8');
        }
        if (t.startsWith('%7B') || t.startsWith('%7b')) {
            return 'payload=' + t;
        }
        return 'payload=' + EncodingUtil.urlEncode(t, 'UTF-8');
    }

    /**
     * Candidate POST bodies for HMAC (v0:timestamp:body). Tries every plausible string:
     * raw requestBody (if any) and all param-derived reconstructions. Some hosts populate
     * requestBody with a value that does not match Slack’s raw POST, so we never stop after one.
     */
    private static List<String> slackSigningBodyCandidates(RestRequest req) {
        List<String> candidates = new List<String>();
        if (req.requestBody != null && req.requestBody.size() > 0) {
            addSigningBodyVariants(candidates, req.requestBody.toString());
        }
        String payloadParam = getPayloadParam(req);
        if (String.isNotBlank(payloadParam)) {
            addPayloadParamSigningCandidates(candidates, payloadParam);
        }
        if (req.params != null && !req.params.isEmpty()) {
            addFormBodyCandidatesFromParams(req, candidates);
        }
        return candidates;
    }

    /**
     * Slack’s raw POST may be {@code k1=v1&k2=v2} with a specific key order. When {@code requestBody} is empty,
     * try sorted keys and Map iteration order (insertion order) for URL-encoded pairs.
     */
    /**
     * Slack signs the URL-encoded form of the JSON they send. After deserialize→serialize, Apex may emit
     * a different minified/key order than the original bytes — that string can match Slack’s HMAC when
     * {@code urlEncode(trimmed)} does not.
     */
    private static void addCanonicalSerializedPayloadSigningCandidates(List<String> candidates, String trimmedJson) {
        try {
            Object root = JSON.deserializeUntyped(trimmedJson);
            String canonical = JSON.serialize(root);
            String rfc = 'payload=' + EncodingUtil.urlEncode(canonical, 'UTF-8');
            addSigningBodyVariants(candidates, rfc);
            String unreserve = rfc.replace('%2A', '*').replace('%7E', '~');
            addSigningBodyVariants(candidates, unreserve);
        } catch (Exception e) {
            // ignore
        }
    }

    private static void addFormBodyCandidatesFromParams(RestRequest req, List<String> candidates) {
        List<String> sortedKeys = new List<String>();
        for (String k : req.params.keySet()) {
            if (k != null) {
                sortedKeys.add(k);
            }
        }
        sortedKeys.sort();
        List<String> sortedPairs = new List<String>();
        for (String k : sortedKeys) {
            String v = req.params.get(k);
            sortedPairs.add(EncodingUtil.urlEncode(k, 'UTF-8') + '=' + EncodingUtil.urlEncode(v == null ? '' : v, 'UTF-8'));
        }
        addSigningBodyVariants(candidates, String.join(sortedPairs, '&'));

        List<String> insertPairs = new List<String>();
        for (String k : req.params.keySet()) {
            if (k == null) {
                continue;
            }
            String v = req.params.get(k);
            insertPairs.add(EncodingUtil.urlEncode(k, 'UTF-8') + '=' + EncodingUtil.urlEncode(v == null ? '' : v, 'UTF-8'));
        }
        addSigningBodyVariants(candidates, String.join(insertPairs, '&'));
    }

    private static void addPayloadParamSigningCandidates(List<String> candidates, String p) {
        if (String.isBlank(p)) {
            return;
        }
        String trimmed = stripBom(p.trim());
        if (trimmed.startsWith('{')) {
            String rfc = 'payload=' + EncodingUtil.urlEncode(trimmed, 'UTF-8');
            addSigningBodyVariants(candidates, rfc);
            String unreserve = rfc.replace('%2A', '*').replace('%7E', '~');
            addSigningBodyVariants(candidates, unreserve);
            addCanonicalSerializedPayloadSigningCandidates(candidates, trimmed);
            return;
        }
        if (trimmed.startsWith('%7B') || trimmed.startsWith('%7b')) {
            String asSent = 'payload=' + trimmed;
            addSigningBodyVariants(candidates, asSent);
            String unreserve = asSent.replace('%2A', '*').replace('%7E', '~');
            addSigningBodyVariants(candidates, unreserve);
            return;
        }
        String rfc = 'payload=' + EncodingUtil.urlEncode(trimmed, 'UTF-8');
        addSigningBodyVariants(candidates, rfc);
        String unreserve = rfc.replace('%2A', '*').replace('%7E', '~');
        addSigningBodyVariants(candidates, unreserve);
        addSigningBodyVariants(candidates, 'payload=' + trimmed);
    }

    /**
     * Adds RFC3986 form body plus common alternates: + for spaces, upper/lower hex in %-escapes.
     */
    private static void addSigningBodyVariants(List<String> candidates, String base) {
        addUnique(candidates, base);
        addUnique(candidates, base.replace('%20', '+'));
        addUnique(candidates, normalizePercentHexDigits(base, true));
        addUnique(candidates, normalizePercentHexDigits(base, false));
        String plusSpaces = base.replace('%20', '+');
        addUnique(candidates, normalizePercentHexDigits(plusSpaces, true));
        addUnique(candidates, normalizePercentHexDigits(plusSpaces, false));
    }

    /**
     * Normalizes %XX sequences to upper- or lower-case hex digits (Slack raw body may differ from Apex urlEncode).
     * Uses a manual scan — Apex Pattern/Matcher on long strings has been observed to match zero %XX sequences,
     * which collapses all variants to one candidate and yields triedCandidates=1.
     */
    private static String normalizePercentHexDigits(String s, Boolean upperHex) {
        if (String.isBlank(s)) {
            return s;
        }
        String out = '';
        Integer n = s.length();
        Integer i = 0;
        while (i < n) {
            if (i + 2 < n && s.charAt(i) == 37 && isHexChar(s.charAt(i + 1)) && isHexChar(s.charAt(i + 2))) {
                String pair = s.substring(i + 1, i + 3);
                out += '%' + (upperHex ? pair.toUpperCase() : pair.toLowerCase());
                i += 3;
            } else {
                out += s.substring(i, i + 1);
                i++;
            }
        }
        return out;
    }

    private static Boolean isHexChar(Integer code) {
        return (code >= 48 && code <= 57) || (code >= 65 && code <= 70) || (code >= 97 && code <= 102);
    }

    /** Strip UTF-8 BOM so {@code startsWith('{')} and signing branches match decoded JSON. */
    private static String stripBom(String s) {
        if (String.isBlank(s)) {
            return s;
        }
        if (s.charAt(0) == 65279) {
            return s.length() > 1 ? s.substring(1) : '';
        }
        return s;
    }

    private static void addUnique(List<String> outList, String candidate) {
        if (String.isBlank(candidate)) {
            return;
        }
        for (String existing : outList) {
            if (existing != null && existing.equals(candidate)) {
                return;
            }
        }
        outList.add(candidate);
    }

    private static String describeBodySource(RestRequest req) {
        if (req.requestBody != null && req.requestBody.size() > 0) {
            return 'requestBody';
        }
        if (String.isNotBlank(getPayloadParam(req))) {
            return 'rebuilt_from_params';
        }
        return 'empty';
    }

    private static Map<String, Object> extractPayloadMap(Object parsedRoot, String rawBody, RestRequest req) {
        if (parsedRoot instanceof Map<String, Object>) {
            Map<String, Object> root = (Map<String, Object>) parsedRoot;
            if (root.containsKey('actions') || 'block_actions'.equals((String) root.get('type'))) {
                return root;
            }
        }
        Map<String, String> form = parseFormUrlEncoded(rawBody);
        String payloadStr = form.get('payload');
        if (String.isBlank(payloadStr)) {
            payloadStr = getPayloadParam(req);
        }
        if (String.isBlank(payloadStr)) {
            return null;
        }
        try {
            Object o = JSON.deserializeUntyped(payloadStr);
            return o instanceof Map<String, Object> ? (Map<String, Object>) o : null;
        } catch (Exception e) {
            return null;
        }
    }

    private static void processBlockActions(Map<String, Object> payloadMap) {
        Object actionsObj = payloadMap.get('actions');
        if (!(actionsObj instanceof List<Object>)) {
            System.debug(LoggingLevel.DEBUG, 'WC_SLACK_INTERACT block_actions: no actions list');
            return;
        }
        List<Object> actions = (List<Object>) actionsObj;
        if (actions.isEmpty()) {
            System.debug(LoggingLevel.DEBUG, 'WC_SLACK_INTERACT block_actions: empty actions');
            return;
        }
        Object first = actions[0];
        if (!(first instanceof Map<String, Object>)) {
            System.debug(LoggingLevel.DEBUG, 'WC_SLACK_INTERACT block_actions: first action not a map');
            return;
        }
        Map<String, Object> action = (Map<String, Object>) first;
        String actionId = (String) action.get('action_id');
        String value = (String) action.get('value');
        System.debug(
            LoggingLevel.DEBUG,
            'WC_SLACK_INTERACT action_id=' + actionId + ' value_len=' + (value == null ? 0 : value.length())
        );

        if (ACTION_APPROVE.equals(actionId) || ACTION_REJECT.equals(actionId)) {
            String decision = ACTION_APPROVE.equals(actionId) ? 'Approve' : 'Reject';
            String claimId = parseClaimIdFromValue(value, decision);
            if (String.isBlank(claimId)) {
                System.debug(LoggingLevel.WARN, 'WC_SLACK_INTERACT could not parse claimId from value');
                return;
            }
            String responseUrl = (String) payloadMap.get('response_url');
            String slackMessageJson = null;
            if (payloadMap.containsKey('message')) {
                try {
                    slackMessageJson = JSON.serialize(payloadMap.get('message'));
                } catch (Exception e) {
                    // ignore
                }
            }
            System.debug(LoggingLevel.DEBUG, 'WC_SLACK_INTERACT enqueue approval claimId=' + claimId + ' decision=' + decision);
            if (Test.isRunningTest()) {
                WC_SlackClaimApprovalService.applySlackDecision(claimId, decision);
            } else {
                WC_SlackClaimApprovalService.applySlackDecisionAsync(claimId, decision, responseUrl, slackMessageJson);
            }
            return;
        }
        System.debug(LoggingLevel.DEBUG, 'WC_SLACK_INTERACT action_id not approve/reject, skipped');
    }

    /**
     * Button value from WC_BuildSlackApproverBlocksAction: "{claimId}|Approve" / "{claimId}|Reject".
     */
    private static String parseClaimIdFromValue(String value, String decision) {
        if (String.isBlank(value)) {
            return null;
        }
        String suffix = '|' + decision;
        if (value.endsWithIgnoreCase(suffix)) {
            return value.substring(0, value.length() - suffix.length());
        }
        Integer pipe = value.lastIndexOf('|');
        if (pipe > 0) {
            return value.substring(0, pipe);
        }
        return value;
    }

    private static Map<String, String> parseFormUrlEncoded(String rawBody) {
        Map<String, String> out = new Map<String, String>();
        if (String.isBlank(rawBody)) {
            return out;
        }
        for (String part : rawBody.split('&')) {
            Integer eq = part.indexOf('=');
            if (eq <= 0) {
                continue;
            }
            try {
                String k = EncodingUtil.urlDecode(part.substring(0, eq), 'UTF-8');
                String v = EncodingUtil.urlDecode(part.substring(eq + 1), 'UTF-8');
                out.put(k, v);
            } catch (Exception e) {
                System.debug(LoggingLevel.DEBUG, 'WC_SLACK_INTERACT parseFormUrlEncoded skip part: ' + e.getMessage());
            }
        }
        return out;
    }

    private static Boolean verifySlackSignature(RestRequest req, String signingSecret) {
        String ts = getHeaderIgnoreCase(req, 'X-Slack-Request-Timestamp');
        String sig = getHeaderIgnoreCase(req, 'X-Slack-Signature');
        if (String.isBlank(ts) || String.isBlank(sig)) {
            System.debug(
                LoggingLevel.WARN,
                'WC_SLACK_INTERACT signature_headers_missing hasTs=' +
                    String.valueOf(String.isNotBlank(ts)) +
                    ' hasSig=' +
                    String.valueOf(String.isNotBlank(sig))
            );
            return false;
        }
        ts = ts.trim();
        sig = sig.trim().toLowerCase();
        try {
            Long t = Long.valueOf(ts);
            Long nowSec = System.now().getTime() / 1000;
            Long skew = Math.abs(nowSec - t);
            if (skew > MAX_TIMESTAMP_SKEW_SEC) {
                System.debug(
                    LoggingLevel.WARN,
                    'WC_SLACK_INTERACT signature_timestamp_skew slackEpochSec=' +
                        t +
                        ' nowEpochSec=' +
                        nowSec +
                        ' skewSec=' +
                        skew +
                        ' maxSec=' +
                        MAX_TIMESTAMP_SKEW_SEC
                );
                return false;
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'WC_SLACK_INTERACT signature_timestamp_invalid: ' + e.getMessage());
            return false;
        }
        List<String> bodies = slackSigningBodyCandidates(req);
        if (bodies.isEmpty()) {
            return false;
        }
        if (bodies.size() == 1 && String.isNotBlank(getPayloadParam(req)) && (req.requestBody == null || req.requestBody.size() == 0)) {
            System.debug(
                LoggingLevel.WARN,
                'WC_SLACK_INTERACT signing_single_body_candidate (encoding variants should not collapse; deploy latest WC_SlackInteractivityRest)'
            );
        }
        Integer idx = 0;
        for (String rawBody : bodies) {
            idx++;
            String baseString = 'v0:' + ts + ':' + rawBody;
            Blob mac = Crypto.generateMac(
                'HmacSHA256',
                Blob.valueOf(baseString),
                Blob.valueOf(signingSecret)
            );
            String hex = EncodingUtil.convertToHex(mac).toLowerCase();
            String expected = 'v0=' + hex;
            if (constantTimeEquals(expected, sig)) {
                System.debug(
                    LoggingLevel.DEBUG,
                    'WC_SLACK_INTERACT signature_ok candidateIndex=' + idx + '/' + bodies.size() + ' bodyLen=' + rawBody.length()
                );
                return true;
            }
        }
        System.debug(
            LoggingLevel.DEBUG,
            'WC_SLACK_INTERACT signature mismatch triedCandidates=' +
                bodies.size() +
                ' requestBodyBytes=' +
                (req.requestBody == null ? 0 : req.requestBody.size()) +
                ' hasPayloadParam=' +
                String.valueOf(String.isNotBlank(getPayloadParam(req)))
        );
        return false;
    }

    /** RestRequest header map keys may not match Slack’s casing; Slack sends X-Slack-Signature, etc. */
    private static String getHeaderIgnoreCase(RestRequest req, String name) {
        if (req == null || req.headers == null || String.isBlank(name)) {
            return null;
        }
        String want = name.trim().toLowerCase();
        for (String k : req.headers.keySet()) {
            if (k != null && k.toLowerCase().equals(want)) {
                return req.headers.get(k);
            }
        }
        return null;
    }

    /** Form param name may vary in casing; Slack sends {@code payload}. */
    private static String getPayloadParam(RestRequest req) {
        if (req == null || req.params == null) {
            return null;
        }
        for (String k : req.params.keySet()) {
            if (k != null && k.equalsIgnoreCase('payload')) {
                return req.params.get(k);
            }
        }
        return null;
    }

    private static Boolean constantTimeEquals(String a, String b) {
        if (a == null || b == null || a.length() != b.length()) {
            return false;
        }
        Integer x = 0;
        for (Integer i = 0; i < a.length(); i++) {
            x |= a.charAt(i) ^ b.charAt(i);
        }
        return x == 0;
    }

    private static WC_Slack_Approval_Config__mdt getDefaultSlackConfig() {
        List<WC_Slack_Approval_Config__mdt> rows = [
            SELECT Slack_Signing_Secret__c, Skip_Slack_Signature_Verification__c
            FROM WC_Slack_Approval_Config__mdt
            WHERE DeveloperName = :CMDT_DEFAULT
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0];
    }

}