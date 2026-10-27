/**
 * The Usage tab of the ops dashboard, kept apart from opsPage.ts so the two
 * can change without touching each other. Both strings are spliced into the
 * page: the CSS inside <style>, the script inside the dashboard's own closure
 * (so it uses its h, shell, state, load, api and num helpers).
 * No backticks or dollar-brace in here — it sits inside a template literal.
 */

export const USAGE_CSS = String.raw`
.us-bar{display:flex;align-items:center;gap:10px;margin:28px 0 8px;flex-wrap:wrap}
.us-bar select,.us-bar input{height:34px;border-radius:17px;border:1px solid var(--line-hi);background:transparent;padding:0 14px;font-size:13px}
.us-bar select option{color:#000}
.us-stats{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:12px;margin:18px 0 6px}
.us-stat{border:1px solid var(--line);border-radius:14px;padding:16px 18px;background:var(--fill)}
.us-stat b{display:block;font:500 28px var(--mono);letter-spacing:-.02em}
.us-stat span{color:var(--faint);font-size:12px}
.us-h{margin:38px 0 4px;font-size:15px;font-weight:600}
.us-sub{margin:0 0 14px;color:var(--faint);font-size:13px}
.us-days{display:flex;align-items:flex-end;gap:3px;height:96px;margin:6px 0 4px}
.us-days i{flex:1;min-width:2px;background:var(--ember);border-radius:2px 2px 0 0;opacity:.85}
.us-axis{display:flex;justify-content:space-between;color:var(--faint);font:400 11px var(--mono)}
.us-fun{display:grid;gap:8px}
.us-fun div{display:grid;grid-template-columns:150px minmax(0,1fr) 110px;align-items:center;gap:14px;font-size:14px}
.us-fun em{display:block;height:10px;border-radius:5px;background:var(--ember);min-width:2px}
.us-ret td,.us-ret th{text-align:center;padding:6px 4px}
.us-ret td:first-child,.us-ret th:first-child{text-align:left}
.us-cell{display:block;border-radius:6px;padding:5px 0;font:400 12px var(--mono);color:var(--ink)}
.us-pre{white-space:pre-wrap;font:400 13px/1.7 var(--mono);color:var(--soft);border:1px solid var(--line);border-radius:12px;padding:14px 16px;margin:0}
.us-two{display:grid;grid-template-columns:repeat(auto-fit,minmax(320px,1fr));gap:28px}
`;

