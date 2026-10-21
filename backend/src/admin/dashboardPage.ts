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
<link href="https://fonts.googleapis.com/css2?family=Geist:wght@300;400;500;600&family=Geist+Mono:wght@400;500&display=swap" rel="stylesheet">
<style>
:root {
  --bg: #09090B; --panel: rgba(255,255,255,0.045); --panel-hi: rgba(255,255,255,0.08);
  --line: rgba(255,255,255,0.09); --line-hi: rgba(255,255,255,0.16);
  --ink: #F5F5F4; --soft: #A1A1AA; --faint: #8B8B94;
  --ember: #FF7A3D; --amber: #FFB86B; --haze: #818CF8; --haze-soft: #C7D2FE;
  --good: #86EFAC; --bad: #F87171;
  --mono: 'Geist Mono', ui-monospace, monospace;
}
* { box-sizing: border-box; }
html, body { margin: 0; background: var(--bg); color: var(--ink); font: 14px/1.45 'Geist', ui-sans-serif, system-ui, sans-serif; }
body { min-height: 100vh; }
.glow { position: fixed; left: -10%; top: -220px; width: 70%; height: 520px; pointer-events: none;
  background: radial-gradient(closest-side, rgba(255,122,61,0.18), rgba(255,122,61,0)); filter: blur(30px); }
button, input, select, textarea { font: inherit; color: inherit; }
a { color: var(--amber); }
.wrap { position: relative; max-width: 1180px; margin: 0 auto; padding: 24px 16px 64px; }
header { display: flex; align-items: center; gap: 16px; margin-bottom: 20px; }
.brand { font-size: 18px; font-weight: 500; letter-spacing: -0.02em; }
.label { font-family: var(--mono); font-size: 11px; letter-spacing: 0.12em; text-transform: uppercase; color: var(--faint); }
.badge { white-space: nowrap; font-family: var(--mono); font-size: 10px; letter-spacing: 0.1em; text-transform: uppercase; padding: 4px 9px; border-radius: 999px; border: 1px solid var(--line-hi); color: var(--soft); }
.badge.good { color: var(--good); border-color: rgba(134,239,172,0.4); }
.badge.bad { color: var(--bad); border-color: rgba(248,113,113,0.45); }
.badge.lit { color: var(--amber); border-color: rgba(255,138,80,0.5); }
.badge.haze { color: var(--haze-soft); border-color: rgba(129,140,248,0.5); }
.spacer { flex: 1; }
nav { display: flex; gap: 6px; flex-wrap: wrap; margin-bottom: 20px; }
nav button { height: 36px; padding: 0 16px; border-radius: 999px; border: 1px solid var(--line); background: var(--panel); color: var(--soft); cursor: pointer; }
nav button[aria-current="page"] { background: var(--ink); color: var(--bg); border-color: var(--ink); font-weight: 500; }
.panel { background: var(--panel); border: 1px solid var(--line); border-radius: 20px; padding: 18px; }
.grid { display: grid; gap: 12px; }
.kpis { grid-template-columns: repeat(auto-fit, minmax(170px, 1fr)); }
.kpi .value { font-size: 32px; font-weight: 300; letter-spacing: -0.03em; margin-top: 6px; }
.kpi .sub { color: var(--faint); font-size: 12px; }
.row { display: flex; align-items: center; gap: 10px; flex-wrap: wrap; }
.section { margin-top: 20px; }
.section h2 { font-size: 15px; font-weight: 500; margin: 0 0 10px; }
.btn { height: 36px; padding: 0 16px; border-radius: 999px; border: 1px solid var(--line-hi); background: var(--panel-hi); cursor: pointer; white-space: nowrap; }
.btn:hover { border-color: rgba(255,255,255,0.3); }
.btn.primary { background: var(--ink); color: var(--bg); border-color: var(--ink); font-weight: 500; }
.btn.danger { color: var(--bad); border-color: rgba(248,113,113,0.4); background: transparent; }
.btn.small { height: 30px; padding: 0 12px; font-size: 13px; }
.btn:disabled { opacity: 0.45; cursor: default; }
input[type=text], input[type=password], input[type=number], input[type=date], input[type=search], select, textarea {
  height: 36px; padding: 0 12px; border-radius: 12px; border: 1px solid var(--line); background: rgba(255,255,255,0.05); outline: none; }
