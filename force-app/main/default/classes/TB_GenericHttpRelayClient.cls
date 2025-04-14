/**
 * A basic Http relay that can be used for many simple use cases.
 * Will send the resolvedMessage (or raw Message__c) in body.
 * Config Params:
 * - "uri" (required): URL or Named credential
 * - "method": http method (GET, POST, PUT, DELETE, etc). Defaults to POST
 * - "headers": A map of headers to send with the request. Can use Named Credentials parameters binding syntax
 * Example:
  {
     "uri": "CALLOUT:MyServiceEndpoint"
     "method": "PUT"
     "headers": {
        "Content-Type": "application/json",
        "Authorization": "Bearer {!$Credential.Token}"
     }
  }
 */
public class TB_GenericHttpRelayClient implements TB_IOutboxRelayClient {
    public void send(TB_OutboxRelayContext ctx) {
        Object bodyObj = ctx.resolvedMessage != null ? ctx.resolvedMessage : ctx.outbox.Outbox_Message__r.Message__c;
        String bodyStr = bodyObj instanceof String ? String.valueof(bodyObj) : JSON.serialize(bodyObj);
        String uri = String.valueof(ctx.subscriptionConfig.get('uri'));
        String method = ctx.subscriptionConfig.containsKey('method')
            ? String.valueof(ctx.subscriptionConfig.get('method'))
            : 'POST';

        ctx.log('Processing Record: ' + ctx.outbox.Id);
        ctx.log(new List<String>{ method, uri, bodyStr });
        // replace with carrier
        HttpRequest req = new HttpRequest();

        Map<String, Object> headers = (Map<String, Object>) ctx.subscriptionConfig.get('headers');
        if (headers != null) {
            for (String header : headers.keySet()) {
                req.setHeader(header, String.valueOf(headers.get(header)));
            }
        }


        ctx.log('body: ' + bodyStr);

        req.setEndpoint(uri);
        req.setBody(bodyStr);
        req.setMethod(method);
        Http http = new Http();
        HTTPResponse res = http.send(req);
        ctx.setResult(new GenericRelayResult(res));
        ctx.log('Status Code: ' + res.getStatusCode());
        if (res.getStatusCode() > 300) {
            throw new HttpRelayException(
                'Request Failed with status ' + res.getStatusCode() + '. Response Body: ' + res.getBody()
            );
        }
        ctx.log('Success. Response:' + res.getBody());
    }

    public class HttpRelayException extends Exception {
    }

    public class GenericRelayResult {
        public HttpResponseResult response;
        //TODO: Add request details?
        public GenericRelayResult(HttpResponse res) {
            response = new HttpResponseResult(res);
        }
    }

    public class HttpResponseResult {
        public Integer statusCode;
        public string status;
        public String body;
        //TODO: Add headers?
        public HttpResponseResult(HttpResponse res){
            this.statusCode = res.getStatusCode();
            this.status = res.getStatus();
            this.body = res.getBody();
        }
    }
}