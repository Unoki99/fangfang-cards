// 方方詞卡 relay: passes the messages of 一起玩 and 詞龍 between the players of a room, over the internet.
//
// Each room is a Durable Object; its name is a hash the apps make from the room code, so the code itself never
// reaches here. Every message is encrypted by the apps with a key made from the room code (AES-GCM): this relay
// only passes on bytes it can't read, keeps nothing (no storage, no logs of the messages), and forgets a room when
// its last player leaves. At most 16 players in a room, and messages of at most 400 kB.

export default {
  async fetch(req, env) {
    const url = new URL(req.url);
    const m = url.pathname.match(/^\/room\/([0-9a-f]{32})$/);
    if (!m) return new Response("方方詞卡 relay: ok\n", { headers: { "content-type": "text/plain; charset=utf-8" } });
    if (req.headers.get("Upgrade") !== "websocket") return new Response("expected a WebSocket\n", { status: 426 });
    return env.ROOMS.get(env.ROOMS.idFromName(m[1])).fetch(req);
  },
};

export class Room {
  constructor(state) {
    this.state = state;
  }

  async fetch() {
    const socks = this.state.getWebSockets();
    if (socks.length >= 16) return new Response("room full\n", { status: 429 });
    const [client, server] = Object.values(new WebSocketPair());
    const id = crypto.randomUUID().slice(0, 8);
    this.state.acceptWebSocket(server);
    server.serializeAttachment({ id });
    // (the newcomer: who's here; the others: someone came)
    const peers = socks.map((s) => s.deserializeAttachment()?.id).filter(Boolean);
    server.send(JSON.stringify({ sys: "welcome", id, peers }));
    for (const s of socks) this.send(s, { sys: "join", id });
    return new Response(null, { status: 101, webSocket: client });
  }

  webSocketMessage(ws, msg) {
    if (typeof msg !== "string" || msg.length > 400000) return;
    const from = ws.deserializeAttachment()?.id;
    for (const s of this.state.getWebSockets()) if (s !== ws) this.send(s, { sys: "msg", from, data: msg });
  }

  webSocketClose(ws) { this.left(ws); }
  webSocketError(ws) { this.left(ws); }

  left(ws) {
    const id = ws.deserializeAttachment()?.id;
    for (const s of this.state.getWebSockets()) if (s !== ws) this.send(s, { sys: "leave", id });
  }

  send(s, o) {
    try { s.send(JSON.stringify(o)); } catch (e) { /* (gone) */ }
  }
}
