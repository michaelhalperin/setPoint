/**
 * The owner's dashboard at /admin: analytics, users, invite codes, feature flags
 * and system health, on top of /api/admin. One self-contained page — it holds no
 * data itself; everything loads after signing in with the admin secret, which
 * stays in this browser tab's session storage.
 *
 * Kept as a raw string so it ships inside the serverless bundle. The script
 * avoids template literals so nothing here is read as interpolation.
 */
export const ADMIN_DASHBOARD_HTML = String.raw`<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex, nofollow">
<title>SetPoint Admin</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Red+Hat+Mono:wght@500&family=Source+Sans+3:wght@400;500;600;700&display=swap" rel="stylesheet">
<style>
:root {
  --bg: #F3F4F6;
  --rail: #FFFFFF;
  --panel: #FFFFFF;
  --line: #E5E7EB;
  --line-hi: #D1D5DB;
  --ink: #111827;
  --soft: #4B5563;
  --faint: #6B7280;
  --accent: #1D4ED8;
  --accent-soft: #EFF6FF;
  --good: #047857;
  --good-bg: #ECFDF5;
  --bad: #B91C1C;
  --bad-bg: #FEF2F2;
  --warn: #B45309;
  --warn-bg: #FFFBEB;
  --mono: "Red Hat Mono", ui-monospace, monospace;
  --sans: "Source Sans 3", ui-sans-serif, system-ui, sans-serif;
  --r: 12px;
  --r-sm: 8px;
  --shadow: 0 8px 24px rgba(17, 24, 39, 0.12);
  --rail-w: 232px;
}
* { box-sizing: border-box; }
html, body { margin: 0; background: var(--bg); color: var(--ink); font: 15px/1.45 var(--sans); }
body { min-height: 100vh; }
::selection { background: #DBEAFE; color: var(--ink); }
:focus-visible { outline: 2px solid var(--accent); outline-offset: 2px; }
input, textarea, select { caret-color: var(--accent); }
button, input, select, textarea { font: inherit; color: inherit; }
a { color: var(--accent); }
.mono { font-family: var(--mono); font-size: 13px; font-variant-numeric: tabular-nums; }
.muted { color: var(--faint); }
.soft { color: var(--soft); }
.spacer { flex: 1; }

.login { width: min(400px, calc(100% - 32px)); margin: 18vh auto 0; background: var(--panel); border: 1px solid var(--line); border-radius: var(--r); padding: 32px; display: grid; gap: 14px; }
.login h1 { font-size: 28px; font-weight: 600; letter-spacing: -0.03em; line-height: 1.15; margin: 0; }
.login p { margin: 0; color: var(--soft); }

.shell { display: grid; grid-template-columns: var(--rail-w) minmax(0, 1fr); min-height: 100vh; }
.rail { background: var(--rail); border-right: 1px solid var(--line); padding: 24px 16px; display: flex; flex-direction: column; gap: 4px; position: sticky; top: 0; height: 100vh; }
.brand { font-size: 16px; font-weight: 650; letter-spacing: -0.03em; padding: 0 12px; }
.env { font-family: var(--mono); font-size: 11px; color: var(--faint); padding: 4px 12px 16px; }
.rail nav { display: flex; flex-direction: column; gap: 2px; }
.rail nav button { display: flex; align-items: center; gap: 8px; width: 100%; text-align: left; background: none; border: 0; color: var(--soft); font-weight: 500; padding: 8px 12px; border-radius: var(--r-sm); cursor: pointer; min-height: 36px; }
.rail nav button:hover { background: var(--bg); color: var(--ink); }
.rail nav button[aria-current="page"] { background: var(--accent-soft); color: var(--accent); font-weight: 600; }
.count { margin-left: auto; min-width: 20px; height: 20px; padding: 0 6px; border-radius: 999px; background: var(--warn-bg); color: var(--warn); font-size: 12px; font-weight: 650; display: inline-flex; align-items: center; justify-content: center; }
.find { width: 100%; height: 36px; margin: 8px 0 16px; padding: 0 12px; border-radius: var(--r-sm); border: 1px solid var(--line); background: var(--bg); }
.rail-foot { margin-top: auto; padding-top: 16px; }
.rail-foot .textish { background: none; border: 0; color: var(--soft); cursor: pointer; font-size: 13px; padding: 8px 12px; text-align: left; }
.rail-foot .textish:hover { color: var(--ink); }

.stage { padding: 28px 32px 64px; max-width: 1180px; }
.page-head { display: flex; align-items: baseline; gap: 12px; flex-wrap: wrap; margin: 0 0 8px; }
.page-head h1 { font-size: 24px; font-weight: 650; letter-spacing: -0.03em; margin: 0; }
.lede { color: var(--soft); margin: 0 0 20px; }
.toolbar { display: flex; align-items: center; gap: 10px; flex-wrap: wrap; margin-bottom: 16px; }
.section { margin-top: 24px; }
.section h2 { font-size: 15px; font-weight: 650; margin: 0 0 10px; }

.panel { background: var(--panel); border: 1px solid var(--line); border-radius: var(--r); padding: 18px; }
.grid { display: grid; gap: 12px; }
.kpis { grid-template-columns: repeat(4, minmax(0, 1fr)); }
.kpis-3 { grid-template-columns: repeat(3, minmax(0, 1fr)); }
.overview-hero { min-height: calc(100vh - 56px); }
.overview-hero .kpi { padding: 28px 22px 36px; }
.kpi .value { font-family: var(--mono); font-size: 40px; font-weight: 500; letter-spacing: -0.03em; margin-top: 8px; font-variant-numeric: tabular-nums; }
.chart-max { font-family: var(--mono); font-size: 12px; color: var(--soft); margin-bottom: 4px; }
h2 { font-size: 15px; font-weight: 650; margin: 0 0 10px; letter-spacing: -0.02em; }
::placeholder { color: var(--soft); opacity: 1; }
.kpi .sub { color: var(--faint); font-size: 13px; margin-top: 4px; }
.kpi .sub.warn { color: var(--warn); }
.split { grid-template-columns: repeat(2, minmax(0, 1fr)); align-items: start; }

.callout { display: flex; align-items: center; gap: 12px; flex-wrap: wrap; padding: 12px 14px; border: 1px solid #F5D0A6; background: var(--warn-bg); border-radius: var(--r); margin-bottom: 16px; color: var(--ink); }
.callout b { font-weight: 650; }

.badge { white-space: nowrap; font-size: 12px; font-weight: 600; padding: 3px 8px; border-radius: 999px; border: 1px solid var(--line); color: var(--soft); background: var(--panel); }
.badge.good { color: var(--good); background: var(--good-bg); border-color: #A7F3D0; }
.badge.bad { color: var(--bad); background: var(--bad-bg); border-color: #FECACA; }
.badge.lit { color: var(--warn); background: var(--warn-bg); border-color: #F5D0A6; }
.badge.haze { color: var(--accent); background: var(--accent-soft); border-color: #BFDBFE; }

.btn { height: 36px; padding: 0 14px; border-radius: var(--r-sm); border: 1px solid var(--line-hi); background: var(--panel); cursor: pointer; white-space: nowrap; font-weight: 500; }
.btn:hover { background: var(--bg); }
.btn.primary { background: var(--accent); color: #fff; border-color: var(--accent); font-weight: 600; }
.btn.primary:hover { filter: brightness(1.05); }
.btn.danger { color: var(--bad); border-color: #FECACA; background: var(--panel); }
.btn.danger:hover { background: var(--bad-bg); }
.btn.small { height: 32px; padding: 0 10px; font-size: 13px; }
.btn:disabled { opacity: 0.45; cursor: default; }
.btn.busy { cursor: progress; }
.isolate { margin-left: auto; }

input[type=text], input[type=password], input[type=number], input[type=date], input[type=search], select, textarea {
  height: 36px; padding: 0 12px; border-radius: var(--r-sm); border: 1px solid var(--line); background: var(--panel); outline: none; }
textarea { height: auto; min-height: 64px; padding: 10px 12px; font-family: var(--mono); font-size: 13px; resize: vertical; }
input:focus, select:focus, textarea:focus { border-color: var(--accent); }
select option { background: #fff; }
input[type=checkbox], input[type=radio] { accent-color: var(--accent); width: 16px; height: 16px; }

.table-wrap { overflow-x: auto; }
table { width: 100%; border-collapse: collapse; }
th { text-align: left; font-size: 12px; font-weight: 650; color: var(--faint); padding: 8px 10px; border-bottom: 1px solid var(--line); white-space: nowrap; position: sticky; top: 0; background: var(--panel); }
th.num, td.num { text-align: right; font-variant-numeric: tabular-nums; font-family: var(--mono); font-size: 13px; }
td { padding: 10px; border-bottom: 1px solid var(--bg); vertical-align: middle; }
tr:last-child td { border-bottom: none; }
tbody tr:hover td { background: #F9FAFB; }

.empty { padding: 36px 20px; text-align: center; color: var(--faint); border: 1px dashed var(--line-hi); border-radius: var(--r); background: var(--panel); }
.skel { height: 88px; border-radius: var(--r); background: linear-gradient(90deg, #E5E7EB 0%, #F3F4F6 50%, #E5E7EB 100%); background-size: 200% 100%; }
@media (prefers-reduced-motion: no-preference) {
  .skel { animation: shimmer 1.1s ease-in-out infinite; }
  .toast { animation: toast-in 180ms ease-out; }
}
@keyframes shimmer { to { background-position: -200% 0; } }
@keyframes toast-in { from { opacity: 0; transform: translate(-50%, 8px); } to { opacity: 1; transform: translate(-50%, 0); } }
@media (prefers-reduced-motion: reduce) { .skel { animation: none; } }

.funnel-row { display: grid; grid-template-columns: 160px 1fr 88px; align-items: center; gap: 12px; padding: 6px 0; }
.bar { height: 8px; border-radius: 4px; background: var(--bg); overflow: hidden; }
.bar > span { display: block; height: 100%; border-radius: 4px; background: var(--accent); }
.chart svg { width: 100%; height: 180px; display: block; }
.legend { display: flex; gap: 16px; margin-top: 8px; color: var(--soft); font-size: 13px; }
.dot { display: inline-block; width: 8px; height: 8px; border-radius: 50%; margin-right: 6px; vertical-align: middle; }

.switch-row { display: flex; align-items: center; justify-content: space-between; gap: 10px; padding: 10px 0; border-bottom: 1px solid var(--bg); }
.switch-row:last-child { border-bottom: none; }
.flag { display: grid; gap: 14px; }
.flag-head { display: flex; align-items: baseline; gap: 10px; flex-wrap: wrap; }
.flag-key { font-family: var(--mono); font-size: 14px; }
.modes { display: flex; gap: 6px; flex-wrap: wrap; }
.modes label { display: flex; align-items: center; gap: 6px; height: 32px; padding: 0 12px; border-radius: 999px; border: 1px solid var(--line); cursor: pointer; color: var(--soft); }
.modes label.on { border-color: var(--accent); color: var(--accent); background: var(--accent-soft); }
.field { display: grid; gap: 6px; }
.field > span { font-size: 13px; color: var(--soft); }
.form-grid { display: grid; gap: 12px; grid-template-columns: repeat(auto-fit, minmax(170px, 1fr)); align-items: end; }
.form-actions { display: flex; justify-content: flex-end; margin-top: 4px; }

.toast { position: fixed; left: 50%; bottom: 24px; transform: translateX(-50%); padding: 12px 18px; border-radius: var(--r); background: var(--ink); color: #fff; box-shadow: var(--shadow); font-size: 14px; z-index: 10; max-width: calc(100% - 32px); }
.toast.bad { background: var(--bad); }
.created { display: flex; align-items: center; gap: 12px; padding: 14px 16px; border-radius: var(--r); border: 1px solid #BFDBFE; background: var(--accent-soft); margin-top: 12px; }
.created .code { font-family: var(--mono); font-size: 22px; letter-spacing: 0.08em; }
pre { margin: 0; font-family: var(--mono); font-size: 12px; white-space: pre-wrap; word-break: break-word; color: var(--soft); }
details summary { cursor: pointer; color: var(--soft); }

.meals { display: grid; gap: 12px; align-items: start; grid-template-columns: repeat(auto-fill, minmax(260px, 1fr)); }
.meal { display: flex; flex-direction: column; gap: 10px; padding: 14px; }
.meal img { width: 100%; height: 160px; object-fit: cover; border-radius: 10px; cursor: zoom-in; display: block; background: var(--bg); }
.meal .title { font-size: 15px; line-height: 1.3; font-weight: 600; }
.meal .items { color: var(--soft); font-size: 13px; line-height: 1.5; }
.macros { display: flex; gap: 12px; font-family: var(--mono); font-size: 12px; color: var(--soft); flex-wrap: wrap; font-variant-numeric: tabular-nums; }
.macros b { color: var(--ink); font-weight: 500; }
.linkish { background: none; border: none; padding: 0; color: var(--accent); cursor: pointer; text-align: left; font-weight: 500; }
.linkish:hover { text-decoration: underline; }
.lightbox { position: fixed; inset: 0; background: rgba(17, 24, 39, 0.72); display: flex; align-items: center; justify-content: center; z-index: 20; cursor: zoom-out; padding: 24px; }
.lightbox img { max-width: 100%; max-height: 100%; border-radius: 12px; }
.kv { display: grid; grid-template-columns: auto 1fr; gap: 6px 16px; font-size: 14px; }
.kv dt { color: var(--faint); }
.kv dd { margin: 0; }

@media (max-width: 960px) {
  .kpis, .kpis-3 { grid-template-columns: repeat(2, minmax(0, 1fr)); }
  .split { grid-template-columns: 1fr; }
}
@media (max-width: 720px) {
  .shell { grid-template-columns: 1fr; }
  .rail { position: sticky; top: 0; z-index: 5; height: auto; display: grid; grid-template-columns: 1fr auto; gap: 8px 12px; padding: 12px; border-right: 0; border-bottom: 1px solid var(--line); }
  .brand { padding: 0; }
  .env { padding: 0; margin: 0; grid-column: 1; }
  .find { width: 100%; margin: 0; grid-column: 1 / -1; }
  .rail nav { grid-column: 1 / -1; flex-direction: row; flex-wrap: nowrap; overflow-x: auto; }
  .rail nav button { width: auto; flex: 0 0 auto; }
  .rail-foot { margin: 0; padding: 0; grid-column: 2; grid-row: 1 / 3; align-self: start; }
  .overview-hero { min-height: calc(100dvh - 148px); }
  .stage { padding: 20px 16px 48px; }
  .funnel-row { grid-template-columns: 110px 1fr 56px; }
  .kpis, .kpis-3 { grid-template-columns: 1fr 1fr; }
  .kpi .value { font-size: 28px; }
}
</style>
</head>
<body>
<div class="wrap" id="app"></div>
<script>
(function () {
  'use strict';
  var KEY = 'setpoint.admin.secret';
  var TABS = [['overview', 'Overview'], ['users', 'Users'], ['meals', 'Meals'], ['invites', 'Invites'], ['flags', 'Flags'], ['health', 'Health']];
  var state = { secret: null, tab: 'overview', status: null, range: 14, cohort: '', userFilter: { q: '', role: '', cohort: '', pending: false }, person: null, mealFilter: { cohort: '', source: '' } };
  var root = document.getElementById('app');

  try { state.secret = sessionStorage.getItem(KEY); } catch (e) { state.secret = null; }
  readHash();

  function h(tag, attrs) {
    var el = document.createElement(tag);
    if (attrs) {
      Object.keys(attrs).forEach(function (k) {
        var v = attrs[k];
        if (v === null || v === undefined || v === false) return;
        if (k === 'class') el.className = v;
        else if (k === 'text') el.textContent = v;
        else if (k.slice(0, 2) === 'on') el.addEventListener(k.slice(2), v);
        else if (k === 'value') el.value = v;
        else if (k === 'checked') el.checked = !!v;
        else el.setAttribute(k, v === true ? '' : String(v));
      });
    }
    for (var i = 2; i < arguments.length; i++) append(el, arguments[i]);
    return el;
  }
  function append(el, child) {
    if (child === null || child === undefined || child === false) return;
    if (Array.isArray(child)) { child.forEach(function (c) { append(el, c); }); return; }
    el.appendChild(typeof child === 'string' || typeof child === 'number' ? document.createTextNode(String(child)) : child);
  }
  function svg(tag, attrs) {
    var el = document.createElementNS('http://www.w3.org/2000/svg', tag);
    Object.keys(attrs || {}).forEach(function (k) { el.setAttribute(k, String(attrs[k])); });
    return el;
  }
  function clear(el) { while (el.firstChild) el.removeChild(el.firstChild); }

  var toastTimer;
  function toast(text, bad) {
    var old = document.querySelector('.toast');
    if (old) old.remove();
    var t = h('div', { class: 'toast' + (bad ? ' bad' : ''), role: 'status', text: text });
    document.body.appendChild(t);
    clearTimeout(toastTimer);
    toastTimer = setTimeout(function () { t.remove(); }, 3200);
  }

  function fmtDate(iso) {
    if (!iso) return '—';
    var d = new Date(iso);
    return d.toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: d.getFullYear() === new Date().getFullYear() ? undefined : 'numeric' });
  }
  function fmtNum(n) { return n === null || n === undefined ? '—' : Number(n).toLocaleString('en-US'); }
  function pct(n) { return n === null || n === undefined ? '—' : Math.round(n * 100) + '%'; }

  function api(path, opts) {
    opts = opts || {};
    var headers = { 'x-admin-secret': state.secret || '' };
    if (opts.body !== undefined) headers['content-type'] = 'application/json';
    return fetch('/api/admin' + path, {
      method: opts.method || 'GET',
      headers: headers,
      body: opts.body !== undefined ? JSON.stringify(opts.body) : undefined,
    }).then(function (res) {
      if (res.status === 401) { signOut('That secret didn’t work.'); throw new Error('unauthorized'); }
      return res.text().then(function (text) {
        var json = {};
        try { json = text ? JSON.parse(text) : {}; } catch (e) { json = {}; }
        if (!res.ok) throw new Error(json.message || ('Request failed (' + res.status + ')'));
        return json;
      });
    });
  }
  function fail(err) { if (err && err.message !== 'unauthorized') toast(err.message || 'Something went wrong.', true); }

  function signOut(message) {
    state.secret = null;
    state.status = null;
    try { sessionStorage.removeItem(KEY); } catch (e) { /* private mode */ }
    renderLogin(message);
  }

  function readHash() {
    var raw = (location.hash || '').replace(/^#/, '');
    if (raw.indexOf('user/') === 0) { state.person = raw.slice(5); state.tab = 'users'; return; }
    var known = { overview: 1, users: 1, meals: 1, invites: 1, flags: 1, health: 1 };
    if (known[raw]) { state.tab = raw; state.person = null; }
  }
  function setHash() {
    var next = state.person ? 'user/' + state.person : state.tab;
    if ((location.hash || '').replace(/^#/, '') !== next) {
      try { history.replaceState(null, '', '#' + next); } catch (e) { location.hash = next; }
    }
  }
  function go(tab, person) {
    state.tab = tab;
    state.person = person || null;
    setHash();
    renderShell();
  }
  window.addEventListener('hashchange', function () {
    var prevTab = state.tab, prevPerson = state.person;
    readHash();
    if (state.secret && (state.tab !== prevTab || state.person !== prevPerson)) renderShell();
  });

  function renderLogin(message) {
    clear(root);
    root.className = '';
    var input = h('input', { type: 'password', placeholder: 'Admin secret', autocomplete: 'current-password', 'aria-label': 'Admin secret' });
    var btn = h('button', { class: 'btn primary', type: 'submit', text: 'Sign in' });
    var err = h('div', { class: 'soft', style: 'color: var(--bad); min-height: 20px', text: message || '' });
    var form = h('form', { class: 'login', onsubmit: function (e) {
      e.preventDefault();
      if (!input.value.trim()) return;
      state.secret = input.value.trim();
      btn.disabled = true;
      btn.classList.add('busy');
      btn.textContent = 'Signing in…';
      api('/status').then(function (status) {
        try { sessionStorage.setItem(KEY, state.secret); } catch (e2) { /* private mode */ }
        state.status = status;
        renderShell();
      }).catch(function (e3) { btn.disabled = false; btn.classList.remove('busy'); btn.textContent = 'Sign in'; if (e3.message !== 'unauthorized') err.textContent = e3.message; });
    } },
      h('h1', { text: 'SetPoint Admin' }),
      h('p', { text: 'Sign in with the admin secret.' }),
      input, btn, err
    );
    root.appendChild(form);
    input.focus();
  }

  var main;

  function renderShell() {
    clear(root);
    root.className = 'shell';
    var env = state.status ? state.status.environment : '';
    var pending = state.status && state.status.users ? state.status.users.pending : 0;
    var find = h('input', { class: 'find', type: 'search', placeholder: 'Find someone', 'aria-label': 'Find someone', value: state.userFilter.q || '' });
    find.addEventListener('keydown', function (e) {
      if (e.key !== 'Enter') return;
      state.userFilter.q = find.value.trim();
      go('users');
    });
    var nav = h('nav', { 'aria-label': 'Sections' });
    TABS.forEach(function (t) {
      nav.appendChild(h('button', {
        type: 'button',
        'aria-current': !state.person && state.tab === t[0] ? 'page' : null,
        onclick: function () { go(t[0]); }
      }, t[1], t[0] === 'users' && pending ? h('span', { class: 'count', text: String(pending) }) : null));
    });
    root.appendChild(h('aside', { class: 'rail' },
      h('div', { class: 'brand', text: 'SetPoint' }),
      env ? h('div', { class: 'env', text: env }) : h('div', { class: 'env', text: ' ' }),
      find,
      nav,
      h('div', { class: 'rail-foot' }, h('button', { class: 'textish', type: 'button', text: 'Sign out', onclick: function () { signOut(); } }))
    ));
    main = h('div', { class: 'stage', id: 'stage' });
    root.appendChild(main);
    setHash();
    if (state.person) { renderPerson(state.person); return; }
    ({ overview: renderOverview, users: renderUsers, meals: renderMeals, invites: renderInvites, flags: renderFlags, health: renderHealth })[state.tab]();
  }

  function loading() {
    clear(main);
    var titles = { overview: 'Overview', users: 'Users', meals: 'Meals', invites: 'Invites', flags: 'Flags', health: 'Health' };
    if (!state.person) pageHead(titles[state.tab] || '');
    main.appendChild(h('div', { class: 'grid kpis', 'aria-hidden': 'true' },
      h('div', { class: 'skel' }), h('div', { class: 'skel' }), h('div', { class: 'skel' }), h('div', { class: 'skel' })));
    main.appendChild(h('div', { class: 'skel section', 'aria-hidden': 'true', style: 'height: 220px' }));
  }
  function refreshStatus() { return api('/status').then(function (s) { state.status = s; return s; }); }

  function pageHead(title, lede) {
    main.appendChild(h('div', { class: 'page-head' }, h('h1', { text: title })));
    if (lede) main.appendChild(h('p', { class: 'lede', text: lede }));
  }

  function renderOverview() {
    loading();
    var to = new Date();
    var from = new Date(to.getTime() - state.range * 86400000);
    var q = '?from=' + encodeURIComponent(from.toISOString()) + '&to=' + encodeURIComponent(to.toISOString()) + (state.cohort ? '&cohort=' + encodeURIComponent(state.cohort) : '');
    Promise.all([api('/analytics' + q), refreshStatus(), api('/nutrition' + q)]).then(function (r) {
      var a = r[0], s = r[1], n = r[2];
      clear(main);
      var hero = h('div', { class: 'overview-hero' });
      main.appendChild(hero);
      hero.appendChild(h('div', { class: 'page-head' }, h('h1', { text: 'Overview' })));

      var rangeSel = h('select', { 'aria-label': 'Range', onchange: function (e) { state.range = Number(e.target.value); renderOverview(); } },
        [7, 14, 30, 90].map(function (d) { return h('option', { value: d, selected: state.range === d ? true : null, text: 'Last ' + d + ' days' }); }));
      var cohortSel = h('select', { 'aria-label': 'Cohort', onchange: function (e) { state.cohort = e.target.value; renderOverview(); } },
        h('option', { value: '', text: 'Everyone' }),
        s.cohorts.map(function (c) { return h('option', { value: c.cohort, selected: state.cohort === c.cohort ? true : null, text: c.cohort + ' · ' + c.users }); }));
      hero.appendChild(h('div', { class: 'toolbar' }, rangeSel, cohortSel,
        a.truncated ? h('span', { class: 'badge bad', text: 'Too many events — narrow the range' }) : null));

      if (s.users.pending) {
        hero.appendChild(h('div', { class: 'callout', role: 'status' },
          h('div', null, h('b', { text: s.users.pending + (s.users.pending === 1 ? ' person is' : ' people are') + ' waiting for an invite' }), h('div', { class: 'muted', text: 'Let them in from Users, or mint a code.' })),
          h('span', { class: 'spacer' }),
          h('button', { class: 'btn small', type: 'button', text: 'Open Users', onclick: function () { go('users'); } })));
      }

      var last = a.daily.length ? a.daily[a.daily.length - 1] : null;
      var totals = a.totals || {};
      function total(name) { return totals[name] ? totals[name].events : 0; }
      function people(name) { return totals[name] ? totals[name].users : 0; }
      hero.appendChild(h('div', { class: 'grid kpis' },
        kpi('People', fmtNum(s.users.total), s.users.pending ? s.users.pending + ' waiting for an invite' : 'none waiting', s.users.pending),
        kpi('Active, last day', fmtNum(last ? last.activeUsers : 0), last ? fmtDate(last.date) : 'no activity yet'),
        kpi('Meals logged', fmtNum(total('meal_logged')), people('meal_logged') + ' people'),
        kpi('Days fully eaten', pct(a.days.fullyEatenRate), a.days.fullyEaten + ' of ' + a.days.settled + ' settled days')
      ));

      var byGoal = Object.keys(n.weight.byGoal).map(function (g) {
        var x = n.weight.byGoal[g];
        return g.charAt(0) + g.slice(1).toLowerCase() + ' ' + signedKg(x.avgKgPerWeek) + ' (' + x.people + ')';
      }).join(' · ');
      main.appendChild(h('div', { class: 'grid kpis kpis-3 section' },
        kpi('Calories vs target', pct(n.calories.avgShareOfTarget), n.calories.daysWithFood + ' settled days with food · ' + n.calories.missedDays + ' missed'),
        kpi('Protein vs target', pct(n.protein.avgShareOfTarget), n.protein.avgGramsPerDay !== null ? n.protein.avgGramsPerDay + ' g a day on average' : 'no meals yet'),
        kpi('Weight change', n.weight.avgKgPerWeek === null ? '—' : signedKg(n.weight.avgKgPerWeek) + '/wk', n.weight.people ? n.weight.people + ' people · ' + byGoal : 'needs two weigh-ins a person')
      ));

      var f = a.funnel;
      var steps = [['Signed up', f.signedUp], ['Finished setup', f.onboarded], ['Logged a meal', f.loggedAMeal], ['Answered a check-in', f.answeredACheckIn], ['Had a fully eaten day', f.hadAFullDay]];
      var funnel = h('div', { class: 'panel' }, h('h2', { text: 'Funnel' }), h('p', { class: 'muted', style: 'margin: 0 0 10px', text: 'People who signed up in this range' }));
      if (!f.signedUp) funnel.appendChild(h('div', { class: 'muted', text: 'Nobody signed up in this range.' }));
      else steps.forEach(function (st) {
        var share = f.signedUp ? st[1] / f.signedUp : 0;
        funnel.appendChild(h('div', { class: 'funnel-row' },
          h('span', { class: 'soft', text: st[0] }),
          h('div', { class: 'bar' }, h('span', { style: 'width:' + Math.max(2, share * 100).toFixed(1) + '%' })),
          h('span', { class: 'mono num', style: 'text-align: right', text: st[1] + ' · ' + pct(share) })));
      });

      var chart = h('div', { class: 'panel chart' }, h('h2', { text: 'Per day' }), dailyChart(a.daily, from, to),
        h('div', { class: 'legend' },
          h('span', null, h('span', { class: 'dot', style: 'background: var(--accent)' }), 'Active people'),
          h('span', null, h('span', { class: 'dot', style: 'background: #111827' }), 'Meals logged')));

      main.appendChild(h('div', { class: 'grid split section' }, funnel, chart));

      var calPanel = h('div', { class: 'panel chart' }, h('h2', { text: 'Calories eaten vs target' }),
        n.calories.daily.length ? shareChart(n.calories.daily) : h('div', { class: 'muted', text: 'No settled days in this range yet.' }));
      var screens = a.screens || [];
      var screenPanel = h('div', { class: 'panel' }, h('h2', { text: 'Screens' }),
        screens.length ? h('div', { class: 'table-wrap' }, h('table', null,
          h('thead', null, h('tr', null, h('th', { text: 'Screen' }), h('th', { class: 'num', text: 'Views' }), h('th', { class: 'num', text: 'People' }))),
          h('tbody', null, screens.map(function (x) { return h('tr', null, h('td', { class: 'mono', text: x.screen }), h('td', { class: 'num', text: fmtNum(x.views) }), h('td', { class: 'num', text: fmtNum(x.users) })); }))))
          : h('div', { class: 'muted', text: 'No screen views yet — they start with the next app build.' }));
      main.appendChild(h('div', { class: 'grid split section' }, calPanel, screenPanel));

      var rows = Object.keys(totals).sort().map(function (name) {
        return h('tr', null, h('td', { class: 'mono', text: name }), h('td', { class: 'num', text: fmtNum(totals[name].events) }), h('td', { class: 'num', text: fmtNum(totals[name].users) }));
      });
      main.appendChild(h('div', { class: 'grid split section' },
        h('div', { class: 'panel' }, h('h2', { text: 'Events' }),
          rows.length ? h('div', { class: 'table-wrap' }, h('table', null, h('thead', null, h('tr', null, h('th', { text: 'Event' }), h('th', { class: 'num', text: 'Times' }), h('th', { class: 'num', text: 'People' }))), h('tbody', null, rows)))
            : h('div', { class: 'muted', text: 'No events in this range yet.' })),
        switchesPanel(s)));
    }).catch(fail);
  }

  function kpi(label, value, sub, warn) {
    return h('div', { class: 'panel kpi' }, h('div', { class: 'soft', text: label }), h('div', { class: 'value', text: value }), h('div', { class: 'sub' + (warn ? ' warn' : ''), text: sub }));
  }

  function signedKg(x) { return x === null || x === undefined ? '—' : (x > 0 ? '+' : '') + x.toFixed(2) + ' kg'; }

  function shareChart(rows) {
    var W = 600, H = 180, pad = 22;
    var max = Math.max(1.2, Math.max.apply(null, rows.map(function (r) { return r.avgShareOfTarget || 0; })));
    var wrap = h('div');
    wrap.appendChild(h('div', { class: 'chart-max', text: '100% of target' }));
    var s = svg('svg', { viewBox: '0 0 ' + W + ' ' + H, preserveAspectRatio: 'none', role: 'img', 'aria-label': 'Average share of calorie target eaten per day' });
    var step = (W - pad) / rows.length, bw = Math.max(2, step * 0.6);
    var y100 = H - pad - (1 / max) * (H - pad * 2);
    rows.forEach(function (r, i) {
      var v = r.avgShareOfTarget || 0;
      var bh = (v / max) * (H - pad * 2);
      s.appendChild(svg('rect', { x: pad + i * step + (step - bw) / 2, y: H - pad - bh, width: bw, height: Math.max(0, bh), rx: 2, fill: v >= 0.9 ? '#047857' : '#1D4ED8', opacity: 0.9 }));
    });
    s.appendChild(svg('line', { x1: pad, y1: y100, x2: W, y2: y100, stroke: '#6B7280', 'stroke-dasharray': '4 4' }));
    wrap.appendChild(s);
    return wrap;
  }

  function dailyChart(daily, from, to) {
    var byDate = {};
    daily.forEach(function (d) { byDate[d.date] = d; });
    var days = [];
    for (var t = new Date(from.toISOString().slice(0, 10) + 'T00:00:00Z'); t <= to; t = new Date(t.getTime() + 86400000)) {
      var key = t.toISOString().slice(0, 10);
      days.push(byDate[key] || { date: key, activeUsers: 0, mealsLogged: 0 });
    }
    var W = 600, H = 180, pad = 22;
    var max = Math.max(1, Math.max.apply(null, days.map(function (d) { return Math.max(d.activeUsers, d.mealsLogged); })));
    var wrap = h('div');
    wrap.appendChild(h('div', { class: 'chart-max', text: 'Peak ' + max }));
    var s = svg('svg', { viewBox: '0 0 ' + W + ' ' + H, preserveAspectRatio: 'none', role: 'img', 'aria-label': 'Active people and meals logged per day' });
    var step = (W - pad) / days.length;
    var bw = Math.max(2, step * 0.55);
    s.appendChild(svg('line', { x1: pad, y1: H - pad, x2: W, y2: H - pad, stroke: '#E5E7EB' }));
    var pts = [];
    days.forEach(function (d, i) {
      var x = pad + i * step + (step - bw) / 2;
      var bh = (d.activeUsers / max) * (H - pad * 2);
      s.appendChild(svg('rect', { x: x, y: H - pad - bh, width: bw, height: Math.max(0, bh), rx: 2, fill: '#1D4ED8', opacity: 0.9 }));
      pts.push((x + bw / 2).toFixed(1) + ',' + (H - pad - (d.mealsLogged / max) * (H - pad * 2)).toFixed(1));
    });
    s.appendChild(svg('polyline', { points: pts.join(' '), fill: 'none', stroke: '#111827', 'stroke-width': 2, 'vector-effect': 'non-scaling-stroke' }));
    wrap.appendChild(s);
    return wrap;
  }

  function switchesPanel(s) {
    var labels = {
      inviteOnly: ['Invite-only sign-up', 'INVITE_ONLY'],
      nearbySampleVenues: ['Made-up places in Order nearby', 'NEARBY_SAMPLE_VENUES'],
      subscriptionGate: ['Subscription required', 'SUBSCRIPTION_GATE'],
      devLogin: ['Developer sign-in', 'ENABLE_DEV_LOGIN'],
      wearableModifier: ['Wearable modifier', 'WEARABLE_MODIFIER_ENABLED'],
      aiConfigured: ['AI configured', 'ANTHROPIC_API_KEY'],
    };
    var p = h('div', { class: 'panel' }, h('h2', { text: 'Switches' }), h('p', { class: 'muted', style: 'margin: 0 0 8px', text: 'Set in Vercel, then redeploy' }));
    Object.keys(labels).forEach(function (k) {
      var on = s.switches[k];
      var warn = (k === 'devLogin' || k === 'nearbySampleVenues') && on && s.environment === 'production';
      p.appendChild(h('div', { class: 'switch-row' },
        h('div', null, h('div', { text: labels[k][0] }), h('div', { class: 'mono muted', text: labels[k][1] })),
        h('span', { class: 'badge ' + (warn ? 'bad' : on ? 'good' : ''), text: on ? (warn ? 'On · turn off' : 'On') : 'Off' })));
    });
    return p;
  }

  function renderUsers() {
    var f = state.userFilter;
    var qs = [];
    if (f.q) qs.push('q=' + encodeURIComponent(f.q));
    if (f.role) qs.push('role=' + f.role);
    if (f.cohort) qs.push('cohort=' + encodeURIComponent(f.cohort));
    if (f.pending) qs.push('pending=true');
    loading();
    Promise.all([api('/users' + (qs.length ? '?' + qs.join('&') : '')), state.status ? Promise.resolve(state.status) : refreshStatus()]).then(function (r) {
      var users = r[0].users, s = r[1];
      clear(main);
      pageHead('Users', users.length + (users.length === 500 ? '+' : '') + ' people');
      var search = h('input', { type: 'search', placeholder: 'Search email', value: f.q, 'aria-label': 'Search email' });
      var timer;
      search.addEventListener('input', function () { clearTimeout(timer); timer = setTimeout(function () { f.q = search.value.trim(); renderUsers(); }, 350); });
      main.appendChild(h('div', { class: 'toolbar' },
        search,
        h('select', { 'aria-label': 'Role', onchange: function (e) { f.role = e.target.value; renderUsers(); } },
          h('option', { value: '', text: 'Any role' }),
          ['USER', 'TRAINER', 'ADMIN'].map(function (x) { return h('option', { value: x, selected: f.role === x ? true : null, text: x.charAt(0) + x.slice(1).toLowerCase() }); })),
        h('select', { 'aria-label': 'Cohort', onchange: function (e) { f.cohort = e.target.value; renderUsers(); } },
          h('option', { value: '', text: 'Any cohort' }),
          s.cohorts.map(function (c) { return h('option', { value: c.cohort, selected: f.cohort === c.cohort ? true : null, text: c.cohort }); })),
        h('label', { class: 'soft', style: 'display:flex;align-items:center;gap:6px' }, h('input', { type: 'checkbox', checked: f.pending, onchange: function (e) { f.pending = e.target.checked; renderUsers(); } }), 'Waiting for an invite')));

      if (!users.length) { main.appendChild(h('div', { class: 'empty', text: 'Nobody matches. Clear the search or filters.' })); return; }
      var body = h('tbody');
      users.forEach(function (u) { body.appendChild(userRow(u)); });
      main.appendChild(h('div', { class: 'panel table-wrap', style: 'padding: 6px 8px' }, h('table', null,
        h('thead', null, h('tr', null, h('th', { text: 'Email' }), h('th', { text: 'Role' }), h('th', { text: 'Cohort' }), h('th', { text: 'Access' }), h('th', { text: 'Setup' }), h('th', { class: 'num', text: 'Meals' }), h('th', { text: 'Invite' }), h('th', { text: 'Joined' }))),
        body)));
    }).catch(fail);
  }

  function userRow(u) {
    function save(patch, done) {
      api('/users/' + encodeURIComponent(u.id), { method: 'PATCH', body: patch }).then(function (res) {
        Object.assign(u, res.user); toast('Saved.'); if (done) done(); state.status = null;
      }).catch(fail);
    }
    var role = h('select', { 'aria-label': 'Role', onchange: function (e) { save({ role: e.target.value }); } },
      ['USER', 'TRAINER', 'ADMIN'].map(function (x) { return h('option', { value: x, selected: u.role === x ? true : null, text: x.charAt(0) + x.slice(1).toLowerCase() }); }));
    var cohort = h('input', { type: 'text', value: u.cohort || '', placeholder: '—', style: 'width: 130px', 'aria-label': 'Cohort' });
    cohort.addEventListener('change', function () { save({ cohort: cohort.value.trim() || null }); });
    var access = h('td');
    function drawAccess() {
      clear(access);
      if (u.accessGrantedAt) access.appendChild(h('span', { class: 'mono soft', text: fmtDate(u.accessGrantedAt) }));
      else access.appendChild(h('div', { style: 'display:flex;align-items:center;gap:8px' }, h('span', { class: 'badge lit', text: 'Waiting' }),
        h('button', { class: 'btn small', text: 'Let in', onclick: function () { save({ access: true }, drawAccess); } })));
    }
    drawAccess();
    return h('tr', null,
      h('td', null, h('button', { class: 'linkish', text: u.email || '(no email)', onclick: function () { go('users', u.id); } }), h('div', { class: 'mono muted', style: 'font-size: 11px', text: u.id })),
      h('td', null, role),
      h('td', null, cohort),
      access,
      h('td', null, u.onboarding && u.onboarding.completedAt ? h('span', { class: 'muted', text: 'Done' }) : h('span', { class: 'badge lit', text: 'Not yet' })),
      h('td', { class: 'num', text: fmtNum(u._count ? u._count.meals : 0) }),
      h('td', { class: 'mono soft', text: u.inviteCode ? u.inviteCode.code : '—' }),
      h('td', { class: 'mono soft', text: fmtDate(u.createdAt) }));
  }

  var SOURCES = [['', 'Any way'], ['TEXT', 'Typed'], ['MANUAL', 'Typed'], ['PHOTO', 'Photo'], ['SAVED', 'Usual'], ['BARCODE', 'Barcode'], ['CATALOG', 'Foods'], ['PRESCRIPTION', 'Check-in plate']];
  function sourceLabel(src) { for (var i = 0; i < SOURCES.length; i++) if (SOURCES[i][0] === src) return SOURCES[i][1]; return src; }

  function lightbox(url) {
    var box = h('div', { class: 'lightbox', role: 'dialog', 'aria-label': 'Meal photo', onclick: function () { box.remove(); } }, h('img', { src: url, alt: 'Meal photo' }));
    document.body.appendChild(box);
  }

  function mealCard(m, showUser) {
    var when = new Date(m.loggedAt);
    var items = (m.items || []).map(function (it) { return it.name + (it.quantity ? ' (' + it.quantity + ')' : '') + ' · ' + it.kcal; }).join(' / ');
    return h('div', { class: 'panel meal' },
      m.photoUrl ? h('img', { src: m.photoUrl, alt: m.summary || 'Meal photo', loading: 'lazy', onclick: function () { lightbox(m.photoUrl); } }) : null,
      h('div', { style: 'display:flex;align-items:center;gap:6px;flex-wrap:wrap' },
        h('span', { class: 'badge', text: sourceLabel(m.source) }),
        m.fixed ? h('span', { class: 'badge haze', text: 'Fixed' }) : null,
        m.parseConfidence !== null && m.parseConfidence < 0.45 ? h('span', { class: 'badge lit', text: 'Rough estimate' }) : null,
        h('span', { class: 'spacer' }),
        h('span', { class: 'mono muted', text: when.toLocaleDateString('en-GB', { day: 'numeric', month: 'short' }) + ' ' + when.toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit' }) })),
      h('div', { class: 'title', text: m.summary || '(no description)' }),
      items ? h('div', { class: 'items', text: items }) : null,
      h('div', { class: 'macros' }, h('span', null, h('b', { text: fmtNum(m.kcal) }), ' kcal'), h('span', null, h('b', { text: Math.round(m.proteinG) }), ' g protein'), h('span', { text: Math.round(m.carbsG) + ' g carbs' }), h('span', { text: Math.round(m.fatG) + ' g fat' })),
      m.notes ? h('div', { class: 'items', text: m.notes }) : null,
      showUser && m.user ? h('button', { class: 'linkish', style: 'font-size: 13px', text: (m.user.email || m.user.id) + (m.user.cohort ? ' · ' + m.user.cohort : ''), onclick: function () { go('users', m.user.id); } }) : null);
  }

  function renderMeals() {
    var f = state.mealFilter;
    loading();
    Promise.all([state.status ? Promise.resolve(state.status) : refreshStatus()]).then(function (r) {
      var s = r[0];
      clear(main);
      pageHead('Meals');
      main.appendChild(h('div', { class: 'toolbar' },
        h('select', { 'aria-label': 'Cohort', onchange: function (e) { f.cohort = e.target.value; renderMeals(); } },
          h('option', { value: '', text: 'Everyone' }),
          s.cohorts.map(function (c) { return h('option', { value: c.cohort, selected: f.cohort === c.cohort ? true : null, text: c.cohort }); })),
        h('select', { 'aria-label': 'How it was logged', onchange: function (e) { f.source = e.target.value; renderMeals(); } },
          SOURCES.map(function (x) { return h('option', { value: x[0], selected: f.source === x[0] ? true : null, text: x[1] }); }))));
      var grid = h('div', { class: 'meals' });
      var more = h('div', { style: 'margin-top: 16px; text-align: center' });
      main.appendChild(grid);
      main.appendChild(more);
      function load(before) {
        var qs = ['limit=60'];
        if (f.cohort) qs.push('cohort=' + encodeURIComponent(f.cohort));
        if (f.source) qs.push('source=' + f.source);
        if (before) qs.push('before=' + encodeURIComponent(before));
        clear(more);
        more.appendChild(h('span', { class: 'muted', text: 'Loading…' }));
        api('/meals?' + qs.join('&')).then(function (res) {
          res.meals.forEach(function (m) { grid.appendChild(mealCard(m, true)); });
          clear(more);
          if (!grid.children.length) more.appendChild(h('div', { class: 'empty', text: 'No meals logged yet. They show up here as people log them in the app.' }));
          else if (res.nextBefore) more.appendChild(h('button', { class: 'btn', text: 'Load more', onclick: function () { load(res.nextBefore); } }));
        }).catch(fail);
      }
      load(null);
    }).catch(fail);
  }

  function renderPerson(id) {
    loading();
    api('/users/' + encodeURIComponent(id) + '/profile').then(function (p) {
      clear(main);
      var u = p.user, o = u.onboarding;
      main.appendChild(h('div', { class: 'toolbar' },
        h('button', { class: 'btn small', text: 'Back to users', onclick: function () { go('users'); } }),
        h('h1', { style: 'font-size: 24px; font-weight: 650; letter-spacing: -0.03em; margin: 0', text: u.email || u.id }),
        h('span', { class: 'badge', text: u.role.toLowerCase() }),
        u.cohort ? h('span', { class: 'badge haze', text: u.cohort }) : null,
        u.accessGrantedAt ? null : h('span', { class: 'badge lit', text: 'Waiting for an invite' })));

      var weightNow = p.weights.length ? p.weights[p.weights.length - 1].weightKg : (o ? o.weightKg : null);
      var plan = h('div', { class: 'panel' }, h('h2', { text: 'Plan' }),
        o ? h('dl', { class: 'kv' },
          h('dt', { text: 'Goal' }), h('dd', { text: o.goal.charAt(0) + o.goal.slice(1).toLowerCase() + (o.paceKgPerWeek ? ' · ' + o.paceKgPerWeek + ' kg/wk' : '') }),
          h('dt', { text: 'Calories' }), h('dd', { text: fmtNum(o.dailyKcalTarget) + ' kcal a day' }),
          h('dt', { text: 'Protein' }), h('dd', { text: o.dailyProteinTargetG ? o.dailyProteinTargetG + ' g a day' : '—' }),
          h('dt', { text: 'Weight' }), h('dd', { text: (o.startWeightKg || '—') + ' → ' + (weightNow || '—') + ' kg' + (o.targetWeightKg ? ' · target ' + o.targetWeightKg : '') }),
          h('dt', { text: 'Appetite' }), h('dd', { text: (o.appetiteMode || '').toLowerCase() }),
          h('dt', { text: 'Setup' }), h('dd', { text: o.completedAt ? 'Done ' + fmtDate(o.completedAt) : 'Not finished' }))
          : h('div', { class: 'muted', text: 'Hasn’t finished setup.' }),
        h('dl', { class: 'kv', style: 'margin-top: 12px' },
          h('dt', { text: 'Joined' }), h('dd', { text: fmtDate(u.createdAt) + (u.inviteCode ? ' · code ' + u.inviteCode.code : '') }),
          h('dt', { text: 'Last active' }), h('dd', { text: p.lastActive ? new Date(p.lastActive.at).toLocaleString('en-GB') + ' · ' + p.lastActive.event : '—' }),
          h('dt', { text: 'Meals logged' }), h('dd', { text: fmtNum(p.mealCount) }),
          h('dt', { text: 'Time zone' }), h('dd', { text: u.timezone })));

      var days = h('div', { class: 'panel chart' }, h('h2', { text: 'Last 14 days' }), personChart(p.days),
        h('div', { class: 'legend' },
          h('span', null, h('span', { class: 'dot', style: 'background: var(--accent)' }), 'Eaten'),
          h('span', null, h('span', { class: 'dot', style: 'background: #6B7280' }), 'Target'),
          h('span', null, h('span', { class: 'dot', style: 'background: #111827' }), 'Protein vs target')));
      main.appendChild(h('div', { class: 'grid split' }, plan, days));

      var dayRows = p.days.slice().reverse().map(function (d) {
        return h('tr', null,
          h('td', { class: 'mono', text: d.date }),
          h('td', { class: 'num', text: fmtNum(d.kcal) + (d.targetKcal ? ' / ' + fmtNum(d.targetKcal) : '') }),
          h('td', { class: 'num', text: d.proteinG + (d.targetProteinG ? ' / ' + d.targetProteinG + ' g' : ' g') }),
          h('td', { class: 'num', text: String(d.meals) }),
          h('td', null, d.kind ? h('span', { class: 'badge ' + ({ ON_TRACK: 'good', OVER: 'good', UNDER: 'lit', MISSED: 'bad' }[d.kind] || ''), text: d.kind.replace('_', ' ').toLowerCase() }) : null));
      });
      var weightPanel = h('div', { class: 'panel chart' }, h('h2', { text: 'Weight · last 6 months' }),
        p.weights.length >= 2 ? weightChart(p.weights) : h('div', { class: 'muted', text: p.weights.length ? 'One weigh-in: ' + p.weights[0].weightKg + ' kg on ' + fmtDate(p.weights[0].measuredAt) : 'No weigh-ins.' }));
      main.appendChild(h('div', { class: 'grid split section' },
        h('div', { class: 'panel table-wrap' }, h('table', null,
          h('thead', null, h('tr', null, h('th', { text: 'Day' }), h('th', { class: 'num', text: 'Calories' }), h('th', { class: 'num', text: 'Protein' }), h('th', { class: 'num', text: 'Meals' }), h('th', { text: 'Result' }))),
          h('tbody', null, dayRows))),
        weightPanel));

      var checkRows = p.checkIns.map(function (c) {
        return h('tr', null,
          h('td', { class: 'mono', text: new Date(c.createdAt).toLocaleString('en-GB', { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' }) }),
          h('td', { class: 'soft', text: c.kind.toLowerCase() + (c.slot ? ' · ' + c.slot : '') + (c.tier > 1 ? ' · tier ' + c.tier : '') }),
          h('td', null, h('span', { class: 'badge', text: c.status.toLowerCase() })),
          h('td', { class: 'soft', text: c.feedbackPositive === true ? 'Yes' : c.feedbackPositive === false ? 'No' : '' }));
      });
      main.appendChild(h('div', { class: 'panel table-wrap section' }, h('h2', { text: 'Check-ins · last 14 days' }),
        checkRows.length ? h('table', null, h('thead', null, h('tr', null, h('th', { text: 'When' }), h('th', { text: 'Kind' }), h('th', { text: 'Status' }), h('th', { text: 'Feedback' }))), h('tbody', null, checkRows))
          : h('div', { class: 'muted', text: 'No check-ins.' })));

      main.appendChild(h('div', { class: 'section' }, h('h2', { text: 'Meals' + (p.mealCount > p.meals.length ? ' · latest ' + p.meals.length + ' of ' + fmtNum(p.mealCount) : '') })));
      main.appendChild(p.meals.length ? h('div', { class: 'meals' }, p.meals.map(function (m) { return mealCard(m, false); })) : h('div', { class: 'empty', text: 'No meals yet.' }));
    }).catch(fail);
  }

  function personChart(days) {
    var W = 600, H = 180, pad = 22;
    var max = Math.max(1, Math.max.apply(null, days.map(function (d) { return Math.max(d.kcal, d.targetKcal || 0); })));
    var wrap = h('div');
    wrap.appendChild(h('div', { class: 'chart-max', text: fmtNum(max) + ' kcal' }));
    var s = svg('svg', { viewBox: '0 0 ' + W + ' ' + H, preserveAspectRatio: 'none', role: 'img', 'aria-label': 'Calories eaten against target per day' });
    var step = (W - pad) / days.length, bw = Math.max(3, step * 0.55);
    var pts = [];
    days.forEach(function (d, i) {
      var x = pad + i * step + (step - bw) / 2;
      var bh = (d.kcal / max) * (H - pad * 2);
      s.appendChild(svg('rect', { x: x, y: H - pad - bh, width: bw, height: Math.max(0, bh), rx: 2, fill: d.targetKcal && d.kcal >= 0.9 * d.targetKcal ? '#047857' : '#1D4ED8', opacity: d.kind === 'TODAY' ? 0.5 : 0.9 }));
      if (d.targetKcal) {
        var ty = H - pad - (d.targetKcal / max) * (H - pad * 2);
        s.appendChild(svg('line', { x1: x - 2, y1: ty, x2: x + bw + 2, y2: ty, stroke: '#6B7280', 'stroke-width': 2 }));
      }
      if (d.targetProteinG) pts.push((x + bw / 2).toFixed(1) + ',' + (H - pad - Math.min(1.5, d.proteinG / d.targetProteinG) / 1.5 * (H - pad * 2)).toFixed(1));
    });
    if (pts.length > 1) s.appendChild(svg('polyline', { points: pts.join(' '), fill: 'none', stroke: '#111827', 'stroke-width': 2, 'vector-effect': 'non-scaling-stroke' }));
    wrap.appendChild(s);
    return wrap;
  }

  function weightChart(rows) {
    var W = 600, H = 180, pad = 26;
    var ws = rows.map(function (r) { return r.weightKg; });
    var lo = Math.min.apply(null, ws) - 0.5, hi = Math.max.apply(null, ws) + 0.5;
    var t0 = new Date(rows[0].measuredAt).getTime(), t1 = new Date(rows[rows.length - 1].measuredAt).getTime();
    var span = Math.max(1, t1 - t0);
    var wrap = h('div');
    wrap.appendChild(h('div', { class: 'chart-max', text: (hi - 0.5).toFixed(1) + ' – ' + (lo + 0.5).toFixed(1) + ' kg' }));
    var s = svg('svg', { viewBox: '0 0 ' + W + ' ' + H, preserveAspectRatio: 'none', role: 'img', 'aria-label': 'Weight over time' });
    var pts = rows.map(function (r) {
      var x = pad + ((new Date(r.measuredAt).getTime() - t0) / span) * (W - pad * 2);
      var y = H - pad - ((r.weightKg - lo) / (hi - lo)) * (H - pad * 2);
      return x.toFixed(1) + ',' + y.toFixed(1);
    });
    s.appendChild(svg('polyline', { points: pts.join(' '), fill: 'none', stroke: '#1D4ED8', 'stroke-width': 2, 'vector-effect': 'non-scaling-stroke' }));
    wrap.appendChild(s);
    return wrap;
  }

  function inviteState(inv) {
    if (inv.disabledAt) return ['Disabled', 'bad'];
    if (inv.expiresAt && new Date(inv.expiresAt) <= new Date()) return ['Expired', 'bad'];
    if (inv.maxUses !== null && inv.uses >= inv.maxUses) return ['Used up', ''];
    return ['Active', 'good'];
  }

  function copy(text) {
    if (navigator.clipboard) navigator.clipboard.writeText(text).then(function () { toast('Copied ' + text); }, function () { toast(text); });
    else toast(text);
  }

  function renderInvites() {
    loading();
    api('/invites').then(function (r) {
      clear(main);
      pageHead('Invites', state.status && !state.status.switches.inviteOnly
        ? 'Invite-only is off, so new accounts get in without a code. A code still puts people in its cohort.'
        : 'Invite-only is on: new accounts need one of these codes.');
      var code = h('input', { type: 'text', placeholder: 'Random if empty', 'aria-label': 'Code' });
      var cohort = h('input', { type: 'text', placeholder: 'e.g. dvir-pilot', 'aria-label': 'Cohort' });
      var role = h('select', { 'aria-label': 'Role' }, ['USER', 'TRAINER', 'ADMIN'].map(function (x) { return h('option', { value: x, text: x.charAt(0) + x.slice(1).toLowerCase() }); }));
      var maxUses = h('input', { type: 'number', min: 1, placeholder: 'Unlimited', 'aria-label': 'Max uses' });
      var expires = h('input', { type: 'date', 'aria-label': 'Expires' });
      var note = h('input', { type: 'text', placeholder: 'Who it’s for', 'aria-label': 'Note' });
      var created = h('div');
      var createBtn = h('button', { class: 'btn primary', type: 'submit', text: 'Create code' });
      var form = h('form', { class: 'panel', onsubmit: function (e) {
        e.preventDefault();
        var body = {};
        if (code.value.trim()) body.code = code.value.trim();
        if (cohort.value.trim()) body.cohort = cohort.value.trim();
        body.role = role.value;
        if (maxUses.value) body.maxUses = Number(maxUses.value);
        if (expires.value) body.expiresAt = new Date(expires.value + 'T23:59:59').toISOString();
        if (note.value.trim()) body.note = note.value.trim();
        createBtn.disabled = true;
        createBtn.classList.add('busy');
        api('/invites', { method: 'POST', body: body }).then(function (res) {
          renderInvites();
          setTimeout(function () {
            var box = document.getElementById('created');
            if (box) { clear(box); box.appendChild(h('div', { class: 'created' }, h('span', { class: 'code', text: res.invite.code }), h('span', { class: 'soft', text: res.invite.cohort ? 'cohort ' + res.invite.cohort : 'no cohort' }), h('span', { class: 'spacer' }), h('button', { class: 'btn small', type: 'button', text: 'Copy', onclick: function () { copy(res.invite.code); } }))); }
          }, 0);
        }).catch(function (err) { createBtn.disabled = false; createBtn.classList.remove('busy'); fail(err); });
      } },
        h('h2', { text: 'New invite code' }),
        h('div', { class: 'form-grid' },
          field('Code', code), field('Cohort', cohort), field('Role', role), field('Max uses', maxUses), field('Expires', expires), field('Note', note)),
        h('div', { class: 'form-actions' }, createBtn),
        h('div', { id: 'created' }, created));
      main.appendChild(form);

      var invites = r.invites;
      if (!invites.length) { main.appendChild(h('div', { class: 'empty section', text: 'No codes yet. Create one above.' })); return; }
      var body = h('tbody');
      invites.forEach(function (inv) {
        var st = inviteState(inv);
        body.appendChild(h('tr', null,
          h('td', null, h('button', { class: 'btn small mono', title: 'Copy', text: inv.code, onclick: function () { copy(inv.code); } })),
          h('td', { class: 'soft', text: inv.cohort || '—' }),
          h('td', { class: 'soft', text: inv.role.charAt(0) + inv.role.slice(1).toLowerCase() }),
          h('td', { class: 'num', text: inv.uses + (inv.maxUses !== null ? ' / ' + inv.maxUses : '') }),
          h('td', { class: 'mono soft', text: inv.expiresAt ? fmtDate(inv.expiresAt) : 'Never' }),
          h('td', null, h('span', { class: 'badge ' + st[1], text: st[0] })),
          h('td', { class: 'soft', text: inv.note || '' }),
          h('td', { class: 'mono soft', text: fmtDate(inv.createdAt) }),
          h('td', null, inv.disabledAt ? null : h('button', { class: 'btn small danger isolate', text: 'Disable', onclick: function () {
            if (!confirm('Disable ' + inv.code + '? Nobody new can use it.')) return;
            api('/invites/' + encodeURIComponent(inv.code) + '/disable', { method: 'POST', body: {} }).then(function () { toast('Disabled ' + inv.code); renderInvites(); }).catch(fail);
          } }))));
      });
      main.appendChild(h('div', { class: 'panel table-wrap section', style: 'padding: 6px 8px' }, h('table', null,
        h('thead', null, h('tr', null, ['Code', 'Cohort', 'Role', 'Used', 'Expires', 'Status', 'Note', 'Created', ''].map(function (t) { return h('th', { text: t }); }))),
        body)));
    }).catch(fail);
  }

  function field(label, control) { return h('label', { class: 'field' }, h('span', { text: label }), control); }

  function renderFlags() {
    loading();
    Promise.all([api('/flags'), state.status ? Promise.resolve(state.status) : refreshStatus()]).then(function (r) {
      clear(main);
      pageHead('Flags', 'Each feature has a default in code. An override turns it on for everyone, off for everyone, or on only for some cohorts, roles or people. The app picks changes up on its next launch.');
      var wrap = h('div', { class: 'grid' });
      r[0].flags.forEach(function (f) { wrap.appendChild(flagCard(f, r[1])); });
      main.appendChild(wrap);
    }).catch(fail);
  }

  function flagCard(f, status) {
    var o = f.override;
    var mode = !o ? 'default' : o.enabled ? 'on' : (o.cohorts.length || o.roles.length || o.userIds.length) ? 'some' : 'off';
    var card = h('div', { class: 'panel flag' });
    var cohorts = h('input', { type: 'text', value: o ? o.cohorts.join(', ') : '', placeholder: 'dvir-pilot, beta', 'aria-label': 'Cohorts' });
    var roles = ['USER', 'TRAINER', 'ADMIN'].map(function (x) {
      return h('label', { class: 'soft', style: 'display:flex;align-items:center;gap:6px' }, h('input', { type: 'checkbox', value: x, checked: o && o.roles.indexOf(x) >= 0 }), x.charAt(0) + x.slice(1).toLowerCase());
    });
    var userIds = h('textarea', { placeholder: 'User ids, one per line', 'aria-label': 'User ids' });
    userIds.value = o ? o.userIds.join('\n') : '';
    var some = h('div', { class: 'grid', style: 'gap: 12px' },
      field('Cohorts', cohorts),
      h('div', { class: 'field' }, h('span', { text: 'Roles' }), h('div', { style: 'display:flex;gap:14px;flex-wrap:wrap' }, roles)),
      field('People', userIds),
      status.cohorts.length ? h('div', { class: 'muted', style: 'font-size: 13px', text: 'Cohorts in use: ' + status.cohorts.map(function (c) { return c.cohort; }).join(', ') }) : null);

    var modes = h('div', { class: 'modes', role: 'radiogroup', 'aria-label': 'State' });
    var choices = [['default', 'Default (' + (f.default ? 'on' : 'off') + ')'], ['on', 'On for everyone'], ['off', 'Off for everyone'], ['some', 'Only for…']];
    function drawModes() {
      clear(modes);
      choices.forEach(function (c) {
        modes.appendChild(h('label', { class: mode === c[0] ? 'on' : '' },
          h('input', { type: 'radio', name: 'mode-' + f.key, value: c[0], checked: mode === c[0], onchange: function () { mode = c[0]; drawModes(); } }), c[1]));
      });
      some.style.display = mode === 'some' ? '' : 'none';
    }
    drawModes();

    var saveBtn = h('button', { class: 'btn primary', text: 'Save', onclick: function () {
      saveBtn.disabled = true;
      saveBtn.classList.add('busy');
      var req;
      if (mode === 'default') req = api('/flags/' + f.key, { method: 'DELETE' });
      else {
        var body = { enabled: mode === 'on', cohorts: [], roles: [], userIds: [] };
        if (mode === 'some') {
          body.cohorts = cohorts.value.split(',').map(function (x) { return x.trim(); }).filter(Boolean);
          body.roles = roles.map(function (l) { return l.querySelector('input'); }).filter(function (i) { return i.checked; }).map(function (i) { return i.value; });
          body.userIds = userIds.value.split(/[\s,]+/).map(function (x) { return x.trim(); }).filter(Boolean);
          if (!body.cohorts.length && !body.roles.length && !body.userIds.length) { saveBtn.disabled = false; saveBtn.classList.remove('busy'); toast('Pick at least one cohort, role or person.', true); return; }
        }
        req = api('/flags/' + f.key, { method: 'PUT', body: body });
      }
      req.then(function () { toast('Saved ' + f.key + '.'); renderFlags(); }).catch(function (err) { saveBtn.disabled = false; saveBtn.classList.remove('busy'); fail(err); });
    } });

    var summary = !o ? 'Default · ' + (f.default ? 'on' : 'off') + ' for everyone'
      : o.enabled ? 'On for everyone'
      : mode === 'off' ? 'Off for everyone'
      : 'On for ' + [o.cohorts.length ? o.cohorts.join(', ') : null, o.roles.length ? o.roles.map(function (x) { return x.toLowerCase() + 's'; }).join(', ') : null, o.userIds.length ? o.userIds.length + ' people' : null].filter(Boolean).join(' · ');
    append(card, [
      h('div', { class: 'flag-head' }, h('span', { class: 'flag-key', text: f.key }), h('span', { class: 'badge ' + (o ? 'haze' : ''), text: summary })),
      h('div', { class: 'soft', text: f.description }),
      modes, some,
      h('div', { style: 'display:flex;align-items:center;gap:10px' }, saveBtn, o && o.updatedAt ? h('span', { class: 'muted', text: 'Changed ' + fmtDate(o.updatedAt) }) : null),
    ]);
    return card;
  }

  function renderHealth() {
    loading();
    api('/metrics').then(function (m) {
      clear(main);
      pageHead('Health');
      var sch = m.scheduler || {};
      var alerts = (m.stopConditions && m.stopConditions.evaluation && m.stopConditions.evaluation.alerts) || [];
      var schLabel = sch.stale ? 'Stale' : sch.lastOk === false ? 'Failing' : 'Running';
      main.appendChild(h('div', { class: 'grid kpis kpis-3' },
        kpi('Check-in scheduler', schLabel, sch.lastRunAt ? 'last run ' + new Date(sch.lastRunAt).toLocaleString('en-GB') : 'never ran', sch.stale || sch.lastOk === false),
        kpi('Alerts', String(alerts.length), alerts.length ? alerts.join(', ') : 'none', alerts.length),
        kpi('Wearable modifier', m.wearableModifier && m.wearableModifier.killSwitch ? 'On' : 'Off', m.wearableModifier && m.wearableModifier.haltedByStopConditions ? 'halted by stop conditions' : (m.wearableModifier ? m.wearableModifier.cohortPercent + '% cohort' : ''))));
      var copyM = Object.assign({}, m);
      main.appendChild(h('div', { class: 'panel section' }, h('details', null, h('summary', { text: 'All beta metrics (last 21 days)' }), h('pre', { style: 'margin-top: 12px', text: JSON.stringify(copyM, null, 2) }))));
    }).catch(fail);
  }

  if (state.secret) {
    root.appendChild(h('div', { class: 'empty', style: 'margin-top: 20vh', text: 'Signing in…' }));
    api('/status').then(function (s) { state.status = s; renderShell(); }).catch(function (e) { if (e.message !== 'unauthorized') signOut(e.message); });
  } else {
    renderLogin();
  }
})();
</script>
</body>
</html>
`;
