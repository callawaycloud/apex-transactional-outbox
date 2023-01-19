trigger CaseCreatedTrigger on Case(after insert) {
    TB_Outbox_Message__c[] messages = new List<TB_Outbox_Message__c>{};
    for (Case c : Trigger.new) {
        messages.add(
            new TB_Outbox_Message__c(
                Type__c = 'case_created',
                Message__c = c.Id,
                Group_Id__c = c.Id
            )
        );
    }

    insert messages;
}