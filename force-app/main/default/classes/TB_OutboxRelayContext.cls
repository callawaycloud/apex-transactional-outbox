public class TB_OutboxRelayContext {
    public Object resolvedMessage;
    public TB_Subscription_Outbox__c outbox;
    public DateTime sentTime;
    public Map<String, Object> subscriptionConfig;

    public TB_OutboxRelayContext(
        TB_Subscription_Outbox__c outbox,
        Object resolvedMessage,
        Map<String, Object> subscriptionConfig
    ) {
        this.outbox = outbox;
        this.resolvedMessage = resolvedMessage;
        this.subscriptionConfig = subscriptionConfig;

        //TODO: Should this always reset? Or should we truncate the oldest lines? (split on \n & reverse before saving)
        if (this.outbox.Log__c == null) {
            this.outbox.Log__c = '';
        }
        if (this.outbox.Relay_Attempts__c == null) {
            this.outbox.Relay_Attempts__c = 0;
        }
    }

    public void setAttempt() {
        outbox.Last_Attempt__c = Datetime.Now();
        outbox.Relay_Attempts__c++;
    }

    public void log(Object trace) {
        outbox.Log__c += System.now() + ': ' + trace.toString() + '\n';
    }

    //these should always be set by Relay, but we could allow the clients to access them for more flexiblity
    public void setError(Exception e) {
        outbox.Last_Error_Message__c = e.getMessage() + '\n' + e.getStackTraceString();
    }

    // will be called by OutboxRelay
    public void setSuccess() {
        outbox.Completed_Timestamp__c = Datetime.Now();
    }
}