textarea { height: auto; min-height: 64px; padding: 10px 12px; font-family: var(--mono); font-size: 12px; resize: vertical; }
input:focus, select:focus, textarea:focus { border-color: var(--line-hi); }
select option { background: #18181B; }
table { width: 100%; border-collapse: collapse; }
th { text-align: left; font-family: var(--mono); font-size: 10px; letter-spacing: 0.1em; text-transform: uppercase; color: var(--faint); font-weight: 400; padding: 8px 10px; border-bottom: 1px solid var(--line); white-space: nowrap; }
td { padding: 10px; border-bottom: 1px solid rgba(255,255,255,0.05); vertical-align: middle; }
td.mono { white-space: nowrap; }
input[type=checkbox], input[type=radio] { accent-color: var(--ember); }
tr:last-child td { border-bottom: none; }
.table-wrap { overflow-x: auto; }
.mono { font-family: var(--mono); font-size: 12px; }
.muted { color: var(--faint); }
.soft { color: var(--soft); }
.empty { padding: 28px; text-align: center; color: var(--faint); border: 1px dashed var(--line-hi); border-radius: 16px; }
.funnel-row { display: grid; grid-template-columns: 160px 1fr 70px; align-items: center; gap: 12px; padding: 6px 0; }
.bar { height: 10px; border-radius: 5px; background: rgba(255,255,255,0.07); overflow: hidden; }
.bar > span { display: block; height: 100%; border-radius: 5px; background: linear-gradient(90deg, var(--ember), var(--amber)); }
.chart svg { width: 100%; height: 180px; display: block; }
.legend { display: flex; gap: 16px; margin-top: 8px; color: var(--soft); font-size: 12px; }
.dot { display: inline-block; width: 8px; height: 8px; border-radius: 50%; margin-right: 6px; vertical-align: middle; }
.switch-row { display: flex; align-items: center; justify-content: space-between; gap: 10px; padding: 9px 0; border-bottom: 1px solid rgba(255,255,255,0.05); }
.switch-row:last-child { border-bottom: none; }
.flag { display: grid; gap: 14px; }
.flag-head { display: flex; align-items: baseline; gap: 10px; flex-wrap: wrap; }
.flag-key { font-family: var(--mono); font-size: 14px; }
.modes { display: flex; gap: 6px; flex-wrap: wrap; }
.modes label { display: flex; align-items: center; gap: 6px; height: 32px; padding: 0 12px; border-radius: 999px; border: 1px solid var(--line); cursor: pointer; color: var(--soft); }
.modes input { accent-color: var(--ember); }
.modes label.on { border-color: var(--ink); color: var(--ink); }
.field { display: grid; gap: 6px; }
.field > span { font-size: 12px; color: var(--soft); }
.form-grid { display: grid; gap: 12px; grid-template-columns: repeat(auto-fit, minmax(170px, 1fr)); align-items: end; }
.login { max-width: 400px; margin: 12vh auto 0; display: grid; gap: 16px; }
.login h1 { font-size: 34px; font-weight: 300; letter-spacing: -0.035em; line-height: 1.1; margin: 0; }
.login h1 span { color: var(--faint); }
.toast { position: fixed; left: 50%; bottom: 24px; transform: translateX(-50%); padding: 12px 18px; border-radius: 16px; background: rgba(28,28,32,0.96); border: 1px solid var(--line-hi); box-shadow: 0 12px 40px rgba(0,0,0,0.5); font-size: 13px; z-index: 10; max-width: calc(100% - 32px); }
.toast.bad { border-color: rgba(248,113,113,0.5); }
.created { display: flex; align-items: center; gap: 12px; padding: 14px 16px; border-radius: 16px; border: 1px solid rgba(255,138,80,0.5); background: rgba(255,122,61,0.08); margin-top: 12px; }
.created .code { font-family: var(--mono); font-size: 22px; letter-spacing: 0.12em; }
pre { margin: 0; font-family: var(--mono); font-size: 12px; white-space: pre-wrap; word-break: break-word; color: var(--soft); }
details summary { cursor: pointer; color: var(--soft); }
.meals { display: grid; gap: 12px; align-items: start; grid-template-columns: repeat(auto-fill, minmax(260px, 1fr)); }
.meal { display: flex; flex-direction: column; gap: 10px; padding: 14px; }
.meal img { width: 100%; height: 160px; object-fit: cover; border-radius: 14px; cursor: zoom-in; display: block; background: #111; }
.meal .title { font-size: 15px; line-height: 1.3; }
.meal .items { color: var(--soft); font-size: 12px; line-height: 1.5; }
.macros { display: flex; gap: 12px; font-family: var(--mono); font-size: 12px; color: var(--soft); flex-wrap: wrap; }
.macros b { color: var(--ink); font-weight: 500; }
.linkish { background: none; border: none; padding: 0; color: var(--amber); cursor: pointer; text-align: left; }
.linkish:hover { text-decoration: underline; }
.lightbox { position: fixed; inset: 0; background: rgba(0,0,0,0.85); display: flex; align-items: center; justify-content: center; z-index: 20; cursor: zoom-out; padding: 24px; }
.lightbox img { max-width: 100%; max-height: 100%; border-radius: 16px; }
.kv { display: grid; grid-template-columns: auto 1fr; gap: 6px 16px; font-size: 13px; }
.kv dt { color: var(--faint); }
.kv dd { margin: 0; }
@media (max-width: 640px) { .funnel-row { grid-template-columns: 110px 1fr 50px; } .kpi .value { font-size: 26px; } }
</style>
</head>
<body>
<div class="glow" aria-hidden="true"></div>
<div class="wrap" id="app"></div>
<script>
(function () {
  'use strict';
  var KEY = 'setpoint.admin.secret';
  var state = { secret: null, tab: 'overview', status: null, range: 14, cohort: '', userFilter: { q: '', role: '', cohort: '', pending: false }, person: null, mealFilter: { cohort: '', source: '' } };
  var root = document.getElementById('app');

  try { state.secret = sessionStorage.getItem(KEY); } catch (e) { state.secret = null; }

  // ---------- tiny DOM helper: never sets innerHTML from data ----------
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

  // ---------- API ----------
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

  // ---------- login ----------
  function renderLogin(message) {
    clear(root);
    var input = h('input', { type: 'password', placeholder: 'Admin secret', autocomplete: 'current-password', 'aria-label': 'Admin secret' });
    var btn = h('button', { class: 'btn primary', type: 'submit', text: 'Sign in' });
    var err = h('div', { class: 'soft', style: 'color: var(--bad); min-height: 20px', text: message || '' });
    var form = h('form', { class: 'login', onsubmit: function (e) {
      e.preventDefault();
      if (!input.value.trim()) return;
      state.secret = input.value.trim();
      btn.disabled = true;
      api('/status').then(function (status) {
        try { sessionStorage.setItem(KEY, state.secret); } catch (e2) { /* private mode */ }
        state.status = status;
        renderShell();
      }).catch(function (e3) { btn.disabled = false; if (e3.message !== 'unauthorized') err.textContent = e3.message; });
    } },
      h('div', { class: 'label', text: 'SetPoint · Admin' }),
      h('h1', null, 'Owner’s dashboard. ', h('span', { text: 'Sign in with the admin secret.' })),
      input, btn, err
    );
    root.appendChild(form);
    input.focus();
  }

  // ---------- shell ----------
  var TABS = [['overview', 'Overview'], ['users', 'Users'], ['meals', 'Meals'], ['invites', 'Invites'], ['flags', 'Flags'], ['health', 'Health']];
  var main;

  function renderShell() {
    clear(root);
    var env = state.status ? state.status.environment : '';
    root.appendChild(h('header', null,
      h('span', { class: 'brand', text: 'SetPoint Admin' }),
      env ? h('span', { class: 'badge' + (env === 'production' ? ' lit' : ''), text: env }) : null,
      h('span', { class: 'spacer' }),
      h('button', { class: 'btn small', text: 'Sign out', onclick: function () { signOut(); } })
    ));
    var nav = h('nav', { 'aria-label': 'Sections' });
    TABS.forEach(function (t) {
      nav.appendChild(h('button', { 'aria-current': state.tab === t[0] ? 'page' : null, text: t[1], onclick: function () { state.tab = t[0]; state.person = null; renderShell(); } }));
    });
    root.appendChild(nav);
    main = h('main');
    root.appendChild(main);
    if (state.person) { renderPerson(state.person); return; }
    ({ overview: renderOverview, users: renderUsers, meals: renderMeals, invites: renderInvites, flags: renderFlags, health: renderHealth })[state.tab]();
  }

  function loading() { clear(main); main.appendChild(h('div', { class: 'empty', text: 'Loading…' })); }
  function refreshStatus() { return api('/status').then(function (s) { state.status = s; return s; }); }

  // ---------- overview ----------
  function renderOverview() {
    loading();
    var to = new Date();
    var from = new Date(to.getTime() - state.range * 86400000);
    var q = '?from=' + encodeURIComponent(from.toISOString()) + '&to=' + encodeURIComponent(to.toISOString()) + (state.cohort ? '&cohort=' + encodeURIComponent(state.cohort) : '');
    Promise.all([api('/analytics' + q), refreshStatus(), api('/nutrition' + q)]).then(function (r) {
      var a = r[0], s = r[1], n = r[2];
      clear(main);

      var rangeSel = h('select', { 'aria-label': 'Range', onchange: function (e) { state.range = Number(e.target.value); renderOverview(); } },
        [7, 14, 30, 90].map(function (d) { return h('option', { value: d, selected: state.range === d ? true : null, text: 'Last ' + d + ' days' }); }));
      var cohortSel = h('select', { 'aria-label': 'Cohort', onchange: function (e) { state.cohort = e.target.value; renderOverview(); } },
        h('option', { value: '', text: 'Everyone' }),
        s.cohorts.map(function (c) { return h('option', { value: c.cohort, selected: state.cohort === c.cohort ? true : null, text: c.cohort + ' · ' + c.users }); }));
      main.appendChild(h('div', { class: 'row', style: 'margin-bottom: 14px' }, rangeSel, cohortSel,
        a.truncated ? h('span', { class: 'badge bad', text: 'Too many events — narrow the range' }) : null));

      var last = a.daily.length ? a.daily[a.daily.length - 1] : null;
      var totals = a.totals || {};
      function total(name) { return totals[name] ? totals[name].events : 0; }
      function people(name) { return totals[name] ? totals[name].users : 0; }
      main.appendChild(h('div', { class: 'grid kpis' },
        kpi('People in the app', fmtNum(s.users.total), s.users.pending ? s.users.pending + ' waiting for an invite' : 'none waiting'),
        kpi('Active, last day', fmtNum(last ? last.activeUsers : 0), last ? fmtDate(last.date) : 'no activity yet'),
        kpi('Meals logged', fmtNum(total('meal_logged')), people('meal_logged') + ' people'),
        kpi('Check-ins answered', fmtNum(total('check_in_answered')), people('check_in_answered') + ' people'),
        kpi('Days fully eaten', pct(a.days.fullyEatenRate), a.days.fullyEaten + ' of ' + a.days.settled + ' settled days')
      ));

      var byGoal = Object.keys(n.weight.byGoal).map(function (g) {
        var x = n.weight.byGoal[g];
        return g.charAt(0) + g.slice(1).toLowerCase() + ' ' + signedKg(x.avgKgPerWeek) + ' (' + x.people + ')';
      }).join(' · ');
      main.appendChild(h('div', { class: 'grid kpis section' },
        kpi('Calories vs target', pct(n.calories.avgShareOfTarget), n.calories.daysWithFood + ' settled days with food · ' + n.calories.missedDays + ' missed'),
        kpi('Protein vs target', pct(n.protein.avgShareOfTarget), n.protein.avgGramsPerDay !== null ? n.protein.avgGramsPerDay + ' g a day on average' : 'no meals yet'),
        kpi('Weight change', n.weight.avgKgPerWeek === null ? '—' : signedKg(n.weight.avgKgPerWeek) + '/wk', n.weight.people ? n.weight.people + ' people · ' + byGoal : 'needs two weigh-ins a person')
      ));

      var f = a.funnel;
      var steps = [['Signed up', f.signedUp], ['Finished setup', f.onboarded], ['Logged a meal', f.loggedAMeal], ['Answered a check-in', f.answeredACheckIn], ['Had a fully eaten day', f.hadAFullDay]];
      var funnel = h('div', { class: 'panel' }, h('div', { class: 'label', style: 'margin-bottom: 10px', text: 'Funnel · people who signed up in this range' }));
      if (!f.signedUp) funnel.appendChild(h('div', { class: 'muted', text: 'Nobody signed up in this range.' }));
      else steps.forEach(function (st) {
        var share = f.signedUp ? st[1] / f.signedUp : 0;
        funnel.appendChild(h('div', { class: 'funnel-row' },
          h('span', { class: 'soft', text: st[0] }),
          h('div', { class: 'bar' }, h('span', { style: 'width:' + Math.max(2, share * 100).toFixed(1) + '%' })),
          h('span', { class: 'mono', style: 'text-align: right', text: st[1] + ' · ' + pct(share) })));
      });

      var chart = h('div', { class: 'panel chart' }, h('div', { class: 'label', style: 'margin-bottom: 10px', text: 'Per day' }), dailyChart(a.daily, from, to),
        h('div', { class: 'legend' },
          h('span', null, h('span', { class: 'dot', style: 'background: var(--amber)' }), 'Active people'),
          h('span', null, h('span', { class: 'dot', style: 'background: var(--haze)' }), 'Meals logged')));

      main.appendChild(h('div', { class: 'grid section', style: 'grid-template-columns: repeat(auto-fit, minmax(340px, 1fr))' }, funnel, chart));

      var calPanel = h('div', { class: 'panel chart' }, h('div', { class: 'label', style: 'margin-bottom: 10px', text: 'Calories eaten vs target · settled days' }),
        n.calories.daily.length ? shareChart(n.calories.daily) : h('div', { class: 'muted', text: 'No settled days in this range yet.' }));
      var screens = a.screens || [];
      var screenPanel = h('div', { class: 'panel' }, h('div', { class: 'label', style: 'margin-bottom: 6px', text: 'Screens' }),
        screens.length ? h('div', { class: 'table-wrap' }, h('table', null,
          h('thead', null, h('tr', null, h('th', { text: 'Screen' }), h('th', { text: 'Views' }), h('th', { text: 'People' }))),
          h('tbody', null, screens.map(function (x) { return h('tr', null, h('td', { class: 'mono', text: x.screen }), h('td', { class: 'mono', text: fmtNum(x.views) }), h('td', { class: 'mono', text: fmtNum(x.users) })); }))))
          : h('div', { class: 'muted', text: 'No screen views yet — they start with the next app build.' }));
      main.appendChild(h('div', { class: 'grid section', style: 'grid-template-columns: repeat(auto-fit, minmax(340px, 1fr))' }, calPanel, screenPanel));

      var rows = Object.keys(totals).sort().map(function (name) {
        return h('tr', null, h('td', { class: 'mono', text: name }), h('td', { class: 'mono', text: fmtNum(totals[name].events) }), h('td', { class: 'mono', text: fmtNum(totals[name].users) }));
      });
      main.appendChild(h('div', { class: 'grid section', style: 'grid-template-columns: repeat(auto-fit, minmax(340px, 1fr))' },
        h('div', { class: 'panel' }, h('div', { class: 'label', style: 'margin-bottom: 6px', text: 'Events' }),
          rows.length ? h('div', { class: 'table-wrap' }, h('table', null, h('thead', null, h('tr', null, h('th', { text: 'Event' }), h('th', { text: 'Times' }), h('th', { text: 'People' }))), h('tbody', null, rows)))
            : h('div', { class: 'muted', text: 'No events in this range yet.' })),
        switchesPanel(s)));
    }).catch(fail);
  }

  function kpi(label, value, sub) {
    return h('div', { class: 'panel kpi' }, h('div', { class: 'label', text: label }), h('div', { class: 'value', text: value }), h('div', { class: 'sub', text: sub }));
  }

  function signedKg(x) { return x === null || x === undefined ? '—' : (x > 0 ? '+' : '') + x.toFixed(2) + ' kg'; }

  /** Bars of a share of target per day, with the 100% line. */
  function shareChart(rows) {
    var W = 600, H = 180, pad = 22;
    var max = Math.max(1.2, Math.max.apply(null, rows.map(function (r) { return r.avgShareOfTarget || 0; })));
    var s = svg('svg', { viewBox: '0 0 ' + W + ' ' + H, preserveAspectRatio: 'none', role: 'img', 'aria-label': 'Average share of calorie target eaten per day' });
    var step = (W - pad) / rows.length, bw = Math.max(2, step * 0.6);
    var y100 = H - pad - (1 / max) * (H - pad * 2);
    rows.forEach(function (r, i) {
      var v = r.avgShareOfTarget || 0;
      var bh = (v / max) * (H - pad * 2);
      s.appendChild(svg('rect', { x: pad + i * step + (step - bw) / 2, y: H - pad - bh, width: bw, height: Math.max(0, bh), rx: 2, fill: v >= 0.9 ? '#86EFAC' : '#FF7A3D', opacity: 0.85 }));
    });
    s.appendChild(svg('line', { x1: pad, y1: y100, x2: W, y2: y100, stroke: 'rgba(255,255,255,0.45)', 'stroke-dasharray': '4 4' }));
    var t = svg('text', { x: 0, y: y100 + 4, fill: '#8B8B94', 'font-size': 11, 'font-family': 'Geist Mono, monospace' });
    t.textContent = '100%';
    s.appendChild(t);
    return s;
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
    var s = svg('svg', { viewBox: '0 0 ' + W + ' ' + H, preserveAspectRatio: 'none', role: 'img', 'aria-label': 'Active people and meals logged per day' });
    var step = (W - pad) / days.length;
    var bw = Math.max(2, step * 0.55);
    s.appendChild(svg('line', { x1: pad, y1: H - pad, x2: W, y2: H - pad, stroke: 'rgba(255,255,255,0.12)' }));
    var pts = [];
    days.forEach(function (d, i) {
      var x = pad + i * step + (step - bw) / 2;
      var bh = (d.activeUsers / max) * (H - pad * 2);
      s.appendChild(svg('rect', { x: x, y: H - pad - bh, width: bw, height: Math.max(0, bh), rx: 2, fill: '#FFB86B', opacity: 0.85 }));
      pts.push((x + bw / 2).toFixed(1) + ',' + (H - pad - (d.mealsLogged / max) * (H - pad * 2)).toFixed(1));
    });
    s.appendChild(svg('polyline', { points: pts.join(' '), fill: 'none', stroke: '#818CF8', 'stroke-width': 2, 'vector-effect': 'non-scaling-stroke' }));
    var top = svg('text', { x: 0, y: pad - 6, fill: '#8B8B94', 'font-size': 11, 'font-family': 'Geist Mono, monospace' });
    top.textContent = String(max);
    s.appendChild(top);
    return s;
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
    var p = h('div', { class: 'panel' }, h('div', { class: 'label', style: 'margin-bottom: 6px', text: 'Switches · set in Vercel, then redeploy' }));
    Object.keys(labels).forEach(function (k) {
      var on = s.switches[k];
      var warn = (k === 'devLogin' || k === 'nearbySampleVenues') && on && s.environment === 'production';
      p.appendChild(h('div', { class: 'switch-row' },
        h('div', null, h('div', { text: labels[k][0] }), h('div', { class: 'mono muted', text: labels[k][1] })),
        h('span', { class: 'badge ' + (warn ? 'bad' : on ? 'good' : ''), text: on ? (warn ? 'On · turn off' : 'On') : 'Off' })));
    });
    return p;
  }

  // ---------- users ----------
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
      var search = h('input', { type: 'search', placeholder: 'Search email', value: f.q, 'aria-label': 'Search email' });
      var timer;
      search.addEventListener('input', function () { clearTimeout(timer); timer = setTimeout(function () { f.q = search.value.trim(); renderUsers(); }, 350); });
      main.appendChild(h('div', { class: 'row', style: 'margin-bottom: 14px' },
        search,
        h('select', { 'aria-label': 'Role', onchange: function (e) { f.role = e.target.value; renderUsers(); } },
          h('option', { value: '', text: 'Any role' }),
          ['USER', 'TRAINER', 'ADMIN'].map(function (x) { return h('option', { value: x, selected: f.role === x ? true : null, text: x.charAt(0) + x.slice(1).toLowerCase() }); })),
        h('select', { 'aria-label': 'Cohort', onchange: function (e) { f.cohort = e.target.value; renderUsers(); } },
          h('option', { value: '', text: 'Any cohort' }),
          s.cohorts.map(function (c) { return h('option', { value: c.cohort, selected: f.cohort === c.cohort ? true : null, text: c.cohort }); })),
        h('label', { class: 'row soft', style: 'gap: 6px' }, h('input', { type: 'checkbox', checked: f.pending, onchange: function (e) { f.pending = e.target.checked; renderUsers(); } }), 'Waiting for an invite'),
        h('span', { class: 'spacer' }),
        h('span', { class: 'muted', text: users.length + (users.length === 500 ? '+' : '') + ' people' })));

      if (!users.length) { main.appendChild(h('div', { class: 'empty', text: 'Nobody matches.' })); return; }
      var body = h('tbody');
      users.forEach(function (u) { body.appendChild(userRow(u)); });
      main.appendChild(h('div', { class: 'panel table-wrap', style: 'padding: 6px 8px' }, h('table', null,
        h('thead', null, h('tr', null, ['Email', 'Role', 'Cohort', 'Access', 'Setup', 'Meals', 'Invite', 'Joined'].map(function (t) { return h('th', { text: t }); }))),
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
      else access.appendChild(h('div', { class: 'row', style: 'gap: 8px' }, h('span', { class: 'badge lit', text: 'Waiting' }),
        h('button', { class: 'btn small', text: 'Let in', onclick: function () { save({ access: true }, drawAccess); } })));
    }
    drawAccess();
    return h('tr', null,
      h('td', null, h('button', { class: 'linkish', text: u.email || '(no email)', onclick: function () { openPerson(u.id); } }), h('div', { class: 'mono muted', style: 'font-size: 10px', text: u.id })),
      h('td', null, role),
      h('td', null, cohort),
      access,
      h('td', null, u.onboarding && u.onboarding.completedAt ? h('span', { class: 'badge good', text: 'Done' }) : h('span', { class: 'badge', text: 'Not yet' })),
      h('td', { class: 'mono', text: fmtNum(u._count ? u._count.meals : 0) }),
      h('td', { class: 'mono soft', text: u.inviteCode ? u.inviteCode.code : '—' }),
      h('td', { class: 'mono soft', text: fmtDate(u.createdAt) }));
  }

  // ---------- meals ----------
  var SOURCES = [['', 'Any way'], ['TEXT', 'Typed'], ['PHOTO', 'Photo'], ['SAVED', 'Usual'], ['BARCODE', 'Barcode'], ['CATALOG', 'Foods'], ['PRESCRIPTION', 'Check-in plate']];
  function sourceLabel(src) { for (var i = 0; i < SOURCES.length; i++) if (SOURCES[i][0] === src) return SOURCES[i][1]; return src; }

  function openPerson(id) { state.person = id; renderShell(); window.scrollTo(0, 0); }

  function lightbox(url) {
    var box = h('div', { class: 'lightbox', role: 'dialog', 'aria-label': 'Meal photo', onclick: function () { box.remove(); } }, h('img', { src: url, alt: 'Meal photo' }));
    document.body.appendChild(box);
  }

  function mealCard(m, showUser) {
    var when = new Date(m.loggedAt);
    var items = (m.items || []).map(function (it) { return it.name + (it.quantity ? ' (' + it.quantity + ')' : '') + ' · ' + it.kcal; }).join(' / ');
    return h('div', { class: 'panel meal' },
      m.photoUrl ? h('img', { src: m.photoUrl, alt: m.summary || 'Meal photo', loading: 'lazy', onclick: function () { lightbox(m.photoUrl); } }) : null,
      h('div', { class: 'row', style: 'gap: 6px' },
        h('span', { class: 'badge', text: sourceLabel(m.source) }),
        m.fixed ? h('span', { class: 'badge haze', text: 'Fixed' }) : null,
        m.parseConfidence !== null && m.parseConfidence < 0.45 ? h('span', { class: 'badge lit', text: 'Rough estimate' }) : null,
        h('span', { class: 'spacer' }),
        h('span', { class: 'mono muted', text: when.toLocaleDateString('en-GB', { day: 'numeric', month: 'short' }) + ' ' + when.toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit' }) })),
      h('div', { class: 'title', text: m.summary || '(no description)' }),
      items ? h('div', { class: 'items', text: items }) : null,
      h('div', { class: 'macros' }, h('span', null, h('b', { text: fmtNum(m.kcal) }), ' kcal'), h('span', null, h('b', { text: Math.round(m.proteinG) }), ' g protein'), h('span', { text: Math.round(m.carbsG) + ' g carbs' }), h('span', { text: Math.round(m.fatG) + ' g fat' })),
      m.notes ? h('div', { class: 'items', text: m.notes }) : null,
      showUser && m.user ? h('button', { class: 'linkish', style: 'font-size: 13px', text: (m.user.email || m.user.id) + (m.user.cohort ? ' · ' + m.user.cohort : ''), onclick: function () { openPerson(m.user.id); } }) : null);
  }

  function renderMeals() {
    var f = state.mealFilter;
    loading();
    Promise.all([state.status ? Promise.resolve(state.status) : refreshStatus()]).then(function (r) {
      var s = r[0];
      clear(main);
      main.appendChild(h('div', { class: 'row', style: 'margin-bottom: 14px' },
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
          if (!grid.children.length) more.appendChild(h('div', { class: 'empty', text: 'No meals logged yet.' }));
          else if (res.nextBefore) more.appendChild(h('button', { class: 'btn', text: 'Load more', onclick: function () { load(res.nextBefore); } }));
        }).catch(fail);
      }
      load(null);
    }).catch(fail);
  }

  // ---------- one person ----------
  function renderPerson(id) {
    loading();
    api('/users/' + encodeURIComponent(id) + '/profile').then(function (p) {
      clear(main);
      var u = p.user, o = u.onboarding;
      main.appendChild(h('div', { class: 'row', style: 'margin-bottom: 14px' },
        h('button', { class: 'btn small', text: '← Back', onclick: function () { state.person = null; renderShell(); } }),
        h('span', { style: 'font-size: 18px', text: u.email || u.id }),
        h('span', { class: 'badge', text: u.role.toLowerCase() }),
        u.cohort ? h('span', { class: 'badge haze', text: u.cohort }) : null,
        u.accessGrantedAt ? null : h('span', { class: 'badge lit', text: 'Waiting for an invite' })));

      var weightNow = p.weights.length ? p.weights[p.weights.length - 1].weightKg : (o ? o.weightKg : null);
      var plan = h('div', { class: 'panel' }, h('div', { class: 'label', style: 'margin-bottom: 10px', text: 'Plan' }),
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

      var days = h('div', { class: 'panel chart' }, h('div', { class: 'label', style: 'margin-bottom: 10px', text: 'Last 14 days · eaten vs target' }), personChart(p.days),
        h('div', { class: 'legend' },
          h('span', null, h('span', { class: 'dot', style: 'background: var(--ember)' }), 'Eaten'),
          h('span', null, h('span', { class: 'dot', style: 'background: rgba(255,255,255,0.6)' }), 'Target'),
          h('span', null, h('span', { class: 'dot', style: 'background: var(--haze)' }), 'Protein vs target')));
      main.appendChild(h('div', { class: 'grid', style: 'grid-template-columns: repeat(auto-fit, minmax(340px, 1fr))' }, plan, days));

      var dayRows = p.days.slice().reverse().map(function (d) {
        return h('tr', null,
          h('td', { class: 'mono', text: d.date }),
          h('td', { class: 'mono', text: fmtNum(d.kcal) + (d.targetKcal ? ' / ' + fmtNum(d.targetKcal) : '') }),
          h('td', { class: 'mono', text: d.proteinG + (d.targetProteinG ? ' / ' + d.targetProteinG + ' g' : ' g') }),
          h('td', { class: 'mono', text: String(d.meals) }),
          h('td', null, d.kind ? h('span', { class: 'badge ' + ({ ON_TRACK: 'good', OVER: 'good', UNDER: 'lit', MISSED: 'bad' }[d.kind] || ''), text: d.kind.replace('_', ' ').toLowerCase() }) : null));
      });
      var weightPanel = h('div', { class: 'panel chart' }, h('div', { class: 'label', style: 'margin-bottom: 10px', text: 'Weight · last 6 months' }),
        p.weights.length >= 2 ? weightChart(p.weights) : h('div', { class: 'muted', text: p.weights.length ? 'One weigh-in: ' + p.weights[0].weightKg + ' kg on ' + fmtDate(p.weights[0].measuredAt) : 'No weigh-ins.' }));
      main.appendChild(h('div', { class: 'grid section', style: 'grid-template-columns: repeat(auto-fit, minmax(340px, 1fr)); align-items: start' },
        h('div', { class: 'panel table-wrap' }, h('table', null,
          h('thead', null, h('tr', null, ['Day', 'Calories', 'Protein', 'Meals', 'Result'].map(function (t) { return h('th', { text: t }); }))),
          h('tbody', null, dayRows))),
        weightPanel));

      var checkRows = p.checkIns.map(function (c) {
        return h('tr', null,
          h('td', { class: 'mono', text: new Date(c.createdAt).toLocaleString('en-GB', { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' }) }),
          h('td', { class: 'soft', text: c.kind.toLowerCase() + (c.slot ? ' · ' + c.slot : '') + (c.tier > 1 ? ' · tier ' + c.tier : '') }),
          h('td', null, h('span', { class: 'badge', text: c.status.toLowerCase() })),
          h('td', { class: 'soft', text: c.feedbackPositive === true ? '👍' : c.feedbackPositive === false ? '👎' : '' }));
      });
      main.appendChild(h('div', { class: 'panel table-wrap section' }, h('div', { class: 'label', style: 'margin-bottom: 6px', text: 'Check-ins · last 14 days' }),
        checkRows.length ? h('table', null, h('thead', null, h('tr', null, ['When', 'Kind', 'Status', 'Feedback'].map(function (t) { return h('th', { text: t }); }))), h('tbody', null, checkRows))
          : h('div', { class: 'muted', text: 'No check-ins.' })));

      main.appendChild(h('div', { class: 'section' }, h('h2', { text: 'Meals' + (p.mealCount > p.meals.length ? ' · latest ' + p.meals.length + ' of ' + fmtNum(p.mealCount) : '') })));
      main.appendChild(p.meals.length ? h('div', { class: 'meals' }, p.meals.map(function (m) { return mealCard(m, false); })) : h('div', { class: 'empty', text: 'No meals yet.' }));
    }).catch(fail);
  }

  function personChart(days) {
    var W = 600, H = 180, pad = 22;
    var max = Math.max(1, Math.max.apply(null, days.map(function (d) { return Math.max(d.kcal, d.targetKcal || 0); })));
    var s = svg('svg', { viewBox: '0 0 ' + W + ' ' + H, preserveAspectRatio: 'none', role: 'img', 'aria-label': 'Calories eaten against target per day' });
    var step = (W - pad) / days.length, bw = Math.max(3, step * 0.55);
    var pts = [];
    days.forEach(function (d, i) {
      var x = pad + i * step + (step - bw) / 2;
      var bh = (d.kcal / max) * (H - pad * 2);
      s.appendChild(svg('rect', { x: x, y: H - pad - bh, width: bw, height: Math.max(0, bh), rx: 2, fill: d.targetKcal && d.kcal >= 0.9 * d.targetKcal ? '#86EFAC' : '#FF7A3D', opacity: d.kind === 'TODAY' ? 0.5 : 0.85 }));
      if (d.targetKcal) {
        var ty = H - pad - (d.targetKcal / max) * (H - pad * 2);
        s.appendChild(svg('line', { x1: x - 2, y1: ty, x2: x + bw + 2, y2: ty, stroke: 'rgba(255,255,255,0.6)', 'stroke-width': 2 }));
      }
      if (d.targetProteinG) pts.push((x + bw / 2).toFixed(1) + ',' + (H - pad - Math.min(1.5, d.proteinG / d.targetProteinG) / 1.5 * (H - pad * 2)).toFixed(1));
    });
    if (pts.length > 1) s.appendChild(svg('polyline', { points: pts.join(' '), fill: 'none', stroke: '#818CF8', 'stroke-width': 2, 'vector-effect': 'non-scaling-stroke' }));
    var t = svg('text', { x: 0, y: pad - 6, fill: '#8B8B94', 'font-size': 11, 'font-family': 'Geist Mono, monospace' });
    t.textContent = fmtNum(max) + ' kcal';
    s.appendChild(t);
    return s;
  }

  function weightChart(rows) {
    var W = 600, H = 180, pad = 26;
    var ws = rows.map(function (r) { return r.weightKg; });
    var lo = Math.min.apply(null, ws) - 0.5, hi = Math.max.apply(null, ws) + 0.5;
    var t0 = new Date(rows[0].measuredAt).getTime(), t1 = new Date(rows[rows.length - 1].measuredAt).getTime();
    var span = Math.max(1, t1 - t0);
    var s = svg('svg', { viewBox: '0 0 ' + W + ' ' + H, preserveAspectRatio: 'none', role: 'img', 'aria-label': 'Weight over time' });
    var pts = rows.map(function (r) {
      var x = pad + ((new Date(r.measuredAt).getTime() - t0) / span) * (W - pad * 2);
      var y = H - pad - ((r.weightKg - lo) / (hi - lo)) * (H - pad * 2);
      return x.toFixed(1) + ',' + y.toFixed(1);
    });
    s.appendChild(svg('polyline', { points: pts.join(' '), fill: 'none', stroke: '#FFB86B', 'stroke-width': 2, 'vector-effect': 'non-scaling-stroke' }));
    [[hi - 0.5, pad], [lo + 0.5, H - pad]].forEach(function (v) {
      var t = svg('text', { x: 0, y: v[1], fill: '#8B8B94', 'font-size': 11, 'font-family': 'Geist Mono, monospace' });
      t.textContent = v[0].toFixed(1);
      s.appendChild(t);
    });
    return s;
  }

  // ---------- invites ----------
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
        api('/invites', { method: 'POST', body: body }).then(function (res) {
          renderInvites();
          setTimeout(function () {
            var box = document.getElementById('created');
            if (box) { clear(box); box.appendChild(h('div', { class: 'created' }, h('span', { class: 'code', text: res.invite.code }), h('span', { class: 'soft', text: res.invite.cohort ? 'cohort ' + res.invite.cohort : 'no cohort' }), h('span', { class: 'spacer' }), h('button', { class: 'btn small', type: 'button', text: 'Copy', onclick: function () { copy(res.invite.code); } }))); }
          }, 0);
        }).catch(function (err) { createBtn.disabled = false; fail(err); });
      } },
        h('div', { class: 'label', style: 'margin-bottom: 12px', text: 'New invite code' }),
        h('div', { class: 'form-grid' },
          field('Code', code), field('Cohort', cohort), field('Role', role), field('Max uses', maxUses), field('Expires', expires), field('Note', note), createBtn),
        h('div', { id: 'created' }, created),
        h('div', { class: 'muted', style: 'margin-top: 10px; font-size: 12px', text: state.status && !state.status.switches.inviteOnly ? 'Invite-only is off, so new accounts get in without a code. A code still puts people in its cohort. Turn on INVITE_ONLY in Vercel to require one.' : 'Invite-only is on: new accounts need one of these codes.' }));
      main.appendChild(form);

      var invites = r.invites;
      if (!invites.length) { main.appendChild(h('div', { class: 'empty section', text: 'No codes yet.' })); return; }
      var body = h('tbody');
      invites.forEach(function (inv) {
        var st = inviteState(inv);
        body.appendChild(h('tr', null,
          h('td', null, h('button', { class: 'btn small mono', title: 'Copy', text: inv.code, onclick: function () { copy(inv.code); } })),
          h('td', { class: 'soft', text: inv.cohort || '—' }),
          h('td', { class: 'soft', text: inv.role.charAt(0) + inv.role.slice(1).toLowerCase() }),
          h('td', { class: 'mono', text: inv.uses + (inv.maxUses !== null ? ' / ' + inv.maxUses : '') }),
          h('td', { class: 'mono soft', text: inv.expiresAt ? fmtDate(inv.expiresAt) : 'Never' }),
          h('td', null, h('span', { class: 'badge ' + st[1], text: st[0] })),
          h('td', { class: 'soft', text: inv.note || '' }),
          h('td', { class: 'mono soft', text: fmtDate(inv.createdAt) }),
          h('td', null, inv.disabledAt ? null : h('button', { class: 'btn small danger', text: 'Disable', onclick: function () {
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

  // ---------- flags ----------
  function renderFlags() {
    loading();
    Promise.all([api('/flags'), state.status ? Promise.resolve(state.status) : refreshStatus()]).then(function (r) {
      clear(main);
      main.appendChild(h('div', { class: 'muted', style: 'margin-bottom: 14px', text: 'Each feature has a default in code. An override turns it on for everyone, off for everyone, or on only for some cohorts, roles or people. The app picks changes up on its next launch.' }));
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
      return h('label', { class: 'row soft', style: 'gap: 6px' }, h('input', { type: 'checkbox', value: x, checked: o && o.roles.indexOf(x) >= 0 }), x.charAt(0) + x.slice(1).toLowerCase());
    });
    var userIds = h('textarea', { placeholder: 'User ids, one per line', 'aria-label': 'User ids' });
    userIds.value = o ? o.userIds.join('\n') : '';
    var some = h('div', { class: 'grid', style: 'gap: 12px' },
      field('Cohorts', cohorts),
      h('div', { class: 'field' }, h('span', { text: 'Roles' }), h('div', { class: 'row', style: 'gap: 14px' }, roles)),
      field('People', userIds),
      status.cohorts.length ? h('div', { class: 'muted', style: 'font-size: 12px', text: 'Cohorts in use: ' + status.cohorts.map(function (c) { return c.cohort; }).join(', ') }) : null);

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
      var req;
      if (mode === 'default') req = api('/flags/' + f.key, { method: 'DELETE' });
      else {
        var body = { enabled: mode === 'on', cohorts: [], roles: [], userIds: [] };
        if (mode === 'some') {
          body.cohorts = cohorts.value.split(',').map(function (x) { return x.trim(); }).filter(Boolean);
          body.roles = roles.map(function (l) { return l.querySelector('input'); }).filter(function (i) { return i.checked; }).map(function (i) { return i.value; });
          body.userIds = userIds.value.split(/[\s,]+/).map(function (x) { return x.trim(); }).filter(Boolean);
          if (!body.cohorts.length && !body.roles.length && !body.userIds.length) { saveBtn.disabled = false; toast('Pick at least one cohort, role or person.', true); return; }
        }
        req = api('/flags/' + f.key, { method: 'PUT', body: body });
      }
      req.then(function () { toast('Saved ' + f.key + '.'); renderFlags(); }).catch(function (err) { saveBtn.disabled = false; fail(err); });
    } });

    var summary = !o ? 'Default · ' + (f.default ? 'on' : 'off') + ' for everyone'
      : o.enabled ? 'On for everyone'
      : mode === 'off' ? 'Off for everyone'
      : 'On for ' + [o.cohorts.length ? o.cohorts.join(', ') : null, o.roles.length ? o.roles.map(function (x) { return x.toLowerCase() + 's'; }).join(', ') : null, o.userIds.length ? o.userIds.length + ' people' : null].filter(Boolean).join(' · ');
    append(card, [
      h('div', { class: 'flag-head' }, h('span', { class: 'flag-key', text: f.key }), h('span', { class: 'badge ' + (o ? 'haze' : ''), text: summary })),
      h('div', { class: 'soft', text: f.description }),
      modes, some,
      h('div', { class: 'row' }, saveBtn, o && o.updatedAt ? h('span', { class: 'muted', text: 'Changed ' + fmtDate(o.updatedAt) }) : null),
    ]);
    return card;
  }

  // ---------- health ----------
  function renderHealth() {
    loading();
    api('/metrics').then(function (m) {
      clear(main);
      var sch = m.scheduler || {};
      var alerts = (m.stopConditions && m.stopConditions.evaluation && m.stopConditions.evaluation.alerts) || [];
      main.appendChild(h('div', { class: 'grid kpis' },
        kpi('Check-in scheduler', sch.stale ? 'Stale' : sch.lastOk === false ? 'Failing' : 'Running', sch.lastRunAt ? 'last run ' + new Date(sch.lastRunAt).toLocaleString('en-GB') : 'never ran'),
        kpi('Alerts', String(alerts.length), alerts.length ? alerts.join(', ') : 'none'),
        kpi('Wearable modifier', m.wearableModifier && m.wearableModifier.killSwitch ? 'On' : 'Off', m.wearableModifier && m.wearableModifier.haltedByStopConditions ? 'halted by stop conditions' : (m.wearableModifier ? m.wearableModifier.cohortPercent + '% cohort' : ''))));
      var copyM = Object.assign({}, m);
      main.appendChild(h('div', { class: 'panel section' }, h('details', null, h('summary', { text: 'All beta metrics (last 21 days)' }), h('pre', { style: 'margin-top: 12px', text: JSON.stringify(copyM, null, 2) }))));
    }).catch(fail);
  }

  // ---------- start ----------
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
