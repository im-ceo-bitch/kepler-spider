// Spyder Chat Devnet v1 — DO persistence, authenticated contacts, opt-in 1:1 messaging.
// NOTE: Devnet messaging only; plaintext stored on server, NOT end-to-end encrypted.
const json = (value, status = 200) => new Response(JSON.stringify(value), {
  status, headers: { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store', 'x-content-type-options': 'nosniff' }
});
const bad = (code, status = 400) => json({ error: code }, status);
const validId = value => typeof value === 'string' && /^[a-f0-9]{32}$/.test(value);
const validSecret = value => typeof value === 'string' && /^[a-f0-9]{64}$/.test(value);
const validInvite = value => typeof value === 'string' && /^[A-F0-9]{24}$/.test(value);
const validClient = value => typeof value === 'string' && /^[a-f0-9-]{36}$/.test(value);
const sanitizedName = value => String(value ?? '').trim().slice(0, 36);
const isText = value => typeof value === 'string' && value.trim().length > 0 && value.length <= 2000;
const sha256 = async str => Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(str)))).map(x => x.toString(16).padStart(2,'0')).join('');
const equal = (a,b) => { if (a.length !== b.length) return false; let v=0; for(let i=0;i<a.length;i++)v |= a.charCodeAt(i)^b.charCodeAt(i); return v===0; };
const messageKey = (a,b) => 'msgs:'+ [a,b].sort().join(':');
const linkKey = (a,b) => 'link:'+ [a,b].sort().join(':');

export class ChatHub {
  constructor(ctx) { this.ctx=ctx; }
  async read(request) {
    const auth=request.headers.get('authorization')||'';
    const match=/^Bearer ([a-f0-9]{32})\.([a-f0-9]{64})$/.exec(auth);
    if(!match)return null;
    const user=await this.ctx.storage.get('user:'+match[1]);
    if(!user||!equal(user.secretHash,await sha256(match[2])))return null;
    return user;
  }
  async body(req) {
    if(Number(req.headers.get('content-length')||0)>8000)return null;
    try {return await req.json();}catch{return null;}
  }
  async fetch(request) {
    const url=new URL(request.url), method=request.method, path=url.pathname;
    if(method==='GET' && path==='/health')return json({status:'ok',service:'spyder-chat-devnet',version:1,e2ee:false});
    if(method==='POST'&&path==='/v1/register') {
      const b=await this.body(request);
      if(!b||!validId(b.id)||!validSecret(b.secret)||!validInvite(b.invite_code)||!sanitizedName(b.name))return bad('invalid_registration');
      if(await this.ctx.storage.get('user:'+b.id))return bad('identity_exists',409);
      if(await this.ctx.storage.get('code:'+b.invite_code))return bad('code_taken',409);
      const u={id:b.id,name:sanitizedName(b.name),invite_code:b.invite_code,secretHash:await sha256(b.secret)};
      await this.ctx.storage.put('user:'+u.id,u);
      await this.ctx.storage.put('code:'+u.invite_code,u.id);
      return json({id:u.id,name:u.name,invite_code:u.invite_code},201);
    }
    const me=await this.read(request);
    if(!me)return bad('unauthorized',401);
    if(method==='GET'&&path==='/v1/me')return json({id:me.id,name:me.name,invite_code:me.invite_code});
    if(method==='GET'&&path==='/v1/contacts') {
      const contacts=[],requests=[];
      const entries=await this.ctx.storage.list({prefix:'invite:'+me.id+':'});
      for(const [key,invite] of entries) { if(invite.status==='pending') {const peer=await this.ctx.storage.get('user:'+invite.from); if(peer)requests.push({id:peer.id,name:peer.name});} }
      const links=await this.ctx.storage.list({prefix:'contact:'+me.id+':'});
      for(const [key,val] of links) {const peer=await this.ctx.storage.get('user:'+val.peer); if(peer)contacts.push({id:peer.id,name:peer.name});}
      return json({contacts,requests,invite_code:me.invite_code});
    }
    if(method==='POST'&&path==='/v1/invites') {
      const b=await this.body(request);
      if(!validInvite(b?.code))return bad('invalid_invite_code');
      const to=await this.ctx.storage.get('code:'+b.code);
      if(!to||to===me.id)return bad('invalid_recipient',404);
      if(await this.ctx.storage.get(linkKey(me.id,to)))return json({status:'already_connected'});
      await this.ctx.storage.put('invite:'+to+':'+me.id,{from:me.id,to,status:'pending'});
      return json({status:'pending'});
    }
    if(method==='POST'&&path==='/v1/invites/accept') {
      const b=await this.body(request);
      if(!validId(b?.from_id))return bad('invalid_sender');
      const key='invite:'+me.id+':'+b.from_id;
      const invite=await this.ctx.storage.get(key);
      if(!invite||invite.status!=='pending')return bad('invitation_not_found',404);
      await this.ctx.storage.put(linkKey(me.id,b.from_id),true);
      await this.ctx.storage.put('contact:'+me.id+':'+b.from_id,{peer:b.from_id});
      await this.ctx.storage.put('contact:'+b.from_id+':'+me.id,{peer:me.id});
      await this.ctx.storage.delete(key);
      return json({status:'connected'});
    }
    if(method==='GET'&&path==='/v1/messages') {
      const peer=url.searchParams.get('peer');
      if(!validId(peer)||!(await this.ctx.storage.get(linkKey(me.id,peer))))return bad('not_contacts',403);
      const all=(await this.ctx.storage.get(messageKey(me.id,peer)))||[];
      return json({messages:all.slice(-100)});
    }
    if(method==='POST'&&path==='/v1/messages') {
      const b=await this.body(request);
      if(!validId(b?.recipient_id)||!validClient(b?.client_id)||!isText(b?.text))return bad('invalid_message');
      if(!(await this.ctx.storage.get(linkKey(me.id,b.recipient_id))))return bad('not_contacts',403);
      const key=messageKey(me.id,b.recipient_id), all=(await this.ctx.storage.get(key))||[];
      if(all.some(m=>m.sender_id===me.id&&m.client_id===b.client_id))return json({status:'already_sent'});
      // bounded recent history for devnet only: no claim of permanent full chat archive.
      const entry={id:crypto.randomUUID(),client_id:b.client_id,sender_id:me.id,recipient_id:b.recipient_id,text:b.text.trim(),created_at:new Date().toISOString()};
      all.push(entry);
      await this.ctx.storage.put(key,all.slice(-300));
      return json({status:'sent',message:entry},201);
    }
    return bad('not_found',404);
  }
}

export default {
  async fetch(request,env) {
    if(!env.CHAT_HUB)return bad('server_not_configured',503);
    const room=env.CHAT_HUB.get(env.CHAT_HUB.idFromName('spyder-chat-devnet-v1'));
    return room.fetch(request);
  }
};
