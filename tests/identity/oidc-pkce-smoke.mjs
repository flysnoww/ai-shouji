import { createHash, createPublicKey, randomBytes, verify } from 'node:crypto';
import { createServer } from 'node:http';

const endpoint = (process.env.LOGTO_ENDPOINT ?? 'http://127.0.0.1:3301').replace(/\/$/, '');
const clientId = process.env.LOGTO_CLIENT_ID ?? 'woebxmgo960m5l0nl12ae';
const redirectUri = process.env.LOGTO_REDIRECT_URI ?? 'http://127.0.0.1:8765/callback';
const timeoutMs = 10 * 60 * 1000;
const b64url = (value) => Buffer.from(value).toString('base64url');
const random = (bytes = 32) => randomBytes(bytes).toString('base64url');
const requireValue = (condition, message) => { if (!condition) throw new Error(message); };

const metadataResponse = await fetch(`${endpoint}/oidc/.well-known/openid-configuration`);
requireValue(metadataResponse.ok, `OIDC discovery failed: HTTP ${metadataResponse.status}`);
const metadata = await metadataResponse.json();
const verifier = random(48);
const challenge = createHash('sha256').update(verifier).digest('base64url');
const state = random();
const nonce = random();
const authorize = new URL(metadata.authorization_endpoint);
for (const [key, value] of Object.entries({
  client_id: clientId,
  redirect_uri: redirectUri,
  response_type: 'code',
  scope: 'openid profile email',
  code_challenge: challenge,
  code_challenge_method: 'S256',
  state,
  nonce,
})) authorize.searchParams.set(key, value);

const server = createServer(async (request, response) => {
  const callback = new URL(request.url, redirectUri);
  if (callback.pathname !== new URL(redirectUri).pathname) {
    response.writeHead(404).end();
    return;
  }
  try {
    requireValue(callback.searchParams.get('state') === state, 'OAuth state mismatch.');
    requireValue(!callback.searchParams.has('error'), `Authorization failed: ${callback.searchParams.get('error')}`);
    const code = callback.searchParams.get('code');
    requireValue(code, 'Authorization code missing.');
    const tokenResponse = await fetch(metadata.token_endpoint, {
      method: 'POST',
      headers: { 'content-type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        grant_type: 'authorization_code',
        code,
        redirect_uri: redirectUri,
        client_id: clientId,
        code_verifier: verifier,
      }),
    });
    const tokens = await tokenResponse.json();
    requireValue(tokenResponse.ok && tokens.id_token, `Token exchange failed: HTTP ${tokenResponse.status}`);

    const [headerPart, claimsPart, signaturePart] = tokens.id_token.split('.');
    const header = JSON.parse(Buffer.from(headerPart, 'base64url').toString());
    const claims = JSON.parse(Buffer.from(claimsPart, 'base64url').toString());
    requireValue(header.alg === 'ES384' && header.kid, 'Unexpected ID token signing algorithm.');
    requireValue(claims.iss === metadata.issuer, 'ID token issuer mismatch.');
    requireValue(Array.isArray(claims.aud) ? claims.aud.includes(clientId) : claims.aud === clientId, 'ID token audience mismatch.');
    requireValue(claims.nonce === nonce, 'ID token nonce mismatch.');
    requireValue(Number(claims.exp) * 1000 > Date.now(), 'ID token has expired.');
    const jwksResponse = await fetch(metadata.jwks_uri);
    requireValue(jwksResponse.ok, `JWKS fetch failed: HTTP ${jwksResponse.status}`);
    const jwks = await jwksResponse.json();
    const jwk = jwks.keys.find((key) => key.kid === header.kid && key.alg === header.alg && key.use === 'sig');
    requireValue(jwk, 'Signing key not found in JWKS.');
    requireValue(jwk.kty === 'EC' && jwk.crv === 'P-384', 'Unexpected signing key type.');
    const publicKey = createPublicKey({ key: jwk, format: 'jwk' });
    requireValue(verify('sha384', Buffer.from(`${headerPart}.${claimsPart}`), { key: publicKey, dsaEncoding: 'ieee-p1363' }, Buffer.from(signaturePart, 'base64url')), 'ID token signature invalid.');
    requireValue(typeof claims.sub === 'string' && claims.sub.length > 0, 'ID token subject missing.');

    response.writeHead(200, { 'content-type': 'text/plain; charset=utf-8' }).end('PKCE sign-in passed. You may close this tab.');
    console.log(`OIDC PKCE sign-in passed; sub=${claims.sub}`);
    server.close();
  } catch (error) {
    response.writeHead(400, { 'content-type': 'text/plain; charset=utf-8' }).end('OIDC test failed; check the local console output.');
    console.error(error.message);
    server.close(() => process.exitCode = 1);
  }
});

server.listen(new URL(redirectUri).port, '127.0.0.1', () => {
  console.log(`Open this local authorization URL in the browser:\n${authorize}`);
  console.log('Complete Email verification code in Logto; this process prints only the verified subject (sub).');
});
server.setTimeout(timeoutMs, () => {
  console.error('Timed out waiting for the local authorization callback.');
  server.close(() => process.exitCode = 1);
});
