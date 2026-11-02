import {webcrypto} from 'node:crypto';
import {ChatHub} from '../../src/chat.mjs';
if(!globalThis.crypto)globalThis.crypto=webcrypto;
export const id=n=>n.repeat(32),code=n=>n.toUpperCase().repeat(24);
export const cipher=(recipient,client=crypto.randomUUID())=>({recipient_id:id(recipient),client_id:client,
 ephemeral_key:Buffer.alloc(32,'x').toString('base64'),recipient_box:Buffer.alloc(52,'y').toString('base64'),
 sender_box:Buffer.alloc(52,'z').toString('base64'),signature:Buffer.alloc(64,'s').toString('base64')});
export async function setup(){
 const db=new Map(),pushes=[];
 const makeStorage=map=>({get:async k=>structuredClone(map.get(k)),put:async(k,v)=>map.set(k,structuredClone(v)),
  delete:async k=>map.delete(k),list:async({prefix})=>new Map(structuredClone([...map].filter(([k])=>k.startsWith(prefix))))});
 const storage=makeStorage(db);
 storage.transaction=async fn=>{
  const staged=new Map(structuredClone([...db]));const result=await fn(makeStorage(staged));
  db.clear();for(const [k,v]of staged)db.set(k,v);return result;
 };
 const hub=new ChatHub({storage});hub.queuePush=(...args)=>pushes.push(args);
 const call=async(path,body,who='a',method=body===undefined?'GET':'POST')=>{
  const res=await hub.fetch(new Request('https://test'+path,{method,
   headers:{authorization:'Bearer '+id(who)+'.'+who.repeat(64),'content-type':'application/json'},
   body:method==='GET'?undefined:JSON.stringify(body)}));
  return {status:res.status,body:await res.json()};
 };
 for(const n of ['a','b','c']){
  const keys={version:2,key_agreement:Buffer.alloc(32,n).toString('base64'),signature:Buffer.alloc(32,n).toString('base64')};
  await call('/v1/register',{id:id(n),secret:n.repeat(64),invite_code:code(n),name:n,keys,username:'user_'+n,discoverable:true},n);
 }
 await call('/v3/contacts/connect',{code:code('b')});
 const send=async(who='a',recipient='b',client)=>call('/v2/messages',cipher(recipient,client),who);
 const list=async(who='a')=>(await call('/v3/conversations',undefined,who)).body.conversations;
 const history=async(who='a',peer='b')=>(await call('/v3/messages?peer='+id(peer),undefined,who)).body.messages;
 return {db,hub,call,send,list,history,pushes};
}
