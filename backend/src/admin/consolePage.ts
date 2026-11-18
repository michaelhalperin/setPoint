/**
 * The admin console at /admin (v2): a left rail with Watch / Test / Control / Manage, and one
 * screen per job. The page holds no data; everything loads from /api/admin/* after signing in
 * with the admin secret (kept in this tab's session storage, shared with the classic page).
 *
 * Kept as a raw string so it ships inside the serverless bundle. The script uses no template
 * literals or backticks, and builds the page with DOM calls (textContent), never innerHTML.
 */
export const CONSOLE_PAGE_HTML = String.raw`<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex, nofollow">
<title>SetPoint admin</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Hanken+Grotesk:wght@400;500;600;700&family=JetBrains+Mono:wght@400;500&display=swap" rel="stylesheet">
<style>
:root{--bg:#0A0A0B;--ink:#F4F2EE;--soft:#A8A59F;--faint:#8A8780;--line:rgba(244,242,238,.1);--line-hi:rgba(244,242,238,.2);--fill:rgba(244,242,238,.05);--ember:#FF7A3D;--good:#7FE0A0;--warn:#FFB86B;--bad:#FF6B6B;--sans:"Hanken Grotesk",ui-sans-serif,system-ui,sans-serif;--mono:"JetBrains Mono",ui-monospace,monospace}
*{box-sizing:border-box}
html,body{margin:0;background:var(--bg);color:var(--ink);font:14px/1.5 var(--sans);-webkit-font-smoothing:antialiased}
button,input,select,textarea{font:inherit;color:inherit}
a{color:inherit}
:focus-visible{outline:2px solid var(--ember);outline-offset:2px}
.mono{font-family:var(--mono);font-variant-numeric:tabular-nums}
.t-good{color:var(--good)}.t-warn{color:var(--warn)}.t-bad{color:var(--bad)}.t-faint{color:var(--faint)}.t-soft{color:var(--soft)}
.app{display:flex;min-height:100vh}
.rail{width:236px;flex:none;border-right:1px solid var(--line);padding:22px 14px;display:flex;flex-direction:column;gap:2px;position:sticky;top:0;height:100vh;overflow:auto}
.logo{font-weight:700;font-size:17px;letter-spacing:-.02em;padding:0 10px 4px}
.logo span{color:var(--faint);font-weight:500}
.env{margin:0 10px 12px;display:inline-flex;align-items:center;gap:7px;font:500 11px var(--mono);color:var(--good)}
.env i{width:7px;height:7px;border-radius:50%;background:var(--good)}
.grp{font:500 11px var(--mono);color:var(--faint);padding:16px 10px 6px;text-transform:uppercase;letter-spacing:.06em}
.nav{display:flex;align-items:center;height:38px;padding:0 10px;border-radius:10px;color:var(--soft);text-decoration:none;font-weight:500;border:0;background:none;cursor:pointer;width:100%;text-align:left}
.nav:hover{background:var(--fill)}
.nav[aria-current=page]{background:rgba(255,122,61,.12);color:var(--ink)}
.nav b{margin-left:auto;font:500 11px var(--mono);background:var(--warn);color:var(--bg);border-radius:9px;padding:0 7px;line-height:18px}
.main{flex:1;min-width:0}
.top{height:64px;display:flex;align-items:center;gap:14px;padding:0 36px;border-bottom:1px solid var(--line);position:sticky;top:0;background:var(--bg);z-index:4}
.chip{display:inline-flex;align-items:center;gap:8px;height:32px;padding:0 14px;border-radius:16px;border:1px solid var(--line-hi);font-weight:600;font-size:13px;background:none;cursor:default}
.chip.ok{color:var(--good);border-color:rgba(127,224,160,.4)}.chip.off{color:var(--warn);border-color:rgba(255,184,107,.5)}
.sp{flex:1}
.pad{padding:34px 36px 80px;max-width:1360px}
.kick{font:500 12px var(--mono);color:var(--faint);text-transform:uppercase}
.h1{margin:10px 0 0;font-size:46px;line-height:1.05;letter-spacing:-.045em;font-weight:500;max-width:920px}
.h1 em{font-style:normal;color:var(--faint)}
.card{border:1px solid var(--line);background:rgba(244,242,238,.03);border-radius:18px;padding:22px}
.h3{margin:0 0 14px;font-size:13px;font-weight:600;color:var(--soft);display:flex;justify-content:space-between;align-items:baseline;gap:12px}
.h3 span{font:400 12px var(--mono);color:var(--faint)}
.grid2{display:grid;grid-template-columns:minmax(0,1.2fr) minmax(0,1fr);gap:24px;margin-top:28px;align-items:start}
.stack{display:flex;flex-direction:column;gap:24px;min-width:0}
@media(max-width:1000px){.grid2{grid-template-columns:1fr}.rail{display:none}.pad{padding:24px 16px 60px}.top{padding:0 16px}.h1{font-size:34px}}
.row{display:flex;align-items:center;gap:12px;padding:12px 0;border-top:1px solid rgba(244,242,238,.08)}
.row:first-of-type{border-top:0}
.row .grow{flex:1;min-width:0}
.dot{width:8px;height:8px;border-radius:50%;flex:none}
.btn{height:32px;padding:0 14px;border-radius:16px;border:1px solid var(--line-hi);background:transparent;cursor:pointer;font-weight:600;font-size:13px;white-space:nowrap}
.btn:hover{background:var(--fill)}.btn:disabled{opacity:.5;cursor:default}
.btn.pri{background:var(--ember);border-color:var(--ember);color:#1A0A04}
.btn.dng{color:var(--bad);border-color:rgba(255,107,107,.4)}
.btns{display:flex;gap:10px;flex-wrap:wrap}
.fld{display:block;font:500 11px var(--mono);color:var(--faint);margin:0 0 6px;text-transform:uppercase;letter-spacing:.05em}
.in{width:100%;height:40px;border-radius:12px;border:1px solid var(--line-hi);background:var(--fill);padding:0 14px}
textarea.in{height:90px;padding:10px 14px;resize:vertical}
select.in{appearance:auto}
.two{display:grid;grid-template-columns:1fr 1fr;gap:12px}
.gap{margin-top:14px}
.tg{width:44px;height:26px;border-radius:13px;background:rgba(244,242,238,.15);position:relative;flex:none;border:0;cursor:pointer;padding:0}
.tg::after{content:"";position:absolute;top:3px;left:3px;width:20px;height:20px;border-radius:50%;background:var(--ink);transition:left .15s}
.tg[aria-checked=true]{background:var(--good)}.tg[aria-checked=true]::after{left:21px;background:var(--bg)}
.nums{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));margin:34px 0 4px;border-top:1px solid var(--line)}
.nums div{padding:16px 20px 0 0}.nums div+div{padding-left:20px;border-left:1px solid var(--line)}
.nums b{display:block;font:400 36px/1 var(--mono);letter-spacing:-.06em;font-weight:400}
.nums span{display:block;margin-top:8px;color:var(--soft);font-size:13px}
.bar{height:10px;border-radius:5px;background:rgba(244,242,238,.08);margin-top:6px;overflow:hidden}.bar i{display:block;height:100%;border-radius:5px;background:var(--ink)}
.log{margin-top:16px;border-radius:12px;background:#000;border:1px solid var(--line);padding:14px 16px;font:12px/1.8 var(--mono);color:var(--soft);white-space:pre-wrap;word-break:break-word;max-height:300px;overflow:auto}
.note{padding:12px 14px;border-radius:12px;background:rgba(255,184,107,.1);border:1px solid rgba(255,184,107,.35);font-size:13px;margin-top:14px}
.chips{display:flex;gap:10px;flex-wrap:wrap;margin:24px 0 8px}
.chips .chip{cursor:pointer}.chips .chip[aria-pressed=true]{background:var(--ink);color:var(--bg);border-color:var(--ink)}
table{width:100%;border-collapse:collapse}
th{font:500 11px var(--mono);color:var(--faint);text-transform:uppercase;letter-spacing:.05em;text-align:left;padding:0 10px 10px}
td{padding:11px 10px;border-top:1px solid rgba(244,242,238,.08);vertical-align:middle}
tr.pick{cursor:pointer}tr.pick:hover td{background:var(--fill)}tr.sel td{background:rgba(255,122,61,.1)}
.scroll{overflow-x:auto}
.login{width:min(420px,calc(100% - 32px));margin:20vh auto 0}
.login h1{margin:0 0 8px;font-size:34px;letter-spacing:-.04em;font-weight:500}
.login p{margin:0 0 20px;color:var(--soft)}.login input{margin-bottom:12px;height:44px}
.err{color:var(--bad);min-height:20px;margin:0 0 12px}
.toast{position:fixed;left:50%;bottom:28px;transform:translateX(-50%);background:var(--ink);color:var(--bg);padding:10px 18px;border-radius:20px;font-weight:600;z-index:20;max-width:90vw}
.toast.bad{background:var(--bad)}
.modal{position:fixed;inset:0;background:rgba(0,0,0,.7);display:flex;align-items:center;justify-content:center;z-index:10;padding:16px}
.phone{width:300px;border-radius:38px;border:7px solid #1c1c1e;background:var(--bg);padding:22px 18px;max-height:90vh;overflow:auto}
.skel{color:var(--faint);padding:40px 0}
</style>
</head>
<body>
<div id="root"></div>
<script>
(function () {
  'use strict';
  var KEY = 'setpoint.ops.secret';
  var state = { secret: null, route: 'overview', cache: {} };
  var root = document.getElementById('root');

  // ---------- tiny DOM helpers ----------
  function h(tag, props) {
    var el = document.createElement(tag);
    props = props || {};
    for (var k in props) {
      if (!Object.prototype.hasOwnProperty.call(props, k) || props[k] == null || props[k] === false) continue;
      if (k === 'class') el.className = props[k];
      else if (k === 'style') el.setAttribute('style', props[k]);
      else if (k.slice(0, 2) === 'on') el.addEventListener(k.slice(2), props[k]);
      else if (k === 'text') el.textContent = props[k];
      else el.setAttribute(k, props[k] === true ? '' : props[k]);
    }
    for (var i = 2; i < arguments.length; i++) add(el, arguments[i]);
    return el;
  }
  function add(el, c) {
    if (c == null || c === false) return;
    if (Array.isArray(c)) { c.forEach(function (x) { add(el, x); }); return; }
    el.appendChild(typeof c === 'string' || typeof c === 'number' ? document.createTextNode(String(c)) : c);
  }
  function clear(el) { while (el.firstChild) el.removeChild(el.firstChild); }
  function toast(msg, bad) {
    var t = h('div', { class: 'toast' + (bad ? ' bad' : ''), role: 'status', text: msg });
    document.body.appendChild(t);
    setTimeout(function () { t.remove(); }, 3200);
  }
  function ago(iso) {
    if (!iso) return 'never';
    var m = Math.round((Date.now() - new Date(iso).getTime()) / 60000);
    if (m < 1) return 'just now'; if (m < 60) return m + ' min ago';
    if (m < 1440) return Math.round(m / 60) + ' h ago';
    return Math.round(m / 1440) + ' d ago';
  }
  function hhmm(iso) { var d = new Date(iso); return ('0' + d.getHours()).slice(-2) + ':' + ('0' + d.getMinutes()).slice(-2); }
  function dot(tone) { var t = tone === 'off' || !tone ? 'faint' : tone; return h('span', { class: 'dot', style: 'background:var(--' + t + ')' }); }
  function minLabel(m) { return ('0' + Math.floor(m / 60)).slice(-2) + ':' + ('0' + (m % 60)).slice(-2); }

  // ---------- api ----------
  function api(path, opts) {
    opts = opts || {};
    var headers = { 'x-admin-secret': state.secret };
    if (opts.body !== undefined) headers['content-type'] = 'application/json';
    return fetch('/api/admin' + path, { method: opts.method || 'GET', headers: headers, body: opts.body !== undefined ? JSON.stringify(opts.body) : undefined }).then(function (res) {
      if (res.status === 401) { signOut(); throw new Error('Signed out'); }
      if (!res.ok) return res.json().catch(function () { return {}; }).then(function (b) { throw new Error(b.message || ('Error ' + res.status)); });
      return res.json();
    });
  }
  function act(btn, fn, okMsg) {
    btn.disabled = true;
    return Promise.resolve().then(fn).then(function (r) { if (okMsg) toast(okMsg); return r; }, function (e) { toast(e.message, true); }).then(function (r) { btn.disabled = false; return r; });
  }
  function signOut() { try { sessionStorage.removeItem(KEY); } catch (e) {} state.secret = null; render(); }

  // ---------- shell ----------
  var NAV = [
    ['Watch', [['overview', 'Overview'], ['health', 'Health + alerts']]],
    ['Test', [['test', 'Test lab']]],
    ['Control', [['control', 'Switches + config'], ['subs', 'Subscriptions']]],
    ['Manage', [['people', 'People'], ['catalog', 'Food catalog'], ['access', 'Flags + invites'], ['audit', 'Audit log']]]
  ];
  var TITLES = { overview: 'Overview', health: 'Health + alerts', test: 'Test lab', control: 'Switches + config', subs: 'Subscriptions', people: 'People', catalog: 'Food catalog', access: 'Flags + invites', audit: 'Audit log' };

  function route() { var r = (location.hash || '#overview').slice(1); return TITLES[r] ? r : 'overview'; }
  function go(r) { location.hash = '#' + r; }

  function render() {
    clear(root);
    if (!state.secret) return root.appendChild(loginView());
    var main = h('div', { class: 'main' });
    var rail = h('nav', { class: 'rail', 'aria-label': 'Admin' },
      h('div', { class: 'logo' }, 'SetPoint ', h('span', { text: 'admin' })),
      h('div', { class: 'env', id: 'env' }, h('i'), 'LIVE'));
    NAV.forEach(function (g) {
      rail.appendChild(h('div', { class: 'grp', text: g[0] }));
      g[1].forEach(function (n) {
        var b = h('a', { class: 'nav', href: '#' + n[0], 'data-r': n[0] }, n[1]);
        if (n[0] === state.route) b.setAttribute('aria-current', 'page');
        rail.appendChild(b);
      });
    });
    rail.appendChild(h('div', { class: 'grp', text: 'Other' }));
    rail.appendChild(h('a', { class: 'nav', href: '/admin/classic' }, 'Classic admin (usage, tour)'));
    rail.appendChild(h('button', { class: 'nav', onclick: signOut }, 'Sign out'));
    var top = h('div', { class: 'top' },
      h('span', { class: 'mono t-faint', id: 'crumb', text: TITLES[state.route] }),
      h('div', { class: 'sp' }),
      h('span', { class: 'chip ok', id: 'swchip', text: 'checking…' }));
    var page = h('div', { class: 'pad', id: 'page' });
    main.appendChild(top); main.appendChild(page);
    root.appendChild(h('div', { class: 'app' }, rail, main));
    refreshSwitchChip();
    var fn = SCREENS[state.route];
    page.appendChild(h('div', { class: 'skel', text: 'Loading…' }));
    fn(page).catch(function (e) { clear(page); page.appendChild(h('p', { class: 't-bad', text: e.message })); });
  }
  function refreshSwitchChip() {
    api('/control').then(function (c) {
      var off = c.switches.filter(function (s) { return !s.on && s.key !== 'invite_only'; });
      var chip = document.getElementById('swchip'); if (!chip) return;
      chip.className = 'chip ' + (off.length ? 'off' : 'ok');
      chip.textContent = off.length ? off.length + ' switch' + (off.length > 1 ? 'es' : '') + ' off: ' + off.map(function (s) { return s.key; }).join(', ') : 'All switches on';
    }).catch(function () {});
  }
  function header(kick, title, em) {
    return [h('div', { class: 'kick', text: kick }), h('h1', { class: 'h1' }, title + ' ', h('em', { text: em }))];
  }
  function card(title, meta) {
    var c = h('div', { class: 'card' }, h('div', { class: 'h3' }, title, meta ? h('span', { text: meta }) : null));
    for (var i = 2; i < arguments.length; i++) add(c, arguments[i]);
    return c;
  }
  function field(label, input) { return h('div', null, h('label', { class: 'fld', text: label }), input); }
  function toggle(on, onchange, label) {
    var t = h('button', { class: 'tg', role: 'switch', 'aria-checked': String(!!on), 'aria-label': label });
    t.addEventListener('click', function () {
      var next = t.getAttribute('aria-checked') !== 'true';
      t.disabled = true;
      Promise.resolve(onchange(next)).then(function () { t.setAttribute('aria-checked', String(next)); }, function (e) { toast(e.message, true); }).then(function () { t.disabled = false; });
    });
    return t;
  }
  function lines(arr) { return arr.map(function (l) { return l; }).join('\n'); }

  var SCREENS = {};

  // ---------- Overview ----------
  SCREENS.overview = function (page) {
    return Promise.all([api('/ops/now'), api('/health-feed'), api('/funnel')]).then(function (r) {
      var now = r[0], hf = r[1], fn = r[2];
      clear(page);
      var n = now.numbers;
      var open = hf.alerts.map(function (a) { return { level: a.level, title: a.title, detail: a.detail, go: 'health' }; }).concat(now.looseEnds.map(function (l) { return { level: l.level, title: l.title, detail: l.detail, go: l.link === 'people' ? 'people' : 'health' }; }));
      page.appendChild(h('div', null, header(new Date().toDateString() + ' · live', open.length ? 'The machine is running.' : 'All quiet.', open.length ? open.length + ' thing' + (open.length > 1 ? 's' : '') + ' need you.' : 'Nothing needs you.')));
      page.appendChild(h('div', { class: 'nums' },
        h('div', null, h('b', { text: n.activeToday }), h('span', { text: 'active today of ' + n.people })),
        h('div', null, h('b', { text: n.meals }), h('span', { text: 'meals logged today' })),
        h('div', null, h('b', { text: n.reachedPct + '%' }), h('span', { text: 'check-ins that reached them' })),
        h('div', null, h('b', { text: '$' + n.aiUsd }), h('span', { text: 'AI spend today (budget $' + n.aiBudget + ')' })),
        h('div', null, h('b', { text: fn.quiet }), h('span', { text: 'went quiet 3+ days' }))));

      var needs = card('Needs you', open.length + ' open');
      if (!open.length) needs.appendChild(h('p', { class: 't-soft', text: 'Nothing open. Scoring is on time and notifications are getting through.' }));
      open.forEach(function (o) {
        needs.appendChild(h('div', { class: 'row' }, dot(o.level === 'bad' ? 'bad' : 'warn'), h('div', { class: 'grow' }, h('div', { style: 'font-weight:600', text: o.title }), h('div', { class: 't-soft', style: 'font-size:13px', text: o.detail })), h('button', { class: 'btn', onclick: function () { go(o.go); } }, 'Open')));
      });

      var jobs = card('Scheduler', 'last score ' + ago(now.day.lastRunAt));
      [['score', 'Score confidence + check-ins'], ['weigh-in', 'Weigh-in reminder'], ['settle', 'Settle day'], ['digest', 'Usage digest'], ['cleanup-photos', 'Photo cleanup']].forEach(function (j) {
        var b = h('button', { class: 'btn', text: 'Run now' });
        b.addEventListener('click', function () {
          if (!confirm('Run "' + j[1] + '" now for everyone? It can send real notifications.')) return;
          act(b, function () { return api('/run/' + j[0], { method: 'POST', body: { confirm: true } }); }, j[1] + ' finished');
        });
        jobs.appendChild(h('div', { class: 'row' }, h('span', { class: 'grow', text: j[1] }), b));
      });

      var funnel = card('Onboarding to week one', 'last ' + fn.days + ' days');
      var top = fn.steps[0].n || 1;
      fn.steps.forEach(function (s) {
        funnel.appendChild(h('div', { class: 'gap' }, h('div', { style: 'display:flex;justify-content:space-between;font-size:13px' }, h('span', { text: s.label }), h('span', { class: 'mono', text: s.n + (s.of != null ? ' of ' + s.of : '') + ' · ' + Math.round((s.n / top) * 100) + '%' })), h('div', { class: 'bar' }, h('i', { style: 'width:' + Math.round((s.n / top) * 100) + '%' }))));
      });
      var quick = card('Quick actions', 'safe, reversible', h('div', { class: 'btns' },
        h('button', { class: 'btn pri', onclick: function () { go('test'); } }, 'Broadcast push'),
        h('button', { class: 'btn', onclick: function () { go('control'); } }, 'Pause AI or show a notice'),
        h('button', { class: 'btn', onclick: function () { go('access'); } }, 'Create invite')));
      page.appendChild(h('div', { class: 'grid2' }, h('div', { class: 'stack' }, needs, jobs), h('div', { class: 'stack' }, funnel, quick)));
    });
  };

  // ---------- Health ----------
  SCREENS.health = function (page) {
    return api('/health-feed').then(function (hf) {
      clear(page);
      page.appendChild(h('div', null, header('Watch · last 24 hours', 'Know it broke', 'before they tell you.')));
      var max = Math.max.apply(null, hf.perHour.sent.concat([1]));
      var bars = h('div', { style: 'display:flex;align-items:flex-end;gap:4px;height:120px', role: 'img', 'aria-label': 'Check-ins per hour, last 24 hours' });
      hf.perHour.sent.forEach(function (v, i) {
        var f = hf.perHour.failed[i];
        bars.appendChild(h('div', { style: 'flex:1;display:flex;flex-direction:column;justify-content:flex-end;height:100%' },
          h('div', { style: 'background:var(--bad);height:' + Math.round((f / max) * 100) + '%' }),
          h('div', { style: 'background:var(--ink);opacity:.85;height:' + Math.round(((v - f) / max) * 100) + '%' })));
      });
      var chart = card('Check-ins per hour', hf.totals.checkIns + ' sent · ' + hf.totals.failed + ' failed (' + hf.totals.failPct + '%)', bars,
        h('div', { class: 'mono t-faint', style: 'display:flex;justify-content:space-between;font-size:11px;margin-top:6px' }, h('span', { text: '24 h ago' }), h('span', { text: 'now' })));

      var alerts = card('Active alerts', hf.alerts.length + ' open');
      if (!hf.alerts.length) alerts.appendChild(h('p', { class: 't-soft', text: 'No alert rule is firing.' }));
      hf.alerts.forEach(function (a) { alerts.appendChild(h('div', { class: 'row' }, dot(a.level), h('div', { class: 'grow' }, h('div', { style: 'font-weight:600', text: a.title }), h('div', { class: 't-soft', style: 'font-size:13px', text: a.detail })))); });

      var feed = card('Server errors + failed deliveries', 'newest first');
      var any = false;
      hf.errors.slice(0, 12).forEach(function (e) { any = true; feed.appendChild(h('div', { class: 'row' }, h('span', { class: 'mono t-faint', style: 'width:52px', text: hhmm(e.at) }), dot('bad'), h('div', { class: 'grow' }, h('div', { style: 'font-weight:600', text: e.method + ' ' + e.route + ' · ' + e.status }), h('div', { class: 't-soft', style: 'font-size:13px', text: ago(e.at) })))); });
      hf.failures.slice(0, 8).forEach(function (f) { any = true; feed.appendChild(h('div', { class: 'row' }, h('span', { class: 'mono t-faint', style: 'width:52px', text: hhmm(f.at) }), dot('warn'), h('div', { class: 'grow' }, h('div', { style: 'font-weight:600', text: 'Push failed · ' + f.reason }), h('a', { class: 't-soft', style: 'font-size:13px', href: '#people', text: 'person ' + f.userId.slice(-6) })))); });
      if (!any) feed.appendChild(h('p', { class: 't-soft', text: 'Nothing in the last day.' }));

      var rules = card('Alert rules', 'checked every time this page loads');
      var R = hf.rules;
      function saveRules() { return api('/control/alert-rules', { method: 'PUT', body: R }); }
      function numIn(val, onc) { var i = h('input', { class: 'in mono', type: 'number', value: val, style: 'width:90px;height:32px' }); i.addEventListener('change', function () { onc(Number(i.value)); saveRules().then(function () { toast('Saved'); }, function (e) { toast(e.message, true); }); }); return i; }
      [['cronMissed', 'A cron job misses its slot', null], ['pushFailure', 'Push failure rate above %', 'pct'], ['aiSpend', 'AI spend above $ / day', 'usd'], ['serverErrors', '5xx errors in an hour above', 'count'], ['safetyTrip', 'Any expert safety trip', null]].forEach(function (d) {
        rules.appendChild(h('div', { class: 'row' }, toggle(R[d[0]].on, function (v) { R[d[0]].on = v; return saveRules(); }, d[1]), h('span', { class: 'grow', text: d[1] }), d[2] ? numIn(R[d[0]][d[2]], function (v) { R[d[0]][d[2]] = v; }) : null));
      });
      var photo = card('Photo cleanup queue', 'pending deletion');
      var pb = h('button', { class: 'btn', text: 'Run cleanup' });
      pb.addEventListener('click', function () { act(pb, function () { return api('/run/cleanup-photos', { method: 'POST', body: { confirm: true } }); }, 'Cleanup ran'); });
      photo.appendChild(h('div', { class: 'row' }, h('span', { class: 'grow' }, h('b', { class: 'mono', text: hf.totals.photoQueue }), ' waiting'), pb));
      page.appendChild(h('div', { class: 'grid2' }, h('div', { class: 'stack' }, chart, feed), h('div', { class: 'stack' }, alerts, rules, photo)));
    });
  };

  // ---------- Test lab ----------
  SCREENS.test = function (page) {
    return Promise.all([api('/ops/now'), api('/control')]).then(function (r) {
      var people = r[0].people, tests = r[1].testAccounts;
      clear(page);
      page.appendChild(h('div', null, header('Test · every action is logged', 'Make the day happen', 'on purpose.')));

      var sel = h('select', { class: 'in' }, h('option', { value: '', text: 'Pick a person…' }));
      people.forEach(function (p) { sel.appendChild(h('option', { value: p.id, text: p.name + (tests.indexOf(p.id) >= 0 ? '  (test account)' : '') })); });
      var badge = h('span', { class: 'chip', text: 'no one picked' });
      var markBtn = h('button', { class: 'btn', text: 'Mark as test account', disabled: true });
      function refreshBadge() {
        var id = sel.value, isTest = tests.indexOf(id) >= 0;
        badge.className = 'chip ' + (!id ? '' : isTest ? 'ok' : 'off');
        badge.textContent = !id ? 'no one picked' : isTest ? 'test account · time travel allowed' : 'real person · confirm needed';
        markBtn.disabled = !id; markBtn.textContent = isTest ? 'Unmark test account' : 'Mark as test account';
      }
      sel.addEventListener('change', refreshBadge);
      markBtn.addEventListener('click', function () {
        var id = sel.value, isTest = tests.indexOf(id) >= 0;
        act(markBtn, function () { return api('/test-accounts/' + id, { method: 'POST', body: { on: !isTest } }).then(function (res) { tests = res.testAccounts; var o = sel.options[sel.selectedIndex]; o.text = o.text.replace('  (test account)', '') + (tests.indexOf(id) >= 0 ? '  (test account)' : ''); refreshBadge(); }); });
      });
      var who = card('Testing as', 'time travel works on test accounts only', h('div', { class: 'two' }, field('Person', sel), h('div', { style: 'display:flex;align-items:flex-end;gap:10px;flex-wrap:wrap' }, badge, markBtn)));

      var when = h('input', { class: 'in mono', type: 'datetime-local' });
      var log = h('div', { class: 'log', text: 'Results show here.' });
      function logLine(s) { log.textContent = new Date().toLocaleTimeString() + '  ' + s + '\n' + log.textContent; }
      function runJob(job, useTime) {
        var id = sel.value;
        if (!id) { toast('Pick a person first', true); return Promise.resolve(); }
        var isTest = tests.indexOf(id) >= 0;
        if (useTime && !when.value) { toast('Pick a date and time first', true); return Promise.resolve(); }
        if (!isTest && !confirm('This is a real person. Run "' + job + '" for them now?')) return Promise.resolve();
        var body = { userId: id, confirm: true };
        if (useTime) body.at = new Date(when.value).toISOString();
        return api('/run/' + job, { method: 'POST', body: body }).then(function (res) { logLine(job + (res.simulatedAt ? ' @ ' + res.simulatedAt : '') + ' · ' + res.ms + ' ms\n' + JSON.stringify(res.result, null, 1)); }, function (e) { logLine(job + ' failed: ' + e.message); });
      }
      function jobBtn(label, job, useTime, pri) { var b = h('button', { class: 'btn' + (pri ? ' pri' : ''), text: label }); b.addEventListener('click', function () { act(b, function () { return runJob(job, useTime); }); }); return b; }
      var sim = card('Simulate a moment', 'runs as if it were this time',
        h('div', { class: 'two' }, field('Pretend it is', when), h('div')),
        h('div', { class: 'btns gap' }, jobBtn('Score + check-ins at this time', 'score', true, true), jobBtn('Settle day at this time', 'settle', true), jobBtn('Weigh-in reminder at this time', 'weigh-in', true)),
        h('div', { class: 'note', text: 'Tip: pick today 20:30 to see the evening top-up, or tomorrow 00:05 to see the day close. Real pushes reach the test account’s phone.' }));
      var now = card('Run now for this person', 'real clock',
        h('div', { class: 'btns' }, jobBtn('Score', 'score', false), jobBtn('Settle', 'settle', false), jobBtn('Weigh-in', 'weigh-in', false), (function () { var b = h('button', { class: 'btn', text: 'Test push' }); b.addEventListener('click', function () { var id = sel.value; if (!id) return toast('Pick a person first', true); act(b, function () { return api('/ops/person/' + id + '/test-push', { method: 'POST' }).then(function (res) { logLine('test push · sent ' + res.sent + ' of ' + res.attempted + (res.error ? ' · ' + res.error : '')); }); }); }); return b; })()),
        log);

      // Broadcast
      var seg = h('select', { class: 'in' }, h('option', { value: 'quiet', text: 'Quiet 3+ days' }), h('option', { value: 'all', text: 'Everyone with a device' }), h('option', { value: 'user', text: 'The person picked above' }));
      var title = h('input', { class: 'in', value: 'SetPoint', maxlength: 60 });
      var msg = h('textarea', { class: 'in', maxlength: 240, placeholder: 'Haven’t seen a log in a few days. One small meal today keeps the plan on track.' });
      var prev = h('div', { class: 'note', text: 'Preview to see how many people it reaches.' });
      function bcast(dry) {
        var body = { segment: seg.value, title: title.value || 'SetPoint', message: msg.value, dryRun: dry };
        if (seg.value === 'user') body.userId = sel.value;
        return api('/broadcast', { method: 'POST', body: body });
      }
      var pBtn = h('button', { class: 'btn', text: 'Preview reach' }), sBtn = h('button', { class: 'btn pri', text: 'Send' });
      pBtn.addEventListener('click', function () { act(pBtn, function () { return bcast(true).then(function (res) { prev.textContent = 'Reaches ' + res.reachable + ' people · ' + res.noToken + ' have no push token.'; }); }); });
      sBtn.addEventListener('click', function () {
        act(sBtn, function () {
          return bcast(true).then(function (res) {
            if (!confirm('Send this to ' + res.reachable + ' people now? It can’t be undone.')) return null;
            return bcast(false).then(function (d) { prev.textContent = 'Sent to ' + d.sent + ' devices, ' + d.failed + ' failed.'; toast('Broadcast sent'); });
          });
        });
      });
      var bc = card('Broadcast push', 'preview first', field('Who', seg), h('div', { class: 'gap' }, field('Title', title)), h('div', { class: 'gap' }, field('Message', msg)), prev, h('div', { class: 'btns gap' }, pBtn, sBtn));

      // Solver
      var kcal = h('input', { class: 'in mono', type: 'number', value: 700 }), prot = h('input', { class: 'in mono', type: 'number', placeholder: 'optional' }), excl = h('input', { class: 'in', placeholder: 'e.g. dairy, gluten' });
      var out = h('div', { class: 'gap' });
      var rBtn = h('button', { class: 'btn pri', text: 'Run solver' });
      rBtn.addEventListener('click', function () {
        act(rBtn, function () {
          return api('/solver', { method: 'POST', body: { targetKcal: Number(kcal.value), proteinG: prot.value ? Number(prot.value) : null, excludedTokens: excl.value.split(',').map(function (s) { return s.trim().toLowerCase(); }).filter(Boolean) } }).then(function (res) {
            clear(out);
            if (!res.result) return out.appendChild(h('p', { class: 't-warn', text: 'No acceptable meal for those limits.' }));
            (res.result.items || []).forEach(function (it) { out.appendChild(h('div', { class: 'row' }, h('span', { class: 'grow', text: it.quantity + ' × ' + (it.servingDesc || '') + ' ' + it.name }), h('span', { class: 'mono t-soft', text: Math.round(it.kcal || 0) + ' kcal' }))); });
            out.appendChild(h('div', { class: 'row' }, h('span', { class: 'grow t-soft', text: 'Total' }), h('span', { class: 'mono', text: Math.round(res.result.totalKcal || 0) + ' kcal · ' + Math.round(res.result.totalProteinG || 0) + ' g protein' })));
          });
        });
      });
      var sv = card('Solver dry-run', 'nothing is saved', h('div', { class: 'two' }, field('Target kcal', kcal), field('Protein g', prot)), h('div', { class: 'gap' }, field('Avoid', excl)), h('div', { class: 'btns gap' }, rBtn), out);

      page.appendChild(who);
      page.appendChild(h('div', { class: 'grid2' }, h('div', { class: 'stack' }, sim, now), h('div', { class: 'stack' }, bc, sv)));
    });
  };

  // ---------- Control ----------
  SCREENS.control = function (page) {
    return api('/control').then(function (c) {
      clear(page);
      page.appendChild(h('div', null, header('Control · reaches the app within a minute', 'Turn things off', 'without a deploy.')));
      var sw = card('Kill switches', c.switches.filter(function (s) { return s.on; }).length + ' on');
      c.switches.forEach(function (s) {
        sw.appendChild(h('div', { class: 'row' }, toggle(s.on, function (v) { return api('/control/switch/' + s.key, { method: 'PUT', body: { on: v } }).then(refreshSwitchChip); }, s.label), h('div', { class: 'grow' }, h('div', { style: 'font-weight:600', text: s.label }), h('div', { class: 't-soft', style: 'font-size:13px', text: s.hint }))));
      });
      var m = c.maintenance;
      var en = h('input', { class: 'in', value: m.en, maxlength: 240, placeholder: 'We’re fixing meal logging. Back in ~20 min.' });
      var he = h('input', { class: 'in', value: m.he, maxlength: 240, dir: 'rtl' });
      var mOn = h('span', { class: 'chip ' + (m.active ? 'off' : 'ok'), text: m.active ? 'notice is showing' : 'no notice' });
      var pub = h('button', { class: 'btn pri', text: 'Publish notice' }), clr = h('button', { class: 'btn', text: 'Clear notice' });
      function saveM(active) { return api('/control/maintenance', { method: 'PUT', body: { active: active, en: en.value, he: he.value } }).then(function () { mOn.className = 'chip ' + (active ? 'off' : 'ok'); mOn.textContent = active ? 'notice is showing' : 'no notice'; }); }
      pub.addEventListener('click', function () { act(pub, function () { return saveM(true); }, 'Notice published'); });
      clr.addEventListener('click', function () { act(clr, function () { return saveM(false); }, 'Notice cleared'); });
      var maint = card('Maintenance notice', 'shown on Today', field('Message (EN)', en), h('div', { class: 'gap' }, field('Message (HE)', he)), h('div', { class: 'btns gap' }, mOn, pub, clr));
      var min = h('input', { class: 'in mono', value: c.version.min || '', placeholder: '1.4.2' }), lat = h('input', { class: 'in mono', value: c.version.latest || '', placeholder: '1.5.0' });
      var vb = h('button', { class: 'btn pri', text: 'Save versions' });
      vb.addEventListener('click', function () { act(vb, function () { return api('/control/version', { method: 'PUT', body: { min: min.value.trim() || null, latest: lat.value.trim() || null } }); }, 'Saved'); });
      var ver = card('App version gate', 'read on every launch', h('div', { class: 'two' }, field('Minimum (forces update)', min), field('Latest (soft nudge)', lat)), h('div', { class: 'note', text: 'Builds below the minimum see an update screen. Leave blank to turn the gate off. The app needs a build that reads this (see the todo list).' }), h('div', { class: 'btns gap' }, vb));
      page.appendChild(h('div', { class: 'grid2' }, h('div', { class: 'stack' }, sw, maint), h('div', { class: 'stack' }, ver)));
    });
  };

  // ---------- Subscriptions ----------
  SCREENS.subs = function (page) {
    return api('/subscriptions').then(function (d) {
      clear(page);
      page.appendChild(h('div', null, header('Control · grant, extend, revoke', 'Who has', 'SetPoint Pro.')));
      page.appendChild(h('div', { class: 'nums' }, h('div', null, h('b', { text: d.counts.paying }), h('span', { text: 'paying' })), h('div', null, h('b', { text: d.counts.trial }), h('span', { text: 'in trial' })), h('div', null, h('b', { text: d.counts.granted }), h('span', { text: 'granted by you' }))));
      var list = card('People with a subscription record', d.people.length + '');
      if (!d.people.length) list.appendChild(h('p', { class: 't-soft', text: 'No one has a subscription yet. Grant one from People.' }));
      d.people.forEach(function (p) {
        var ext = h('button', { class: 'btn', text: 'Add 30 d' }), rev = h('button', { class: 'btn dng', text: 'Revoke' });
        ext.addEventListener('click', function () { act(ext, function () { return api('/users/' + p.id + '/subscription', { method: 'POST', body: { action: 'grant', days: 30 } }); }, 'Extended 30 days').then(function () { SCREENS.subs(page); }); });
        rev.addEventListener('click', function () { if (!confirm('Revoke their access?')) return; act(rev, function () { return api('/users/' + p.id + '/subscription', { method: 'POST', body: { action: 'revoke' } }); }, 'Revoked').then(function () { SCREENS.subs(page); }); });
        list.appendChild(h('div', { class: 'row' }, dot(p.live ? 'good' : 'faint'), h('div', { class: 'grow' }, h('div', { style: 'font-weight:600', text: p.displayName || p.email || p.id.slice(-8) }), h('div', { class: 'mono t-faint', style: 'font-size:12px', text: (p.granted ? 'granted' : String(p.subscriptionStatus).toLowerCase()) + ' · ' + (p.subscriptionExpiresAt ? (p.live ? 'until ' : 'ended ') + new Date(p.subscriptionExpiresAt).toLocaleDateString() : 'no date') })), ext, rev));
      });
      page.appendChild(list);
    });
  };

  // ---------- People ----------
  SCREENS.people = function (page) {
    return Promise.all([api('/ops/now'), api('/control')]).then(function (r) {
      var people = r[0].people, tests = r[1].testAccounts, filter = 'all', q = '';
      clear(page);
      page.appendChild(h('div', null, header('Manage · ' + r[0].peopleTotal + ' people', 'See the app', 'as they see it.')));
      var chipsBox = h('div', { class: 'chips' });
      var search = h('input', { class: 'in', placeholder: 'Search by name…', style: 'max-width:260px;height:32px' });
      var tableBox = h('div', { class: 'card scroll' }), detail = h('div', { class: 'stack' });
      var FILTERS = [['all', 'All'], ['active', 'Active today'], ['nopush', 'No push token'], ['test', 'Test accounts']];
      function drawChips() {
        clear(chipsBox);
        FILTERS.forEach(function (f) { chipsBox.appendChild(h('button', { class: 'chip', 'aria-pressed': String(filter === f[0]), onclick: function () { filter = f[0]; drawChips(); drawTable(); }, text: f[1] })); });
        chipsBox.appendChild(search);
      }
      function matches(p) {
        if (q && p.name.toLowerCase().indexOf(q) < 0) return false;
        if (filter === 'nopush') return p.pushKind === 'none' || p.pushKind === 'sandbox';
        if (filter === 'test') return tests.indexOf(p.id) >= 0;
        if (filter === 'active') return p.streak > 0;
        return true;
      }
      var selected = null;
      function drawTable() {
        clear(tableBox);
        var t = h('table', null, h('thead', null, h('tr', null, h('th', { text: 'Person' }), h('th', { text: 'Streak' }), h('th', { text: 'Answered' }), h('th', { text: 'Push' }))), h('tbody'));
        people.filter(matches).forEach(function (p) {
          var tr = h('tr', { class: 'pick' + (selected === p.id ? ' sel' : ''), tabindex: '0', onclick: function () { selected = p.id; drawTable(); drawDetail(p); } },
            h('td', null, h('div', { style: 'font-weight:600', text: p.name }), h('div', { class: 'mono t-faint', style: 'font-size:12px', text: p.sub })),
            h('td', { class: 'mono', text: p.streak + ' d' }), h('td', { class: 'mono', text: p.answered }),
            h('td', null, h('span', { style: 'display:inline-flex;gap:6px;align-items:center' }, dot(p.tone), h('span', { class: 'mono', style: 'font-size:12px', text: p.push }))));
          tr.addEventListener('keydown', function (e) { if (e.key === 'Enter') tr.click(); });
          t.lastChild.appendChild(tr);
        });
        tableBox.appendChild(t);
      }
      search.addEventListener('input', function () { q = search.value.toLowerCase(); drawTable(); });
      function drawDetail(p) {
        clear(detail);
        var isTest = tests.indexOf(p.id) >= 0;
        var view = h('button', { class: 'btn pri', text: 'View as ' + p.name.split(' ')[0] }), tp = h('button', { class: 'btn', text: 'Test push' }), rb = h('button', { class: 'btn', text: 'Reset backoff' }), gp = h('button', { class: 'btn', text: 'Grant 30 d Pro' }), ex = h('button', { class: 'btn', text: 'Export data' }), del = h('button', { class: 'btn dng', text: 'Delete account' });
        view.addEventListener('click', function () { act(view, function () { return api('/users/' + p.id + '/view-as').then(showPhone); }); });
        tp.addEventListener('click', function () { act(tp, function () { return api('/ops/person/' + p.id + '/test-push', { method: 'POST' }).then(function (res) { toast('Sent ' + res.sent + ' of ' + res.attempted + (res.error ? ' · ' + res.error : '')); }); }); });
        rb.addEventListener('click', function () { act(rb, function () { return api('/ops/person/' + p.id + '/reset-backoff', { method: 'POST' }); }, 'Backoff cleared'); });
        gp.addEventListener('click', function () { act(gp, function () { return api('/users/' + p.id + '/subscription', { method: 'POST', body: { action: 'grant', days: 30 } }); }, 'Granted 30 days'); });
        ex.addEventListener('click', function () { act(ex, function () { return api('/users/' + p.id + '/export').then(function (d) { var a = h('a', { href: URL.createObjectURL(new Blob([JSON.stringify(d, null, 2)], { type: 'application/json' })), download: 'setpoint-' + p.id + '.json' }); document.body.appendChild(a); a.click(); a.remove(); }); }); });
        del.addEventListener('click', function () { if (prompt('This deletes ' + p.name + ' and all their data for good. Type DELETE to confirm.') !== 'DELETE') return; act(del, function () { return api('/users/' + p.id, { method: 'DELETE' }); }, 'Deleted').then(function () { people = people.filter(function (x) { return x.id !== p.id; }); selected = null; clear(detail); drawTable(); }); });
        var info = h('div', { class: 'note', style: 'margin-top:12px', text: 'Loading…' });
        detail.appendChild(card(p.name, isTest ? 'test account' : '', h('div', { class: 'btns' }, view, tp, rb), h('div', { class: 'btns gap' }, gp, ex, del), info));
        api('/ops/person/' + p.id).then(function (d) {
          var ci = d.checkIns && d.checkIns[0];
          info.textContent = lines([
            'Joined ' + new Date(d.joined).toLocaleDateString() + ' · ' + d.timezone + (d.settings ? ' · goal ' + d.settings.goal : ''),
            'Last check-in: ' + (ci ? hhmm(ci.at) + ' ' + ci.kind + ' · ' + ci.delivery + ' · ' + ci.outcome : 'none yet'),
            d.scoring ? 'Scoring: ' + d.scoring : null,
            d.settings && d.settings.backedOffUntil ? 'Backed off until ' + new Date(d.settings.backedOffUntil).toLocaleString() : null
          ].filter(Boolean));
        }).catch(function () { info.textContent = 'No details yet.'; });
      }
      drawChips(); drawTable();
      page.appendChild(chipsBox);
      page.appendChild(h('div', { class: 'grid2', style: 'margin-top:8px' }, tableBox, detail));
    });
  };
  function showPhone(home) {
    var L = home.ledger || {};
    var pct = L.targetKcal ? Math.min(100, Math.round((L.consumedKcal / L.targetKcal) * 100)) : 0;
    var meals = (home.meals || []).slice(0, 6);
    var next = home.nextCheckIn;
    var phone = h('div', { class: 'phone' },
      h('div', { class: 'mono t-faint', style: 'font-size:10px;text-align:center', text: 'READ-ONLY · what the app shows them' }),
      h('div', { class: 't-soft', style: 'margin-top:14px;font-size:12px', text: 'Today' }),
      h('div', { style: 'font-size:28px;font-weight:500;letter-spacing:-.04em', text: (L.consumedKcal || 0) + ' ' }, h('span', { class: 't-faint', style: 'font-size:14px', text: '/ ' + (L.targetKcal || 0) + ' kcal' })),
      h('div', { class: 'bar' }, h('i', { style: 'width:' + pct + '%;background:var(--ember)' })),
      home.managerNote ? h('p', { class: 't-soft', style: 'font-size:13px', text: home.managerNote }) : null,
      next ? h('div', { class: 'note', style: 'background:rgba(255,122,61,.12);border-color:rgba(255,122,61,.35)', text: 'Next check-in ' + minLabel(next.dueMin) + (next.light ? ' (light meal)' : '') }) : null,
      home.topUp ? h('div', { class: 'note', text: 'Top-up offered: ' + home.topUp.behindKcal + ' kcal behind pace' }) : null,
      home.closeCheckIn ? h('div', { class: 'note', text: 'Evening close at ' + minLabel(home.closeCheckIn.dueMin) + ': ' + home.closeCheckIn.gapKcal + ' kcal short' }) : null,
      h('div', { class: 'grp', style: 'padding-left:0', text: 'Meals' }),
      meals.length ? meals.map(function (m) { return h('div', { class: 'row', style: 'padding:8px 0;font-size:13px' }, h('span', { class: 'grow', text: m.title || m.name || m.rawInput || 'Meal' }), h('span', { class: 'mono t-soft', text: (m.kcal || 0) + ' kcal' })); }) : h('p', { class: 't-faint', style: 'font-size:13px', text: 'Nothing logged yet.' }));
    var modal = h('div', { class: 'modal', onclick: function (e) { if (e.target === modal) modal.remove(); } }, phone);
    document.body.appendChild(modal);
  }

  // ---------- Catalog ----------
  SCREENS.catalog = function (page) {
    var kind = 'catalog', q = '';
    clear(page);
    page.appendChild(h('div', null, header('Manage · foods', 'Fix a wrong food', 'in a minute.')));
    var box = h('div', { class: 'card scroll' });
    var chips = h('div', { class: 'chips' });
    var search = h('input', { class: 'in', placeholder: 'Search foods…', style: 'max-width:260px;height:32px' });
    function drawChips() { clear(chips); [['catalog', 'Catalog'], ['barcode', 'Barcode']].forEach(function (k) { chips.appendChild(h('button', { class: 'chip', 'aria-pressed': String(kind === k[0]), onclick: function () { kind = k[0]; drawChips(); load(); }, text: k[1] })); }); chips.appendChild(search); }
    var timer;
    search.addEventListener('input', function () { clearTimeout(timer); timer = setTimeout(function () { q = search.value.trim(); load(); }, 300); });
    function num(v) { return h('input', { class: 'in mono', type: 'number', step: '0.1', value: v, style: 'width:84px;height:32px;padding:0 8px' }); }
    function load() {
      clear(box); box.appendChild(h('div', { class: 'skel', text: 'Loading…' }));
      api('/catalog?kind=' + kind + (q ? '&q=' + encodeURIComponent(q) : '')).then(function (d) {
        clear(box);
        box.appendChild(h('div', { class: 'h3' }, d.total + ' foods', h('span', { text: 'values are per 100 g · showing ' + d.rows.length })));
        var t = h('table', null, h('thead', null, h('tr', null, h('th', { text: 'Food' }), h('th', { text: 'kcal' }), h('th', { text: 'P' }), h('th', { text: 'C' }), h('th', { text: 'F' }), h('th'))), h('tbody'));
        d.rows.forEach(function (r) {
          var k = num(r.kcal100g), p = num(r.proteinG100g), c = num(r.carbsG100g), f = num(r.fatG100g);
          var save = h('button', { class: 'btn', text: 'Save' });
          save.addEventListener('click', function () { act(save, function () { return api('/catalog/' + kind + '/' + r.id, { method: 'PATCH', body: { kcal100g: Number(k.value), proteinG100g: Number(p.value), carbsG100g: Number(c.value), fatG100g: Number(f.value) } }); }, 'Saved ' + r.name); });
          t.lastChild.appendChild(h('tr', null, h('td', null, h('div', { style: 'font-weight:600', text: r.name }), r.suspicious ? h('div', { class: 't-warn mono', style: 'font-size:12px', text: 'looks off' }) : r.brand ? h('div', { class: 't-faint', style: 'font-size:12px', text: r.brand }) : null), h('td', null, k), h('td', null, p), h('td', null, c), h('td', null, f), h('td', null, save)));
        });
        box.appendChild(t);
      }).catch(function (e) { clear(box); box.appendChild(h('p', { class: 't-bad', text: e.message })); });
    }
    drawChips(); page.appendChild(chips); page.appendChild(box); load();
    return Promise.resolve();
  };

  // ---------- Flags + invites ----------
  SCREENS.access = function (page) {
    return Promise.all([api('/flags'), api('/invites'), api('/status')]).then(function (r) {
      clear(page);
      page.appendChild(h('div', null, header('Manage · who gets what', 'Flags and', 'invites.')));
      var fl = card('Feature flags', 'override the default in code');
      r[0].flags.forEach(function (f) {
        var on = f.override ? f.override.enabled : f.default;
        fl.appendChild(h('div', { class: 'row' }, toggle(on, function (v) { return api('/flags/' + f.key, { method: 'PUT', body: { enabled: v } }); }, f.key), h('div', { class: 'grow' }, h('div', { style: 'font-weight:600', class: 'mono', text: f.key }), h('div', { class: 't-soft', style: 'font-size:13px', text: f.description + (f.override && (f.override.groups.length || f.override.roles.length || f.override.userIds.length) ? ' (also on for a list: edit in Classic)' : '') }))));
      });
      var code = h('input', { class: 'in mono', placeholder: 'leave blank for a random code' }), grp = h('input', { class: 'in', placeholder: 'group, e.g. beta' }), uses = h('input', { class: 'in mono', type: 'number', placeholder: 'max uses' });
      var mk = h('button', { class: 'btn pri', text: 'Create invite' });
      mk.addEventListener('click', function () { var body = {}; if (code.value.trim()) body.code = code.value.trim(); if (grp.value.trim()) body.group = grp.value.trim(); if (uses.value) body.maxUses = Number(uses.value); act(mk, function () { return api('/invites', { method: 'POST', body: body }); }, 'Invite created').then(function () { SCREENS.access(page); }); });
      var inv = card('Invite codes', r[2].switches.inviteOnly ? 'signups are invite-only' : 'signups are open', h('div', { class: 'two' }, field('Code', code), field('Group', grp)), h('div', { class: 'two gap' }, field('Max uses', uses), h('div', { style: 'display:flex;align-items:flex-end' }, mk)));
      r[1].invites.slice(0, 15).forEach(function (i) {
        var dis = h('button', { class: 'btn', text: 'Disable' });
        dis.addEventListener('click', function () { act(dis, function () { return api('/invites/' + encodeURIComponent(i.code) + '/disable', { method: 'POST' }); }, 'Disabled').then(function () { SCREENS.access(page); }); });
        inv.appendChild(h('div', { class: 'row' }, dot(i.disabledAt ? 'faint' : 'good'), h('div', { class: 'grow' }, h('div', { class: 'mono', style: 'font-weight:600', text: i.code }), h('div', { class: 't-soft', style: 'font-size:12px', text: (i.group || 'no group') + ' · used ' + i.uses + (i.maxUses ? '/' + i.maxUses : '') })), i.disabledAt ? null : dis));
      });
      page.appendChild(h('div', { class: 'grid2' }, fl, inv));
    });
  };

  // ---------- Audit ----------
  SCREENS.audit = function (page) {
    return api('/audit').then(function (d) {
      clear(page);
      page.appendChild(h('div', null, header('Manage · last 200 changes', 'Who changed', 'what.')));
      var c = card('Admin actions', 'newest first');
      if (!d.entries.length) c.appendChild(h('p', { class: 't-soft', text: 'Nothing yet. Every change made from this console shows here.' }));
      d.entries.forEach(function (e) { c.appendChild(h('div', { class: 'row' }, h('span', { class: 'mono t-faint', style: 'width:130px;font-size:12px', text: new Date(e.at).toLocaleString() }), h('span', { class: 'mono', style: 'width:60px;font-size:12px', text: e.method }), h('span', { class: 'grow mono', style: 'font-size:13px', text: e.route }), h('span', { class: 'mono t-faint', text: e.actor }))); });
      page.appendChild(c);
    });
  };

  // ---------- login ----------
  function loginView() {
    var input = h('input', { class: 'in', type: 'password', placeholder: 'Admin secret', autocomplete: 'current-password', 'aria-label': 'Admin secret' });
    var err = h('p', { class: 'err', role: 'alert' });
    var btn = h('button', { class: 'btn pri', style: 'height:44px;width:100%', text: 'Sign in' });
    function submit() {
      state.secret = input.value.trim(); if (!state.secret) return;
      btn.disabled = true;
      fetch('/api/admin/control', { headers: { 'x-admin-secret': state.secret } }).then(function (res) {
        if (res.ok) { try { sessionStorage.setItem(KEY, state.secret); } catch (e) {} state.route = route(); render(); }
        else { state.secret = null; err.textContent = res.status === 401 ? 'That secret is not right.' : 'Could not sign in (' + res.status + ').'; btn.disabled = false; }
      }).catch(function () { state.secret = null; err.textContent = 'Could not reach the server.'; btn.disabled = false; });
    }
    btn.addEventListener('click', submit);
    input.addEventListener('keydown', function (e) { if (e.key === 'Enter') submit(); });
    return h('div', { class: 'login' }, h('h1', { text: 'SetPoint admin' }), h('p', { text: 'Sign in with the admin secret. It stays in this tab only.' }), input, err, btn);
  }

  window.addEventListener('hashchange', function () { state.route = route(); render(); });
  try { state.secret = sessionStorage.getItem(KEY); } catch (e) {}
  state.route = route();
  render();
})();
</script>
</body>
</html>`;
