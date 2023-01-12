public class OutboxMetadataProvider {
  @testVisible
  static Message_Definition__mdt[] msgDefinitions;
  public static Map<String, Message_Definition__mdt> getMessageDefintionMap(Set<String> msgTypes) {
    if (msgDefinitions == null) {
      msgDefinitions = [
        SELECT DeveloperName, QualifiedApiName, Message_Resolver__c
        FROM Message_Definition__mdt
      ];
    }

    Map<String, Message_Definition__mdt> definitionsByLabel = new Map<String, Message_Definition__mdt>();
    for (Message_Definition__mdt def : msgDefinitions) {
      definitionsByLabel.put(def.DeveloperName, def);
    }
    return definitionsByLabel;
  }

  @testVisible
  static Message_Subscription__mdt[] subscriptions;
  public static Map<String, Message_Subscription__mdt> getMessageSubscritionMap(
    Set<String> msgTypes
  ) {
    if (subscriptions == null) {
      subscriptions = [
        SELECT
          DeveloperName,
          Application__r.DeveloperName,
          Message_Definition__r.DeveloperName,
          Relay_Client__c,
          Config__c,
          Max_Attempts__c,
          Enabled__c
        FROM Message_Subscription__mdt
      ];
    }

    Map<String, Message_Subscription__mdt> subscriptionsByLabel = new Map<String, Message_Subscription__mdt>();
    for (Message_Subscription__mdt sub : subscriptions) {
      if(msgTypes.contains(sub.Message_Definition__r.DeveloperName)){
        subscriptionsByLabel.put(sub.DeveloperName, sub);
      }
    }
    return subscriptionsByLabel;
  }

  static Map<String, Map<String, Object>> configCache = new Map<String, Map<String, Object>>();
  public static Map<String, Object> getSubscriptionConfig(
    Message_Subscription__mdt subscriptionDef
  ) {
    if (configCache.containsKey(subscriptionDef.DeveloperName)) {
      return configCache.get(subscriptionDef.DeveloperName);
    }

    Map<String, Object> config = new Map<String, Object>();
    if (subscriptionDef.Config__c != null) {
      config = (Map<String, Object>) JSON.deserializeUntyped(subscriptionDef.Config__c);
    }
    configCache.put(subscriptionDef.DeveloperName, config);
    return config;
  }

  static Map<String, IOutboxRelayClient> clientCache = new Map<String, IOutboxRelayClient>();
  public static IOutboxRelayClient getSubscriptionRelayClient(
    Message_Subscription__mdt subscriptionDef
  ) {
    if (clientCache.containsKey(subscriptionDef.DeveloperName)) {
      return clientCache.get(subscriptionDef.DeveloperName);
    }

    IOutboxRelayClient client = (IOutboxRelayClient) OutboxUtils.constructFromName(
      subscriptionDef.Relay_Client__c
    );
    clientCache.put(subscriptionDef.DeveloperName, client);
    return client;
  }

  public static IOutboxMessageResolver getMessageResolver(Message_Definition__mdt def) {
    return (IOutboxMessageResolver) OutboxUtils.constructFromName(def.Message_Resolver__c);
  }
}
