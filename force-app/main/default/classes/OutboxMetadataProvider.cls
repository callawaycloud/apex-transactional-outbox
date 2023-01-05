public class OutboxMetadataProvider {
  public static Map<String, Message_Definition__mdt> getMessageDefintionMap(Set<String> msgTypes) {
    Message_Definition__mdt[] msgDefinitions = [
      SELECT DeveloperName, QualifiedApiName, Message_Resolver__c
      FROM Message_Definition__mdt
      WHERE DeveloperName IN :msgTypes
    ];

    Map<String, Message_Definition__mdt> definitionsByLabel = new Map<String, Message_Definition__mdt>();
    for (Message_Definition__mdt def : msgDefinitions) {
      definitionsByLabel.put(def.DeveloperName, def);
    }
    return definitionsByLabel;
  }

  public static Map<String, Message_Subscription__mdt> getMessageSubscritionMap(Set<String> msgTypes) {
    Message_Subscription__mdt[] subscriptions = [
        SELECT DeveloperName, QualifiedApiName, Message_Definition__r.DeveloperName, Relay_Client__c,
        Config__c
        FROM Message_Subscription__mdt
        WHERE Message_Definition__r.DeveloperName IN :msgTypes
      ];
  
      Map<String, Message_Subscription__mdt> subscriptionsByLabel = new Map<String, Message_Subscription__mdt>();
      for (Message_Subscription__mdt sub : subscriptions) {
        subscriptionsByLabel.put(sub.DeveloperName, sub);
      }
      return subscriptionsByLabel;
  }

  static Map<String, Map<String, Object>> configCache = new Map<String, Map<String, Object>>();
  public static Map<String, Object> getSubscriptionConfig(Message_Subscription__mdt subscriptionDef){
    if(configCache.containsKey(subscriptionDef.DeveloperName)){
        // may still be null
        return configCache.get(subscriptionDef.DeveloperName);
    }

    Map<String, Object> config;
    if(subscriptionDef.Config__c != null){
        config = (Map<String, Object>) JSON.deserializeUntyped(subscriptionDef.Config__c);
    }
    configCache.put(subscriptionDef.DeveloperName, config);
    return config;
  }

  static Map<String, IOutboxRelayClient> clientCache = new Map<String, IOutboxRelayClient>();
  public static IOutboxRelayClient getSubscriptionRelayClient(Message_Subscription__mdt subscriptionDef){
    if(clientCache.containsKey(subscriptionDef.DeveloperName)){
        // may still be null
        return clientCache.get(subscriptionDef.DeveloperName);
    }

    IOutboxRelayClient client = (IOutboxRelayClient) OutboxUtils.constructFromName(subscriptionDef.Relay_Client__c);
    clientCache.put(subscriptionDef.DeveloperName,client);
    return client;
  }

  public static IOutboxMessageResolver getMessageResolver(Message_Definition__mdt def){
    return (IOutboxMessageResolver) OutboxUtils.constructFromName(def.Message_Resolver__c);
  }
}
