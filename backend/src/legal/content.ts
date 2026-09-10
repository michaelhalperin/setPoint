/**
 * Privacy policy + terms of service (plan §4, §7 compliance step).
 *
 * These are served as plain public pages so the App Store listing and the app's
 * Settings → Legal links have a real URL to point at. They are written to match
 * what the app actually does today; if you later run them through a generator
 * (Termly / iubenda, per §4), swap `LEGAL_URLS` to point at that instead and
 * these become the fallback.
 */
import { env } from '../env.js';

/** Bump when the substance changes; the app can compare it to what a user accepted. */
export const LEGAL_VERSION = '2026-09-10';
export const LEGAL_EFFECTIVE_DATE = 'September 10, 2026';

const SUPPORT = env.SUPPORT_EMAIL;

function page(title: string, bodyHtml: string): string {
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="index, follow">
<title>${title} — SetPoint</title>
<style>
  :root { color-scheme: light dark; }
  body {
    margin: 0 auto; max-width: 46rem; padding: 2.5rem 1.25rem 4rem;
    font: 16px/1.6 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
    color: #1c1917; background: #faf8f5;
  }
  @media (prefers-color-scheme: dark) { body { color: #e7e5e4; background: #1c1917; } }
  h1 { font-size: 1.7rem; margin-bottom: 0.25rem; }
  h2 { font-size: 1.15rem; margin-top: 2rem; }
  .meta { color: #78716c; font-size: 0.9rem; margin-bottom: 2rem; }
  a { color: #c2410c; }
  ul { padding-left: 1.25rem; }
  code { background: rgba(120,113,108,0.15); padding: 0.1em 0.35em; border-radius: 4px; }
  footer { margin-top: 3rem; padding-top: 1.5rem; border-top: 1px solid rgba(120,113,108,0.3); color: #78716c; font-size: 0.9rem; }
</style>
</head>
<body>
${bodyHtml}
<footer>
  SetPoint · Effective ${LEGAL_EFFECTIVE_DATE} (version ${LEGAL_VERSION})<br>
  Questions: <a href="mailto:${SUPPORT}">${SUPPORT}</a>
</footer>
</body>
</html>`;
}

export function privacyPolicyHtml(): string {
  return page(
    'Privacy Policy',
    `<h1>Privacy Policy</h1>
<p class="meta">Effective ${LEGAL_EFFECTIVE_DATE}</p>

<p>SetPoint ("we", "us") is an app that helps you eat enough for a weight goal by
checking in when you appear to be falling behind. This policy explains what we
collect, why, and the choices you have. We collect the minimum needed to run the
service and we never sell your data or use health data for advertising.</p>

<h2>What we collect</h2>
<ul>
  <li><strong>Account</strong> — your Apple ID identifier and, if you share it during Sign in with Apple, your email address. Used to sign you in and to contact you about the service.</li>
  <li><strong>Your profile</strong> — height, weight, date of birth, sex, activity level, goal, target weight and pace, preferred meal times, quiet hours, and time zone. Used to calculate your calorie and protein targets and to decide when a check-in is due.</li>
  <li><strong>Meals you log</strong> — the text or photo you enter, and the resulting calorie and macronutrient estimate. Photos and text you submit for automatic parsing are sent to our AI provider (see "Service providers"). Meal photos are kept in private storage that is only readable through short-lived links the app requests.</li>
  <li><strong>Dietary restrictions</strong> — allergies and restrictions you enter, used as hard exclusions when suggesting food.</li>
  <li><strong>Safety screening answers</strong> — a medical-supervision question and a validated eating-concern questionnaire, used once to decide whether the app's active check-ins should be enabled for you. Stored so you don't have to answer again; never used for any other purpose.</li>
  <li><strong>Weight entries</strong> — weigh-ins you record or that are read from Apple Health.</li>
  <li><strong>Derived biosignal values (Smart mode only)</strong> — if you connect Apple Health, the app reads your heart-rate variability and resting heart rate <em>on your device</em>, converts them to a normalized deviation from your own baseline, and sends only that derived number. Raw heart-rate time series never leave your phone.</li>
  <li><strong>Check-in activity</strong> — when check-ins fire, whether you logged, deferred, or missed them, and any thumbs up/down you give. Used to operate the escalation logic and to tune the detection thresholds during the beta.</li>
  <li><strong>Device push token</strong> — an Apple-issued identifier used to deliver check-in notifications and Live Activities.</li>
</ul>

<h2>How we use it</h2>
<ul>
  <li>To calculate your nutrition targets and track progress toward your goal.</li>
  <li>To determine when to send a check-in and what food to suggest.</li>
  <li>To deliver notifications and Live Activities.</li>
  <li>To improve the accuracy of the detection formula in aggregate during the closed beta.</li>
  <li>To respond to your support requests.</li>
</ul>
<p>We do not use your information for advertising or profiling, and we do not sell it.</p>

<h2>Apple Health (HealthKit)</h2>
<p>Health data access is optional and used only for the features described above:
reading heart-rate variability and resting heart rate to detect under-fuelling,
and reading body weight to track progress. Data read from Health is processed on
your device; only derived values (a biosignal deviation score, a weight number)
are sent to our server. Health data is never used for advertising and is never
shared with third parties. You can revoke access at any time in the Health app or
in iOS Settings.</p>

<h2>Service providers</h2>
<ul>
  <li><strong>Anthropic</strong> — processes the meal text or photo you submit to return a nutrition estimate, and generates the wording of check-in messages. Input is sent over an encrypted connection for that purpose.</li>
  <li><strong>Vercel</strong> — hosts the backend service.</li>
  <li><strong>Neon</strong> — hosts the database.</li>
  <li><strong>Cloudflare</strong> — stores the meal photos you log, in private storage.</li>
  <li><strong>Sentry</strong> — receives crash and error reports (technical details and an internal account identifier — never meal contents or health data) so we can fix problems.</li>
  <li><strong>Apple Push Notification service</strong> — delivers notifications.</li>
</ul>
<p>These providers process data on our behalf under their own security and privacy commitments.</p>

<h2>Retention</h2>
<p>We keep your data while your account exists. When you delete your account (see
below) all of it — including stored meal photos — is erased, and the stored push token is
revoked. Backups roll off on their normal cycle.</p>

<h2>Your choices and rights</h2>
<ul>
  <li><strong>Delete your account</strong> — Settings → You → Account → Delete account. This permanently erases your data across every record we hold and cannot be undone.</li>
  <li><strong>Pause check-ins</strong> — Settings → Rhythm, at any time.</li>
  <li><strong>Revoke Health access</strong> — in the Health app or iOS Settings.</li>
  <li><strong>Access or export</strong> — email us at <a href="mailto:${SUPPORT}">${SUPPORT}</a> and we will provide a copy of your data.</li>
</ul>
<p>Depending on where you live you may have additional rights (access, correction, deletion, portability, objection). Contact us to exercise them.</p>

<h2>Children</h2>
<p>SetPoint is not directed to children under 16 and we do not knowingly collect their data.</p>

<h2>Security</h2>
<p>Data is encrypted in transit. Access to production systems is limited to what
is needed to operate the service.</p>

<h2>Changes</h2>
<p>If we change this policy we will update the effective date and version above and,
for material changes, notify you in the app.</p>

<h2>Not medical advice</h2>
<p>SetPoint provides general nutrition guidance and is not a medical device or a
substitute for professional care. If a health condition affects your eating,
follow your care team's plan.</p>`,
  );
}

export function termsOfServiceHtml(): string {
  return page(
    'Terms of Service',
    `<h1>Terms of Service</h1>
<p class="meta">Effective ${LEGAL_EFFECTIVE_DATE}</p>

<p>By using SetPoint you agree to these terms.</p>

<h2>What SetPoint is</h2>
<p>SetPoint is a tool that estimates nutrition targets, tracks what you eat, and
sends check-ins prompting you to eat when you appear to be falling behind. It is
intended for generally healthy adults pursuing a weight-gain, fat-loss, or
maintenance goal.</p>

<h2>Not medical advice</h2>
<p>SetPoint is not a medical device and does not provide medical, nutritional, or
psychological advice. Calorie and macronutrient targets are estimates based on
standard formulas and the information you provide. Do not rely on SetPoint for
decisions that require professional judgment. If you have a medical condition
that affects nutrition, are pregnant, or have a history of disordered eating,
consult a qualified professional before using the app, and follow their guidance
over the app's. If the app's screening disables active check-ins for you, that is
by design and not a diagnosis.</p>

<h2>Your responsibilities</h2>
<ul>
  <li>Provide accurate profile information; targets are only as good as the inputs.</li>
  <li>Use the app for yourself, not on behalf of someone else.</li>
  <li>You are 16 or older.</li>
  <li>Don't misuse the service (interfering with its operation, attempting unauthorized access, or reverse-engineering it beyond what the law allows).</li>
</ul>

<h2>Check-ins and notifications</h2>
<p>SetPoint sends time-sensitive notifications and Live Activities as part of its
core function. You can pause check-ins or disable notifications at any time in
the app or in iOS Settings.</p>

<h2>Accounts</h2>
<p>You sign in with Apple. You may delete your account at any time in Settings,
which permanently erases your data.</p>

<h2>Availability and changes</h2>
<p>The service is provided "as is" and may change, be interrupted, or be
discontinued. During the beta, features and detection behavior may change
frequently.</p>

<h2>Limitation of liability</h2>
<p>To the maximum extent permitted by law, SetPoint and its operators are not
liable for indirect, incidental, or consequential damages, or for outcomes
arising from reliance on the app's estimates or prompts. Nothing in these terms
limits liability that cannot be limited by law.</p>

<h2>Changes to these terms</h2>
<p>We may update these terms; the effective date and version above will change and
material changes will be surfaced in the app. Continued use after a change means
you accept it.</p>

<h2>Contact</h2>
<p><a href="mailto:${SUPPORT}">${SUPPORT}</a></p>`,
  );
}
