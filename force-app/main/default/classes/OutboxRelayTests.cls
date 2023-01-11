@isTest
public class OutboxRelayTests {
  @isTest
  static void testRelayProcessingSuccess() {
    //Setup an Application & Message Definition
    Application__mdt app = TransactionOutboxTestUtils.addApplication('TestApp');
    Message_Definition__mdt msgDef = TransactionOutboxTestUtils.addEventDefinition('test.message1');
    msgDef.Message_Resolver__c = 'TransactionOutboxTestUtils.TestResolver';
    Message_Subscription__mdt subscription = TransactionOutboxTestUtils.addSubscription(
      app,
      msgDef,
      'EnabledSubscription'
    );
    subscription.Relay_Client__c = 'TransactionOutboxTestUtils.TestClient';

    // setup an Outbox_Message__c record
    Outbox_Message__c outboxMessage = new Outbox_Message__c();

    // set type & message
    outboxMessage.Type__c = msgDef.DeveloperName;
    outboxMessage.Message__c = 'Test Payload';

    Test.startTest();
    insert outboxMessage;
    Test.stopTest();
    List<Subscription_Outbox__c> subscriptionOutboxes = [
      SELECT Id, Outbox_Message__c, Subscription__c, Relay_Attempts__c, Last_Error_Message__c, Completed_Timestamp__c
      FROM Subscription_Outbox__c
      WHERE Outbox_Message__c = :outboxMessage.Id
    ];
    System.assertEquals(1, subscriptionOutboxes.size());

    System.assertEquals(
      1,
      subscriptionOutboxes[0].Relay_Attempts__c,
      'The outbox should have been attempted once'
    );

    System.assertEquals(
      null,
      subscriptionOutboxes[0].Last_Error_Message__c,
      'There should be no error message'
    );

    System.assertNotEquals(
      null,
      subscriptionOutboxes[0].Completed_Timestamp__c,
      'The completed timestamp should not be null'
    );

    System.assertEquals(
        1,
        TransactionOutboxTestUtils.testExecuted,
        'The TestMessageResolver should have been executed once'
    );
  }

  @isTest
  static void testRelayProcessingFailure() {
    //Setup an Application & Message Definition
    Application__mdt app = TransactionOutboxTestUtils.addApplication('TestApp');
    Message_Definition__mdt msgDef = TransactionOutboxTestUtils.addEventDefinition('test.message1');
    Message_Subscription__mdt subscription = TransactionOutboxTestUtils.addSubscription(
      app,
      msgDef,
      'EnabledSubscription'
    );
    subscription.Relay_Client__c = 'TransactionOutboxTestUtils.TestClient';
    //setup client to fail
    subscription.Config__c = '{"throwError":true, "log": "hello"}';

    // setup an Outbox_Message__c record
    Outbox_Message__c outboxMessage = new Outbox_Message__c();

    // set type & message
    outboxMessage.Type__c = msgDef.DeveloperName;
    outboxMessage.Message__c = 'Test Payload';

    Test.startTest();
    insert outboxMessage;
    Test.stopTest();
    List<Subscription_Outbox__c> subscriptionOutboxes = [
      SELECT Id, Outbox_Message__c, Subscription__c, Relay_Attempts__c, Last_Error_Message__c, Completed_Timestamp__c, Log__c
      FROM Subscription_Outbox__c
      WHERE Outbox_Message__c = :outboxMessage.Id
    ];
    System.assertEquals(1, subscriptionOutboxes.size());

    System.assertEquals(
      1,
      subscriptionOutboxes[0].Relay_Attempts__c,
      'The outbox should have been attempted once'
    );

    System.assertNotEquals(
      null,
      subscriptionOutboxes[0].Last_Error_Message__c,
      'There should be an error message'
    );

    System.assertEquals(
      null,
      subscriptionOutboxes[0].Completed_Timestamp__c,
      'The completed timestamp should be null'
    );

    System.assert(
        subscriptionOutboxes[0].Log__c.contains('hello'),
        'Log should contain "hello"'
      );
  }


  @isTest
  static void testRelayProcessingGroup() {
    //Setup an Application & Message Definition
    Application__mdt app = TransactionOutboxTestUtils.addApplication('TestApp');
    Message_Definition__mdt msgDef = TransactionOutboxTestUtils.addEventDefinition('test.message1');
    Message_Subscription__mdt subscription = TransactionOutboxTestUtils.addSubscription(
      app,
      msgDef,
      'subscription1'
    );
    subscription.Relay_Client__c = 'TransactionOutboxTestUtils.TestClient';
    //setup client to fail
    subscription.Config__c = '{"throwError":true, "log": "hello"}';

    Message_Definition__mdt msgDef2 = TransactionOutboxTestUtils.addEventDefinition('test.message2');
    Message_Subscription__mdt subscription2 = TransactionOutboxTestUtils.addSubscription(
        app,
        msgDef2,
        'subscription2'
    );
    subscription2.Relay_Client__c = 'TransactionOutboxTestUtils.TestClient';

    // setup an Outbox_Message__c record
    Outbox_Message__c outboxMessage = new Outbox_Message__c();
    outboxMessage.Type__c = msgDef.DeveloperName;
    outboxMessage.Message__c = 'Test Payload';
    outboxMessage.Group_Id__c = 'group1';

    Outbox_Message__c outboxMessage2 = new Outbox_Message__c();
    outboxMessage2.Type__c = msgDef2.DeveloperName;
    outboxMessage2.Message__c = 'Test Payload';
    outboxMessage2.Group_Id__c = 'group1';

    Test.startTest();
    insert new Outbox_Message__c[]{outboxMessage, outboxMessage2};
    Test.stopTest();
    
    List<Subscription_Outbox__c> subscriptionOutboxes = [
      SELECT Id, Outbox_Message__c, Group_Id__c, Subscription__c, Relay_Attempts__c, Last_Error_Message__c, Completed_Timestamp__c, Log__c
      FROM Subscription_Outbox__c
      ORDER BY Outbox_Message__r.Sequence_Number__c
    ];
    System.assertEquals(2, subscriptionOutboxes.size());

    System.assertEquals(
        subscriptionOutboxes[0].Group_Id__c,
        subscriptionOutboxes[1].Group_Id__c,
        'Both outbox should have the same group'
    );

    System.assertEquals(
      1,
      subscriptionOutboxes[0].Relay_Attempts__c,
      'The outbox should have been attempted once'
    );

    System.assertNotEquals(
        null,
        subscriptionOutboxes[0].Last_Error_Message__c,
        'There should be an error message'
      );

    System.assertEquals(
        0,
        subscriptionOutboxes[1].Relay_Attempts__c,
        'The outbox should not have been attempted'
    );

  }
}
