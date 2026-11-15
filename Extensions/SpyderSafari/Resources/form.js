/* Runs only on explicit extension invocation, in an isolated world, top frame only.
   No DOM-injected buttons, listeners to keystrokes, background capture or remote traffic. */
function spyderForm(operation, expectedOrigin, payload) {
  if (window.top !== window || location.origin !== expectedOrigin || location.protocol !== 'https:') throw new Error('Страница изменилась. Откройте Spyder заново.');
  const visible = el => !el.disabled && !el.readOnly && el.getClientRects().length > 0 && getComputedStyle(el).visibility !== 'hidden';
  const all = [...document.querySelectorAll('input')].filter(visible);
  const passwords = all.filter(el => el.type === 'password');
  const primary = passwords.find(el => el.autocomplete === 'new-password') || passwords[0];
  if (!primary) throw new Error('Не найдено доступное поле пароля. Откройте нужный шаг формы.');
  const form = primary.form;
  const fields = all.filter(el => form ? el.form === form : !el.form);
  const user = fields.find(el => /(^|\s)username(\s|$)/.test(el.autocomplete)) || fields.find(el => el.type === 'email') || fields.filter(el => el.type === 'text' && el.compareDocumentPosition(primary) & Node.DOCUMENT_POSITION_FOLLOWING).at(-1);
  if (operation === 'read') return {username: user?.value || '', password: primary.value};
  if (operation !== 'fill' || !payload || typeof payload.password !== 'string') throw new Error('Некорректный запрос.');
  // Refuse a form explicitly submitting credentials to a different origin or insecure URL.
  if (form && new URL(form.action || location.href, location.href).origin !== expectedOrigin) throw new Error('Форма отправляет данные на другой сайт. Заполнение отменено.');
  const set = (el, value) => {
    const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set;
    setter.call(el, value); el.dispatchEvent(new Event('input', {bubbles:true})); el.dispatchEvent(new Event('change', {bubbles:true}));
  };
  if (user && payload.username) set(user, payload.username);
  set(primary, payload.password);
  // Only fill confirmation fields in the same form; never replace a current-password field.
  const confirm = fields.filter(el => el !== primary && el.type === 'password' && el.autocomplete !== 'current-password');
  if (confirm.length === 1 && (primary.autocomplete === 'new-password' || /confirm|repeat|повтор|подтвер/i.test([confirm[0].name, confirm[0].id, confirm[0].placeholder, confirm[0].getAttribute('aria-label')].join(' ')))) set(confirm[0], payload.password);
  return {filled:true};
}
if (typeof module !== 'undefined') module.exports = {spyderForm};
