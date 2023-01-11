@isTest
public class TransactionOutboxTestUtils {
  public static Application__mdt addApplication(String name) {
    //Setup an Application & Message Definition
    Application__mdt app = new Application__mdt(DeveloperName = name);
    return app;
  }

  public static Message_Definition__mdt addEventDefinition(String type) {
    Message_Definition__mdt msgDef = new Message_Definition__mdt(DeveloperName = type);
    if (OutboxMetadataProvider.msgDefinitions == null) {
      OutboxMetadataProvider.msgDefinitions = new List<Message_Definition__mdt>();
    }

    OutboxMetadataProvider.msgDefinitions.add(msgDef);
    return msgDef;
  }

  public static Message_Subscription__mdt addSubscription(
    Application__mdt app,
    Message_Definition__mdt msgDef,
    String name
  ) {
    Message_Subscription__mdt subscription = new Message_Subscription__mdt(
      DeveloperName = name,
      Max_Attempts__c = 3,
      Message_Definition__r = msgDef,
      Application__r = app,
      Enabled__c = true
    );

    if (OutboxMetadataProvider.subscriptions == null) {
      OutboxMetadataProvider.subscriptions = new List<Message_Subscription__mdt>();
    }

    OutboxMetadataProvider.subscriptions.add(subscription);
    return subscription;
  }

  public class TestClient implements IOutboxRelayClient {
    public void send(OutboxRelayContext ctx) {
        if(ctx.subscriptionConfig.containsKey('log')){
            ctx.log(ctx.subscriptionConfig.get('log'));
        }
        if(ctx.subscriptionConfig.get('throwError') == true){
            throw new TestException('Test Error');
        }
        
    }
  }

  @testVisible static Integer testExecuted = 0;
  public class TestResolver implements IOutboxMessageResolver {
    public Map<Id,Object> resolveMessages(Outbox_Message__c[] messages){
        testExecuted++;
        Map<Id,Object> result = new Map<Id,Object>();
        for(Outbox_Message__c msg : messages){
            result.put(msg.Id, 'resolved:' + msg.Message__c);
        }
        return result;
    }
  }

  public class TestException extends Exception {}
}
