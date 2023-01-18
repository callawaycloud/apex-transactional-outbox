/** Demostrates how to use an AfterRelayAction
 *  This action will update the description of the case with the response from the last relay
 */
public with sharing class CaseCreatedAfterRelayAction implements TB_IAfterRelayAction {
    public void execute(TB_OutboxRelayContext[] ctxs) {
        //get the payload of all the messages
        Case[] casesToUpdate = new List<Case>{};
        for (TB_OutboxRelayContext ctx : ctxs) {
            TB_GenericHttpRelayClient.GenericRelayResult result = (TB_GenericHttpRelayClient.GenericRelayResult) ctx.relayResult;

            //get the payload
            Case c = (Case) ctx.resolvedMessage;

            c.Description = 'Last Relay ' + (ctx.isComplete() ? 'Completed' : 'Failed') + ': ' + result.response.body;
            casesToUpdate.add(c);
        }
        update casesToUpdate;
    }
}
