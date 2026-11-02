import {apnsConfigured, sendAPNs} from './apns.mjs';
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
const cleanBio = value => typeof value === 'string' && value.length <= 160 && !/[\u0000-\u0009\u000b-\u001f\u007f]/.test(value);
const cleanStatus = value => typeof value === 'string' && value.length <= 64 && !/[\u0000-\u001f\u007f]/.test(value);
const avatarStyles = new Set(['pulse','orbit','web','halo','constellation','radar','waves','nexus','eclipse','breathe','spark','quiet']);
const avatarColors = new Set(['red','blue','violet','cyan','magenta','lime','amber','emerald','orange','ice','pink','ultraviolet','gold','silver','copper','white']);
const validAvatar = value => value && typeof value === 'object' && !Array.isArray(value) &&
  value.version === 1 && avatarStyles.has(value.style) && avatarColors.has(value.accent) &&
  typeof value.seed === 'string' && /^[a-f0-9]{32}$/.test(value.seed);
const privacyMode = u => ['public','private','hidden'].includes(u.privacy_mode) ? u.privacy_mode : (u.discoverable===true?'public':'private');
const publicPerson = u => ({privacy_mode:privacyMode(u),id:u.id,name:u.name,username:u.username || null,
  bio:u.bio || '',status:u.status || '',avatar:u.avatar || null});
