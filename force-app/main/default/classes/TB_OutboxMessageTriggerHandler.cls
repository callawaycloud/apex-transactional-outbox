public with sharing class TB_OutboxMessageTriggerHandler {
    public void handle() {
        if (Trigger.isBefore && Trigger.isInsert) {
            beforeInsert();
        } else if (Trigger.isAfter && Trigger.isInsert) {
            afterInsert();
        }
    }

    private static void beforeInsert() {
        Map<String, TB_Message_Definition__mdt> messageDefinitions = TB_OutboxMetadataProvider.getMessageDefintionMap();
        for (TB_Outbox_Message__c outboxMessage : (List<TB_Outbox_Message__c>) Trigger.new) {
            if (!messageDefinitions.containsKey(outboxMessage.Type__c)) {
                outboxMessage.addError('The outbox message Type does not match a message definition.');
            }
        }
    }

    private static void afterInsert() {
        Map<String, List<TB_Outbox_Message__c>> recordsByMessageType = new Map<String, List<TB_Outbox_Message__c>>();
        for (TB_Outbox_Message__c evt : (List<TB_Outbox_Message__c>) Trigger.new) {
            // group evts by type
            String evtType = evt.Type__c;
            List<TB_Outbox_Message__c> evts = recordsByMessageType.get(evtType);
            if (evts == null) {
                evts = new List<TB_Outbox_Message__c>();
                recordsByMessageType.put(evtType, evts);
            }
            evts.add(evt);
        }

        TB_Message_Subscription__mdt[] subscriptions = TB_OutboxMetadataProvider.getMessageSubscritionMap(
                recordsByMessageType.keySet()
            )
            .values();

        // setup an "outbox" record for each subscription
        List<TB_Subscription_Outbox__c> outboxToInsert = new List<TB_Subscription_Outbox__c>();
        for (TB_Message_Subscription__mdt sub : subscriptions) {
            if (sub.Enabled__c == false) {
                continue;
            }

            for (TB_Outbox_Message__c subEvt : recordsByMessageType.get(sub.Message_Definition__r.DeveloperName)) {
                TB_Subscription_Outbox__c outbox = new TB_Subscription_Outbox__c(
                    Outbox_Message__c = subEvt.Id,
                    Subscription__c = sub.DeveloperName,
                    Max_Attempts__c = sub.Max_Attempts__c,
                    Application__c = sub.Application__r.DeveloperName
                );
                outboxToInsert.add(outbox);
            }
        }
        insert outboxToInsert;

        TB_OutboxRelayQueuable.enqueue(null);
    }
}