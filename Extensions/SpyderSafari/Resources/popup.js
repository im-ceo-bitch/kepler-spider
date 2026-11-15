'use strict';
const $ = id => document.getElementById(id);
let tabID, origin;
async function target() {
  const tab = await browser.tabs.get(tabID);
  if (!tab.url || new URL(tab.url).origin !== origin) throw new Error('Сайт изменился. Откройте Spyder заново.');
  return tab;
}
async function form(operation, payload) {
  await target();
  const result = await browser.scripting.executeScript({target:{tabId:tabID, frameIds:[0]}, func:spyderForm, args:[operation,origin,payload || null]});
  if (!result?.[0]?.result) throw new Error('Safari не предоставил доступ к форме. Проверьте разрешение расширения.');
  return result[0].result;
}
async function native(action, extra={}) {
  await target();
  const result = await browser.runtime.sendNativeMessage('com.spyder.wallet', {action,origin,...extra});
  if (result?.error) throw new Error(result.error);
  if (!result) throw new Error('Нет ответа от сейфа.');
  return result;
}
async function run(task) {
  document.querySelectorAll('button').forEach(b=>b.disabled=true);
  $('status').textContent='Подтвердите доступ к Spyder ID…';
  try { await task(); } catch(e) { $('status').textContent=e.message || 'Не удалось выполнить действие.'; }
  finally { document.querySelectorAll('button').forEach(b=>b.disabled=false); }
}
function account(item) {
  const row=document.createElement('div');row.className='account';
  const title=document.createElement('strong'); title.textContent=item.title;
  const user=document.createElement('small'); user.textContent=item.username+(item.draft?' · Черновик':'');
  const fill=document.createElement('button');fill.textContent='Заполнить';
  fill.onclick=()=>run(async()=>{const credential=await native('fill',{id:item.id});await form('fill',credential);credential.password='';$('status').textContent='Поля заполнены. Нажмите кнопку входа на сайте.';});
  row.append(title,user,fill);
  if(item.draft){const confirm=document.createElement('button');confirm.textContent='Подтвердить созданный пароль';confirm.onclick=()=>run(async()=>{let current;try{current=await form('read')}catch{};try{await native('confirm',{id:item.id,username:current?.username||item.username,password:current?.password||null});}finally{if(current)current.password='';}item.draft=false;confirm.remove();user.textContent=item.username;$('status').textContent='Аккаунт сохранён. Это не проверка успешной регистрации на сайте.';});row.append(confirm);}
  $('accounts').append(row);
}
$('generate').onclick=()=>run(async()=>{
  const username=$('username').value.trim();if(!username)throw new Error('Укажите логин.');
  const result=await native('generate',{username,title:$('title').value.trim()});
  account({id:result.id,username,title:$('title').value || new URL(origin).host,draft:true});
  try {await form('fill',result);$('status').textContent='Пароль заполнен. Черновик уже в сейфе. После регистрации откройте Spyder и подтвердите сохранение.';}
  catch(e){throw new Error('Черновик сохранён в сейфе, но поля не заполнены: '+e.message);}
  finally{result.password='';}
});
$('save').onclick=()=>run(async()=>{
  const values=await form('read');const username=$('username').value.trim()||values.username;
  if(!values.password||!username)throw new Error('Заполните логин и пароль на сайте.');
  try{await native('save',{username,password:values.password,title:$('title').value.trim()});$('status').textContent='Доступ сохранён отдельной записью в Spyder ID.';}finally{values.password='';}
});
$('list').onclick=()=>run(async()=>{const result=await native('list');$('accounts').replaceChildren();result.items.forEach(account);$('status').textContent=result.items.length?'Выберите аккаунт.':'На этом сайте ещё нет сохранённых аккаунтов.';});
(async()=>{try{const [tab]=await browser.tabs.query({active:true,currentWindow:true});tabID=tab.id;const url=new URL(tab.url);if(url.protocol!=='https:')throw new Error('Откройте HTTPS-страницу входа или регистрации.');origin=url.origin;$('site').textContent=url.host;$('title').value=url.host;try{const data=await form('read');$('username').value=data.username;data.password='';}catch{} }catch(e){$('status').textContent=e.message;document.querySelectorAll('button').forEach(b=>b.disabled=true);}})();
