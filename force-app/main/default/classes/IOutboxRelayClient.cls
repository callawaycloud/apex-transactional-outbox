public interface IOutboxRelayClient {
    /** 
     * Must throw exception on failure
    */
    void send(OutboxRelayContext ctx);
}
