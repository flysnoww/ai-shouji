import test from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { createHash, generateKeyPairSync, sign } from 'node:crypto';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { fileURLToPath } from 'node:url';

const listen = async (server) => { server.listen(0, '127.0.0.1'); await once(server, 'listening'); return `http://127.0.0.1:${server.address().port}`; };
const encoded = (value) => Buffer.from(JSON.stringify(value)).toString('base64url');

for (const invalidState of [false, true]) {
  test(`local harness ${invalidState ? 'rejects invalid state' : 'validates PKCE and signed claims'} without logging auth URL`, { timeout: 15000 }, async () => {
    const { privateKey, publicKey } = generateKeyPairSync('ec', { namedCurve: 'secp384r1' });
    const key = { ...publicKey.export({ format: 'jwk' }), kid: 'fixture', alg: 'ES384', use: 'sig' };
    let authorize, exchanges = 0, pkceValid = false;
    const backend = createServer(async (req, res) => {
      res.setHeader('content-type', 'application/json');
      if (req.url.includes('well-known')) return res.end(JSON.stringify({ issuer: `${endpoint}/oidc`, authorization_endpoint: `${endpoint}/authorize`, token_endpoint: `${endpoint}/token`, jwks_uri: `${endpoint}/jwks` }));
      if (req.url === '/jwks') return res.end(JSON.stringify({ keys: [key] }));
      if (req.url === '/token') {
        exchanges++;
        let body = ''; for await (const chunk of req) body += chunk;
        const params = new URLSearchParams(body);
        pkceValid = createHash('sha256').update(params.get('code_verifier')).digest('base64url') === authorize.searchParams.get('code_challenge');
        const payload = `${encoded({ alg: 'ES384', kid: 'fixture' })}.${encoded({ iss: `${endpoint}/oidc`, aud: 'fixture-client', sub: 'fixture-subject', nonce: authorize.searchParams.get('nonce'), exp: Math.floor(Date.now() / 1000) + 60 })}`;
        const signature = sign('sha384', Buffer.from(payload), { key: privateKey, dsaEncoding: 'ieee-p1363' }).toString('base64url');
        return res.end(JSON.stringify({ id_token: `${payload}.${signature}` }));
      }
      res.writeHead(404).end('{}');
    });
    const endpoint = await listen(backend);
    const reservation = createServer(); const callbackOrigin = await listen(reservation);
    await new Promise(resolve => reservation.close(resolve));
    const child = spawn(process.execPath, [fileURLToPath(new URL('./oidc-pkce-smoke.mjs', import.meta.url))], { env: { ...process.env, LOGTO_ENDPOINT: endpoint, LOGTO_CLIENT_ID: 'fixture-client', LOGTO_REDIRECT_URI: `${callbackOrigin}/callback` }, stdio: ['ignore', 'pipe', 'pipe'] });
    let output = '';
    const exit = once(child, 'exit');
    const ready = new Promise((resolve, reject) => {
      child.stdout.on('data', data => { output += data; if (output.includes('sign-in launcher')) resolve(); });
      child.stderr.on('data', data => { output += data; });
      child.on('error', reject);
      child.on('exit', () => reject(new Error('Harness exited before launch')));
    });
    try {
      await ready;
      const start = await fetch(`${callbackOrigin}/start`, { redirect: 'manual' });
      assert.equal(start.status, 302); authorize = new URL(start.headers.get('location'));
      const callback = new URL('/callback', callbackOrigin);
      callback.searchParams.set('state', invalidState ? 'wrong-state' : authorize.searchParams.get('state'));
      callback.searchParams.set('code', 'fixture-code');
      const result = await fetch(callback);
      assert.equal(result.status, invalidState ? 400 : 200);
      const [code] = await exit;
      assert.equal(code, invalidState ? 1 : 0);
      assert.equal(exchanges, invalidState ? 0 : 1);
      if (!invalidState) assert.equal(pkceValid, true);
      assert.equal(output.includes(authorize.toString()), false);
      assert.equal(output.includes('fixture-code'), false);
    } finally {
      child.kill(); backend.closeAllConnections(); await new Promise(resolve => backend.close(resolve));
    }
  });
}
