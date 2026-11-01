import test from 'node:test';
import assert from 'node:assert/strict';
import {webcrypto} from 'node:crypto';
import unifiedWorker, {ChatHub, SpyderMessageRoom} from '../src/index.mjs';
if (!globalThis.crypto) globalThis.crypto = webcrypto;

const makeStorage = () => {
  const records=new Map();
  return {records, get: async k=>records.get(k), put: async (k,v)=>{records.set(k,v)}, delete: async k=>records.delete(k), transaction: async fn=>fn({get:async k=>records.get(k),put:async(k,v)=>records.set(k,v)})};
};
function harness({chat=true}={}) {
  const roomKeys=[];
  const oldRoom=new SpyderMessageRoom({storage:makeStorage(),getWebSockets:()=>[]});
  const hub=new ChatHub({storage:makeStorage()},{});
  const env={
    DEVNET_OPERATOR_TOKEN:'private-test-only',
    MESSAGE_ROOMS:{idFromName: id=>id,get:id=>{roomKeys.push(id);return oldRoom;}},
    ...(chat ? {CHAT_HUB:{idFromName:id=>id,get:id=>{assert.equal(id,'spyder-chat-devnet-v1');return hub;}}} : {})
  };
  const req=async(path,{method='GET',body,headers={}}={})=> {
    const res=await unifiedWorker.fetch(new Request('https://kepler-spider.helloiumrah.workers.dev'+path,{
      method,headers:{...headers,...(body?{'content-type':'application/json'}:{})},
      ...(body?{body:JSON.stringify(body)}:{})
    }),env);
    return {status:res.status,data:await res.json()};
  };
  return {req,roomKeys};
}

test('legacy /health is byte-compatible in JSON structure; Chat v2 has independent /chat/health',async()=>{
  const {req}=harness();
  assert.deepEqual((await req('/health')).data,{status:'ok',name:'spyder-messagechain-devnet',version:1,e2ee_audited:false});
  assert.deepEqual((await req('/chat/health')).data,{status:'ok',service:'spyder-chat-devnet',version:2,e2ee:true});
});

test('existing MessageChain routes retain operator authentication and same conversation id',async()=>{
  const {req,roomKeys}=harness();
  const cid='a'.repeat(64);
  assert.equal((await req('/v1/conversations/'+cid+'/envelopes')).status,403);
  const headers={'x-spyder-devnet-token':'private-test-only'};
  const created=await req('/v1/conversations/'+cid+'/init',{
    method:'POST',headers,body:{participants:['b'.repeat(60),'c'.repeat(60)]}
  });
  assert.equal(created.status,201);
  assert.equal((await req('/v1/conversations/'+cid+'/envelopes',{headers})).status,200);
  assert.deepEqual(roomKeys,[cid,cid]);
});

test('Chat v2 register is served from same Worker and does not use MESSAGE_ROOMS',async()=>{
  const {req,roomKeys}=harness();
  const data=await req('/v1/register',{method:'POST',body:{
    id:'a'.repeat(32),secret:'b'.repeat(64),invite_code:'A'.repeat(24),
    name:'Alice',username:'alice_spyder',discoverable:true
  }});
  assert.equal(data.status,201);
  assert.equal(data.data.username,'alice_spyder');
  assert.deepEqual(roomKeys,[]);
});

test('missing CHAT_HUB does not change legacy service availability',async()=>{
  const {req}=harness({chat:false});
  assert.equal((await req('/health')).status,200);
  assert.equal((await req('/chat/health')).status,503);
  assert.equal((await req('/v1/conversations/'+'a'.repeat(64)+'/envelopes')).status,403);
});
