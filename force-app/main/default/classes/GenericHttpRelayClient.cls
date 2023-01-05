
/**
 * A basic Http relay that can be used for many simple use cases. 
 * Will send the resolvedMessage (or raw Message__c) in body.  
 * Config Params:
 * - "uri" (required): URL or Named crediential
 * - "method": http method (GET, POST, PUT, DELETE, etc). Defaults to POST
 * 
 * Example:
  {
     "uri": "CALLOUT:MyServiceEndpoint"
     "method": "PUT"
  }
 */
public class GenericHttpRelayClient implements IOutboxRelayClient {
    public void send(OutboxRelayContext ctx) {
        Object bodyObj = ctx.resolvedMessage != null ? ctx.resolvedMessage : ctx.outbox.Outbox_Message__r.Message__c;
        String bodyStr = bodyObj instanceOf String ? String.valueof(bodyObj) : JSON.serialize(bodyObj);
        String uri = String.valueof(ctx.subscriptionConfig.get('uri'));
        String method = ctx.subscriptionConfig.containsKey('method') ? String.valueof(ctx.subscriptionConfig.get('method')) : 'POST';
        
        ctx.log('Processing Record: ' + ctx.outbox.Id);
        ctx.log(new String[]{
            method, uri, bodyStr
        });
        // replace with carrier
        HttpRequest req = new HttpRequest();
        req.setEndpoint(uri);
        req.setBody(bodyStr);
        req.setMethod(method);
        Http http = new Http();
        HTTPResponse res = http.send(req);
        ctx.log('Status Code: ' + res.getStatusCode());
        if (res.getStatusCode() > 300) {
          throw new HttpRelayException('Request Failed with status ' + res.getStatusCode() + '. Response Body: ' + res.getBody());
        }
        ctx.log('Success. Response:' + req.getBody());
      }

    public class HttpRelayException extends Exception {
    }
}

