public with sharing class CaseCreatedRelayClient implements TB_IOutboxRelayClient {
    public void send(TB_OutboxRelayContext ctx) {
        Case evt = (Case) ctx.resolvedMessage;

        ctx.log('Processing Record: ' + evt.Id);
        // replace with carrier
        HttpRequest req = new HttpRequest();
        req.setEndpoint('https://google.com');
        req.setMethod('GET');
        Http http = new Http();
        HTTPResponse res = http.send(req);
        ctx.log('Status Code: ' + res.getStatusCode());
        if (res.getStatusCode() > 301) {
            throw new TestException('testing');
        }
    }

    public class TestException extends Exception {
    }
}