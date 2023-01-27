global with sharing class TB_RecordCleanup implements Schedulable {
    global void execute(SchedulableContext sc) {
        cleanup();
    }

    //should we run this in the finalizer? Or just allow it to be scheduled
    public void cleanup() {
        List<TB_Subscription_Outbox__c> expiredRecords = [
            SELECT Id
            FROM TB_Subscription_Outbox__c
            WHERE TTL__c > :Date.today()
        ];
        if (!expiredRecords.isEmpty()) {
            System.debug('Removing Outbox: ' + expiredRecords.size());
            delete expiredRecords;
        }

        // find all Outbox_Message__c records which are configured in the Custom Metadata to purge when the outbox is empty
        Set<String> purgeOutboxOnEmpty = new Set<String>();
        for (TB_Message_Definition__mdt evtDef : TB_OutboxMetadataProvider.getMessageDefintionMap().values()) {
            if (evtDef.Delete_When_Outbox_Empty__c == true) {
                purgeOutboxOnEmpty.add(evtDef.DeveloperName);
            }
        }

        List<TB_Outbox_Message__c> outboxMessages = [
            SELECT Id
            FROM TB_Outbox_Message__c
            WHERE Type__c IN :purgeOutboxOnEmpty AND Id NOT IN (SELECT Outbox_Message__c FROM TB_Subscription_Outbox__c)
        ];
        if (!outboxMessages.isEmpty()) {
            System.debug('Removing Messages: ' + outboxMessages.size());
            delete outboxMessages;
        }

    }
}