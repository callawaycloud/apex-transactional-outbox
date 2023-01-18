/**
 * AfterRelayActions allow code to be excuted with the results for a single subscription.
 * 
 * WARNING: 
 * - Hitting a uncatchable exception (IE limits) in an AfterRelayAction 
 * may cause the Relay results to be lost!
 * 
 * - This AfterRelayActions are NOT guanteed to succeed.  
 * If an action fails, the Relay will catch the exception and move on without retry.
 */
public interface TB_IAfterRelayAction{
    void execute(TB_OutboxRelayContext[] ctx);
}