// Usernames are public, case-insensitive, unique identifiers. They are not credentials.
const normalizedUsername = value => typeof value === 'string' ? value.trim().replace(/^@/, '').toLowerCase() : '';
const validUsername = value => typeof value === 'string' && /^[a-z][a-z0-9_]{2,19}$/.test(value) && !['admin', 'support', 'spyder', 'system', 'security'].includes(value);
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
  constructor(ctx, env) { this.ctx=ctx; this.env=env; }
  // A push wake-up is best-effort, never proof of message delivery. No plaintext is sent.
  queuePush(recipient, event, sender = null) {
    const job = this.notify(recipient, event, sender);
    if (typeof this.ctx.waitUntil === 'function') this.ctx.waitUntil(job);
    else void job;
  }
  async notify(recipient, event, sender = null) {
    if(sender && (await this.ctx.storage.get('contactprefs:'+recipient+':'+sender))?.muted)return;
    const record = await this.ctx.storage.get('push:'+recipient);
    if (!record?.token || !record.enabled) return;
    const status = await sendAPNs(this.env, record.token, event, fetch, record.sound || 'pulse');
    // Diagnostic metadata contains only HTTP status and time, never APNs tokens or chat text.
    await this.ctx.storage.put('pushlast:'+recipient, {status, at:new Date().toISOString()});
    if (status === 410) {
      // Invalidation must not delete a device token replaced while APNs was in flight.
      const latest = await this.ctx.storage.get('push:'+recipient);
      if (latest?.token === record.token) await this.ctx.storage.delete('push:'+recipient);
    }
  }
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
  async connectPeople(from,to,source,pendingKey=null) {
    const apply=async storage=>{
      const sender=await storage.get('user:'+from),recipient=await storage.get('user:'+to);
      if(!sender||!recipient||from===to)return {error:'invalid_recipient',code:404};
      if(await storage.get('blocked:'+from+':'+to)||await storage.get('blocked:'+to+':'+from)) {
        if(pendingKey)await storage.delete(pendingKey);
        return {error:'blocked',code:403};
      }
      if(source==='username'&&!recipient.discoverable)return {error:'recipient_private',code:404};
      if(await storage.get(linkKey(from,to))) {
        const key='contactprefs:'+from+':'+to,prefs=await storage.get(key);
        if(prefs?.removed){prefs.removed=false;await storage.put(key,prefs);}
        if(pendingKey)await storage.delete(pendingKey);
        return {status:'already_connected',peer:publicPerson(recipient)};
      }
      if(privacyMode(recipient)==='hidden'){if(pendingKey)await storage.delete(pendingKey);return {error:'recipient_hidden',code:403};}
      const privacy=await storage.get('contactprivacy:'+to);
      if(privacy?.limit_unknown && source!=='code') {
        if(pendingKey)await storage.delete(pendingKey);
        return {error:'unknown_contacts_limited',code:403};
      }
      const at=new Date().toISOString();
      await storage.put(linkKey(from,to),true);
      await storage.put('contact:'+from+':'+to,{peer:to});
      await storage.put('contact:'+to+':'+from,{peer:from});
      await storage.delete('invite:'+from+':'+to);
      await storage.delete('invite:'+to+':'+from);
      for(const [owner,peer,direction] of [[from,to,'outgoing'],[to,from,'incoming']]) {
        const history=await storage.get('invitehistory:'+owner)||[];
        await storage.put('invitehistory:'+owner,[{peer_id:peer,direction,source,at},...history].slice(0,40));
      }
      return {status:'connected',peer:publicPerson(recipient)};
    };
    // Cloudflare commits both contact records and history atomically.
    return typeof this.ctx.storage.transaction==='function'
      ? this.ctx.storage.transaction(apply) : apply(this.ctx.storage);
  }
  async transaction(apply) {
    return typeof this.ctx.storage.transaction==='function'
      ? this.ctx.storage.transaction(apply) : apply(this.ctx.storage);
  }
  async sequenced(storage,a,b) {
    const key='encmsgs:'+messageKey(a,b);
    const messages=await storage.get(key)||[];
    let counter=await storage.get('seq:'+messageKey(a,b))||0;
    for(const item of messages) {
      if(!Number.isSafeInteger(item.seq))item.seq=++counter;
      else counter=Math.max(counter,item.seq);
    }
    await storage.put('seq:'+messageKey(a,b),counter);
    return {key,messages,counter};
  }
  async conversationRoutes(request,me,url) {
    const path=url.pathname,method=request.method;
    if(method==='POST'&&path==='/v3/presence') {
      if(!(await this.permit(me.id,'presence',40,60000)))return bad('rate_limited',429);
      const b=await this.body(request);
      if(typeof b?.active!=='boolean')return bad('invalid_presence');
      await this.ctx.storage.put('presence:'+me.id,b.active?Date.now():0);
      return json({status:'saved'});
    }
    if(method==='GET'&&path==='/v3/conversations') {
      const links=await this.ctx.storage.list({prefix:'contact:'+me.id+':'}),conversations=[];
      for(const [,link] of links) {
        const peer=await this.ctx.storage.get('user:'+link.peer);if(!peer)continue;
        const prefs=await this.ctx.storage.get('contactprefs:'+me.id+':'+peer.id)||{muted:false,hidden:false};
        const all=await this.ctx.storage.get('encmsgs:'+messageKey(me.id,peer.id))||[];
        const visible=all.filter(m=>(m.seq||1)>(prefs.clear_through||0));
        const latest=visible.at(-1)||null;
        const incomingNew=latest&&latest.sender_id===peer.id&&latest.seq>(prefs.clear_through||0);
        if(prefs.removed&&!incomingNew)continue;
        conversations.push({peer:publicPerson(peer),preferences:{...prefs,removed:false},last_message:latest,
          unread_count:visible.filter(m=>m.recipient_id===me.id&&!m.read_at).length,
          online:(await this.ctx.storage.get('presence:'+peer.id)||0)>Date.now()-45000,
          typing:(await this.ctx.storage.get('typing:'+peer.id+':'+me.id)||0)>Date.now()-7000});
      }
      return json({conversations});
    }
    if((path==='/v3/messages'||path==='/v3/messages/ack'||path==='/v3/typing'||path==='/v3/conversations/action')) {
      const b=method==='POST'?await this.body(request):null;
      const peer=method==='GET'?url.searchParams.get('peer'):b?.peer_id;
      if(!validId(peer)||!(await this.ctx.storage.get(linkKey(me.id,peer))))return bad('not_contacts',403);
      if(method==='POST'&&path==='/v3/typing') {
        if(typeof b.active!=='boolean')return bad('invalid_typing');
        if(!(await this.permit(me.id,'typing',90,60000)))return bad('rate_limited',429);
        await this.ctx.storage.put('typing:'+me.id+':'+peer,b.active?Date.now():0);
        return json({status:'saved'});
      }
      if(method==='POST'&&path==='/v3/conversations/action') {
        if(!['pin','archive','restore','delete','unpin','unarchive'].includes(b.action))return bad('invalid_action');
        return this.transaction(async storage=>{
          if(!(await storage.get(linkKey(me.id,peer))))return bad('not_contacts',403);
          const key='contactprefs:'+me.id+':'+peer;
          const prefs=await storage.get(key)||{muted:false,hidden:false};
          if(b.action==='pin')prefs.pinned=true;
          if(b.action==='unpin')prefs.pinned=false;
          if(b.action==='archive')prefs.archived=true;
          if(b.action==='unarchive'||b.action==='restore'){prefs.archived=false;prefs.removed=false;}
          if(b.action==='delete'){
            const log=await this.sequenced(storage,me.id,peer);
            await storage.put(log.key,log.messages);
            prefs.clear_through=log.counter;prefs.removed=true;prefs.archived=false;prefs.pinned=false;
          }
          await storage.put(key,prefs);return json({status:'saved'});
        });
      }
      if(method==='GET'&&path==='/v3/messages') {
        if(!me.keys)return bad('encryption_not_activated',409);
        const log=await this.ctx.storage.get('encmsgs:'+messageKey(me.id,peer))||[];
        const prefs=await this.ctx.storage.get('contactprefs:'+me.id+':'+peer);
        return json({messages:log.filter(m=>(m.seq||1)>(prefs?.clear_through||0))});
      }
      if(method==='POST'&&path==='/v3/messages/ack') {
        const delivered=b.delivered_ids,read=b.read_ids;
        if(!Array.isArray(delivered)||!Array.isArray(read)||delivered.length>100||read.length>100||
          [...delivered,...read].some(id=>typeof id!=='string'||id.length>64))return bad('invalid_ack');
        return this.transaction(async storage=>{
          // Recheck authorization inside the transaction, including concurrent block operations.
          if(!(await storage.get(linkKey(me.id,peer))))return bad('not_contacts',403);
          const key='encmsgs:'+messageKey(me.id,peer),all=await storage.get(key)||[];
          const ids=new Set([...delivered,...read]);
          if([...ids].some(id=>!all.some(m=>m.id===id&&m.recipient_id===me.id)))return bad('invalid_ack_target',403);
          const readSet=new Set(read),now=new Date().toISOString();
          for(const m of all)if(ids.has(m.id)){
            m.delivered_at ||= now;if(readSet.has(m.id))m.read_at ||= now;
          }
          await storage.put(key,all);return json({status:'saved'});
        });
      }
    }
    return null;
  }
  async fetch(request) {
    const url=new URL(request.url), method=request.method, path=url.pathname;
    if(method==='GET' && path==='/health')return json({status:'ok',service:'spyder-chat-devnet',version:2,e2ee:true});
    if(method==='POST'&&path==='/v1/register') {
      if(!(await this.permit(request.headers.get('cf-connecting-ip')||'unknown','register',10,3600000)))return bad('rate_limited',429);
      const b=await this.body(request);
      if(!b||!validId(b.id)||!validSecret(b.secret)||!validInvite(b.invite_code)||!sanitizedName(b.name))return bad('invalid_registration');
      const username = normalizedUsername(b.username);
      if(b.username != null && b.username !== '' && !validUsername(username))return bad('invalid_username');
      if(b.keys != null && !keyPair(b.keys))return bad('invalid_public_keys');
      if(await this.ctx.storage.get('user:'+b.id))return bad('identity_exists',409);
      if(await this.ctx.storage.get('code:'+b.invite_code))return bad('code_taken',409);
      if(username && await this.ctx.storage.get(usernameKey(username)))return bad('username_taken',409);
      const u={id:b.id,name:sanitizedName(b.name),username:username || null,invite_code:b.invite_code,
        secretHash:await sha256(b.secret),keys:b.keys || null,discoverable:Boolean(username && b.discoverable===true),
        bio:'',status:'',avatar:null};
      await this.ctx.storage.put('user:'+u.id,u);
      await this.ctx.storage.put('code:'+u.invite_code,u.id);
      if(username) await this.ctx.storage.put(usernameKey(username),u.id);
      return json({id:u.id,name:u.name,username:u.username,invite_code:u.invite_code},201);
    }
    const me=await this.read(request);
    if(!me)return bad('unauthorized',401);
    if(path.startsWith('/v3/')) {
      const result=await this.conversationRoutes(request,me,url);
      if(result)return result;
    }
    if(path==='/v4/profile/privacy' && (method==='GET'||method==='POST')) {
      if(method==='GET')return json({mode:privacyMode(me),discoverable:me.discoverable===true});
      const b=await this.body(request);
      if(!['public','private','hidden'].includes(b?.mode))return bad('invalid_privacy');
      return this.transaction(async storage=>{
        const latest=await storage.get('user:'+me.id);
        if(b.mode==='public'&&!validUsername(latest.username))return bad('username_required',409);
        latest.privacy_mode=b.mode;latest.discoverable=b.mode==='public';
        await storage.put('user:'+me.id,latest);
        return json({mode:latest.privacy_mode,discoverable:latest.discoverable});
      });
    }
    if(method==='GET'&&path==='/v1/me')return json({...publicPerson(me),invite_code:me.invite_code,has_keys:!!me.keys});
    if(method==='GET'&&path==='/v3/profile/me')return json(publicPerson(me));
    if(method==='POST'&&path==='/v3/profile'){
      const b=await this.body(request);
      if(!b || !cleanBio(b.bio) || !cleanStatus(b.status) || !validAvatar(b.avatar))return bad('invalid_profile');
      return this.transaction(async storage=>{
        const latest=await storage.get('user:'+me.id);
        latest.bio=b.bio;latest.status=b.status;latest.avatar=b.avatar;
        await storage.put('user:'+me.id,latest);
        return json(publicPerson(latest));
      });
    }
    if(method==='GET'&&path==='/v3/profile/contact'){
      const peerId=url.searchParams.get('peer');
      if(!validId(peerId) || !(await this.ctx.storage.get(linkKey(me.id,peerId))))return bad('not_contacts',403);
      const peer=await this.ctx.storage.get('user:'+peerId);
      if(!peer)return bad('not_found',404);
      return json(publicPerson(peer));
    }
    if(method==='GET'&&path==='/v2/push/status') {
      const p=await this.ctx.storage.get('push:'+me.id);
      const last=await this.ctx.storage.get('pushlast:'+me.id);
      return json({provider_ready:apnsConfigured(this.env),enabled:Boolean(p?.enabled),
        sound:p?.enabled ? (p.sound || 'system') : null,
        last_apns_status:last?.status ?? null, last_attempt_at:last?.at ?? null});
    }
    if(method==='POST'&&path==='/v2/push/register') {
      const b=await this.body(request);
      if(!apnsConfigured(this.env))return bad('push_not_configured',503);
      if(typeof b?.token!=='string'||!/^(?:[a-f0-9]{2}){16,128}$/i.test(b.token))return bad('invalid_push_token');
      // One token per identity for this single-device protocol. No token in responses.
      const sound = ['pulse','system','mute'].includes(b.sound) ? b.sound : 'system';
      await this.ctx.storage.put('push:'+me.id,{token:b.token.toLowerCase(),enabled:true,sound});
      return json({status:'registered'});
    }
    if(method==='POST'&&path==='/v2/push/preferences') {
      const b=await this.body(request);
      if(!['pulse','system','mute'].includes(b?.sound))return bad('invalid_notification_sound');
      const p=await this.ctx.storage.get('push:'+me.id);
      if(!p?.enabled)return bad('push_not_registered',409);
      await this.ctx.storage.put('push:'+me.id,{...p,sound:b.sound});
      return json({status:'saved'});
    }
    if(method==='POST'&&path==='/v2/push/test') {
      if(!(await this.permit(me.id,'push_test',3,3600000)))return bad('rate_limited',429);
      const p=await this.ctx.storage.get('push:'+me.id);
      if(!p?.token || !p?.enabled)return bad('push_not_registered',409);
      if(!apnsConfigured(this.env))return bad('push_not_configured',503);
      this.queuePush(me.id,'test');
      return json({status:'queued'});
    }
    if(method==='POST'&&path==='/v2/push/unregister') {
      await this.ctx.storage.delete('push:'+me.id);
      return json({status:'unregistered'});
    }
    if(method==='POST'&&path==='/v2/profile/name') {
      const b=await this.body(request);
      if(typeof b?.name !== 'string' || !b.name.trim() || b.name.trim().length>36)return bad('invalid_display_name');
      return this.transaction(async storage=>{
        const latest=await storage.get('user:'+me.id);latest.name=sanitizedName(b.name);
        await storage.put('user:'+me.id,latest);return json({name:latest.name});
      });
    }
    if(method==='GET'&&path==='/v2/profile/privacy')return json({discoverable:me.discoverable === true});
    if(method==='POST'&&path==='/v2/profile/privacy'){
      const b=await this.body(request);
      if(typeof b?.discoverable!=='boolean')return bad('invalid_privacy_settings');
      return this.transaction(async storage=>{
        const latest=await storage.get('user:'+me.id);
        if(privacyMode(latest)==='hidden')return bad('explicit_privacy_change_required',409);
        if(b.discoverable&&!validUsername(latest.username))return bad('username_required',409);
        latest.privacy_mode=b.discoverable?'public':'private';latest.discoverable=b.discoverable;
        await storage.put('user:'+me.id,latest);return json({discoverable:latest.discoverable});
      });
    }
    if(method==='POST'&&path==='/v2/keys/activate'){
      const keys=await this.body(request);
      if(!keyPair(keys))return bad('invalid_public_keys');
      return this.transaction(async storage=>{
        const latest=await storage.get('user:'+me.id);
        if(latest.keys){
          if(latest.keys.version!==keys.version||latest.keys.key_agreement!==keys.key_agreement||latest.keys.signature!==keys.signature)return bad('keys_immutable',409);
          return json({status:'already_active'});
        }
        latest.keys={version:2,key_agreement:keys.key_agreement,signature:keys.signature};
        await storage.put('user:'+me.id,latest);return json({status:'active'});
      });
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
      await this.transaction(async storage=>{
      await storage.put('blocked:'+me.id+':'+peer,true);
      await storage.delete(linkKey(me.id,peer));
      await storage.delete('contact:'+me.id+':'+peer);
      await storage.delete('contact:'+peer+':'+me.id);
      await storage.delete('invite:'+me.id+':'+peer);
      await storage.delete('invite:'+peer+':'+me.id);
      });
      // Historical encrypted/legacy messages remain for retention policy; access is revoked.
      return json({status:'blocked'});
    }
    if(method==='POST'&&path==='/v1/profile/username') {
      const b=await this.body(request);
      const username=normalizedUsername(b?.username);
      if(!validUsername(username))return bad('invalid_username');
      return this.transaction(async storage=>{
        const latest=await storage.get('user:'+me.id);
        const existing=await storage.get(usernameKey(username));
        if(existing&&existing!==me.id)return bad('username_taken',409);
        if(latest.username===username)return json({username});
        if(latest.username)await storage.delete(usernameKey(latest.username));
        await storage.put(usernameKey(username),me.id);latest.username=username;
        await storage.put('user:'+me.id,latest);return json({username});
      });
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
        if(peer && peer.username && peer.discoverable===true && users.length<12)users.push(publicPerson(peer));
      }
      return json({users});
    }
    if(method==='POST'&&path==='/v3/contacts/preferences') {
      const b=await this.body(request),peer=b?.peer_id;
      if(!validId(peer)||!(await this.ctx.storage.get(linkKey(me.id,peer))))return bad('not_contacts',403);
      if(typeof b.muted!=='boolean'||typeof b.hidden!=='boolean')return bad('invalid_preferences');
      const existing=await this.ctx.storage.get('contactprefs:'+me.id+':'+peer)||{};
      await this.ctx.storage.put('contactprefs:'+me.id+':'+peer,{...existing,muted:b.muted,hidden:b.hidden});
      return json({status:'saved'});
    }
    if(path==='/v3/contacts/privacy' && (method==='GET'||method==='POST')) {
      if(method==='POST') {
        const b=await this.body(request);
        if(typeof b?.limit_unknown!=='boolean')return bad('invalid_privacy');
        await this.ctx.storage.put('contactprivacy:'+me.id,{limit_unknown:b.limit_unknown});
      }
      return json(await this.ctx.storage.get('contactprivacy:'+me.id)||{limit_unknown:false});
    }
    if(method==='GET'&&path==='/v3/invites/history') {
      return json({events:await this.ctx.storage.get('invitehistory:'+me.id)||[]});
    }
    if(method==='GET'&&path==='/v1/contacts') {
      // Migrate old pending invitations using the same block/privacy checks as new connections.
      const entries=await this.ctx.storage.list({prefix:'invite:'+me.id+':'});
      for(const [key,invite] of entries) {
        if(invite.status==='pending')await this.connectPeople(invite.from,me.id,'legacy',key);
      }
      const contacts=[],preferences={};
      const links=await this.ctx.storage.list({prefix:'contact:'+me.id+':'});
      for(const [key,val] of links) {const peer=await this.ctx.storage.get('user:'+val.peer); if(peer){contacts.push(publicPerson(peer));preferences[peer.id]=await this.ctx.storage.get('contactprefs:'+me.id+':'+peer.id)||{muted:false,hidden:false};}}
      return json({contacts,requests:[],preferences,invite_code:me.invite_code});
    }
    if(method==='POST'&&(path==='/v1/invites'||path==='/v3/contacts/connect')) {
      if(!(await this.permit(me.id,'invite',15,3600000)))return bad('rate_limited',429);
      const b=await this.body(request);
      const username=normalizedUsername(b?.username);
      if(!validInvite(b?.code) && !validUsername(username))return bad('invalid_recipient_lookup');
      const byCode=validInvite(b?.code);
      const to=byCode ? await this.ctx.storage.get('code:'+b.code) : await this.ctx.storage.get(usernameKey(username));
      if(!to||to===me.id)return bad('invalid_recipient',404);
      const result=await this.connectPeople(me.id,to,byCode?'code':'username');
      if(result.error)return bad(result.error,result.code);
      if(result.status==='connected')this.queuePush(to,'invite');
      return json(result);
    }
    if(method==='POST'&&path==='/v1/invites/accept') {
      // Compatibility for installed old clients; new clients have no accept/reject flow.
      const b=await this.body(request);
      if(!validId(b?.from_id))return bad('invalid_sender');
      if(await this.ctx.storage.get(linkKey(me.id,b.from_id)))return json({status:'connected'});
      const key='invite:'+me.id+':'+b.from_id;
      const invite=await this.ctx.storage.get(key);
      if(!invite||invite.status!=='pending')return bad('invitation_not_found',404);
      const result=await this.connectPeople(b.from_id,me.id,'legacy',key);
      return result.error?bad(result.error,result.code):json(result);
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
      const result=await this.transaction(async storage=>{
        if(!(await storage.get(linkKey(me.id,b.recipient_id))))return {error:'not_contacts'};
        const log=await this.sequenced(storage,me.id,b.recipient_id),all=log.messages;
        if(all.some(m=>m.sender_id===me.id&&m.client_id===b.client_id))return {status:'already_sent'};
        const entry={id:crypto.randomUUID(),client_id:b.client_id,sender_id:me.id,recipient_id:b.recipient_id,
          ephemeral_key:b.ephemeral_key,recipient_box:b.recipient_box,sender_box:b.sender_box,
          signature:b.signature,created_at:new Date().toISOString(),seq:log.counter+1};
        all.push(entry);
        await storage.put(log.key,all.slice(-300));
        await storage.put('seq:'+messageKey(me.id,b.recipient_id),entry.seq);
        // A new message restores a deleted recipient-side conversation, without restoring old history.
        for(const [owner,other] of [[b.recipient_id,me.id],[me.id,b.recipient_id]]) {
          const prefKey='contactprefs:'+owner+':'+other,prefs=await storage.get(prefKey);
          if(prefs?.removed){prefs.removed=false;await storage.put(prefKey,prefs);}
        }
        return {status:'sent',message:entry};
      });
      if(result.error)return bad(result.error,403);
      if(result.status==='already_sent')return json(result);
      this.queuePush(b.recipient_id, 'message', me.id);
      return json(result,201);
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
