// Spyder Chat Devnet v2: authenticated contacts and encrypted-envelope relay.
// E2EE is implemented on devices. The server never accepts or stores new cleartext messages.
// Historical v1 plaintext is not migrated or deleted automatically; handle it separately.
const json = (value, status = 200) => new Response(JSON.stringify(value), {
  status, headers: { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store', 'x-content-type-options': 'nosniff' }
});
const bad = (code, status = 400) => json({ error: code }, status);
const validId = value => typeof value === 'string' && /^[a-f0-9]{32}$/.test(value);
const validSecret = value => typeof value === 'string' && /^[a-f0-9]{64}$/.test(value);
const validInvite = value => typeof value === 'string' && /^[A-F0-9]{24}$/.test(value);
const validClient = value => typeof value === 'string' && /^[a-f0-9-]{36}$/.test(value);
const sanitizedName = value => String(value ?? '').trim().slice(0, 36);
// Usernames are public, case-insensitive, unique identifiers. They are not credentials.
const normalizedUsername = value => typeof value === 'string' ? value.trim().replace(/^@/, '').toLowerCase() : '';
const validUsername = value => /^[a-z][a-z0-9_]{2,19}$/.test(value) && !['admin', 'support', 'spyder', 'system', 'security'].includes(value);
const usernameKey = value => 'handle:' + value;
const isBase64 = (value, min, max) => typeof value === 'string' && value.length >= min && value.length <= max &&
  /^[A-Za-z0-9+/]+={0,2}$/.test(value) && value.length % 4 === 0;
const isKey32 = value => isBase64(value,44,44) && value.endsWith('=') && (() => {
  try { return atob(value).length === 32; } catch { return false; }
})();
const keyPair = value => value && value.version === 2 && isKey32(value.key_agreement) && isKey32(value.signature);
const validCipher = value => validId(value?.recipient_id) && validClient(value?.client_id) &&
  isBase64(value?.ephemeral_key,44,44) && isBase64(value?.recipient_box,40,16000) &&
  isBase64(value?.sender_box,40,16000) && isBase64(value?.signature,88,88) &&
  !Object.hasOwn(value,'text') && !Object.hasOwn(value,'seed') && !Object.hasOwn(value,'secret');
const sha256 = async str => Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(str)))).map(x => x.toString(16).padStart(2,'0')).join('');
const equal = (a,b) => { if (a.length !== b.length) return false; let v=0; for(let i=0;i<a.length;i++)v |= a.charCodeAt(i)^b.charCodeAt(i); return v===0; };
const messageKey = (a,b) => 'msgs:'+ [a,b].sort().join(':');
const linkKey = (a,b) => 'link:'+ [a,b].sort().join(':');

