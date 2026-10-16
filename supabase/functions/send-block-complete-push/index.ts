// Sends a push notification to a coach when one of their trainees finishes
// every loop of their assigned block.
//
// Called from Postgres (see public.advance_block_position in
// 001_multi_coach_auth.sql), not from the app directly — the trainee's device
// never talks to this function or to Firebase. That call is authenticated with
// a shared secret (X-Push-Trigger-Secret) rather than a user JWT, since the
// caller is the database itself, not a signed-in session.
//
// Deployed with verify_jwt = false for exactly that reason: Supabase's normal
// JWT check would reject a call with no user session. The shared-secret check
// below is what stands in its place.

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const TRIGGER_SECRET = Deno.env.get('PUSH_TRIGGER_SECRET')!;
const FIREBASE_SERVICE_ACCOUNT_JSON = Deno.env.get('FIREBASE_SERVICE_ACCOUNT_JSON');

interface ServiceAccount {
  project_id: string;
  client_email: string;
  private_key: string;
}

interface RequestBody {
  coach_id: string;
  trainee_name: string;
  loops: number;
  day_count: number;
}

// ---------------------------------------------------------------------------
// Google OAuth2 — exchange the Firebase service account for a short-lived
// bearer token, using a self-signed JWT (RFC 7523). No external library: Deno's
// Web Crypto API can do RS256 signing directly.
// ---------------------------------------------------------------------------

function base64url(bytes: ArrayBuffer | Uint8Array): string {
  const arr = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
  let str = '';
  for (const b of arr) str += String.fromCharCode(b);
  return btoa(str).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function pemToArrayBuffer(pem: string): ArrayBuffer {
  const b64 = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, '')
    .replace(/-----END PRIVATE KEY-----/, '')
    .replace(/\s+/g, '');
  const raw = atob(b64);
  const buf = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i++) buf[i] = raw.charCodeAt(i);
  return buf.buffer;
}

async function getAccessToken(account: ServiceAccount): Promise<string> {
  const header = { alg: 'RS256', typ: 'JWT' };
  const now = Math.floor(Date.now() / 1000);
  const claims = {
    iss: account.client_email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
  };

  const encHeader = base64url(new TextEncoder().encode(JSON.stringify(header)));
  const encClaims = base64url(new TextEncoder().encode(JSON.stringify(claims)));
  const signingInput = `${encHeader}.${encClaims}`;

  const key = await crypto.subtle.importKey(
    'pkcs8',
    pemToArrayBuffer(account.private_key),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const signature = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    key,
    new TextEncoder().encode(signingInput),
  );
  const assertion = `${signingInput}.${base64url(signature)}`;

  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion,
    }),
  });
  if (!res.ok) {
    throw new Error(`OAuth token exchange failed: ${res.status} ${await res.text()}`);
  }
  const json = await res.json();
  return json.access_token as string;
}

// ---------------------------------------------------------------------------

Deno.serve(async (req) => {
  if (req.method !== 'POST') {
    return new Response('Method not allowed', { status: 405 });
  }

  if (req.headers.get('X-Push-Trigger-Secret') !== TRIGGER_SECRET) {
    return new Response('Forbidden', { status: 403 });
  }

  if (!FIREBASE_SERVICE_ACCOUNT_JSON) {
    // Not configured yet — fail quietly rather than error the DB call that
    // triggered this. The trainee's own save must never depend on push setup.
    console.log('FIREBASE_SERVICE_ACCOUNT_JSON not set; skipping push.');
    return new Response('ok (push not configured)', { status: 200 });
  }

  let body: RequestBody;
  try {
    body = await req.json();
  } catch {
    return new Response('Bad request', { status: 400 });
  }

  const supabaseHeaders = {
    apikey: SERVICE_ROLE_KEY,
    Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
    'Content-Type': 'application/json',
  };

  const tokensRes = await fetch(
    `${SUPABASE_URL}/rest/v1/push_tokens?profile_id=eq.${body.coach_id}&select=id,token`,
    { headers: supabaseHeaders },
  );
  const tokens: { id: string; token: string }[] = tokensRes.ok ? await tokensRes.json() : [];

  if (tokens.length === 0) {
    return new Response('ok (no device registered)', { status: 200 });
  }

  const account: ServiceAccount = JSON.parse(FIREBASE_SERVICE_ACCOUNT_JSON);
  const accessToken = await getAccessToken(account);

  const title = 'Block complete!';
  const message = `${body.trainee_name} finished all ${body.loops} ` +
    `${body.loops === 1 ? 'loop' : 'loops'} — set their next program.`;

  const deadTokenIds: string[] = [];

  await Promise.all(
    tokens.map(async ({ id, token }) => {
      const res = await fetch(
        `https://fcm.googleapis.com/v1/projects/${account.project_id}/messages:send`,
        {
          method: 'POST',
          headers: {
            Authorization: `Bearer ${accessToken}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            message: {
              token,
              notification: { title, body: message },
              android: { priority: 'high', notification: { channel_id: 'block_complete' } },
            },
          }),
        },
      );

      if (!res.ok) {
        const text = await res.text();
        // UNREGISTERED / INVALID_ARGUMENT on a token means it will never work
        // again (uninstalled app, revoked registration) — stop retrying it.
        if (text.includes('UNREGISTERED') || text.includes('INVALID_ARGUMENT')) {
          deadTokenIds.push(id);
        } else {
          console.log(`FCM send failed for token ${id}: ${res.status} ${text}`);
        }
      }
    }),
  );

  if (deadTokenIds.length > 0) {
    await fetch(`${SUPABASE_URL}/rest/v1/push_tokens?id=in.(${deadTokenIds.join(',')})`, {
      method: 'DELETE',
      headers: supabaseHeaders,
    });
  }

  return new Response(
    JSON.stringify({ ok: true, sent: tokens.length - deadTokenIds.length, pruned: deadTokenIds.length }),
    { status: 200, headers: { 'Content-Type': 'application/json' } },
  );
});
