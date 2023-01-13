trigger CaseCreatedTrigger on Case(after insert, after update) {
    System.debug('Running Case Created Trigger.  Update: ' + Trigger.isUpdate + ' Records: ' + Trigger.size);
    TB_Outbox_Message__c[] messages = new List<TB_Outbox_Message__c>{};
    for (Case c : Trigger.new) {
        messages.add(
            new TB_Outbox_Message__c(
                Type__c = Trigger.isUpdate ? 'case_updated' : 'case_created',
                Message__c = c.Id,
                Group_Id__c = c.Id
            )
        );
    }

    insert messages;
}