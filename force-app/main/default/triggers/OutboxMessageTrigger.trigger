/**
 * Initilizes Outbox Records for Each subscription of an message
 */
trigger OutboxMessageTrigger on Outbox_Message__c(after insert) {
    new OutboxMessageTriggerHandler().handle();
}