export const USAGE_JS = String.raw`
  // ----- usage -----
  function pct(v) { return v === null || v === undefined ? '–' : Math.round(v * 100) + '%'; }
  function usageStat(value, label) { return h('div', { class: 'us-stat' }, [h('b', { text: String(value) }), h('span', { text: label })]); }
  function usageHead(title, sub) { return h('div', null, [h('h3', { class: 'us-h', text: title }), sub ? h('p', { class: 'us-sub', text: sub }) : null]); }
  function usageTable(heads, rows) {
    return h('table', { class: 'tbl' }, [
      h('thead', null, [h('tr', null, heads.map(function (t) { return h('th', { text: t }); }))]),
      h('tbody', null, rows.map(function (r) { return h('tr', null, r.map(function (c) { return h('td', { text: String(c) }); })); }))
    ]);
  }
  // One try per key, so an endpoint that errors doesn't re-fetch on every render.
  function usageLoad(k, path) {
    state.usageTried = state.usageTried || {};
    if (state.usageTried[k]) return;
    state.usageTried[k] = true;
    load(k, path);
  }
  function usageScreen() {
    var loose = state.data.now ? state.data.now.looseEnds.length : 0;
    var days = state.usageDays || 14, cohort = state.usageCohort || '';
    var key = 'usage:' + days + ':' + cohort;
    var u = state.data[key];
    var controls = h('div', { class: 'us-bar' }, [
      h('select', { 'aria-label': 'Range', onchange: function (e) { state.usageDays = Number(e.target.value); render(); } },
        [7, 14, 30, 90].map(function (n) { return h('option', { value: String(n), selected: n === days, text: 'Last ' + n + ' days' }); })),
      h('input', { placeholder: 'Cohort (all)', 'aria-label': 'Cohort', value: cohort, onchange: function (e) { state.usageCohort = e.target.value.trim(); render(); } }),
      h('button', { class: 'btn', type: 'button', text: 'Refresh', onclick: function () { state.usageTried = {}; delete state.data[key]; delete state.data.digestDaily; delete state.data.digestWeekly; render(); } })
    ]);
    if (!u) {
      usageLoad(key, '/api/admin/usage?days=' + days + (cohort ? '&cohort=' + encodeURIComponent(cohort) : ''));
      return shell('usage', loose, [controls, h('p', { class: 'empty', text: state.usageTried[key] && !state.data['_loading:' + key] ? 'Could not load usage.' : 'Loading…' })]);
    }
    var s = u.summary, a = u.activity, r = u.retention;
    var kids = [controls];
    kids.push(h('div', { class: 'us-stats' }, [
      usageStat(a.dau, 'Active today'), usageStat(a.wau, 'Active, 7 days'), usageStat(a.mau, 'Active, 30 days'),
      usageStat(pct(a.stickiness), 'Daily / monthly'), usageStat(u.people, 'People in the app')
    ]));
    if (u.truncated) kids.push(h('p', { class: 't-warn', text: 'Too many events for this range — the numbers cover only the first part. Pick a shorter range.' }));

    // activity
    var max = Math.max.apply(null, a.series.map(function (p) { return p.activeUsers; }).concat([1]));
    kids.push(usageHead('Active people per day', 'Anyone who did something in the app that day.'));
    kids.push(h('div', { class: 'us-days' }, a.series.map(function (p) {
      return h('i', { title: p.date + ': ' + p.activeUsers, style: 'height:' + Math.max(2, Math.round((p.activeUsers / max) * 100)) + '%' });
    })));
    kids.push(h('div', { class: 'us-axis' }, [h('span', { text: a.series.length ? a.series[0].date : '' }), h('span', { text: a.series.length ? a.series[a.series.length - 1].date : '' })]));

    // funnel
    var f = s.funnel, top = Math.max(f.signedUp, 1);
    var steps = [['Signed up', f.signedUp], ['Set up', f.onboarded], ['Logged a meal', f.loggedAMeal], ['Answered a check-in', f.answeredACheckIn], ['Had a fully eaten day', f.hadAFullDay]];
    kids.push(usageHead('From sign-up to a full day', 'People who signed up in this range, and how far they got.'));
    kids.push(h('div', { class: 'us-fun' }, steps.map(function (st) {
      return h('div', null, [h('span', { text: st[0] }), h('em', { style: 'width:' + Math.round((st[1] / top) * 100) + '%' }), h('span', { class: 'mono t-soft', text: st[1] + ' · ' + pct(st[1] / top) })]);
    })));

    // retention
    kids.push(usageHead('Do they come back?', 'Returned on day 1: ' + pct(r.d1.rate) + ' (' + r.d1.returned + ' of ' + r.d1.eligible + ') · day 7: ' + pct(r.d7.rate) + ' (' + r.d7.returned + ' of ' + r.d7.eligible + ') · day 30: ' + pct(r.d30.rate) + ' (' + r.d30.returned + ' of ' + r.d30.eligible + ')'));
    if (!r.cohorts.length) kids.push(h('p', { class: 'empty', text: 'No sign-ups in the last two months.' }));
    else {
      var heads = ['Signed up (week of)', 'People'];
      for (var w = 0; w < r.cohorts[0].weeks.length; w++) heads.push('W' + w);
      kids.push(h('table', { class: 'tbl us-ret' }, [
        h('thead', null, [h('tr', null, heads.map(function (t) { return h('th', { text: t }); }))]),
        h('tbody', null, r.cohorts.map(function (c) {
          return h('tr', null, [h('td', { text: c.weekStart }), h('td', { class: 'mono', text: String(c.size) })].concat(c.weeks.map(function (v) {
            return h('td', null, [v === null ? h('span', { class: 't-faint', text: '·' }) : h('span', { class: 'us-cell', style: 'background:rgba(255,122,61,' + (0.08 + v * 0.6).toFixed(2) + ')', text: Math.round(v * 100) + '%' })]);
          })));
        }))
      ]));
    }

    // adoption + screens
    kids.push(h('div', { class: 'us-two' }, [
      h('div', null, [usageHead('What people use', 'Of everyone in the app.'),
        usageTable(['Feature', 'Ever', 'This week', '3+ times', 'Share'], u.adoption.map(function (x) { return [x.feature, x.everUsed, x.usedThisWeek, x.usedThreeTimes, pct(x.share)]; }))]),
      h('div', null, [usageHead('Screens', 'Views and people, this range.'),
        s.screens.length ? usageTable(['Screen', 'Views', 'People'], s.screens.slice(0, 15).map(function (x) { return [x.screen, x.views, x.users]; })) : h('p', { class: 'empty', text: 'No screen views yet.' })])
    ]));

    // meals + health
    kids.push(h('div', { class: 'us-two' }, [
      h('div', null, [usageHead('Meal logging', 'Failed: ' + pct(s.meals.failRate) + ' · queued offline: ' + s.meals.queuedOffline + ' · deleted: ' + s.meals.deleted),
        s.meals.bySource.length ? usageTable(['Source', 'Logged', 'Failed'], s.meals.bySource.map(function (x) { return [x.source, x.logged, x.failed]; })) : h('p', { class: 'empty', text: 'No meals in this range.' })]),
      h('div', null, [usageHead('Problems', 'Crashes: ' + s.problems.crashes + ' (' + s.problems.crashUsers + ' people) · server errors: ' + s.problems.serverErrors + ' · check-in failures: ' + s.problems.checkInFailed),
        s.problems.byReason.length ? usageTable(['Why a log failed', 'Times'], s.problems.byReason.map(function (x) { return [x.reason, x.events]; })) : h('p', { class: 'empty', text: 'No failed logs.' })])
    ]));

    // digests
    kids.push(usageHead('Digests', 'Sent each morning; the weekly one on Mondays.'));
    var dg = [['digestDaily', 'daily', 'Yesterday'], ['digestWeekly', 'weekly', 'Last 7 days']];
    var boxes = dg.map(function (d) {
      var v = state.data[d[0]];
      if (!v) usageLoad(d[0], '/api/admin/usage/digest?period=' + d[1]);
      return h('div', null, [h('h4', { class: 'us-h', text: d[2] }), v ? h('pre', { class: 'us-pre', text: v.text }) : h('p', { class: 'empty', text: 'Loading…' })]);
    });
    kids.push(h('div', { class: 'us-two' }, boxes));
    return shell('usage', loose, kids);
  }
`;
