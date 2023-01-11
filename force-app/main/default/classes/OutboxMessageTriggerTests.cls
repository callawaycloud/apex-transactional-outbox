@isTest
public class OutboxMessageTriggerTests {
  /**
   * Test the setup of outbox records when a new Outbox_Message__c record is inserted
   */
  static testMethod void testOutboxSetup() {
    //Setup an Application & Message Definition
    Application__mdt app = TransactionOutboxTestUtils.addApplication('TestApp');
    Message_Definition__mdt msgDef = TransactionOutboxTestUtils.addEventDefinition('test.message1');
    Message_Subscription__mdt enabledSubscription = TransactionOutboxTestUtils.addSubscription(
      app,
      msgDef,
      'EnabledSubscription'
    );

    Message_Subscription__mdt disabledSubscription = TransactionOutboxTestUtils.addSubscription(
      app,
      msgDef,
      'DisabledSubscription'
    );

    disabledSubscription.Enabled__c = false;

    // setup an Outbox_Message__c record
    Outbox_Message__c outboxMessage = new Outbox_Message__c();

    // set type & message
    outboxMessage.Type__c = msgDef.DeveloperName;
    outboxMessage.Message__c = 'Test Payload';

    //disable automatic queuing of job
    OutboxRelayQueuable.alreadyQueuedInContext = true;

    // insert the record
    insert outboxMessage;

    // assert that a Subscription Outbox record was created for each Subscription__mdt record related to the message type
    List<Subscription_Outbox__c> subscriptionOutboxes = [
      SELECT Id, Outbox_Message__c, Subscription__c, Relay_Attempts__c, Completed_Timestamp__c
      FROM Subscription_Outbox__c
      WHERE Outbox_Message__c = :outboxMessage.Id
    ];

    System.assertEquals(
      1,
      subscriptionOutboxes.size(),
      'There should be 1 Subscription Outbox record created for the Outbox Message record'
    );

    System.assertEquals(
      outboxMessage.Id,
      subscriptionOutboxes[0].Outbox_Message__c,
      'The Subscription Outbox record should be related to the Outbox Message record'
    );
    System.assertEquals(
      'EnabledSubscription',
      subscriptionOutboxes[0].Subscription__c,
      'The Subscription Outbox record should be related to the Subscription__mdt record with the same message type'
    );

    System.assertEquals(
      0,
      subscriptionOutboxes[0].Relay_Attempts__c,
      'The Subscription Outbox record should have 0 attempts'
    );

    System.assertEquals(
      null,
      subscriptionOutboxes[0].Completed_Timestamp__c,
      'The Subscription Outbox record should have a null completed timestamp'
    );
  }
}
