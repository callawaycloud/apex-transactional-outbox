trigger CaseCreatedTrigger on Case (after insert) {
    Outbox_Message__c[] messages = new Outbox_Message__c[]{};
    for(Case c : Trigger.new){
        messages.add(new Outbox_Message__c(
            Type__c='case-created',
            Message__c = c.Id
        ));
    }
    
    insert messages;
}