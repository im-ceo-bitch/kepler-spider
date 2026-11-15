// npm install --no-save jsdom; node tools/spyder-id/test-safari.cjs
const {JSDOM}=require(process.env.SPYDER_TEST_JSDOM || 'jsdom');
const fs=require('fs'),path=require('path'),assert=require('node:assert/strict');
const source=fs.readFileSync(path.join(__dirname,'../../Extensions/SpyderSafari/Resources/form.js'),'utf8');
let tests=0;
function context(html,url='https://example.com/signup'){
 const dom=new JSDOM(html,{url,runScripts:'outside-only'});const w=dom.window;
 w.HTMLElement.prototype.getClientRects=function(){return this.hidden||this.style.display==='none'?[]:[{}]};
 w.eval(source);return w;
}
function test(name,fn){fn();tests++;console.log('PASS',name)}
test('read username and password only from the same form',()=>{
 const w=context('<form><input type=email value=wrong><input type=text></form><form><input autocomplete=username value=alex><input type=password value=secret></form>');
 const r=w.spyderForm('read','https://example.com');assert.equal(r.username,'alex');assert.equal(r.password,'secret');w.close();
});
test('generate fills new password and confirmation and dispatches input/change',()=>{
 const w=context('<form><input type=email><input id=p type=password autocomplete=new-password><input id=c type=password></form>');
 let events=0;w.document.querySelector('#p').addEventListener('input',()=>events++);w.document.querySelector('#p').addEventListener('change',()=>events++);
 w.spyderForm('fill','https://example.com',{username:'alex@example.com',password:'Generated-123!'});
 assert.equal(w.document.querySelector('#c').value,'Generated-123!');assert.equal(events,2);w.close();
});
test('never overwrites a current password during password change',()=>{
 const w=context('<form><input id=old type=password autocomplete=current-password value=old><input id=new type=password autocomplete=new-password><input id=confirm type=password></form>');
 w.spyderForm('fill','https://example.com',{password:'new'});assert.equal(w.document.querySelector('#old').value,'old');assert.equal(w.document.querySelector('#confirm').value,'new');w.close();
});
test('rejects changed origin before accessing fields',()=>{const w=context('<input type=password>');assert.throws(()=>w.spyderForm('read','https://attacker.example'));w.close()});
test('rejects insecure HTTP',()=>{const w=context('<input type=password>','http://example.com');assert.throws(()=>w.spyderForm('read','http://example.com'));w.close()});
test('rejects cross-origin form action',()=>{const w=context('<form action="https://attacker.example"><input type=password></form>');assert.throws(()=>w.spyderForm('fill','https://example.com',{password:'secret'}));w.close()});
test('ignores disabled readonly and invisible password fields',()=>{const w=context('<input type=password disabled><input type=password readonly><input type=password hidden><input type=password style="display:none">');assert.throws(()=>w.spyderForm('read','https://example.com'));w.close()});
test('does not change passwords in other forms',()=>{const w=context('<form><input id=a type=password autocomplete=new-password></form><form><input id=b type=password value=untouched></form>');w.spyderForm('fill','https://example.com',{password:'new'});assert.equal(w.document.querySelector('#b').value,'untouched');w.close()});
test('does not auto-submit a form',()=>{const w=context('<form><input type=password></form>');let submit=false;w.document.querySelector('form').addEventListener('submit',()=>submit=true);w.spyderForm('fill','https://example.com',{password:'x'});assert.equal(submit,false);w.close()});
console.log(`${tests} Safari form tests passed.`);
