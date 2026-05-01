public class AuthTokenService {
    
    private static final String TOKEN_ENDPOINT = URL.getOrgDomainUrl().toExternalForm() + '/services/oauth2/token';
    private static final String CLIENT_ID = '3MVG91oqviqJKoEGm9y67D6nFhqHBea8FL9GDLZ2Kh3xG6q6olnkwQoxmrY.4kW9ULzI3_9qGAY3nfxMLcHQW';
    private static final String CLIENT_SECRET = 'DB4B4702FA99D39524F9B200092704246F702E49E634D6120C57F023A785603E';
    private static final String USERNAME = 'epic.9aa2b80f7f87@orgfarm.salesforce.com';
    
    // Cache token to avoid repeated auth calls
    private static String cachedToken;
    
    public static String getToken() {
        if (cachedToken != null) {
            return cachedToken;
        }
        
        // Option 1: JWT Bearer Flow (Recommended)
        //cachedToken = getTokenViaJWT();
        
        // Option 2: Client Credentials Flow
         cachedToken = getTokenViaClientCredentials();
        System.debug(cachedToken);
        return cachedToken;
    }
    
    private static String getTokenViaClientCredentials() {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(TOKEN_ENDPOINT);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/x-www-form-urlencoded');
        req.setBody(
            'grant_type=client_credentials' +
            '&client_id=' + EncodingUtil.urlEncode(CLIENT_ID, 'UTF-8') +
            '&client_secret=' + EncodingUtil.urlEncode(CLIENT_SECRET, 'UTF-8')
        );
        
        Http http = new Http();
        HttpResponse res = http.send(req);
        System.debug(res);
        Map<String, Object> responseMap = 
            (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        
        return (String) responseMap.get('access_token');
    }
    
    private static String getTokenViaJWT() {
        // If you have a JWT certificate configured
        // This is more secure for production
        Auth.JWT jwt = new Auth.JWT();
        jwt.setSub(USERNAME);
        jwt.setAud(TOKEN_ENDPOINT);
        jwt.setIss(CLIENT_ID);
        
        Auth.JWS jws = new Auth.JWS(jwt, 'YOUR_CERTIFICATE_NAME');
        Auth.JWTBearerTokenExchange exchange = 
            new Auth.JWTBearerTokenExchange(TOKEN_ENDPOINT, jws);
        
        return exchange.getAccessToken();
    }
}