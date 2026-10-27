/**
 * The ops dashboard at /ops: the day as a timeline, people as a 14-day grid, the path
 * of one notification, delivery by kind, and the machine room. One self-contained page
 * that holds no data; everything loads from /api/admin/ops/* after signing in with the
 * admin secret, which stays in this tab's session storage.
 *
 * Kept as a raw string so it ships inside the serverless bundle. The script uses no
 * template literals or backticks so nothing here is read as interpolation.
 */
import { PHONE_CSS, PHONE_HTML } from './tourPhone.js';
import { USAGE_CSS, USAGE_JS } from './usagePage.js';

export const OPS_PAGE_HTML = String.raw`<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex, nofollow">
<title>SetPoint ops</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Hanken+Grotesk:wght@400;500;600;700&family=JetBrains+Mono:wght@400;500&family=Geist:wght@300;400;500&family=Geist+Mono:wght@400;500&display=swap" rel="stylesheet">
<style>
:root{
  --bg:#0A0A0B;--ink:#F4F2EE;--soft:#A8A59F;--faint:#8A8780;
  --line:rgba(244,242,238,.10);--line-hi:rgba(244,242,238,.2);--fill:rgba(244,242,238,.05);
  --ember:#FF7A3D;--good:#7FE0A0;--warn:#FFB86B;--bad:#FF6B6B;
  --sans:"Hanken Grotesk",ui-sans-serif,system-ui,sans-serif;--mono:"JetBrains Mono",ui-monospace,monospace;
}
*{box-sizing:border-box}
html,body{margin:0;background:var(--bg);color:var(--ink);font:15px/1.5 var(--sans);-webkit-font-smoothing:antialiased}
button,input,select,textarea{font:inherit;color:inherit}
a{color:inherit}
:focus-visible{outline:2px solid var(--ember);outline-offset:2px}
.mono{font-family:var(--mono);font-variant-numeric:tabular-nums}
.t-bad{color:var(--bad)}.t-warn{color:var(--warn)}.t-good{color:var(--good)}.t-faint{color:var(--faint)}.t-soft{color:var(--soft)}
.dot{display:inline-block;width:8px;height:8px;border-radius:50%;flex:none}
.d-bad{background:var(--bad)}.d-warn{background:var(--warn)}.d-good{background:var(--good)}.d-off{background:var(--faint)}
.bar{display:flex;align-items:center;height:60px;padding:0 40px;border-bottom:1px solid var(--line);gap:36px;position:sticky;top:0;background:var(--bg);z-index:5}
.word{font-weight:700;letter-spacing:-.02em;font-size:16px}
.word span{color:var(--faint);font-weight:500;margin-left:6px}
.tabs{display:flex;gap:26px;height:100%}
.tabs a{display:flex;align-items:center;height:100%;color:var(--soft);text-decoration:none;font-size:14px;font-weight:500;border-bottom:2px solid transparent;margin-bottom:-1px}
.tabs a[aria-current=page]{color:var(--ink);border-bottom-color:var(--ember)}
.tabs i{font:500 11px var(--mono);font-style:normal;color:var(--bg);background:var(--warn);border-radius:9px;padding:0 6px;line-height:17px;margin-left:7px}
.sp{flex:1}
.find{width:250px;height:34px;border-radius:17px;border:1px solid var(--line);background:var(--fill);padding:0 14px;font-size:13px}
.find::placeholder{color:var(--faint)}
.env{font:500 12px var(--mono);color:var(--soft);white-space:nowrap}
.out{background:none;border:0;color:var(--faint);cursor:pointer;font-size:13px}
.wrap{padding:36px 40px 80px;max-width:1440px;margin:0 auto}
.kick{font:500 12px var(--mono);color:var(--faint)}
.h1{margin:10px 0 0;font-size:56px;line-height:1.02;letter-spacing:-.045em;font-weight:500;max-width:1000px}
.h1 em{font-style:normal;color:var(--faint)}
.h3{margin:0 0 14px;font-size:13px;font-weight:600;color:var(--soft);display:flex;gap:12px;align-items:baseline;flex-wrap:wrap}
.h3 span{font:400 12px var(--mono);color:var(--faint)}
.btn{height:34px;padding:0 15px;border-radius:17px;border:1px solid var(--line-hi);background:transparent;cursor:pointer;font-weight:600;font-size:13px}
.btn:hover{background:var(--fill)}.btn:disabled{opacity:.5;cursor:default}
.btn.pri{background:var(--ember);border-color:var(--ember);color:#1A0A04}
.btn.dng{color:var(--bad);border-color:rgba(255,107,107,.4)}
.login{width:min(420px,calc(100% - 32px));margin:20vh auto 0}
.login h1{margin:0 0 8px;font-size:34px;letter-spacing:-.04em;font-weight:500}
.login p{margin:0 0 20px;color:var(--soft)}
.login input{width:100%;height:44px;border-radius:12px;border:1px solid var(--line-hi);background:var(--fill);padding:0 14px;margin-bottom:12px}
.login .err{color:var(--bad);margin:0 0 12px;min-height:20px}
.loose{display:flex;flex-direction:column;gap:6px;margin-top:26px}
.loose a{display:flex;align-items:center;gap:12px;font-size:19px;letter-spacing:-.015em;text-decoration:none;width:max-content;max-width:100%}
.loose a u{font-size:15px;color:var(--ember);text-decoration:none;font-weight:600}
.nums{display:grid;grid-template-columns:repeat(5,minmax(0,1fr));margin:44px 0 52px;border-top:1px solid var(--line)}
.nums div{padding:16px 24px 0 0}
.nums div+div{padding-left:24px;border-left:1px solid var(--line)}
.nums b{display:block;font:400 40px/1 var(--mono);letter-spacing:-.06em;font-weight:400}
.nums span{display:block;margin-top:8px;color:var(--soft);font-size:13px}
.day{position:relative;margin-bottom:52px}
.lane{display:grid;grid-template-columns:128px minmax(0,1fr);align-items:center;height:46px;border-top:1px solid var(--line)}
.lane label{color:var(--soft);font-size:13px}
.area{position:relative;height:100%}
.run{position:absolute;top:14px;bottom:14px;width:2px;background:var(--soft);margin-left:-1px}
.gap{position:absolute;top:10px;bottom:10px;border-radius:5px;background:repeating-linear-gradient(135deg,rgba(255,184,107,.32) 0 4px,transparent 4px 8px);border:1px solid rgba(255,184,107,.5)}
.gapl{position:absolute;top:-2px;transform:translateY(-100%);font:500 12px var(--mono);color:var(--warn);white-space:nowrap}
.pt{position:absolute;top:50%;width:11px;height:11px;margin:-5.5px 0 0 -5.5px;border-radius:50%}
.pt.g{background:var(--good)}.pt.b{background:var(--bad)}.pt.n{border:1.5px solid var(--faint)}
.mb{position:absolute;bottom:8px;width:6px;margin-left:-3px;border-radius:2px 2px 0 0;background:var(--ember)}
.now{position:absolute;top:0;bottom:0;width:1px;background:var(--ink)}
.axis{display:grid;grid-template-columns:128px minmax(0,1fr);height:30px;border-top:1px solid var(--line)}
.axis div{position:relative}
.axis span{position:absolute;top:8px;font:400 11px var(--mono);color:var(--faint);transform:translateX(-50%)}
.note{color:var(--faint);font-size:13px;margin:-34px 0 40px}
.grid{display:grid;grid-template-columns:210px 130px minmax(0,1fr) 70px 80px;align-items:center;gap:0 20px;padding:11px 0;border-top:1px solid var(--line);text-decoration:none;color:inherit}
a.grid:hover{background:var(--fill)}
.grid.hd{border-top:0;padding:0 0 10px;color:var(--faint);font:400 12px var(--mono)}
.who b{display:block;font-weight:600}.who span{display:block;color:var(--soft);font-size:13px}
.push{display:flex;align-items:center;gap:8px;font-size:13px;color:var(--soft)}
.cells{display:grid;grid-template-columns:repeat(14,minmax(0,1fr));gap:4px}
.cells i{display:block;height:26px;border-radius:6px}
.c0{border:1px dashed rgba(244,242,238,.22)}
.c1{background:rgba(255,122,61,.22)}.c2{background:rgba(255,122,61,.42)}.c3{background:rgba(255,122,61,.68)}.c4{background:var(--ember)}.cx{background:var(--fill)}
.legend{display:flex;align-items:center;gap:10px;margin-top:16px;color:var(--faint);font:400 12px var(--mono);flex-wrap:wrap}
.legend i{display:block;width:18px;height:12px;border-radius:4px}
.more{margin-top:14px;color:var(--ember);font-weight:600;text-decoration:none;display:inline-block}
.chips{display:flex;gap:8px;margin:18px 0 26px;flex-wrap:wrap}
.chip{height:32px;padding:0 14px;border-radius:16px;border:1px solid var(--line);background:transparent;color:var(--soft);cursor:pointer;font-size:13px}
.chip[aria-pressed=true]{background:var(--fill);color:var(--ink);border-color:var(--line-hi)}
.top{display:flex;align-items:flex-end;gap:24px;flex-wrap:wrap}
.acts{display:flex;gap:8px;flex-wrap:wrap}
.path{position:relative;display:grid;grid-template-columns:repeat(5,minmax(0,1fr));margin:12px 0 0}
.path:before{content:"";position:absolute;left:10%;right:10%;top:11px;height:2px;background:rgba(244,242,238,.16)}
.node{position:relative;padding:0 14px}
.node .c{position:relative;width:24px;height:24px;border-radius:50%;margin:0 auto 14px;background:var(--bg);border:2px solid var(--faint);display:flex;align-items:center;justify-content:center;font:600 12px var(--mono)}
.node.ok .c{border-color:var(--good);background:var(--good);color:#0A0A0B}
.node.no .c{border-color:var(--bad);background:var(--bad);color:#0A0A0B}
.node h4{margin:0;text-align:center;font-size:15px;font-weight:600}
.node p{margin:4px 0 0;text-align:center;color:var(--soft);font-size:13px}
.why{margin:26px auto 0;max-width:780px;text-align:center;font-size:20px;line-height:1.35;letter-spacing:-.02em}
.why em{font-style:normal;color:var(--bad)}
.two{display:grid;grid-template-columns:minmax(0,1fr) 380px;gap:56px;margin-top:56px}
.chart{position:relative;height:190px;display:grid;grid-template-columns:repeat(14,minmax(0,1fr));gap:8px;align-items:end;border-bottom:1px solid var(--line)}
.chart i{display:block;background:rgba(255,122,61,.75);border-radius:5px 5px 0 0}
.chart i.z{background:transparent;border:1px dashed rgba(244,242,238,.22);border-bottom:0;height:18px}
.tgt{position:absolute;left:0;right:0;border-top:1px dashed var(--line-hi)}
.tgt span{position:absolute;right:0;top:-20px;font:400 11px var(--mono);color:var(--faint)}
.days{display:grid;grid-template-columns:repeat(14,minmax(0,1fr));gap:8px;margin-top:8px;font:400 11px var(--mono);color:var(--faint);text-align:center}
.dl{display:grid;grid-template-columns:130px minmax(0,1fr);gap:11px 12px;margin:0}
.dl dt{color:var(--faint)}.dl dd{margin:0}
.lr{display:grid;grid-template-columns:110px minmax(0,1fr) 200px 150px;gap:20px;padding:13px 0;border-top:1px solid var(--line);align-items:baseline}
.lr .w{font:400 12px var(--mono);color:var(--faint)}
.lr .m{font-weight:500}.lr .m small{display:block;margin-top:2px;color:var(--faint);font-weight:400;font-size:13px}
.st{display:inline-flex;align-items:center;gap:7px;font-size:13px}
.k{display:grid;grid-template-columns:230px minmax(0,1fr) 150px;gap:28px;align-items:center;padding:20px 0;border-top:1px solid var(--line)}
.k:last-child{border-bottom:1px solid var(--line)}
.k h4{margin:0;font-size:17px;font-weight:600;letter-spacing:-.015em}.k p{margin:2px 0 0;color:var(--soft);font-size:13px}
.stack{display:flex;height:34px;border-radius:8px;overflow:hidden;gap:2px;background:var(--fill)}
.stack i{display:flex;align-items:center;padding-left:10px;font:500 12px var(--mono);color:#0A0A0B;overflow:hidden;white-space:nowrap;min-width:0}
.s-ate{background:var(--ember)}.s-ans{background:rgba(255,122,61,.5);color:var(--ink)!important}.s-ign{background:rgba(244,242,238,.2);color:var(--ink)!important}.s-fail{background:var(--bad)}
.k .r{text-align:right}.k .r b{display:block;font:400 28px/1 var(--mono);letter-spacing:-.05em;font-weight:400}.k .r span{display:block;margin-top:4px;color:var(--soft);font-size:13px}
.leg{display:flex;gap:22px;margin:26px 0 0;color:var(--soft);font-size:13px;flex-wrap:wrap}
.leg span{display:flex;align-items:center;gap:8px}.leg i{width:14px;height:14px;border-radius:4px}
.two2{display:grid;grid-template-columns:minmax(0,1fr) minmax(0,1fr);gap:64px;margin-top:64px}
.fr{display:grid;grid-template-columns:200px minmax(0,1fr) 40px;gap:16px;align-items:center;padding:12px 0;border-top:1px solid var(--line)}
.fr .t{height:8px;border-radius:4px;background:var(--fill)}.fr .t i{display:block;height:100%;border-radius:4px;background:var(--bad)}
.fr span.m{font:400 13px var(--mono);text-align:right}
.hrs{display:grid;grid-template-columns:repeat(17,minmax(0,1fr));gap:5px;align-items:end;height:130px;margin-top:6px}
.hrs i{display:block;background:rgba(255,122,61,.7);border-radius:4px 4px 0 0;min-height:2px}
.hl{display:grid;grid-template-columns:repeat(17,minmax(0,1fr));gap:5px;margin-top:8px;font:400 11px var(--mono);color:var(--faint);text-align:center}
.hero{display:grid;grid-template-columns:minmax(0,1fr) 420px;gap:64px;margin-top:36px;align-items:end}
.cost b{display:block;font:400 96px/.95 var(--mono);letter-spacing:-.07em;font-weight:400}
.cost b small{font-size:28px;letter-spacing:-.02em;color:var(--faint);margin-left:10px}
.cost p{margin:10px 0 0;color:var(--soft);font-size:15px}
.meter{position:relative;height:10px;border-radius:5px;background:var(--fill);margin-top:26px}
.meter i{position:absolute;left:0;top:0;bottom:0;border-radius:5px;background:var(--ink)}
.meter u{position:absolute;right:0;top:-6px;width:2px;height:22px;background:var(--faint)}
.meter span{position:absolute;right:0;top:20px;font:400 11px var(--mono);color:var(--faint)}
.days14{display:grid;grid-template-columns:repeat(14,minmax(0,1fr));gap:6px;align-items:end;height:110px}
.days14 i{display:block;background:rgba(244,242,238,.2);border-radius:4px 4px 0 0;min-height:2px}.days14 i.n{background:var(--ink)}
.chk{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:0 56px;margin-top:8px}
.ci{display:grid;grid-template-columns:8px minmax(0,1fr);gap:12px;padding:15px 0;border-top:1px solid var(--line);align-items:start}
.ci .dot{margin-top:7px}.ci h4{margin:0;font-size:15px;font-weight:600}.ci p{margin:2px 0 0;color:var(--soft);font-size:13px}
.empty{color:var(--faint);padding:24px 0}
.tbl{width:100%;border-collapse:collapse}
.tbl th{text-align:left;font:400 12px var(--mono);color:var(--faint);padding:0 12px 10px 0}
.tbl td{padding:12px 12px 12px 0;border-top:1px solid var(--line);color:var(--soft);vertical-align:middle}
.tbl td:first-child{color:var(--ink)}
.form{display:flex;gap:10px;flex-wrap:wrap;align-items:center;margin:0 0 28px}
.form input,.form select{height:36px;border-radius:18px;border:1px solid var(--line-hi);background:var(--fill);padding:0 14px;font-size:13px;min-width:0}
.form input.w{width:200px}.form input.s{width:110px}
.flag input{height:36px;border-radius:18px;border:1px solid var(--line-hi);background:var(--fill);padding:0 14px;font-size:13px;min-width:0;width:100%}
.flag input::placeholder,.form input::placeholder{color:var(--faint)}
.flag{display:grid;grid-template-columns:minmax(0,1fr) auto 230px auto;gap:20px;align-items:center;padding:16px 0;border-top:1px solid var(--line)}
.flag b{font-weight:600;font-family:var(--mono);font-size:13px}.flag p{margin:2px 0 0;color:var(--soft);font-size:13px}
.seg{display:flex;border:1px solid var(--line);border-radius:18px;padding:3px}
.seg button{height:28px;padding:0 13px;border:0;border-radius:14px;background:transparent;color:var(--soft);cursor:pointer;font-size:13px}
.seg button[aria-pressed=true]{background:var(--fill);color:var(--ink)}
.sw{display:flex;gap:28px;flex-wrap:wrap;margin:26px 0 8px;color:var(--soft);font-size:14px}
.sw span{display:flex;align-items:center;gap:8px}
.toast{position:fixed;left:50%;bottom:28px;transform:translateX(-50%);background:var(--ink);color:#0A0A0B;padding:10px 18px;border-radius:20px;font-weight:600;font-size:14px;z-index:20}
.wrap:has(.tr-app){padding:14px 28px 0;max-width:1700px}
.tr-app{height:calc(100vh - 60px - 14px);min-height:520px;display:flex;flex-direction:column;gap:14px}
.tr-head{display:flex;align-items:center;gap:14px;flex-wrap:wrap;padding:0 0 12px;border-bottom:1px solid var(--line);flex:none}
.tr-head h1{margin:0;font-size:22px;letter-spacing:-.03em;font-weight:500}
.tr-head .meta{color:var(--faint);font-size:13px}
.tr-head .sp{flex:1}
.tr-head .state{font-size:13px;color:var(--faint);display:flex;align-items:center;gap:8px}
.tr-head .state.dirty{color:var(--warn)}
.tr-head .state i{width:8px;height:8px;border-radius:50%;background:currentColor}
.tr-head .ck{display:flex;align-items:center;gap:8px;color:var(--soft);font-size:13px}
.tr3{display:grid;grid-template-columns:250px minmax(0,1fr) minmax(340px,420px);gap:28px;flex:1;min-height:0}
.tr-col{min-width:0;min-height:0;display:flex;flex-direction:column}
.tr-left .ts-list{flex:1;min-height:0;overflow-y:auto;padding-right:4px}
.tr-mid{align-items:center;gap:10px}
.tr-fit{position:relative;flex:none}
.tr-right{overflow-y:auto}
.ts-list{list-style:none;margin:0;padding:0;display:flex;flex-direction:column;gap:4px}
.ts{display:grid;grid-template-columns:20px 10px minmax(0,1fr) auto;gap:8px;align-items:center;height:38px;padding:0 10px;border:1px solid var(--line);border-radius:12px;cursor:pointer;background:transparent}
.ts:hover{background:var(--fill)}
.ts.sel{border-color:rgba(255,184,107,.65);background:rgba(255,184,107,.08)}
.ts.over{border-color:var(--ember);box-shadow:0 -2px 0 var(--ember)}
.ts .n{font:500 11px var(--mono);color:var(--faint);text-align:center}
.ts .dotc{width:8px;height:8px;border-radius:50%}
.ts .tt{font-size:13.5px;font-weight:600;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.ts .badge{font:500 10px var(--mono);padding:2px 6px;border-radius:8px;background:rgba(255,107,107,.15);color:var(--bad)}
.ts-add{margin-top:8px;flex:none}
.tr-edit{border:1px solid var(--line);border-radius:18px;padding:16px;display:flex;flex-direction:column;gap:14px}
.tr-edit h2{margin:0;font-size:16px;font-weight:600;letter-spacing:-.01em}
.tr-edit .top{display:flex;align-items:center;gap:8px}
.tr-edit .top .sp{flex:1}
.sec{display:flex;flex-direction:column;gap:8px}
.sec>label,.sec>.lab{font:500 11px var(--mono);letter-spacing:.06em;color:var(--faint);text-transform:uppercase;display:flex;justify-content:space-between;align-items:baseline}
.sec .cnt{text-transform:none;letter-spacing:0;font-weight:400}
.sec input[type=text],.sec textarea{width:100%;min-width:0;border-radius:12px;border:1px solid var(--line-hi);background:var(--fill);padding:0 12px;font-size:14px;height:38px}
.sec textarea{height:auto;min-height:74px;padding:9px 12px;resize:vertical;line-height:1.4}
.sec input.ti{font-weight:600}
.sec.he input,.sec.he textarea{direction:rtl;text-align:right}
.segs{display:flex;gap:6px;flex-wrap:wrap}
.opts{display:flex;gap:6px;flex-wrap:wrap}
.opt{display:inline-flex;align-items:center;gap:7px;text-align:left;padding:0 12px;height:32px;border-radius:16px;border:1px solid var(--line);background:transparent;cursor:pointer;font-size:13px}
.opt:hover{background:var(--fill)}
.opt[aria-pressed=true]{border-color:rgba(255,122,61,.8);background:rgba(255,122,61,.14)}
.opt i{width:10px;height:10px;border-radius:50%;border:1.5px solid var(--faint);flex:none}
.opt[aria-pressed=true] i{border-color:var(--ember);background:var(--ember)}
.mini{height:28px;min-width:28px;padding:0 10px;border-radius:14px;border:1px solid var(--line);background:transparent;cursor:pointer;font-size:12px}
.mini:hover{background:var(--fill)}.mini:disabled{opacity:.3;cursor:default}.mini.dng{color:var(--bad)}
.hint{margin:0;color:var(--faint);font-size:12px;line-height:1.45}
.tr-empty{border:1px dashed var(--line-hi);border-radius:18px;padding:24px;color:var(--soft)}
@media (max-width:1180px){.tr3{grid-template-columns:220px minmax(0,1fr) minmax(300px,360px);gap:18px}}
@media (max-width:1000px){
  .bar{padding:0 16px;gap:16px;overflow-x:auto}.find{display:none}.wrap{padding:24px 16px 60px}
  .h1{font-size:36px}.nums{grid-template-columns:repeat(2,minmax(0,1fr))}.nums div{padding-left:0!important;border-left:0!important}
  .grid{grid-template-columns:minmax(0,1fr) 90px}.grid .cells,.grid>span{display:none}
  .two,.two2,.hero,.chk{grid-template-columns:minmax(0,1fr);gap:32px}.path{grid-template-columns:minmax(0,1fr);gap:18px}.path:before{display:none}
  .k{grid-template-columns:minmax(0,1fr)}.lr{grid-template-columns:minmax(0,1fr)}.cost b{font-size:64px}.lane,.axis{grid-template-columns:80px minmax(0,1fr)}
}
${PHONE_CSS}
${USAGE_CSS}
</style>
</head>
<body>
<div id="root"></div>
<template id="phone-tpl">${PHONE_HTML}</template>
<script>
(function () {
  'use strict';
  var KEY = 'setpoint.ops.secret';
  var state = { secret: null, data: {}, filter: 'all', query: '' };
  var root = document.getElementById('root');

  function h(tag, attrs, kids) {
    var el = document.createElement(tag);
    attrs = attrs || {};
    Object.keys(attrs).forEach(function (k) {
      var v = attrs[k];
      if (v === null || v === undefined || v === false) return;
      if (k === 'text') el.textContent = v;
      else if (k === 'class') el.className = v;
      else if (k === 'style') el.setAttribute('style', v);
      else if (k.indexOf('on') === 0) el.addEventListener(k.slice(2), v);
      else el.setAttribute(k, v === true ? '' : v);
    });
    (kids || []).forEach(function (c) {
      if (c === null || c === undefined || c === false) return;
      el.appendChild(typeof c === 'string' ? document.createTextNode(c) : c);
    });
    return el;
  }
  function clear(el) { while (el.firstChild) el.removeChild(el.firstChild); }
  function num(n) { return Number(n).toLocaleString('en-US'); }
  function pad(n) { return (n < 10 ? '0' : '') + n; }
  function clock(iso) { var d = new Date(iso); return pad(d.getHours()) + ':' + pad(d.getMinutes()); }
  function ago(iso) {
    var m = Math.round((Date.now() - new Date(iso).getTime()) / 60000);
    if (m < 1) return 'just now';
    if (m < 60) return m + ' min ago';
    if (m < 1440) return Math.round(m / 60) + ' h ago';
    return Math.round(m / 1440) + ' d ago';
  }
  function dayLabel(iso) {
    var d = new Date(iso), t = new Date();
    if (d.toDateString() === t.toDateString()) return 'Today ' + clock(iso);
    var y = new Date(t.getTime() - 86400000);
    if (d.toDateString() === y.toDateString()) return 'Yesterday ' + clock(iso);
    return d.toLocaleDateString('en-GB', { month: 'short', day: 'numeric' }) + ' ' + clock(iso);
  }
  function midnight() { var d = new Date(); d.setHours(0, 0, 0, 0); return d; }
  function toast(text) {
    var t = h('div', { class: 'toast', role: 'status', text: text });
    document.body.appendChild(t);
    setTimeout(function () { t.remove(); }, 3200);
  }

  function api(path, opts) {
    opts = opts || {};
    var headers = { 'x-admin-secret': state.secret };
    if (opts.body) headers['content-type'] = 'application/json';
    return fetch(path, { method: opts.method || 'GET', headers: headers, body: opts.body ? JSON.stringify(opts.body) : undefined }).then(function (res) {
      if (res.status === 401) { signOut(); throw new Error('Signed out'); }
      if (!res.ok) return res.json().catch(function () { return {}; }).then(function (b) { throw new Error(b.message || ('Error ' + res.status)); });
      return res.json();
    });
  }
  function signOut() {
    try { sessionStorage.removeItem(KEY); } catch (e) {}
    state.secret = null; state.data = {}; state.tw = null;
    render();
  }

  // ----- routing -----
  function route() {
    var raw = (location.hash || '#now').slice(1);
    if (raw.indexOf('person/') === 0) return { name: 'person', id: raw.slice(7) };
    if (['now', 'people', 'usage', 'delivery', 'machine', 'access', 'tour'].indexOf(raw) >= 0) return { name: raw };
    return { name: 'now' };
  }
  window.addEventListener('hashchange', function () { if (state.secret) render(); window.scrollTo(0, 0); });

  // ----- shell -----
  function shell(active, loose, body) {
    var tabs = [['now', 'Now'], ['people', 'People'], ['usage', 'Usage'], ['delivery', 'Delivery'], ['machine', 'Machine'], ['access', 'Access'], ['tour', 'Tour']];
    var bar = h('header', { class: 'bar' }, [
      h('div', { class: 'word' }, ['SetPoint', h('span', { text: 'ops' })]),
      h('nav', { class: 'tabs', 'aria-label': 'Sections' }, tabs.map(function (t) {
        var kids = [t[1]];
        if (t[0] === 'now' && loose) kids.push(h('i', { text: String(loose) }));
        return h('a', { href: '#' + t[0], 'aria-current': active === t[0] ? 'page' : null }, kids);
      })),
      h('span', { class: 'sp' }),
      h('input', { class: 'find', placeholder: 'Find a person', 'aria-label': 'Find a person', value: state.query, oninput: function (e) {
        state.query = e.target.value;
        if (route().name !== 'people') location.hash = '#people'; else renderPeopleList();
      } }),
      h('span', { class: 'env', text: 'production' }),
      h('button', { class: 'out', type: 'button', text: 'Sign out', onclick: signOut })
    ]);
    return h('div', null, [bar, h('main', { class: 'wrap' }, body)]);
  }

  function signIn() {
    var input = h('input', { type: 'password', placeholder: 'Admin secret', 'aria-label': 'Admin secret', autocomplete: 'current-password' });
    var err = h('p', { class: 'err', role: 'alert' });
    function go() {
      if (!input.value) return;
      state.secret = input.value;
      api('/api/admin/ops/now?since=' + encodeURIComponent(midnight().toISOString())).then(function (d) {
        try { sessionStorage.setItem(KEY, state.secret); } catch (e) {}
        state.data.now = d; render();
      }).catch(function () { state.secret = null; err.textContent = 'That secret didn’t work.'; });
    }
    input.addEventListener('keydown', function (e) { if (e.key === 'Enter') go(); });
    return h('div', { class: 'login' }, [
      h('h1', { text: 'SetPoint ops' }),
      h('p', { text: 'Sign in with the admin secret.' }),
      input, err,
      h('button', { class: 'btn pri', type: 'button', onclick: go, text: 'Sign in' })
    ]);
  }

  // ----- Now -----
  function nowScreen() {
    var d = state.data.now;
    if (!d) return shell('now', 0, [h('p', { class: 'empty', text: 'Loading…' })]);
    var n = d.numbers, loose = d.looseEnds;
    var title = loose.length === 0
      ? [h('h1', { class: 'h1' }, ['Quiet day. ', h('em', { text: 'Nothing needs you.' })])]
      : [h('h1', { class: 'h1' }, [(loose.length === 1 ? 'One loose end. ' : loose.length + ' loose ends. '), h('em', { text: 'Otherwise a quiet day.' })])];
    var body = [h('div', { class: 'kick', text: new Date().toLocaleDateString('en-GB', { weekday: 'long', day: 'numeric', month: 'long' }) })].concat(title);
    body.push(h('div', { class: 'loose' }, loose.map(function (l) {
      return h('a', { href: '#' + l.link }, [h('span', { class: 'dot ' + (l.level === 'bad' ? 'd-bad' : 'd-warn') }), l.title, h('u', { text: l.link === 'people' ? 'See who →' : 'See the checks →' })]);
    })));
    var reached = n.reachedPct === null ? '–' : n.reachedPct + '%';
    body.push(h('div', { class: 'nums' }, [
      h('div', null, [h('b', { text: String(n.activeToday) }), h('span', { text: 'people active today, of ' + n.people })]),
      h('div', null, [h('b', { text: String(n.meals) }), h('span', { text: 'meals logged, ' + n.photoMeals + ' by photo' })]),
      h('div', null, [h('b', { text: String(n.checkInsWeek) }), h('span', { text: 'check-ins sent this week' })]),
      h('div', null, [h('b', { class: n.reachedPct !== null && n.reachedPct < 95 ? 't-warn' : '', text: reached }), h('span', { text: 'of them reached a phone' })]),
      h('div', null, [h('b', { text: '$' + n.aiUsd.toFixed(2) }), h('span', { text: 'AI spend today, an estimate, of $' + n.aiBudget })])
    ]));
    body.push(h('div', { class: 'h3' }, ['The day so far', h('span', { text: '00:00 to now' })]));
    body.push(dayTimeline(d.day));
    if (d.day.runs.length < 2) body.push(h('p', { class: 'note', text: 'Scoring history starts from when this version went live, so the heartbeat fills in over the next hours.' }));
    body.push(h('div', { class: 'h3' }, ['Everyone, last 14 days', h('span', { text: 'how much of their target they ate, sorted by who needs you' })]));
    body.push(peopleGrid(d.people.slice(0, 10)));
    body.push(legend());
    if (d.peopleTotal > 10) body.push(h('a', { class: 'more', href: '#people', text: 'All ' + d.peopleTotal + ' people →' }));
    return shell('now', loose.length, body);
  }

  function dayTimeline(day) {
    var start = new Date(day.start).getTime(), span = 86400000, nowT = Date.now();
    var pct = function (t) { return Math.max(0, Math.min(100, ((t - start) / span) * 100)); };
    var nowPct = pct(nowT);
    var nowLine = function () { return h('div', { class: 'now', style: 'left:' + nowPct + '%' }); };
    var runs = day.runs.map(function (r) { return new Date(r).getTime(); }).sort(function (a, b) { return a - b; });
    var scoring = [];
    runs.forEach(function (t) { scoring.push(h('i', { class: 'run', style: 'left:' + pct(t) + '%' })); });
    var marks = runs.concat([nowT]);
    for (var i = 1; i < marks.length; i++) {
      var gapMin = (marks[i] - marks[i - 1]) / 60000;
      if (gapMin > 25) {
        scoring.push(h('div', { class: 'gap', style: 'left:' + pct(marks[i - 1]) + '%;width:' + (pct(marks[i]) - pct(marks[i - 1])) + '%' }));
        if (gapMin > 40) scoring.push(h('span', { class: 'gapl', style: 'left:' + pct(marks[i - 1]) + '%', text: 'no run for ' + Math.round(gapMin) + ' min' }));
      }
    }
    var checkIns = day.checkIns.map(function (c) {
      return h('span', { class: 'pt ' + (c.outcome === 'good' ? 'g' : c.outcome === 'bad' ? 'b' : 'n'), style: 'left:' + pct(new Date(c.at).getTime()) + '%', title: clock(c.at) });
    });
    var meals = day.meals.map(function (m) {
      return h('i', { class: 'mb', style: 'left:' + pct(new Date(m.at).getTime()) + '%;height:' + Math.min(46, 6 + m.kcal / 16) + 'px', title: clock(m.at) + ' · ' + m.kcal + ' kcal' });
    });
    var axis = [0, 3, 6, 9, 12, 15, 18, 21].map(function (hr) { return h('span', { style: 'left:' + (hr / 24) * 100 + '%', text: pad(hr) }); });
    return h('div', { class: 'day' }, [
      h('div', { class: 'lane' }, [h('label', { text: 'Scoring runs' }), h('div', { class: 'area' }, scoring.concat([nowLine()]))]),
      h('div', { class: 'lane' }, [h('label', { text: 'Check-ins' }), h('div', { class: 'area' }, checkIns.concat([nowLine()]))]),
      h('div', { class: 'lane', style: 'height:64px' }, [h('label', { text: 'Meals logged' }), h('div', { class: 'area' }, meals.concat([nowLine()]))]),
      h('div', { class: 'axis' }, [h('div'), h('div', null, axis)])
    ]);
  }

  function peopleGrid(people) {
    var rows = [h('div', { class: 'grid hd' }, [h('span', { text: 'Person' }), h('span', { text: 'Notifications' }), h('span', { text: 'Last 14 days, oldest to today' }), h('span', { text: 'Streak' }), h('span', { text: 'Answered' })])];
    if (!people.length) rows.push(h('p', { class: 'empty', text: 'Nobody matches.' }));
    people.forEach(function (p) {
      rows.push(h('a', { class: 'grid', href: '#person/' + p.id }, [
        h('div', { class: 'who' }, [h('b', { text: p.name }), h('span', { text: p.sub })]),
        h('div', { class: 'push' }, [h('span', { class: 'dot d-' + p.tone }), p.push]),
        h('div', { class: 'cells' }, p.cells.map(function (c) { return h('i', { class: c < 0 ? 'cx' : 'c' + c }); })),
        h('span', { class: 'mono t-soft', text: p.streak ? p.streak + ' d' : '0 d' }),
        h('span', { class: 'mono t-soft', text: p.answered })
      ]));
    });
    return h('div', null, rows);
  }
  function legend() {
    return h('div', { class: 'legend' }, ['Target reached ', h('i', { class: 'c0' }), 'none ', h('i', { class: 'c1' }), 'a little ', h('i', { class: 'c2' }), h('i', { class: 'c3' }), h('i', { class: 'c4' }), 'all of it ', h('i', { class: 'cx' }), 'not joined yet']);
  }

  // ----- People -----
  var peopleHost = null;
  function renderPeopleList() {
    if (!peopleHost) return;
    var all = state.data.now.people;
    var q = state.query.trim().toLowerCase();
    var list = all.filter(function (p) {
      if (q && p.name.toLowerCase().indexOf(q) < 0) return false;
      if (state.filter === 'noreach') return p.pushKind === 'none' || p.pushKind === 'sandbox';
      if (state.filter === 'quiet') return /No meal/.test(p.sub);
      if (state.filter === 'admin') return /^(Admin|Trainer)/.test(p.sub);
      return true;
    });
    clear(peopleHost);
    peopleHost.appendChild(peopleGrid(list));
  }
  function peopleScreen() {
    var d = state.data.now;
    if (!d) return shell('people', 0, [h('p', { class: 'empty', text: 'Loading…' })]);
    var all = d.people;
    var count = function (f) { return all.filter(f).length; };
    var chips = [
      ['all', 'Everyone ' + d.peopleTotal],
      ['noreach', 'Can’t get notifications ' + count(function (p) { return p.pushKind === 'none' || p.pushKind === 'sandbox'; })],
      ['quiet', 'Quiet 2+ days ' + count(function (p) { return /No meal/.test(p.sub); })],
      ['admin', 'Admins and trainers ' + count(function (p) { return /^(Admin|Trainer)/.test(p.sub); })]
    ];
    var chipRow = h('div', { class: 'chips' }, chips.map(function (c) {
      return h('button', { class: 'chip', type: 'button', 'aria-pressed': state.filter === c[0] ? 'true' : 'false', text: c[1], onclick: function () { state.filter = c[0]; render(); } });
    }));
    peopleHost = h('div');
    var body = [h('div', { class: 'kick', text: 'People' }), h('h1', { class: 'h1' }, [d.peopleTotal + ' people. ', h('em', { text: 'Pick one to see where it breaks.' })]), chipRow, peopleHost, legend()];
    var el = shell('people', d.looseEnds.length, body);
    setTimeout(renderPeopleList, 0);
    return el;
  }

  // ----- Person -----
  function personScreen(id) {
    var key = 'person:' + id, p = state.data[key];
    var loose = state.data.now ? state.data.now.looseEnds.length : 0;
    if (!p) { load(key, '/api/admin/ops/person/' + id); return shell('people', loose, [h('p', { class: 'empty', text: 'Loading…' })]); }
    var broken = p.pipeline.why;
    var firstBad = -1; p.pipeline.steps.forEach(function (s, i) { if (firstBad < 0 && s.state === 'no') firstBad = i; });
    function act(label, path, method, cls, after) {
      return h('button', { class: 'btn ' + (cls || ''), type: 'button', text: label, onclick: function (e) {
        var b = e.target; b.disabled = true;
        api(path, { method: method || 'POST', body: after && after.body }).then(function (r) {
          toast(after && after.say ? after.say(r) : 'Done');
          delete state.data[key];
          if (after && after.leave) location.hash = '#people'; else render();
        }).catch(function (err) { toast(err.message); }).then(function () { b.disabled = false; });
      } });
    }
    var roleBtn = h('button', { class: 'btn', type: 'button', text: 'Change role', onclick: function () {
      var role = (prompt('New role: USER, TRAINER or ADMIN', p.role) || '').toUpperCase().trim();
      if (['USER', 'TRAINER', 'ADMIN'].indexOf(role) < 0 || role === p.role) return;
      api('/api/admin/users/' + p.id, { method: 'PATCH', body: { role: role } }).then(function () { toast('Role is now ' + role); delete state.data[key]; render(); }).catch(function (e) { toast(e.message); });
    } });
    var delBtn = h('button', { class: 'btn dng', type: 'button', text: 'Delete', onclick: function () {
      if (!confirm('Delete ' + p.name + ' and everything they logged? This cannot be undone.')) return;
      api('/api/admin/users/' + p.id, { method: 'DELETE' }).then(function () { toast('Deleted'); delete state.data[key]; delete state.data.now; location.hash = '#people'; }).catch(function (e) { toast(e.message); });
    } });
    var head = h('div', { class: 'top' }, [
      h('h1', { class: 'h1', style: 'margin:10px 0 0' }, broken ? [p.name + ' can’t be reached. ', h('em', { text: 'Their check-ins fail.' })] : [p.name + ' is reachable. ', h('em', { text: 'Notifications work.' })]),
      h('span', { class: 'sp' }),
      h('div', { class: 'acts' }, [
        act('Send a test notification', '/api/admin/ops/person/' + p.id + '/test-push', 'POST', '', { say: function (r) { return r.error ? 'Not sent: ' + r.error : r.sent + ' of ' + r.attempted + ' accepted by Apple'; } }),
        act('Reset back-off', '/api/admin/ops/person/' + p.id + '/reset-backoff', 'POST', '', { say: function () { return 'Back-off cleared'; } }),
        roleBtn, delBtn
      ])
    ]);
    var steps = p.pipeline.steps;
    var path = h('div', { class: 'path' }, steps.map(function (s, i) {
      return h('div', { class: 'node ' + (s.state === 'ok' ? 'ok' : s.state === 'no' ? 'no' : '') }, [
        h('div', { class: 'c', text: s.state === 'ok' ? '✓' : s.state === 'no' ? '!' : String(i + 1) }),
        h('h4', { text: s.title }),
        h('p', { class: s.state === 'no' ? 't-bad' : '', text: s.detail })
      ]);
    }));
    var why = broken ? h('div', { class: 'why' }, ['It breaks at step ' + (firstBad + 1) + '. ', h('em', { text: broken })]) : h('div', { class: 'why' }, ['Every step looks fine.']);
    var max = Math.max(p.chart.target * 1.1, 1);
    var chartBars = p.chart.days.map(function (day) {
      return day.kcal > 0 ? h('i', { style: 'height:' + Math.min(100, (day.kcal / max) * 100) + '%', title: day.date + ' · ' + num(day.kcal) + ' kcal' }) : h('i', { class: 'z', title: day.date });
    });
    var chart = h('div', { class: 'chart' }, [h('div', { class: 'tgt', style: 'bottom:' + Math.min(100, (p.chart.target / max) * 100) + '%' }, [h('span', { text: num(p.chart.target) })])].concat(chartBars));
    var days = h('div', { class: 'days' }, p.chart.days.map(function (day) { return h('span', { text: String(Number(day.date.slice(8))) }); }));
    var s = p.settings;
    var mt = function (m) { return pad(Math.floor(m / 60)) + ':' + pad(m % 60); };
    var facts = s ? [
      ['Meal times', s.mealTimes.map(mt).join(' · ')], ['Waits after', s.graceMin + ' minutes'], ['Quiet hours', mt(s.quiet[0]) + ' – ' + mt(s.quiet[1])],
      ['Back-off', s.backedOffUntil && new Date(s.backedOffUntil) > new Date() ? 'Until ' + dayLabel(s.backedOffUntil) : 'None'], ['Paused by them', s.paused ? 'Yes' : 'No'],
      ['Goal', s.goal.toLowerCase() + (s.targetWeightKg ? ' to ' + s.targetWeightKg + ' kg' : '')], ['Role', p.role.toLowerCase()], ['Joined', new Date(p.joined).toLocaleDateString('en-GB', { day: 'numeric', month: 'short' })]
    ] : [['Setup', 'Not finished']];
    var dl = h('dl', { class: 'dl' }, []);
    facts.forEach(function (f) { dl.appendChild(h('dt', { text: f[0] })); dl.appendChild(h('dd', { text: f[1] })); });
    var tokens = p.tokens.length ? p.tokens.map(function (t) { return t.environment + ' …' + t.tail + ' (seen ' + ago(t.lastSeenAt) + ')'; }).join('  ·  ') : 'No tokens on file';
    var log = [h('div', { class: 'h3', style: 'margin-top:56px' }, ['Their last check-ins', h('span', { text: 'what was sent, and what happened' })])];
    if (!p.checkIns.length) log.push(h('p', { class: 'empty', text: 'No check-ins yet.' }));
    p.checkIns.forEach(function (c) {
      var res = { ate: 'Ate it', answered: 'Answered', ignored: 'Ignored', failed: 'Expired' }[c.outcome];
      log.push(h('div', { class: 'lr' }, [
        h('span', { class: 'w', text: dayLabel(c.at) }),
        h('span', { class: 'm' }, [c.message || c.kind, h('small', { text: c.kind })]),
        h('span', { class: 'st ' + (c.failed ? 't-bad' : 't-good') }, [h('span', { class: 'dot ' + (c.failed ? 'd-bad' : 'd-good') }), c.delivery]),
        h('span', { class: 't-soft', text: res })
      ]));
    });
    var body = [h('div', { class: 'kick' }, [h('a', { href: '#people', text: 'People' }), ' / ' + p.name]), head,
      h('div', { class: 'h3', style: 'margin-top:44px' }, ['Why the phone stays quiet', h('span', { text: 'the path of one notification' })]), path, why,
      h('div', { class: 'two' }, [
        h('section', null, [h('div', { class: 'h3' }, ['Kcal eaten, 14 days', h('span', { text: 'dashed line is their target' })]), chart, days]),
        h('section', null, [h('div', { class: 'h3' }, ['How check-ins treat them']), dl, h('p', { class: 't-faint', style: 'margin:18px 0 0;font-size:13px', text: tokens })])
      ])].concat(log);
    return shell('people', loose, body);
  }

  // ----- Delivery -----
  function deliveryScreen() {
    var d = state.data.delivery, loose = state.data.now ? state.data.now.looseEnds.length : 0;
    if (!d) { load('delivery', '/api/admin/ops/delivery?days=7&tzOffsetMin=' + (-new Date().getTimezoneOffset())); return shell('delivery', loose, [h('p', { class: 'empty', text: 'Loading…' })]); }
    var rate = function (k) { return k.sent ? (k.ate + k.answered) / k.sent : 0; };
    var big = d.kinds.filter(function (k) { return k.sent >= 3; }).sort(function (a, b) { return rate(b) - rate(a); });
    var title = big.length >= 2 ? [big[0].label + ' work best. ', h('em', { text: big[big.length - 1].label + ' work least.' })] : [d.total + ' check-ins, last ' + d.days + ' days. ', h('em', { text: 'Not enough yet to compare.' })];
    var pc = function (n, t) { return t ? Math.round((n / t) * 100) : 0; };
    var kinds = d.kinds.map(function (k) {
      var seg = function (cls, n, label) { return n ? h('i', { class: cls, style: 'flex:' + n, text: pc(n, k.sent) >= 14 ? pc(n, k.sent) + '%' + (label ? '  ' + label : '') : '' }) : null; };
      return h('div', { class: 'k' }, [
        h('div', null, [h('h4', { text: k.label }), h('p', { text: k.sent + ' sent' })]),
        h('div', { class: 'stack' }, [seg('s-ate', k.ate, 'ate within 30 min'), seg('s-ans', k.answered, ''), seg('s-ign', k.ignored, 'ignored'), seg('s-fail', k.failed, '')]),
        h('div', { class: 'r' }, [h('b', { text: pc(k.ate + k.answered, k.sent) + '%' }), h('span', { text: 'answered' })])
      ]);
    });
    var reasons = d.reasons.length ? d.reasons.map(function (r) {
      return h('div', { class: 'fr' }, [h('b', { text: r.label }), h('div', { class: 't' }, [h('i', { style: 'width:' + pc(r.count, d.reasons[0].count) + '%' })]), h('span', { class: 'm', text: String(r.count) })]);
    }) : [h('p', { class: 'empty', text: 'Nothing failed. ' })];
    var hrs = d.answerHours.slice(7, 24), maxH = Math.max.apply(null, hrs.concat([1]));
    var failed = d.total - d.reached;
    var body = [h('div', { class: 'kick', text: 'Last ' + d.days + ' days · ' + d.total + ' check-ins' }), h('h1', { class: 'h1' }, title),
      h('div', { style: 'margin-top:40px' }, kinds.length ? kinds : [h('p', { class: 'empty', text: 'No check-ins in this range.' })]),
      h('div', { class: 'leg' }, [h('span', null, [h('i', { class: 's-ate' }), 'Answered, and a meal followed']), h('span', null, [h('i', { class: 's-ans' }), 'Answered']), h('span', null, [h('i', { class: 's-ign' }), 'Ignored or expired']), h('span', null, [h('i', { class: 's-fail' }), 'Never reached the phone'])]),
      h('div', { class: 'two2' }, [
        h('section', null, [h('div', { class: 'h3' }, ['Why ' + failed + ' never reached a phone', h('span', { text: d.days + ' days' })])].concat(reasons)),
        h('section', null, [h('div', { class: 'h3' }, ['When people answer', h('span', { text: 'answers by hour, 07:00 to 23:00' })]),
          h('div', { class: 'hrs' }, hrs.map(function (n) { return h('i', { style: 'height:' + Math.max(2, (n / maxH) * 100) + '%', title: n + ' answers' }); })),
          h('div', { class: 'hl' }, hrs.map(function (n, i) { return h('span', { text: (i % 2 === 0) ? String(7 + i) : '' }); }))])
      ])];
    return shell('delivery', loose, body);
  }

  // ----- Machine -----
  function machineScreen() {
    var m = state.data.machine, loose = state.data.now ? state.data.now.looseEnds.length : 0;
    if (!m) { load('machine', '/api/admin/ops/machine?since=' + encodeURIComponent(midnight().toISOString())); return shell('machine', loose, [h('p', { class: 'empty', text: 'Loading…' })]); }
    var bad = m.checks.filter(function (c) { return c.state === 'bad'; }), warn = m.checks.filter(function (c) { return c.state === 'warn'; });
    var title = bad.length ? ['Something is broken. ', h('em', { text: bad[0].title + '.' })] : warn.length ? ['Healthy. ', h('em', { text: warn[0].title + ' needs watching.' })] : ['All checks pass. ', h('em', { text: 'Nothing to watch.' })];
    var maxD = Math.max.apply(null, m.ai.days14.concat([0.01]));
    var cost = h('div', { class: 'hero' }, [
      h('div', { class: 'cost' }, [h('b', null, ['$' + m.ai.todayUsd.toFixed(2), h('small', { text: 'today' })]),
        h('p', { text: m.ai.todayCalls + ' AI calls. About $' + m.ai.monthUsd.toFixed(0) + ' in the last 30 days. An estimate from call counts.' + (m.ai.topUser ? ' ' + m.ai.topUser.name + ' costs the most, $' + m.ai.topUser.usd.toFixed(2) + '.' : '') }),
        h('div', { class: 'meter' }, [h('i', { style: 'width:' + Math.min(100, (m.ai.todayUsd / m.ai.budget) * 100) + '%' }), h('u'), h('span', { text: '$' + m.ai.budget + ' a day' })])]),
      h('div', null, [h('div', { class: 'days14' }, m.ai.days14.map(function (v, i) { return h('i', { class: i === 13 ? 'n' : '', style: 'height:' + Math.max(2, (v / maxD) * 100) + '%', title: '$' + v.toFixed(2) }); })), h('div', { class: 'h3', style: 'justify-content:space-between;margin:8px 0 0' }, [h('span', { text: '14 days ago' }), h('span', { text: 'today' })])])
    ]);
    var hb = dayTimelineHeartbeat(m.heartbeat);
    var cols = [[], [], []];
    m.checks.forEach(function (c, i) {
      var tone = { ok: 'd-good', warn: 'd-warn', bad: 'd-bad', off: 'd-off' }[c.state];
      cols[i % 3].push(h('div', { class: 'ci' }, [h('span', { class: 'dot ' + tone }), h('div', null, [h('h4', { text: c.title }), h('p', { text: c.detail })])]));
    });
    var body = [h('div', { class: 'kick', text: 'Machine room' }), h('h1', { class: 'h1' }, title), cost,
      h('div', { style: 'margin-top:60px' }, [h('div', { class: 'h3' }, ['Heartbeat', h('span', { text: 'scoring runs, last 6 hours' })]), hb]),
      h('div', { class: 'h3', style: 'margin-top:56px' }, ['Checks', h('span', { text: String(m.checks.length) })]),
      h('div', { class: 'chk' }, cols.map(function (c) { return h('div', null, c); }))];
    return shell('machine', loose, body);
  }
  function dayTimelineHeartbeat(hb) {
    var nowT = Date.now(), from = nowT - 6 * 3600000, span = nowT - from;
    var pct = function (t) { return Math.max(0, Math.min(100, ((t - from) / span) * 100)); };
    var runs = hb.runs.map(function (r) { return new Date(r).getTime(); }).filter(function (t) { return t >= from; }).sort(function (a, b) { return a - b; });
    var kids = runs.map(function (t) { return h('i', { class: 'run', style: 'left:' + pct(t) + '%' }); });
    var marks = runs.concat([nowT]);
    for (var i = 1; i < marks.length; i++) {
      if ((marks[i] - marks[i - 1]) / 60000 > 25) kids.push(h('div', { class: 'gap', style: 'left:' + pct(marks[i - 1]) + '%;width:' + (pct(marks[i]) - pct(marks[i - 1])) + '%' }));
    }
    var ticks = [0, 1, 2, 3, 4, 5].map(function (k) { var t = new Date(from + k * 3600000); return h('span', { style: 'left:' + (k / 6) * 100 + '%', text: pad(t.getHours()) + ':00' }); });
    return h('div', null, [
      h('div', { class: 'lane' }, [h('label', { text: 'Scoring job' }), h('div', { class: 'area' }, kids.concat([h('div', { class: 'now', style: 'left:100%' })]))]),
      h('div', { class: 'axis' }, [h('div'), h('div', null, ticks)]),
      hb.lastRunAt ? h('p', { class: 't-soft', style: 'margin:6px 0 0', text: 'Last run ' + ago(hb.lastRunAt) + (hb.durationMs != null ? ', took ' + (hb.durationMs / 1000).toFixed(1) + ' s' : '') + (hb.lastOk === false ? ', and it failed' : '') + '.' }) : h('p', { class: 'empty', text: 'No runs recorded.' })
    ]);
  }

  // ----- Access: invites and feature flags -----
  function accessScreen() {
    var loose = state.data.now ? state.data.now.looseEnds.length : 0;
    var st = state.data.status, inv = state.data.invites, fl = state.data.flags;
    if (!st || !inv || !fl) {
      if (!st) load('status', '/api/admin/status');
      if (!inv) load('invites', '/api/admin/invites');
      if (!fl) load('flags', '/api/admin/flags');
      return shell('access', loose, [h('p', { class: 'empty', text: 'Loading\u2026' })]);
    }
    var sw = st.switches;
    var onoff = function (label, v, good) { return h('span', null, [h('span', { class: 'dot ' + (v === good ? 'd-good' : 'd-off') }), label + ': ' + (v ? 'on' : 'off')]); };
    var refresh = function (key) { delete state.data[key]; render(); };
    var fail = function (e) { toast(e.message); };

    // invites
    var f = { code: h('input', { class: 'w', placeholder: 'Code, or leave empty', 'aria-label': 'Code' }), cohort: h('input', { class: 's', placeholder: 'Cohort', 'aria-label': 'Cohort' }),
      role: h('select', { 'aria-label': 'Role' }, [h('option', { value: 'USER', text: 'Person' }), h('option', { value: 'TRAINER', text: 'Trainer' }), h('option', { value: 'ADMIN', text: 'Admin' })]),
      max: h('input', { class: 's', type: 'number', min: '1', placeholder: 'Max uses', 'aria-label': 'Max uses' }), note: h('input', { class: 'w', placeholder: 'Note', 'aria-label': 'Note' }) };
    var create = h('button', { class: 'btn pri', type: 'button', text: 'Create invite', onclick: function () {
      var body = {};
      if (f.code.value.trim()) body.code = f.code.value.trim();
      if (f.cohort.value.trim()) body.cohort = f.cohort.value.trim();
      body.role = f.role.value;
      if (f.max.value) body.maxUses = Number(f.max.value);
      if (f.note.value.trim()) body.note = f.note.value.trim();
      api('/api/admin/invites', { method: 'POST', body: body }).then(function (r) { toast('Created ' + r.invite.code); refresh('invites'); }).catch(fail);
    } });
    var rows = inv.invites.map(function (i) {
      var off = !!i.disabledAt, used = i.maxUses ? i.uses + ' of ' + i.maxUses : i.uses + ' used';
      return h('tr', null, [
        h('td', { class: 'mono', text: i.code }), h('td', { text: i.cohort || '\u2013' }), h('td', { text: i.role.toLowerCase() }), h('td', { class: 'mono', text: used }),
        h('td', { text: i.expiresAt ? new Date(i.expiresAt).toLocaleDateString('en-GB', { day: 'numeric', month: 'short' }) : 'No expiry' }), h('td', { text: i.note || '' }),
        h('td', null, [off ? h('span', { class: 't-faint', text: 'Disabled' }) : h('button', { class: 'btn', type: 'button', text: 'Disable', onclick: function () {
          api('/api/admin/invites/' + encodeURIComponent(i.code) + '/disable', { method: 'POST', body: {} }).then(function () { toast('Disabled ' + i.code); refresh('invites'); }).catch(fail);
        } })])
      ]);
    });
    var table = inv.invites.length ? h('table', { class: 'tbl' }, [h('thead', null, [h('tr', null, ['Code', 'Cohort', 'Gives', 'Uses', 'Expires', 'Note', ''].map(function (t) { return h('th', { text: t }); }))]), h('tbody', null, rows)]) : h('p', { class: 'empty', text: 'No invite codes yet.' });

    // flags
    var flags = fl.flags.map(function (flag) {
      var ov = flag.override, mode = !ov ? 'default' : ov.enabled ? 'on' : 'off';
      var cohorts = h('input', { class: 'w', placeholder: 'Off, except cohorts: beta, friends', 'aria-label': 'Cohorts for ' + flag.key, value: ov && ov.cohorts ? ov.cohorts.join(', ') : '' });
      var pick = function (m) {
        var req = m === 'default' ? api('/api/admin/flags/' + flag.key, { method: 'DELETE' })
          : api('/api/admin/flags/' + flag.key, { method: 'PUT', body: m === 'on' ? { enabled: true } : { enabled: false, cohorts: cohorts.value.split(',').map(function (c) { return c.trim(); }).filter(Boolean) } });
        req.then(function () { toast('Saved ' + flag.key); refresh('flags'); }).catch(fail);
      };
      var seg = h('div', { class: 'seg' }, [['default', 'Default ' + (flag.default ? 'on' : 'off')], ['on', 'On for all'], ['off', 'Off']].map(function (m) {
        return h('button', { type: 'button', 'aria-pressed': mode === m[0] ? 'true' : 'false', text: m[1], onclick: function () { pick(m[0]); } });
      }));
      return h('div', { class: 'flag' }, [h('div', null, [h('b', { text: flag.key }), h('p', { text: flag.description })]), seg, cohorts, h('button', { class: 'btn', type: 'button', text: 'Save cohorts', onclick: function () { pick('off'); } })]);
    });

    var body = [h('div', { class: 'kick', text: 'Access' }), h('h1', { class: 'h1' }, [st.users.total + ' people. ', h('em', { text: st.users.pending + ' waiting for an invite.' })]),
      h('div', { class: 'sw' }, [onoff('Invite only', sw.inviteOnly, true), onoff('Subscription gate', sw.subscriptionGate, true), onoff('Dev login', sw.devLogin, false), onoff('Wearable modifier', sw.wearableModifier, true), h('span', { class: 't-faint', text: 'These switches are set in Vercel.' })]),
      h('div', { class: 'h3', style: 'margin-top:44px' }, ['Invite codes', h('span', { text: String(inv.invites.length) })]),
      h('div', { class: 'form' }, [f.code, f.cohort, f.role, f.max, f.note, create]), table,
      h('div', { class: 'h3', style: 'margin-top:56px' }, ['Feature flags', h('span', { text: 'who gets what, without a new build' })])].concat(flags);
    return shell('access', loose, body);
  }

  // ----- Tour: edit the in-app guided tour, shown on the app itself -----
  var TOUR_TABS = [['today', 'Today'], ['train', 'Train'], ['progress', 'Progress'], ['you', 'You']];
  var TOUR_WORDS = {
    en: { skip: 'Not now', show: 'Show me', back: 'Back', next: 'Next', done: 'Done', of: ' of ' },
    he: { skip: 'לא עכשיו', show: 'הראה לי', back: 'חזרה', next: 'הבא', done: 'סיום', of: ' מתוך ' }
  };
  function tourScreen() {
    var loose = state.data.now ? state.data.now.looseEnds.length : 0;
    var d = state.data.tour;
    if (!d) { load('tour', '/api/admin/tour'); return shell('tour', loose, [h('p', { class: 'empty', text: 'Loading…' })]); }
    if (!state.tw) state.tw = { steps: JSON.parse(JSON.stringify(d.tour.steps)), revision: d.tour.revision, sel: 0, dirty: false, bump: false, lang: 'en', closed: false, picking: false, pickTab: null };
    var tw = state.tw, anchors = d.anchors, byId = {};
    anchors.forEach(function (a) { byId[a.id] = a; });
    var redo = function () { var y = window.scrollY; render(); window.scrollTo(0, y); };
    var saveBtn = null, stateEl = null;
    var touch = function () {
      tw.dirty = true;
      if (saveBtn) saveBtn.disabled = false;
      if (stateEl) { stateEl.className = 'state dirty'; stateEl.lastChild.textContent = 'Unsaved changes'; }
    };
    var fail = function (e) { toast(e.message); };
    function step() { return tw.steps[tw.sel]; }
    function tabOf(s) { return s && s.anchor && byId[s.anchor] ? byId[s.anchor].tab : null; }

    // ---- the phone: screenshots of the app, with the tour drawn the way the app draws it
    var ph = document.getElementById('phone-tpl').content.firstElementChild.cloneNode(true);
    var scr = ph.querySelector('.screen'), layer = ph.querySelector('#tour'), hl = ph.querySelector('#hl'), pop = ph.querySelector('#pop'), arrow = ph.querySelector('#pop-arrow');
    var q = function (sel) { return ph.querySelector(sel); };
    var refW = d.screen[0], refH = d.screen[1], curTab = 'today';
    var hits = q('#hits');
    anchors.forEach(function (a) {
      if (!a.frame) return;
      hits.appendChild(h('button', { type: 'button', class: 'hit', 'data-anchor': a.id, 'aria-label': a.label,
        style: 'left:' + a.frame[0] + 'px;top:' + a.frame[1] + 'px;width:' + a.frame[2] + 'px;height:' + a.frame[3] + 'px;border-radius:' + a.radius + 'px' }));
    });
    function setTab(name) {
      curTab = name;
      Array.prototype.forEach.call(ph.querySelectorAll('.shot'), function (p) { p.classList.toggle('on', p.dataset.pane === name); });
      Array.prototype.forEach.call(ph.querySelectorAll('.hit'), function (b) { var a = byId[b.dataset.anchor]; b.classList.toggle('on', a.id === 'nav.plus' || a.tab === name); });
    }
    function words(s) { return (tw.lang === 'he' && s.he && s.he.title && s.he.body) ? s.he : s; }
    function realCount() { return tw.steps.filter(function (x) { return !x.welcome; }).length; }
    function realIndex() { return tw.steps.slice(0, tw.sel + 1).filter(function (x) { return !x.welcome; }).length; }
    function renderPop() {
      var s = step(); if (!s) return;
      var w = words(s), L = TOUR_WORDS[tw.lang], last = tw.sel === tw.steps.length - 1;
      pop.dir = tw.lang === 'he' ? 'rtl' : 'ltr';
      q('#pop-title').textContent = w.title || '…';
      q('#pop-body').textContent = w.body || '';
      var dots = q('#pop-dots'); clear(dots);
      if (!s.welcome) for (var k = 1; k <= realCount(); k++) dots.appendChild(h('i', { class: k <= realIndex() ? 'on' : '' }));
      dots.hidden = !!s.welcome;
      q('#pop-count').textContent = s.welcome ? '' : realIndex() + L.of + realCount();
      q('#pop-back').textContent = s.welcome ? L.skip : L.back;
      var nx = q('#pop-next'); clear(nx); nx.appendChild(h('i')); nx.appendChild(document.createTextNode(s.welcome ? L.show : last ? L.done : L.next));
    }
    var lastBase = null, nudgeEl = null, nudgeReset = null;
    function place() {
      var s = step(); if (!s || layer.hidden) return;
      var W = scr.offsetWidth, H = scr.offsetHeight;
      var pw = Math.min(284, W - 32); pop.style.width = pw + 'px';
      var ph2 = pop.getBoundingClientRect().height / (scr.getBoundingClientRect().width / scr.offsetWidth), top, left, rawTop, rawLeft, sideNow = null, rect = null;
      var a = s.anchor ? byId[s.anchor] : null;
      if (a && a.frame) {
        var k = W / refW, pad = a.pad;
        rect = { l: (a.frame[0] - pad) * k, t: (a.frame[1] - pad) * k, w: (a.frame[2] + pad * 2) * k, h: (a.frame[3] + pad * 2) * k };
        hl.style.left = rect.l + 'px'; hl.style.top = rect.t + 'px'; hl.style.width = rect.w + 'px'; hl.style.height = rect.h + 'px'; hl.style.borderRadius = (a.radius * k) + 'px';
        var gap = 16, below = refH - (rect.t + rect.h) - gap - 8, above = rect.t - gap - 56;
        var want = s.side || 'auto';
        var under = want === 'below' ? true : want === 'above' ? false : (below >= ph2 || (above < ph2 && below > above));
        rawTop = under ? rect.t + rect.h + gap : rect.t - gap - ph2;
        rawLeft = rect.l + rect.w / 2 - pw / 2;
        top = Math.max(58, Math.min(H - ph2 - 24, rawTop));
        left = Math.max(16, Math.min(W - pw - 16, rawLeft));
        sideNow = under;
      } else {
        hl.style.left = W / 2 + 'px'; hl.style.top = H / 2 + 'px'; hl.style.width = '0px'; hl.style.height = '0px';
        top = (H - ph2) / 2 - 30; left = (W - pw) / 2; rawTop = top; rawLeft = left;
      }
      // A nudge counts from the tip's spot against its element, not from where the phone's
      // bottom edge would push it, so it lands the same on a phone of any height.
      lastBase = { rawLeft: rawLeft, rawTop: rawTop, left: left, top: top, under: sideNow };
      var nudged = (s.dx || 0) !== 0 || (s.dy || 0) !== 0;
      var nl = nudged ? Math.max(16, Math.min(W - pw - 16, rawLeft + (s.dx || 0))) : left;
      var nt = nudged ? Math.max(58, Math.min(H - ph2 - 24, rawTop + (s.dy || 0))) : top;
      pop.style.left = nl + 'px'; pop.style.top = nt + 'px';
      var arrowSide = null;
      if (rect) { if (nt >= rect.t + rect.h - 2) arrowSide = 'bottom'; else if (nt + ph2 <= rect.t + 2) arrowSide = 'top'; }
      if (arrowSide) {
        arrow.hidden = false;
        arrow.style.left = (Math.max(22, Math.min(pw - 22, rect.l + rect.w / 2 - nl)) - 7) + 'px';
        arrow.style.top = arrowSide === 'bottom' ? '-5px' : 'auto'; arrow.style.bottom = arrowSide === 'top' ? '-5px' : 'auto';
      } else arrow.hidden = true;
    }
    function apply() {
      var s = step(), showing = !!s && !tw.closed && !tw.picking;
      setTab(showing ? (tabOf(s) || 'today') : (tw.pickTab || tabOf(s) || curTab));
      layer.hidden = !showing;
      if (showing) { renderPop(); place(); }
    }
    var listEls = [];
    function choose(i) {
      tw.sel = Math.max(0, Math.min(tw.steps.length - 1, i)); tw.closed = false; tw.picking = false; tw.pickTab = null;
      redo();
    }
    function close() { tw.closed = true; layer.hidden = true; }
    q('#pop-next').addEventListener('click', function (e) { e.stopPropagation(); tw.sel >= tw.steps.length - 1 ? close() : choose(tw.sel + 1); });
    q('#pop-back').addEventListener('click', function (e) { e.stopPropagation(); (step() && step().welcome) || tw.sel === 0 ? close() : choose(tw.sel - 1); });
    q('#pop-x').addEventListener('click', function (e) { e.stopPropagation(); close(); });
    layer.addEventListener('click', close);
    pop.addEventListener('click', function (e) { e.stopPropagation(); });
    // drag the tip to nudge it; the app moves it by the same amount from its own spot
    pop.addEventListener('pointerdown', function (e) {
      if (e.button !== 0 || e.target.closest('button') || !lastBase) return;
      var s = step(); if (!s) return;
      var k = scr.getBoundingClientRect().width / scr.offsetWidth, sx = e.clientX, sy = e.clientY;
      var was = (s.dx || 0) !== 0 || (s.dy || 0) !== 0;
      var d0x = was ? s.dx : lastBase.left - lastBase.rawLeft, d0y = was ? s.dy : lastBase.top - lastBase.rawTop;
      var side0 = s.side, dx0 = s.dx || 0, dy0 = s.dy || 0;
      pop.classList.add('fresh'); pop.classList.add('grabbing'); pop.setPointerCapture(e.pointerId);
      var move = function (ev) {
        s.dx = d0x + (ev.clientX - sx) / k; s.dy = d0y + (ev.clientY - sy) / k;
        place();
        s.dx = Math.round(parseFloat(pop.style.left) - lastBase.rawLeft); s.dy = Math.round(parseFloat(pop.style.top) - lastBase.rawTop);
        // pin the side the tip sits on, so a phone with more or less room doesn't flip it
        if (lastBase.under !== null && (!s.side || s.side === 'auto')) s.side = lastBase.under ? 'below' : 'above';
        showNudge();
      };
      var up = function () {
        pop.removeEventListener('pointermove', move); pop.removeEventListener('pointerup', up); pop.removeEventListener('pointercancel', up);
        pop.classList.remove('grabbing'); requestAnimationFrame(function () { pop.classList.remove('fresh'); });
        if (s.dx !== dx0 || s.dy !== dy0 || s.side !== side0) touch();
      };
      pop.addEventListener('pointermove', move); pop.addEventListener('pointerup', up); pop.addEventListener('pointercancel', up);
      e.preventDefault();
    });
    function showNudge() {
      var s = step(); if (!nudgeEl || !s) return;
      var moved = (s.dx || 0) !== 0 || (s.dy || 0) !== 0;
      nudgeEl.textContent = moved ? 'Moved ' + (s.dx || 0) + ', ' + (s.dy || 0) : 'Not moved';
      if (nudgeReset) nudgeReset.disabled = !moved;
    }
    Array.prototype.forEach.call(ph.querySelectorAll('.tabhit'), function (t) { t.addEventListener('click', function () { if (!tw.picking) { tw.closed = true; layer.hidden = true; } tw.pickTab = t.dataset.tab; setTab(t.dataset.tab); }); });
    scr.addEventListener('click', function (e) {
      if (!tw.picking) return;
      var t = e.target.closest('[data-anchor]'); if (!t) return;
      e.preventDefault(); e.stopPropagation();
      tw.picking = false; setAnchor(tw.sel, t.dataset.anchor);
    }, true);

    // ---- changing the steps
    function move(i, dir) { var j = i + dir; if (j < 0 || j >= tw.steps.length) return; var t = tw.steps[i]; tw.steps[i] = tw.steps[j]; tw.steps[j] = t; tw.sel = j; tw.closed = false; touch(); redo(); }
    function dropAt(from, to) { if (from === to) return; var t = tw.steps.splice(from, 1)[0]; tw.steps.splice(to, 0, t); tw.sel = to; tw.closed = false; touch(); redo(); }
    function remove(i) { tw.steps.splice(i, 1); tw.sel = Math.max(0, Math.min(tw.sel, tw.steps.length - 1)); tw.closed = false; touch(); redo(); }
    function add() {
      var first = anchors.filter(function (a) { return a.tab === curTab; })[0];
      tw.steps.push({ id: 's' + Date.now().toString(36) + Math.floor(Math.random() * 1000).toString(36), anchor: first ? first.id : null, welcome: false, title: 'New step', body: 'Say what this does in one line.', he: null });
      tw.sel = tw.steps.length - 1; tw.closed = false; tw.pickTab = null; touch(); redo();
    }
    function setAnchor(i, id) { tw.steps[i].anchor = id || null; if (id) tw.steps[i].welcome = false; tw.closed = false; tw.pickTab = null; touch(); redo(); }
    var live = function () { if (!layer.hidden) { renderPop(); place(); } };
    function sub(s) { return s.welcome ? 'Opening prompt' : s.anchor && byId[s.anchor] ? byId[s.anchor].label : 'Shown in the middle'; }

    // ---- left: the steps
    var dragFrom = null;
    var TAB_DOT = { today: '#FF7A3D', train: '#818CF8', progress: '#FFB86B', you: '#86EFAC' };
    var items = tw.steps.map(function (s, i) {
      var missing = !s.welcome && !(s.he && s.he.title && s.he.body);
      var tab = tabOf(s);
      var item = h('li', null, [h('div', { class: 'ts' + (tw.sel === i ? ' sel' : ''), role: 'button', tabindex: '0', draggable: 'true', title: sub(s), 'aria-label': 'Step ' + (i + 1) + ': ' + s.title + ', ' + sub(s),
        onclick: function () { choose(i); },
        onkeydown: function (e) {
          if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); choose(i); }
          else if (e.key === 'ArrowDown' && e.altKey) { e.preventDefault(); move(i, 1); }
          else if (e.key === 'ArrowUp' && e.altKey) { e.preventDefault(); move(i, -1); }
        },
        ondragstart: function (e) { dragFrom = i; e.dataTransfer.effectAllowed = 'move'; try { e.dataTransfer.setData('text/plain', String(i)); } catch (x) {} },
        ondragover: function (e) { if (dragFrom === null) return; e.preventDefault(); e.currentTarget.classList.add('over'); },
        ondragleave: function (e) { e.currentTarget.classList.remove('over'); },
        ondrop: function (e) { e.preventDefault(); var from = dragFrom; dragFrom = null; if (from !== null) dropAt(from, i); },
        ondragend: function () { dragFrom = null; }
      }, [h('span', { class: 'n', text: s.welcome ? '\u00b7' : String(i) }), h('span', { class: 'dotc', style: 'background:' + (tab ? TAB_DOT[tab] : 'transparent') + (tab ? '' : ';border:1.5px solid var(--faint)') }), h('span', { class: 'tt', text: s.title || 'Untitled' }), missing ? h('span', { class: 'badge', title: 'No Hebrew yet, people on Hebrew see English', text: 'HE' }) : null])]);
      listEls.push(item.firstChild);
      return item;
    });
    var leftCol = h('div', { class: 'tr-col tr-left' }, [
      h('div', { class: 'h3', style: 'margin:0 0 8px', title: 'Drag to reorder, or Alt with the arrow keys. A red HE means no Hebrew yet.' }, ['Steps', h('span', { text: String(tw.steps.length) })]),
      h('ul', { class: 'ts-list' }, items),
      h('button', { class: 'btn ts-add', type: 'button', text: '+ Add a step', onclick: add })
    ]);

    // ---- middle: the phone
    var fitBox = h('div', { class: 'tr-fit' }, [ph]);
    var midCol = h('div', { class: 'tr-col tr-mid' }, [fitBox]);
    // the phone shrinks to the height that is left, so the whole page fits the screen
    function fit() {
      if (!midCol.isConnected) return;
      var availH = midCol.clientHeight, availW = midCol.clientWidth;
      var k = Math.max(0.4, Math.min(1, availH / 874, availW / 402));
      fitBox.style.width = Math.round(402 * k) + 'px'; fitBox.style.height = Math.round(874 * k) + 'px';
      ph.style.transform = 'scale(' + k + ')'; ph.style.transformOrigin = '0 0';
    }
    window.__tourFit = fit;

    // ---- right: the selected step
    var s = step(), right;
    if (!s) {
      right = h('div', { class: 'tr-empty' }, [h('p', { style: 'margin:0 0 14px', text: 'No steps yet. People will not see a tour until you add one.' }), h('button', { class: 'btn pri', type: 'button', text: '+ Add the first step', onclick: add })]);
    } else {
      var he = tw.lang === 'he';
      var field = function () { if (!he) return s; if (!s.he) s.he = { title: '', body: '' }; return s.he; };
      var cur = field();
      var titleIn = h('input', { type: 'text', class: 'ti', maxlength: '60', 'aria-label': 'Title', value: cur.title || '', placeholder: he ? 'English is shown when this is empty' : '' });
      var bodyIn = h('textarea', { maxlength: '260', 'aria-label': 'Text', placeholder: he ? 'English is shown when this is empty' : '' }); bodyIn.value = cur.body || '';
      var tCnt = h('span', { class: 'cnt', text: (cur.title || '').length + '/60' }), bCnt = h('span', { class: 'cnt', text: (cur.body || '').length + '/260' });
      titleIn.addEventListener('input', function () { field().title = titleIn.value; tCnt.textContent = titleIn.value.length + '/60'; touch(); live(); var t = listEls[tw.sel] && listEls[tw.sel].querySelector('.tt'); if (t && !he) t.textContent = titleIn.value || 'Untitled'; });
      bodyIn.addEventListener('input', function () { field().body = bodyIn.value; bCnt.textContent = bodyIn.value.length + '/260'; touch(); live(); });

      var pickTab = tw.pickTab || tabOf(s) || 'today';
      var tabSegs = h('div', { class: 'segs' }, TOUR_TABS.map(function (t) {
        return h('button', { class: 'chip', type: 'button', 'aria-pressed': pickTab === t[0] ? 'true' : 'false', text: t[1], onclick: function () { tw.pickTab = t[0]; tw.closed = true; tw.picking = false; redo(); } });
      }));
      var opts = anchors.filter(function (a) { return a.tab === pickTab; }).map(function (a) {
        return h('button', { class: 'opt', type: 'button', 'aria-pressed': s.anchor === a.id ? 'true' : 'false', onclick: function () { setAnchor(tw.sel, a.id); } }, [h('i'), a.label]);
      });
      opts.push(h('button', { class: 'opt', type: 'button', 'aria-pressed': !s.anchor ? 'true' : 'false', onclick: function () { setAnchor(tw.sel, null); } }, [h('i'), 'Nothing, show in the middle']));
      var ck = h('input', { type: 'checkbox', id: 'tr-welcome', onchange: function (e) {
        tw.steps.forEach(function (x) { x.welcome = false; }); s.welcome = e.target.checked; if (s.welcome) s.anchor = null; touch(); redo();
      } }); ck.checked = !!s.welcome;
      var pickBtn = h('button', { class: 'btn' + (tw.picking ? ' pri' : ''), type: 'button', text: tw.picking ? 'Click an element on the phone… (cancel)' : 'Pick on the phone', onclick: function () { tw.picking = !tw.picking; if (tw.picking) tw.pickTab = tw.pickTab || tabOf(s) || 'today'; redo(); } });

      var sideBtn = function (v, label) {
        return h('button', { class: 'chip', type: 'button', 'aria-pressed': (s.side || 'auto') === v ? 'true' : 'false', text: label, onclick: function () { s.side = v; s.dx = 0; s.dy = 0; touch(); redo(); } });
      };
      nudgeEl = h('span', { class: 'cnt' });
      nudgeReset = h('button', { class: 'mini', type: 'button', text: 'Put back', onclick: function () { s.dx = 0; s.dy = 0; touch(); showNudge(); live(); } });
      var posSec = h('div', { class: 'sec' }, [h('div', { class: 'lab' }, ['Tip position', nudgeEl]),
        h('div', { class: 'segs' }, (s.anchor ? [sideBtn('auto', 'Auto'), sideBtn('above', 'Above'), sideBtn('below', 'Below')] : []).concat([nudgeReset])),
        h('p', { class: 'hint', text: 'Or drag the tip on the phone to nudge it.' })]);
      right = h('div', { class: 'tr-edit' }, [
        h('div', { class: 'top' }, [h('h2', { text: s.welcome ? 'Opening prompt' : 'Step ' + tw.sel }), h('span', { class: 'sp' }),
          h('button', { class: 'mini', type: 'button', 'aria-label': 'Move up', disabled: tw.sel === 0, onclick: function () { move(tw.sel, -1); }, text: '↑' }),
          h('button', { class: 'mini', type: 'button', 'aria-label': 'Move down', disabled: tw.sel === tw.steps.length - 1, onclick: function () { move(tw.sel, 1); }, text: '↓' }),
          h('button', { class: 'mini dng', type: 'button', onclick: function () { remove(tw.sel); }, text: 'Remove' })]),
        s.welcome ? h('p', { class: 'hint', text: 'This one has no element. It asks “Show me / Not now” before the tour starts.' }) :
          h('div', { class: 'sec' }, [h('div', { class: 'lab', text: 'Points at' }), tabSegs, h('div', { class: 'opts' }, opts), pickBtn]),
        posSec,
        h('div', { class: 'sec' + (he ? ' he' : '') }, [h('label', null, ['Title' + (he ? ' (עברית)' : ''), tCnt]), titleIn]),
        h('div', { class: 'sec' + (he ? ' he' : '') }, [h('label', null, ['Text' + (he ? ' (עברית)' : ''), bCnt]), bodyIn]),
        h('label', { class: 'ck', for: 'tr-welcome' }, [ck, 'Make this the opening prompt'])
      ]);
    }
    var rightCol = h('div', { class: 'tr-col tr-right' }, [right]);

    // ---- the top bar: the one place to save
    saveBtn = h('button', { class: 'btn pri', type: 'button', text: 'Save tour', disabled: !tw.dirty, onclick: function () {
      saveBtn.disabled = true;
      api('/api/admin/tour', { method: 'PUT', body: { steps: tw.steps, bumpRevision: tw.bump } }).then(function () {
        toast('Saved. The app picks it up on next launch.'); delete state.data.tour; state.tw = null; render();
      }).catch(function (e) { saveBtn.disabled = false; fail(e); });
    } });
    stateEl = h('span', { class: 'state' + (tw.dirty ? ' dirty' : '') }, [h('i'), document.createTextNode(tw.dirty ? 'Unsaved changes' : 'Saved')]);
    var bump = h('input', { type: 'checkbox', id: 'tr-bump', onchange: function (e) { tw.bump = e.target.checked; touch(); } }); bump.checked = tw.bump;
    var armed = false;
    var resetBtn = h('button', { class: 'btn', type: 'button', text: 'Reset to defaults', onclick: function () {
      if (!armed) { armed = true; resetBtn.textContent = 'Click again to reset'; resetBtn.classList.add('dng'); setTimeout(function () { armed = false; resetBtn.textContent = 'Reset to defaults'; resetBtn.classList.remove('dng'); }, 3500); return; }
      api('/api/admin/tour', { method: 'DELETE' }).then(function () { toast('Back to the built-in tour'); delete state.data.tour; state.tw = null; render(); }).catch(fail);
    } });
    var langBtn = function (code, label) { return h('button', { class: 'chip', type: 'button', 'aria-pressed': tw.lang === code ? 'true' : 'false', text: label, onclick: function () { tw.lang = code; redo(); } }); };
    var langRow = h('div', { class: 'segs', role: 'group', 'aria-label': 'Preview language' }, [langBtn('en', 'English'), langBtn('he', '\u05e2\u05d1\u05e8\u05d9\u05ea')]);
    var head = h('div', { class: 'tr-head' }, [
      h('h1', { text: 'Guided tour', title: 'What a new person sees once after setup, and again from You, How SetPoint works. Changes reach the app on its next launch, no build needed.' }),
      h('span', { class: 'meta', text: tw.revision > 1 ? 'Shown again ' + (tw.revision - 1) + ' time' + (tw.revision > 2 ? 's' : '') : 'Never re-shown' }),
      h('span', { class: 'sp' }), langRow, stateEl,
      h('label', { class: 'ck', for: 'tr-bump' }, [bump, 'Show again to everyone who has seen it']),
      resetBtn, saveBtn
    ]);

    var body = [h('div', { class: 'tr-app' }, [head, h('div', { class: 'tr3' }, [leftCol, midCol, rightCol])])];
    setTimeout(function () { fit(); apply(); showNudge(); }, 0);
    if (document.fonts && document.fonts.ready) document.fonts.ready.then(function () { fit(); place(); });
    return shell('tour', loose, body);
  }

  window.addEventListener('resize', function () { if (window.__tourFit) window.__tourFit(); });

${USAGE_JS}
  // ----- loading + render -----
  function load(key, path) {
    if (state.data['_loading:' + key]) return;
    state.data['_loading:' + key] = true;
    api(path).then(function (d) { state.data[key] = d; }).catch(function (e) { if (e.message !== 'Signed out') toast(e.message); }).then(function () { delete state.data['_loading:' + key]; if (state.secret) render(); });
  }
  function render() {
    clear(root);
    peopleHost = null;
    if (!state.secret) { root.appendChild(signIn()); return; }
    var r = route();
    if (!state.data.now && !state.data['_loading:now']) load('now', '/api/admin/ops/now?since=' + encodeURIComponent(midnight().toISOString()));
    var view = r.name === 'now' ? nowScreen() : r.name === 'people' ? peopleScreen() : r.name === 'person' ? personScreen(r.id) : r.name === 'usage' ? usageScreen() : r.name === 'delivery' ? deliveryScreen() : r.name === 'access' ? accessScreen() : r.name === 'tour' ? tourScreen() : machineScreen();
    root.appendChild(view);
  }

  try { state.secret = sessionStorage.getItem(KEY); } catch (e) {}
  render();
})();
</script>
</body>
</html>`;
