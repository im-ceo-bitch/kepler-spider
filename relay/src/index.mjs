/**
 * Spyder MessageChain DEVNET relay (Cloudflare Durable Objects, SQLite backend).
 * Only stores encrypted envelopes. This is a research relay, not mainnet and
 * not an audited secure messenger. Requires a private DEVNET_OPERATOR_TOKEN.
 * Never ship that token in an iOS build. No wallet secrets are transmitted.
 */
import { validateEnvelopeShape, verifyEnvelopeSignature, validateNext, envelopeHash, ZERO_HASH } from '../../protocol/messagechain.mjs';
const headers = {'content-type':'application/json; charset=utf-8','cache-control':'no-store','x-content-type-options':'nosniff'};
const json = (obj,status=200) => new Response(JSON.stringify(obj),{status,headers});
const validHash = x => typeof x === 'string' && /^[a-f0-9]{64}$/.test(x);
async function parseBody(request, max = 24_000) {
  if (Number(request.headers.get('content-length')||0) > max) throw new Error('body_too_large');
  const body = await request.text();
  if (new TextEncoder().encode(body).length > max) throw new Error('body_too_large');
  return JSON.parse(body);
}

export class SpyderMessageRoom {
  constructor(ctx) { this.ctx = ctx; }
  async fetch(request) {
    const u = new URL(request.url);
    try {
      if (u.pathname.endsWith('/socket') && request.headers.get('upgrade')?.toLowerCase() === 'websocket') {
        const pair = new WebSocketPair();
        const [client,server] = Object.values(pair);
        this.ctx.acceptWebSocket(server); // hibernation: no per-connection compute while idle
        return new Response(null,{status:101,webSocket:client});
      }
      if (u.pathname.endsWith('/init') && request.method === 'POST') {
        const data = await parseBody(request,2000);
        if (!Array.isArray(data.participants) || data.participants.length !== 2 ||
            new Set(data.participants).size !== 2 || data.participants.some(k => typeof k !== 'string' || k.length > 140 || k.length < 40)) {
          return json({error:'invalid_participants'},400);
        }
        if (await this.ctx.storage.get('participants')) return json({error:'conversation_exists'},409);
        await this.ctx.storage.put('participants',data.participants);
        await this.ctx.storage.put('total',0);
        return json({status:'created'},201);
      }
      const participants = await this.ctx.storage.get('participants');
      if (!participants) return json({error:'not_initialized'},404);
      if (u.pathname.endsWith('/envelopes') && request.method === 'GET') {
        const after = Number(u.searchParams.get('after')||'0');
        if (!Number.isSafeInteger(after) || after < 0) return json({error:'invalid_cursor'},400);
        const total = await this.ctx.storage.get('total')||0;
        const envelopes = [];
        for (let i=after+1; i<=Math.min(total,after+100); i++) {
          const item = await this.ctx.storage.get('item:'+i);
          if (item) envelopes.push(item);
        }
        return json({envelopes,head_cursor:total,next_cursor:Math.min(total,after+100)});
      }
      if (u.pathname.endsWith('/envelopes') && request.method === 'POST') {
        const envelope = await parseBody(request);
        validateEnvelopeShape(envelope);
        const id = u.pathname.split('/')[3];
        if (envelope.conversation_id !== id || !participants.includes(envelope.sender_key)) return json({error:'unauthorized_sender'},403);
        if (!await verifyEnvelopeSignature(envelope)) return json({error:'invalid_signature'},403);
        const hash = await envelopeHash(envelope);
        // Durable Object transactions prevent two concurrent POSTs with the same
        // sequence from overwriting each other after asynchronous signature checks.
        const result=await this.ctx.storage.transaction(async tx => {
          if (await tx.get('hash:'+hash)) return {status:'already_seen',hash};
          const headKey='head:'+envelope.sender_key;
          const state=await tx.get(headKey) || {sequence:0,head:ZERO_HASH};
          try { validateNext(envelope,state); } catch { return {error:'chain_conflict',expected_sequence:state.sequence+1}; }
          if (envelope.peer_head!==ZERO_HASH && !await tx.get('hash:'+envelope.peer_head)) return {error:'unknown_peer_head'};
          const count=await tx.get('total')||0;
          // No silent pruning: the research room has an explicit, bounded capacity.
          if (count>=1000) return {error:'devnet_capacity_reached'};
          const entry={index:count+1,hash,envelope};
          await tx.put('item:'+(count+1),entry);
          await tx.put(headKey,{sequence:envelope.sequence,head:hash});
          await tx.put('hash:'+hash,true);
          await tx.put('total',count+1);
          return {status:'accepted',hash,cursor:count+1};
        });
        if (result.error) return json(result,result.error==='devnet_capacity_reached'?507:409);
        if (result.status==='already_seen') return json(result);
        for (const socket of this.ctx.getWebSockets()) {
          try { socket.send(JSON.stringify({event:'new_envelope',cursor:result.cursor,hash})); } catch { /* stale socket */ }
        }
        return json(result,201);
      }
      return json({error:'not_found'},404);
    } catch (error) {
      return json({error: error instanceof SyntaxError?'invalid_json':error?.message==='body_too_large'?'body_too_large':'invalid_envelope'},400);
    }
  }
  async webSocketMessage(ws, _message) {
    // Notification-only socket. Envelopes must be sent via authenticated HTTP.
    try { ws.send(JSON.stringify({event:'use_http_for_submissions'})); } catch { /* disconnected */ }
  }
}

export default {
  async fetch(request,env) {
    const url = new URL(request.url);
    if (request.method==='GET' && url.pathname==='/health') return json({status:'ok',name:'spyder-messagechain-devnet',version:1,e2ee_audited:false});
    // Operator-only access: this MUST NOT be embedded in mobile clients.
    if (!env.DEVNET_OPERATOR_TOKEN ||
        request.headers.get('x-spyder-devnet-token')!==env.DEVNET_OPERATOR_TOKEN) return json({error:'forbidden'},403);
    const match = /^\/v1\/conversations\/([0-9a-f]{64})\/(init|envelopes|socket)$/.exec(url.pathname);
    if (!match) return json({error:'not_found'},404);
    if (!env.MESSAGE_ROOMS) return json({error:'relay_unconfigured'},503);
    const room=env.MESSAGE_ROOMS.get(env.MESSAGE_ROOMS.idFromName(match[1]));
    return room.fetch(request);
  }
};
