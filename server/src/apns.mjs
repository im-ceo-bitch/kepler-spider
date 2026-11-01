// APNs delivery: notifications never contain plaintext, wallet keys, or encrypted envelopes.
// The provider authentication key stays in Cloudflare secrets, never in the iOS binary.
const textEncoder = new TextEncoder();
const base64url = bytes => btoa(String.fromCharCode(...bytes))
  .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/g, '');
const encoded = obj => base64url(textEncoder.encode(JSON.stringify(obj)));

export const apnsConfigured = env => Boolean(
  env?.APNS_TEAM_ID && env?.APNS_KEY_ID && env?.APNS_PRIVATE_KEY && env?.APNS_BUNDLE_ID &&
  /^[A-Z0-9]{10}$/.test(env.APNS_TEAM_ID) && /^[A-Z0-9]{10}$/.test(env.APNS_KEY_ID) &&
  /^[A-Za-z0-9.-]+$/.test(env.APNS_BUNDLE_ID)
);

// Returns the APNs response status; 0 is a delivery transport or configuration failure.
export async function sendAPNs(env, deviceToken, event, fetcher = fetch, tone = 'pulse') {
  if (!apnsConfigured(env) || !/^(?:[a-f0-9]{2}){16,128}$/i.test(deviceToken)) return 0;
  if (!['message','invite','test'].includes(event)) return 0;
  try {
    const keyPEM = env.APNS_PRIVATE_KEY.replace(/\\n/g, '\n');
    const raw = keyPEM.replace(/-----BEGIN PRIVATE KEY-----|-----END PRIVATE KEY-----|\s/g, '');
    const keyData = Uint8Array.from(atob(raw), c => c.charCodeAt(0));
    const key = await crypto.subtle.importKey('pkcs8', keyData,
      {name:'ECDSA', namedCurve:'P-256'}, false, ['sign']);
    const now = Math.floor(Date.now() / 1000);
    const head = encoded({alg:'ES256',kid:env.APNS_KEY_ID});
    const body = encoded({iss:env.APNS_TEAM_ID,iat:now});
    const signed = head + '.' + body;
    const signature = new Uint8Array(await crypto.subtle.sign(
      {name:'ECDSA',hash:'SHA-256'},key,textEncoder.encode(signed)));
    // Apple's APNs expects the JOSE / P1363 signature, returned by WebCrypto.
    if(signature.length !== 64)return 0;
    const jwt = signed + '.' + base64url(signature);
    const host = env.APNS_ENVIRONMENT === 'development'
      ? 'api.development.push.apple.com' : 'api.push.apple.com';
    const sound = tone === 'mute' ? undefined : tone === 'system' ? 'default'
      : event === 'invite' ? 'spyder_connect.caf' : 'spyder_receive.caf';
    const payload = {aps:{alert:{title:'Spyder Network',body:event === 'invite'
      ? 'Новое приглашение в сеть' : event === 'test' ? 'Проверка уведомлений Spyder'
      : 'Новое зашифрованное сообщение'},
      ...(sound ? {sound} : {}), 'thread-id':'spyder.chat'},spyder_event:event};
    const response = await fetcher(`https://${host}/3/device/${deviceToken}`, {
      method:'POST', headers:{authorization:'bearer '+jwt,'apns-topic':env.APNS_BUNDLE_ID,
        'apns-push-type':'alert','apns-priority':'10','content-type':'application/json'},
      body:JSON.stringify(payload)
    });
    return response.status;
  } catch { return 0; }
}