export class ChatHub {
  constructor(ctx) { this.ctx=ctx; }
  // Persistent rolling-window counters. A WAF and account-level quotas are still recommended.
  async permit(identity, category, max, windowMs) {
    const key='rl:'+identity+':'+category, now=Date.now();
    const old=await this.ctx.storage.get(key);
    const next=!old||now-old.since>=windowMs?{since:now,count:1}:{since:old.since,count:old.count+1};
    if(next.count>max)return false;
    await this.ctx.storage.put(key,next);
    return true;
  }
  async read(request) {
    const auth=request.headers.get('authorization')||'';
    const match=/^Bearer ([a-f0-9]{32})\.([a-f0-9]{64})$/.exec(auth);
    if(!match)return null;
    const user=await this.ctx.storage.get('user:'+match[1]);
    if(!user||!equal(user.secretHash,await sha256(match[2])))return null;
    return user;
  }
  async body(req) {
    if(Number(req.headers.get('content-length')||0)>24000)return null;
    try {
      const text = await req.text();
      if(text.length > 24000)return null;
      return JSON.parse(text);
    }catch{return null;}
  }
  async fetch(request) {
    const url=new URL(request.url), method=request.method, path=url.pathname;
    if(method==='GET' && path==='/health')return json({status:'ok',service:'spyder-chat-devnet',version:2,e2ee:true});
    if(method==='POST'&&path==='/v1/register') {
      if(!(await this.permit(request.headers.get('cf-connecting-ip')||'unknown','register',10,3600000)))return bad('rate_limited',429);
      const b=await this.body(request);
      if(!b||!validId(b.id)||!validSecret(b.secret)||!validInvite(b.invite_code)||!sanitizedName(b.name))return bad('invalid_registration');
      const username = normalizedUsername(b.username);
      if(b.username != null && !validUsername(username))return bad('invalid_username');
      if(b.keys != null && !keyPair(b.keys))return bad('invalid_public_keys');
      if(await this.ctx.storage.get('user:'+b.id))return bad('identity_exists',409);
      if(await this.ctx.storage.get('code:'+b.invite_code))return bad('code_taken',409);
      if(username && await this.ctx.storage.get(usernameKey(username)))return bad('username_taken',409);
      const u={id:b.id,name:sanitizedName(b.name),username:username || null,invite_code:b.invite_code,secretHash:await sha256(b.secret),keys:b.keys || null,discoverable:false};
      await this.ctx.storage.put('user:'+u.id,u);
      await this.ctx.storage.put('code:'+u.invite_code,u.id);
      if(username) await this.ctx.storage.put(usernameKey(username),u.id);
      return json({id:u.id,name:u.name,username:u.username,invite_code:u.invite_code},201);
    }
    const me=await this.read(request);
    if(!me)return bad('unauthorized',401);
    if(method==='GET'&&path==='/v1/me')return json({id:me.id,name:me.name,username:me.username || null,invite_code:me.invite_code,has_keys:!!me.keys});
    if(method==='GET'&&path==='/v2/profile/privacy')return json({discoverable:me.discoverable === true});
    if(method==='POST'&&path==='/v2/profile/privacy'){
      const b=await this.body(request);
      if(typeof b?.discoverable!=='boolean')return bad('invalid_privacy_settings');
      me.discoverable=b.discoverable;
      await this.ctx.storage.put('user:'+me.id,me);
      return json({discoverable:me.discoverable});
    }
    if(method==='POST'&&path==='/v2/keys/activate'){
      const keys=await this.body(request);
      if(!keyPair(keys))return bad('invalid_public_keys');
      if(me.keys){
        if(me.keys.version!==keys.version || me.keys.key_agreement!==keys.key_agreement || me.keys.signature!==keys.signature)return bad('keys_immutable',409);
        return json({status:'already_active'});
      }
      me.keys={version:2,key_agreement:keys.key_agreement,signature:keys.signature};
      await this.ctx.storage.put('user:'+me.id,me);
      return json({status:'active'});
    }
    if(method==='GET'&&path==='/v2/keys'){
      const peerID=url.searchParams.get('peer');
      if(!validId(peerID)||!(await this.ctx.storage.get(linkKey(me.id,peerID))))return bad('not_contacts',403);
      const peer=await this.ctx.storage.get('user:'+peerID);
      if(!peer?.keys)return bad('peer_has_no_encryption_keys',409);
      return json({keys:peer.keys});
    }
    if(method==='POST'&&path==='/v2/contacts/block'){
      const b=await this.body(request), peer=b?.peer_id;
      if(!validId(peer)||peer===me.id)return bad('invalid_contact');
      await this.ctx.storage.put('blocked:'+me.id+':'+peer,true);
      await this.ctx.storage.delete(linkKey(me.id,peer));
      await this.ctx.storage.delete('contact:'+me.id+':'+peer);
      await this.ctx.storage.delete('contact:'+peer+':'+me.id);
      await this.ctx.storage.delete('invite:'+me.id+':'+peer);
      await this.ctx.storage.delete('invite:'+peer+':'+me.id);
      // Historical encrypted/legacy messages remain for retention policy; access is revoked.
      return json({status:'blocked'});
    }
    if(method==='POST'&&path==='/v1/profile/username') {
      const b=await this.body(request);
      const username=normalizedUsername(b?.username);
      if(!validUsername(username))return bad('invalid_username');
      const existing=await this.ctx.storage.get(usernameKey(username));
      if(existing && existing!==me.id)return bad('username_taken',409);
      if(me.username===username)return json({username});
      if(me.username)await this.ctx.storage.delete(usernameKey(me.username));
      await this.ctx.storage.put(usernameKey(username),me.id);
      me.username=username;
      await this.ctx.storage.put('user:'+me.id,me);
      return json({username});
    }
    if(method==='GET'&&path==='/v1/users/search') {
      if(!(await this.permit(me.id,'search',60,60000)))return bad('rate_limited',429);
      const q=normalizedUsername(url.searchParams.get('q'));
      if(!/^[a-z][a-z0-9_]{1,19}$/.test(q))return json({users:[]});
      const matches=await this.ctx.storage.list({prefix:usernameKey(q),limit:25});
      const users=[];
      for(const [key,id] of matches){
        if(id===me.id)continue;
        const peer=await this.ctx.storage.get('user:'+id);
        if(peer && peer.username && peer.discoverable===true && users.length<12)users.push({id:peer.id,name:peer.name,username:peer.username});
      }
      return json({users});
    }
    if(method==='GET'&&path==='/v1/contacts') {
      const contacts=[],requests=[];
      const entries=await this.ctx.storage.list({prefix:'invite:'+me.id+':'});
      for(const [key,invite] of entries) { if(invite.status==='pending') {const peer=await this.ctx.storage.get('user:'+invite.from); if(peer)requests.push({id:peer.id,name:peer.name,username:peer.username || null});} }
      const links=await this.ctx.storage.list({prefix:'contact:'+me.id+':'});
      for(const [key,val] of links) {const peer=await this.ctx.storage.get('user:'+val.peer); if(peer)contacts.push({id:peer.id,name:peer.name,username:peer.username || null});}
      return json({contacts,requests,invite_code:me.invite_code});
    }
    if(method==='POST'&&path==='/v1/invites') {
      if(!(await this.permit(me.id,'invite',15,3600000)))return bad('rate_limited',429);
      const b=await this.body(request);
      const username=normalizedUsername(b?.username);
      if(!validInvite(b?.code) && !validUsername(username))return bad('invalid_recipient_lookup');
      const to=validUsername(username) ? await this.ctx.storage.get(usernameKey(username)) : await this.ctx.storage.get('code:'+b.code);
      if(!to||to===me.id)return bad('invalid_recipient',404);
      if(validUsername(username) && !(await this.ctx.storage.get('user:'+to))?.discoverable)return bad('recipient_private',404);
      if(await this.ctx.storage.get('blocked:'+me.id+':'+to)||await this.ctx.storage.get('blocked:'+to+':'+me.id))return bad('blocked',403);
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
      if(await this.ctx.storage.get('blocked:'+me.id+':'+b.from_id)||await this.ctx.storage.get('blocked:'+b.from_id+':'+me.id))return bad('blocked',403);
      await this.ctx.storage.put(linkKey(me.id,b.from_id),true);
      await this.ctx.storage.put('contact:'+me.id+':'+b.from_id,{peer:b.from_id});
      await this.ctx.storage.put('contact:'+b.from_id+':'+me.id,{peer:me.id});
      await this.ctx.storage.delete(key);
      return json({status:'connected'});
    }
    // Fail closed: never accept a plaintext message, even from obsolete clients.
    if(path==='/v1/messages')return bad('plaintext_protocol_retired',410);
    if(method==='GET'&&path==='/v2/messages') {
      const peer=url.searchParams.get('peer');
      if(!validId(peer)||!(await this.ctx.storage.get(linkKey(me.id,peer))))return bad('not_contacts',403);
      if(!me.keys)return bad('encryption_not_activated',409);
      const all=(await this.ctx.storage.get('encmsgs:'+messageKey(me.id,peer)))||[];
      return json({messages:all.slice(-100)});
    }
    if(method==='POST'&&path==='/v2/messages') {
      if(!(await this.permit(me.id,'message',60,60000)))return bad('rate_limited',429);
      const b=await this.body(request);
      if(!validCipher(b))return bad('invalid_encrypted_envelope');
      if(!me.keys)return bad('encryption_not_activated',409);
      if(!(await this.ctx.storage.get(linkKey(me.id,b.recipient_id))))return bad('not_contacts',403);
      const peer=await this.ctx.storage.get('user:'+b.recipient_id);
      if(!peer?.keys)return bad('peer_has_no_encryption_keys',409);
      const key='encmsgs:'+messageKey(me.id,b.recipient_id), all=(await this.ctx.storage.get(key))||[];
      if(all.some(m=>m.sender_id===me.id&&m.client_id===b.client_id))return json({status:'already_sent'});
      const entry={id:crypto.randomUUID(),client_id:b.client_id,sender_id:me.id,recipient_id:b.recipient_id,
        ephemeral_key:b.ephemeral_key,recipient_box:b.recipient_box,sender_box:b.sender_box,
        signature:b.signature,created_at:new Date().toISOString()};
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
