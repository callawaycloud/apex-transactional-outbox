@isTest
public class TB_TransactionOutboxTestUtils {
    public static TB_Application__mdt addApplication(String name) {
        //Setup an Application & Message Definition
        TB_Application__mdt app = new TB_Application__mdt(DeveloperName = name);
        return app;
    }

    public static TB_Message_Definition__mdt addEventDefinition(String type) {
        TB_Message_Definition__mdt msgDef = new TB_Message_Definition__mdt(DeveloperName = type);
        if (TB_OutboxMetadataProvider.msgDefinitions == null) {
            TB_OutboxMetadataProvider.msgDefinitions = new List<TB_Message_Definition__mdt>();
        }

        TB_OutboxMetadataProvider.msgDefinitions.add(msgDef);
        return msgDef;
    }

    public static TB_Message_Subscription__mdt addSubscription(
        TB_Application__mdt app,
        TB_Message_Definition__mdt msgDef,
        String name
    ) {
        TB_Message_Subscription__mdt subscription = new TB_Message_Subscription__mdt(
            DeveloperName = name,
            Max_Attempts__c = 3,
            Message_Definition__r = msgDef,
            Application__r = app,
            Enabled__c = true
        );

        if (TB_OutboxMetadataProvider.subscriptions == null) {
            TB_OutboxMetadataProvider.subscriptions = new List<TB_Message_Subscription__mdt>();
        }

        TB_OutboxMetadataProvider.subscriptions.add(subscription);
        return subscription;
    }

    public class TestClient implements TB_IOutboxRelayClient {
        public void send(TB_OutboxRelayContext ctx) {
            if (ctx.subscriptionConfig.containsKey('log')) {
                ctx.log(ctx.subscriptionConfig.get('log'));
            }
            if (ctx.subscriptionConfig.get('throwError') == true) {
                throw new TestException('Test Error');
            }
        }
    }

    @testVisible
    static Integer testExecuted = 0;
    public class TestResolver implements TB_IOutboxMessageResolver {
        public Map<Id, Object> resolveMessages(TB_Outbox_Message__c[] messages) {
            testExecuted++;
            Map<Id, Object> result = new Map<Id, Object>();
            for (TB_Outbox_Message__c msg : messages) {
                result.put(msg.Id, 'resolved:' + msg.Message__c);
            }
            return result;
        }
    }

    public class TestException extends Exception {
    }
}