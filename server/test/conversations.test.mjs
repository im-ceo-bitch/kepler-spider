import test from 'node:test';
import assert from 'node:assert/strict';
import {setup,id} from './helpers/conversation-harness.mjs';

test('message acceptance, delivery and read are separate recipient-confirmed events',async()=>{
 const {send,call,list,history}=await setup();const msg=(await send()).body.message;
 assert.equal(msg.delivered_at,undefined);assert.equal(msg.read_at,undefined);
 assert.equal((await list('b'))[0].unread_count,1);
 // Fetching either history or preview never claims device delivery/read.
 await history('b','a');await list('b');
 assert.equal((await history())[0].delivered_at,undefined);
 assert.equal((await call('/v3/messages/ack',{peer_id:id('a'),delivered_ids:[msg.id],read_ids:[]},'b')).status,200);
 let result=(await history())[0];assert.ok(result.delivered_at);assert.equal(result.read_at,undefined);
 assert.equal((await list('b'))[0].unread_count,1);
 await call('/v3/messages/ack',{peer_id:id('a'),delivered_ids:[],read_ids:[msg.id]},'b');
 result=(await history())[0];assert.ok(result.read_at);assert.equal((await list('b'))[0].unread_count,0);
 const first=result.read_at;await call('/v3/messages/ack',{peer_id:id('a'),delivered_ids:[],read_ids:[msg.id]},'b');
 assert.equal((await history())[0].read_at,first);
});
test('sender and outsiders cannot forge receipts or partially acknowledge invalid batches',async()=>{
 const {send,call,history}=await setup();const msg=(await send()).body.message;
 const payload={peer_id:id('b'),delivered_ids:[msg.id],read_ids:[msg.id]};
 assert.equal((await call('/v3/messages/ack',payload)).status,403);
 assert.equal((await call('/v3/messages/ack',{...payload,peer_id:id('a')},'c')).status,403);
 assert.equal((await call('/v3/messages/ack',{peer_id:id('a'),delivered_ids:[msg.id,'unknown'],read_ids:[]},'b')).status,403);
 assert.equal((await history())[0].delivered_at,undefined);
 assert.equal((await call('/v3/messages/ack',{peer_id:id('a'),delivered_ids:'oops',read_ids:[]},'b')).status,400);
});
test('pin and archive are owner-scoped and mute preferences preserve them',async()=>{
 const {call,list}=await setup();
 await call('/v3/conversations/action',{peer_id:id('b'),action:'pin'});
 await call('/v3/conversations/action',{peer_id:id('b'),action:'archive'});
 await call('/v3/contacts/preferences',{peer_id:id('b'),muted:true,hidden:true});
 let prefs=(await list())[0].preferences;assert.equal(prefs.pinned,true);assert.equal(prefs.archived,true);assert.equal(prefs.muted,true);
 assert.equal((await list('b'))[0].preferences.pinned,undefined);
 await call('/v3/conversations/action',{peer_id:id('b'),action:'unpin'});
 await call('/v3/conversations/action',{peer_id:id('b'),action:'unarchive'});
 prefs=(await list())[0].preferences;assert.equal(prefs.pinned,false);assert.equal(prefs.archived,false);
});
test('delete is owner-only, new incoming restores chat without old history',async()=>{
 const {send,call,list,history}=await setup();await send();await send('b','a');
 await call('/v3/conversations/action',{peer_id:id('b'),action:'delete'});
 assert.equal((await list()).length,0);assert.equal((await history()).length,0);
 assert.equal((await history('b','a')).length,2);
 const newer=(await send('b','a')).body.message;
 assert.equal((await list()).length,1);assert.equal((await list())[0].unread_count,1);
 assert.deepEqual((await history()).map(m=>m.id),[newer.id]);
});
test('legacy messages without sequence migrate safely before deleting',async()=>{
 const {send,db,call,history}=await setup();await send();
 const key=[...db.keys()].find(k=>k.startsWith('encmsgs:'));const data=db.get(key);delete data[0].seq;db.set(key,data);
 for(const key of [...db.keys()])if(key.startsWith('seq:'))db.delete(key);
 assert.equal((await history()).length,1);
 await call('/v3/conversations/action',{peer_id:id('b'),action:'delete'});
 assert.equal((await history()).length,0);
 const msg=(await send('b','a')).body.message;assert.equal(msg.seq,2);assert.equal((await history())[0].id,msg.id);
});
test('presence and typing expire and cannot be published for an unlinked peer',async()=>{
 const {call,list,db}=await setup();
 await call('/v3/presence',{active:true},'b');await call('/v3/typing',{peer_id:id('a'),active:true},'b');
 let row=(await list())[0];assert.equal(row.online,true);assert.equal(row.typing,true);
 db.set('presence:'+id('b'),Date.now()-46000);db.set('typing:'+id('b')+':'+id('a'),Date.now()-8000);
 row=(await list())[0];assert.equal(row.online,false);assert.equal(row.typing,false);
 assert.equal((await call('/v3/typing',{peer_id:id('c'),active:true})).status,403);
});
test('blocking revokes history, receipt and conversation actions',async()=>{
 const {call,send,list}=await setup();const msg=(await send()).body.message;
 await call('/v2/contacts/block',{peer_id:id('b')});
 assert.equal((await list()).length,0);assert.equal((await list('b')).length,0);
 assert.equal((await call('/v3/messages?peer='+id('a'),undefined,'b')).status,403);
 assert.equal((await call('/v3/messages/ack',{peer_id:id('a'),delivered_ids:[msg.id],read_ids:[]},'b')).status,403);
 assert.equal((await call('/v3/conversations/action',{peer_id:id('a'),action:'pin'},'b')).status,403);
});
test('encrypted summary excludes plaintext; duplicates do not inflate unread or sequence',async()=>{
 const {send,list,history}=await setup();const client=crypto.randomUUID();await send('a','b',client);await send('a','b',client);
 const row=(await list('b'))[0];assert.equal(row.unread_count,1);assert.equal(row.last_message.text,undefined);
 assert.equal((await history()).length,1);assert.equal((await history())[0].seq,1);
});
test('reconnecting or sending restores only the owner view while preserving its clear boundary',async()=>{
 const {send,call,list,history}=await setup();await send();
 await call('/v3/conversations/action',{peer_id:id('b'),action:'delete'});
 await call('/v3/contacts/connect',{code:'B'.repeat(24)});
 assert.equal((await list()).length,1);assert.equal((await history()).length,0);
 await call('/v3/conversations/action',{peer_id:id('b'),action:'delete'});
 await send();assert.equal((await list()).length,1);assert.equal((await history()).length,1);
 assert.equal((await history('b','a')).length,2);
});
test('all retained unread messages are reachable and acknowledgements are bounded',async()=>{
 const {send,db,call,list,history}=await setup();const seed=(await send()).body.message;
 const key=[...db.keys()].find(k=>k.startsWith('encmsgs:'));
 const records=Array.from({length:300},(_,i)=>({...seed,id:crypto.randomUUID(),client_id:crypto.randomUUID(),seq:i+1}));
 db.set(key,records);db.set('seq:msgs:'+['a'.repeat(32),'b'.repeat(32)].join(':'),300);
 assert.equal((await history('b','a')).length,300);assert.equal((await list('b'))[0].unread_count,300);
 assert.equal((await call('/v3/messages/ack',{peer_id:id('a'),delivered_ids:records.slice(0,101).map(m=>m.id),read_ids:[]},'b')).status,400);
 for(let start=0;start<300;start+=100){
  assert.equal((await call('/v3/messages/ack',{peer_id:id('a'),delivered_ids:records.slice(start,start+100).map(m=>m.id),read_ids:[]},'b')).status,200);
 }
 assert.equal((await history()).filter(m=>m.delivered_at).length,300);
 assert.equal((await list('b'))[0].unread_count,300);
});
test('different personas talking to the same peer have separate histories and unread state',async()=>{
 const {call,send,list,history}=await setup();await send('a','b');
 assert.equal((await call('/v3/messages?peer='+id('b'),undefined,'c')).status,403);
 await call('/v3/contacts/connect',{code:'B'.repeat(24)},'c');
 assert.equal((await history('c','b')).length,0);
 await send('c','b');
 const rows=await list('b');assert.equal(rows.length,2);
 assert.equal(rows.find(row=>row.peer.id===id('a')).unread_count,1);
 assert.equal(rows.find(row=>row.peer.id===id('c')).unread_count,1);
 const msg=(await history('b','a'))[0];
 await call('/v3/messages/ack',{peer_id:id('a'),delivered_ids:[],read_ids:[msg.id]},'b');
 const after=await list('b');assert.equal(after.find(row=>row.peer.id===id('a')).unread_count,0);
 assert.equal(after.find(row=>row.peer.id===id('c')).unread_count,1);
});
