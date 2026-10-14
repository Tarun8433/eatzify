import { OFFER_CODE_PATTERN } from './personal-offer-rules';

/// D-265: the page behind a personal-offer link. It reads nothing from the database, so it cannot
/// say whether a code exists — the app asks the server, signed in, once it opens.

const PACKAGE = 'com.zynthovo.eatzify';
const SCHEME = 'eatzify';
const STORE_LISTING = `https://play.google.com/store/apps/details?id=${PACKAGE}`;

const ESCAPES: Record<string, string> = {
  '&': '&amp;',
  '<': '&lt;',
  '>': '&gt;',
  '"': '&quot;',
  "'": '&#39;',
};

export function escapeHtml(text: string): string {
  return text.replace(/[&<>"']/g, (c) => ESCAPES[c]!);
}

/// Android's intent URL: opens the app on `eatzify://offer/<code>`, or the Play listing when the
/// app is not installed.
export function offerIntentUrl(code: string): string {
  return (
    `intent://offer/${code}#Intent;scheme=${SCHEME};package=${PACKAGE};` +
    `S.browser_fallback_url=${encodeURIComponent(STORE_LISTING)};end`
  );
}

/// The whole HTML response. A code that does not match the pattern gets the same page with no
/// redirect and no echo of what was sent.
export function offerPage(code: string): string {
  const valid = OFFER_CODE_PATTERN.test(code);
  // ponytail: the code is already restricted to [A-Za-z0-9_-]; escaping anyway costs nothing.
  const target = valid ? escapeHtml(offerIntentUrl(code)) : null;
  // Both: Chrome follows the script, browsers without script follow the refresh.
  const redirect = valid
    ? `<meta http-equiv="refresh" content="0;url=${target}">\n` +
      `<script>location.replace(${JSON.stringify(offerIntentUrl(code)).replace(/</g, '\\u003c')});</script>`
    : '';
  const button = target
    ? `<p><a class="btn" href="${target}">Open in Eatzify</a></p>`
    : `<p><a class="btn" href="${escapeHtml(STORE_LISTING)}">Get Eatzify</a></p>`;

  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex">
<title>Eatzify offer</title>
${redirect}
<style>body{font-family:system-ui,sans-serif;max-width:28rem;margin:3rem auto;padding:0 1rem;text-align:center}.btn{display:inline-block;padding:.75rem 1.5rem;border-radius:999px;background:#1f7a4d;color:#fff;text-decoration:none}</style>
</head>
<body>
<h1>Eatzify</h1>
<p>Open this link on your phone with Eatzify installed.</p>
${button}
</body>
</html>`;
}
