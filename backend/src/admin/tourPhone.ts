/**
 * The phone drawn in the Tour tab of /admin: the app's own screens (Today, Train, Progress,
 * You) and the tour tip exactly as the app draws them, so editing a step shows what people
 * will see. Static markup and styles; opsPage.ts runs the spotlight over it.
 * Every style is scoped under `.ph` so nothing leaks into the dashboard.
 */
export const PHONE_CSS = String.raw`.ph{--bg:#09090b;--panel:#131316;--sunk:#1a1a1d;--ink:#f5f5f4;--soft:#a1a1aa;--faint:#8b8b94;--ember:#ff7a3d;--amber:#ffb86b;--haze:#818cf8;--haze-soft:#c7d2fe;--good:#86efac;--glass:rgba(255,255,255,.045);--glass-hi:rgba(255,255,255,.08);--hair:rgba(255,255,255,.09);--sans:-apple-system,"SF Pro Text","SF Pro Display","Geist",ui-sans-serif,system-ui,"Helvetica Neue",sans-serif;--mono:ui-monospace,"SF Mono","Geist Mono",Menlo,monospace;--dim:.72;font-family:var(--sans);font-size:15px;line-height:normal;color:var(--ink);-webkit-font-smoothing:antialiased}
.ph *{box-sizing:border-box}
.ph button{font:inherit;color:inherit;cursor:pointer}
.ph h1,.ph h2,.ph h3,.ph h4,.ph p{margin:0}
/* the dashboard has classes with these names; the phone starts from nothing */
.ph .hl,.ph .k,.ph .st,.ph .stack,.ph .top,.ph .legend,.ph .acts{all:unset}
.ph .phone{
  position: relative;
  width: 390px;
  max-width: 100%;
  height: 812px;
  border-radius: 54px;
  padding: 10px;
  background: #1b1b1f;
  box-shadow: 0 0 0 1px rgba(255,255,255,.1), 0 40px 90px rgba(0,0,0,.6);
}
.ph .screen{
  position: relative;
  height: 100%;
  border-radius: 44px;
  overflow: hidden;
  background: var(--bg);
  isolation: isolate;
}
.ph .island{
  position: absolute; z-index: 5; top: 11px; left: 50%; translate: -50% 0;
  width: 104px; height: 30px; border-radius: 20px; background: #000;
}
.ph .status{
  position: absolute; z-index: 4; inset: 0 0 auto; height: 52px;
  display: flex; align-items: center; justify-content: space-between;
  padding: 6px 30px 0; font-size: 15px; font-weight: 500;
  background: linear-gradient(var(--bg) 55%, transparent);
}
.ph .status svg{ display: block; }
.ph .glow{
  position: absolute; z-index: 0; inset: -80px -40px auto; height: 420px;
  background:
    radial-gradient(closest-side at 42% 46%, rgba(255,122,61,.26), transparent),
    radial-gradient(closest-side at 84% 70%, rgba(129,140,248,.14), transparent);
  pointer-events: none;
}
.ph .screen[data-tone="haze"] .glow{ background: radial-gradient(closest-side at 50% 46%, rgba(129,140,248,.2), transparent), radial-gradient(closest-side at 80% 20%, rgba(199,210,254,.07), transparent); }
.ph .screen[data-tone="ember"] .glow{ background: radial-gradient(closest-side at 46% 40%, rgba(255,122,61,.34), transparent), radial-gradient(closest-side at 90% 62%, rgba(129,140,248,.12), transparent); }
.ph .pane{
  position: absolute; inset: 0; z-index: 1; display: none;
  overflow-y: auto; scrollbar-width: none;
  padding: 62px 16px 130px;
}
.ph .pane::-webkit-scrollbar{ display: none; }
.ph .pane.on{ display: flex; flex-direction: column; gap: 12px; animation: paneIn .28s ease both; }
@keyframes paneIn{ from { opacity: 0; } to { opacity: 1; } }
.ph .label{ font-family: var(--mono); font-size: 11px; letter-spacing: .13em; text-transform: uppercase; color: var(--faint); }
.ph .label.amber{ color: var(--amber); }
.ph .label.haze{ color: var(--haze-soft); }
.ph .head{ margin: 0; font-size: 31px; line-height: 1.08; font-weight: 300; letter-spacing: -.035em; }
.ph .head span{ color: var(--faint); }
.ph .card{ border-radius: 26px; background: var(--glass); border: 1px solid var(--hair); padding: 18px; }
.ph .mono{ font-family: var(--mono); }
.ph .orb3d{ border-radius: 50%; background: radial-gradient(circle at 36% 30%, #ffe2b0 0, #ffa862 9%, #f06a2e 30%, #7a3016 62%, #2a110a 92%); box-shadow: 0 0 60px rgba(255,122,61,.35); }
.ph .glass{ border-radius: 28px; background: rgba(255,255,255,.035); border: 1px solid var(--hair); }
.ph .mlabel{ font-family: var(--mono); font-size: 11px; letter-spacing: .14em; text-transform: uppercase; color: var(--faint); }
.ph .circle{ width: 44px; height: 44px; border-radius: 50%; display: grid; place-items: center; border: 1px solid var(--hair); background: rgba(255,255,255,.06); flex: none; }
.ph .outline{ height: 40px; padding: 0 16px; border-radius: 999px; display: inline-flex; align-items: center; gap: 8px; font-size: 15px; border: 1px solid rgba(129,140,248,.55); background: rgba(129,140,248,.14); color: var(--haze-soft); }
.ph .bonebtn{ height: 40px; padding: 0 18px; border-radius: 999px; background: var(--ink); color: #09090b; font-weight: 500; font-size: 15px; display: inline-flex; align-items: center; }
.ph .dayhead b{ display: block; font-size: 25px; font-weight: 400; letter-spacing: -.02em; }
.ph .orbwrap{ position: relative; align-self: center; flex: none; width: 250px; height: 250px; margin: 6px 0 0; display: grid; place-items: center; }
.ph .orbwrap svg{ position: absolute; inset: 0; }
.ph .orbwrap .orb3d{ width: 188px; height: 188px; display: grid; place-items: center; text-align: center; }
.ph .orbwrap .num{ font-size: 62px; font-weight: 300; letter-spacing: -.045em; line-height: 1; text-shadow: 0 2px 14px rgba(0,0,0,.35); }
.ph .orbwrap .of{ font-family: var(--mono); font-size: 13px; margin-top: 6px; color: #fde6cf; }
.ph .pacepill{ align-self: center; display: inline-flex; align-items: center; gap: 9px; height: 42px; padding: 0 16px; border-radius: 999px; border: 1px solid var(--hair); background: rgba(255,255,255,.04); font-size: 15px; }
.ph .pacepill i{ width: 3px; height: 15px; border-radius: 2px; background: var(--ember); }
.ph .pacepill span{ color: var(--soft); }
.ph .nextcard{ padding: 18px 18px 16px; }
.ph .nextcard .top{ display: flex; justify-content: space-between; align-items: baseline; gap: 8px; }
.ph .nextcard .kc{ font-family: var(--mono); font-size: 13px; color: var(--amber); }
.ph .nextcard h2{ margin: 12px 0 14px; font-size: 25px; line-height: 1.12; font-weight: 300; letter-spacing: -.035em; }
.ph .nextcard h2 span{ color: var(--faint); }
.ph .acts{ display: flex; align-items: center; gap: 10px; }
.ph .acts .link{ flex: 1; text-align: center; color: var(--soft); font-size: 16px; }
.ph .daydots{ position: relative; height: 54px; margin: 8px 4px 0; }
.ph .daydots .ln{ position: absolute; left: 12%; right: 12%; top: 11px; height: 1.5px; background: rgba(255,255,255,.14); }
.ph .daydots .d{ position: absolute; top: 0; width: 22px; height: 22px; translate: -50% 0; border-radius: 50%; }
.ph .daydots .d.on{ background: radial-gradient(circle at 35% 30%, #ffe0b8, #ffb86b 60%, #f59a45); box-shadow: 0 0 14px rgba(255,184,107,.55); }
.ph .daydots .d.off{ border: 1.5px solid rgba(255,255,255,.5); background: var(--bg); }
.ph .daydots .t{ position: absolute; top: 34px; translate: -50% 0; font-family: var(--mono); font-size: 12px; color: var(--soft); }
.ph .mealrow{ display: flex; align-items: center; gap: 12px; height: 54px; padding: 0 16px; border-radius: 22px; border: 1px solid var(--hair); background: rgba(255,255,255,.035); }
.ph .mealrow small{ font-family: var(--mono); font-size: 11px; color: var(--faint); width: 56px; }
.ph .mealrow b{ flex: 1; font-weight: 400; font-size: 16px; }
.ph .mealrow span{ font-family: var(--mono); font-size: 14px; color: var(--soft); }
.ph .topbar{ position: relative; display: flex; align-items: center; height: 46px; }
.ph .topbar .mlabel{ position: absolute; left: 0; right: 0; text-align: center; }
.ph .trhead{ display: flex; align-items: center; justify-content: space-between; margin-top: 6px; }
.ph .addc{ width: 46px; height: 46px; border-radius: 50%; display: grid; place-items: center; background: #1a1c3a; border: 1.5px solid rgba(129,140,248,.6); color: var(--haze-soft); }
.ph .weekcard{ padding: 16px; }
.ph .weekcard .hd{ display: flex; align-items: center; justify-content: space-between; }
.ph .weekcard .hd b{ display: block; font-weight: 400; font-size: 17px; }
.ph .weekcard .hd .circle{ width: 40px; height: 40px; }
.ph .wk{ display: grid; grid-template-columns: repeat(7, 1fr); gap: 2px; margin: 16px -4px 12px; text-align: center; }
.ph .wk div{ padding: 8px 0 8px; border-radius: 16px; display: flex; flex-direction: column; align-items: center; gap: 4px; }
.ph .wk .l{ font-family: var(--mono); font-size: 11px; color: var(--soft); }
.ph .wk .n{ font-size: 20px; font-weight: 400; }
.ph .wk .sel{ background: #f5f5f4; color: #09090b; }
.ph .wk .sel .l{ color: #52525b; }
.ph .wk i{ width: 6px; height: 6px; border-radius: 50%; }
.ph .wk .a{ background: var(--amber); }
.ph .wk .r{ background: #d2501a; }
.ph .wk .h{ border: 1.5px solid var(--haze-soft); }
.ph .weekcard .sum{ font-size: 14px; color: var(--soft); }
.ph .daycard{ padding: 18px; background: linear-gradient(170deg, #1b1d3b, #101120 70%); border-color: rgba(129,140,248,.3); border-radius: 30px; }
.ph .daycard .hd{ display: flex; align-items: center; gap: 12px; }
.ph .daycard .ic{ width: 46px; height: 46px; border-radius: 14px; background: #272a58; display: grid; place-items: center; color: var(--haze-soft); }
.ph .daycard .hd b{ display: block; font-weight: 400; font-size: 18px; }
.ph .daycard .hd span{ font-size: 14px; color: var(--soft); }
.ph .daycard h2{ margin: 16px 0 12px; font-size: 32px; font-weight: 300; letter-spacing: -.04em; }
.ph .stack{ display: flex; height: 12px; border-radius: 6px; overflow: hidden; gap: 3px; }
.ph .stack i{ display: block; }
.ph .stack .n{ width: 85%; background: #d4d4d8; border-radius: 6px 0 0 6px; }
.ph .stack .t{ flex: 1; background: linear-gradient(90deg, #6f78e8, #a5b0ff); border-radius: 0 6px 6px 0; }
.ph .stackl{ display: flex; justify-content: space-between; margin-top: 8px; font-size: 13px; color: var(--soft); font-family: var(--mono); }
.ph .stackl .tr{ color: var(--haze-soft); }
.ph .stackl .td{ color: var(--amber); }
.ph .tl{ margin-top: 18px; display: grid; gap: 16px; }
.ph .tl .r{ display: grid; grid-template-columns: 44px 24px 1fr auto; gap: 10px; align-items: start; }
.ph .tl .tm{ font-family: var(--mono); font-size: 12px; color: var(--soft); padding-top: 4px; }
.ph .tl .st{ width: 24px; height: 24px; border-radius: 50%; display: grid; place-items: center; font-size: 12px; font-weight: 600; }
.ph .tl .st.w{ border: 2px solid var(--amber); color: var(--amber); }
.ph .tl .st.ok{ background: var(--good); color: #09090b; }
.ph .tl .st.o{ border: 2px solid var(--haze-soft); }
.ph .tl b{ display: block; font-weight: 400; font-size: 17px; }
.ph .tl p{ margin: 2px 0 0; font-size: 14px; color: var(--amber); line-height: 1.35; }
.ph .tl .k{ font-family: var(--mono); font-size: 12px; color: var(--soft); padding-top: 4px; }
.ph .wcard{ padding: 18px; background: linear-gradient(170deg, rgba(255,122,61,.22), rgba(255,122,61,.04) 70%); border-color: rgba(255,122,61,.3); }
.ph .wcard .hd{ display: flex; align-items: center; justify-content: space-between; }
.ph .wcard .big{ margin-top: 14px; display: flex; align-items: baseline; gap: 10px; }
.ph .wcard .big b{ font-size: 66px; font-weight: 300; letter-spacing: -.05em; line-height: 1; }
.ph .wcard .big span{ color: var(--soft); font-size: 17px; }
.ph .wcard svg{ width: 100%; height: 130px; display: block; margin-top: 4px; }
.ph .wcard .ft{ display: flex; justify-content: space-between; font-family: var(--mono); font-size: 11px; color: var(--faint); }
.ph .wcard .pace{ margin-top: 14px; font-family: var(--mono); font-size: 12px; color: var(--amber); }
.ph .wcard .pace span{ color: var(--soft); margin-left: 10px; }
.ph .pill{ height: 40px; padding: 0 16px; border-radius: 999px; border: 1px solid rgba(255,122,61,.55); background: rgba(255,122,61,.1); color: var(--amber); display: inline-flex; align-items: center; font-size: 15px; }
.ph .closed{ padding: 18px; }
.ph .closed h2{ margin: 0 0 16px; font-size: 27px; font-weight: 300; letter-spacing: -.035em; line-height: 1.12; }
.ph .closed h2 span{ color: var(--faint); }
.ph .orbs{ display: grid; grid-template-columns: repeat(7, 1fr); gap: 6px; text-align: center; }
.ph .orbs div{ font-family: var(--mono); font-size: 12px; color: var(--faint); }
.ph .orbs i{ display: block; width: 100%; aspect-ratio: 1; border-radius: 50%; margin-bottom: 8px; }
.ph .orbs .f{ background: radial-gradient(circle at 36% 30%, #ffc48a, #f06a2e 55%, #c2410c); box-shadow: 0 0 16px rgba(255,122,61,.35); }
.ph .orbs .h{ background: linear-gradient(#26231f 55%, #8a4a25 55%); border: 1.5px solid rgba(255,184,107,.4); }
.ph .orbs .e{ background: #19191c; border: 1.5px solid var(--hair); }
.ph .legend{ margin-top: 14px; display: flex; gap: 18px; font-size: 14px; color: var(--soft); }
.ph .ident{ display: flex; align-items: center; justify-content: space-between; }
.ph .me{ display: inline-flex; align-items: center; gap: 12px; height: 48px; padding: 0 14px 0 6px; border-radius: 999px; background: rgba(255,255,255,.05); border: 1px solid rgba(255,122,61,.25); font-size: 18px; }
.ph .me i{ width: 36px; height: 36px; border-radius: 50%; display: grid; place-items: center; font-style: normal; color: #1a0a04; font-weight: 500; background: radial-gradient(circle at 35% 30%, #ffd9a8, #ff7a3d 55%, #c2410c); }
.ph .me svg{ margin-left: 2px; }
.ph .editplan{ height: 42px; padding: 0 18px; border-radius: 999px; border: 1px solid var(--hair); background: rgba(255,255,255,.05); display: inline-flex; align-items: center; font-size: 16px; }
.ph .goalcard{ padding: 18px; display: flex; align-items: center; gap: 16px; background: linear-gradient(170deg, rgba(255,122,61,.14), rgba(255,122,61,.03)); border-color: rgba(255,122,61,.32); }
.ph .goalcard .gr{ position: relative; width: 112px; height: 112px; flex: none; display: grid; place-items: center; }
.ph .goalcard .gr svg{ position: absolute; inset: 0; }
.ph .goalcard .orb3d{ width: 82px; height: 82px; display: grid; place-items: center; text-align: center; }
.ph .goalcard .orb3d b{ display: block; font-size: 25px; font-weight: 300; letter-spacing: -.04em; line-height: 1; }
.ph .goalcard .orb3d small{ font-family: var(--mono); font-size: 9px; color: #fde6cf; }
.ph .goalcard h3{ margin: 6px 0 8px; font-size: 29px; font-weight: 300; letter-spacing: -.04em; line-height: 1; }
.ph .goalcard .m{ font-family: var(--mono); font-size: 11px; letter-spacing: .06em; color: var(--soft); text-transform: uppercase; line-height: 1.6; }
.ph .grid2{ display: grid; grid-template-columns: 1fr 1fr; gap: 8px; }
.ph .tile{ border-radius: 26px; background: rgba(255,255,255,.04); border: 1px solid var(--hair); padding: 16px; min-height: 112px; display: flex; flex-direction: column; justify-content: space-between; position: relative; }
.ph .tile b{ display: block; font-weight: 400; font-size: 18px; letter-spacing: -.01em; }
.ph .tile small{ display: block; margin-top: 2px; font-size: 15px; color: var(--soft); }
.ph .tile .ic{ display: flex; align-items: center; gap: 6px; height: 22px; }
.ph .tile .ic u{ width: 9px; height: 9px; border-radius: 50%; background: var(--amber); text-decoration: none; box-shadow: 0 0 6px rgba(255,184,107,.6); }
.ph .tile .ic u.o{ background: none; border: 1.5px solid var(--amber); box-shadow: none; }
.ph .tile .ic u.e{ width: 13px; height: 13px; background: var(--ember); }
.ph .tile .ic u.g{ background: #52525b; box-shadow: none; }
.ph .tile .new{ position: absolute; top: 14px; right: 14px; font-family: var(--mono); font-size: 11px; padding: 3px 9px; border-radius: 999px; background: var(--amber); color: #1a0a04; font-weight: 500; }
.ph .dest{ display: flex; align-items: center; gap: 12px; border-radius: 26px; background: rgba(255,255,255,.04); border: 1px solid var(--hair); padding: 18px 20px; }
.ph .dest b{ display: block; font-weight: 500; font-size: 21px; letter-spacing: -.02em; }
.ph .dest span{ font-size: 17px; color: var(--soft); }
.ph .dest svg{ margin-left: auto; }
.ph .nav{
  position: absolute; z-index: 3; left: 10px; right: 10px; bottom: 26px; height: 66px;
  display: flex; align-items: center; justify-content: space-between; padding: 0 14px;
  border-radius: 999px; background: rgba(22,22,25,.9); border: 1px solid rgba(255,255,255,.1);
  backdrop-filter: blur(18px); -webkit-backdrop-filter: blur(18px);
}
.ph .tab{ background: none; border: 0; width: 56px; height: 54px; display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 4px; color: #6b6b73; font-size: 12px; }
.ph .tab.on{ color: var(--ink); }
.ph .tab svg{ width: 26px; height: 26px; }
.ph .plus{ width: 62px; height: 62px; border-radius: 50%; border: 0; display: grid; place-items: center; color: #1a0a04; margin-top: -4px; background: radial-gradient(circle at 36% 28%, #ffd9a8, #ff8a4c 52%, #ee6a2c); box-shadow: 0 0 30px rgba(255,122,61,.5); }
.ph .home{ position: absolute; z-index: 6; bottom: 7px; left: 50%; translate: -50% 0; width: 124px; height: 4px; border-radius: 3px; background: rgba(255,255,255,.7); }
.ph .tour{ position: absolute; inset: 0; z-index: 20; }
.ph .tour[hidden]{ display: none; }
.ph .hl{
  position: absolute; pointer-events: none; border-radius: 20px;
  box-shadow: 0 0 0 2000px rgba(5,5,7,var(--dim)), 0 0 0 1.5px rgba(255,184,107,.75) inset;
  transition: left .42s cubic-bezier(.3,.9,.3,1), top .42s cubic-bezier(.3,.9,.3,1), width .42s cubic-bezier(.3,.9,.3,1), height .42s cubic-bezier(.3,.9,.3,1), border-radius .3s;
}
.ph .hl::after{ content: ""; position: absolute; inset: 0; border-radius: inherit; animation: ping 2.2s ease-out infinite; box-shadow: 0 0 0 0 rgba(255,184,107,.5); }
@keyframes ping{ 0% { box-shadow: 0 0 0 0 rgba(255,184,107,.45); } 70%, 100% { box-shadow: 0 0 0 12px rgba(255,184,107,0); } }
.ph .pop{
  position: absolute; width: 284px; padding: 16px 16px 14px; border-radius: 22px;
  background: #f5f5f4; color: #09090b; box-shadow: 0 24px 60px rgba(0,0,0,.55);
  transition: left .42s cubic-bezier(.3,.9,.3,1), top .42s cubic-bezier(.3,.9,.3,1), opacity .2s;
}
.ph .pop.fresh{ transition: opacity .2s; }
.ph .pop h4{ margin: 0 26px 6px 0; font-size: 18px; line-height: 1.2; font-weight: 500; letter-spacing: -.015em; text-wrap: balance; }
.ph .pop p{ margin: 0; font-size: 14px; line-height: 1.45; color: #3f3f46; }
.ph .pop .x{ position: absolute; top: 10px; right: 10px; width: 28px; height: 28px; border-radius: 50%; border: 0; background: rgba(9,9,11,.07); display: grid; place-items: center; }
.ph .pop .foot{ display: flex; align-items: center; gap: 8px; margin-top: 14px; }
.ph .pop .count{ margin-right: auto; font-family: var(--mono); font-size: 11px; color: #71717a; }
.ph .pop .b{ height: 36px; padding: 0 15px; border-radius: 999px; border: 0; font-size: 13px; font-weight: 500; }
.ph .pop .b.ghost{ background: rgba(9,9,11,.07); }
.ph .pop .b.dark{ background: #09090b; color: #f5f5f4; display: inline-flex; align-items: center; gap: 8px; }
.ph .pop .b.dark i{ width: 8px; height: 8px; border-radius: 50%; background: var(--ember); box-shadow: 0 0 8px var(--ember); }
.ph .pop .arrow{ position: absolute; width: 14px; height: 14px; background: #f5f5f4; rotate: 45deg; border-radius: 3px; }
.ph .pop .dots{ display: flex; gap: 4px; margin: 0 0 10px; }
.ph .pop .dots i{ height: 3px; flex: 1; border-radius: 2px; background: rgba(9,9,11,.12); }
.ph .pop .dots i.on{ background: #09090b; }`;

export const PHONE_HTML = String.raw`<div class="ph"><div class="phone">
    <div class="screen" id="screen">
      <div class="glow"></div>
      <div class="island"></div>
      <div class="status"><span>9:41</span>
        <svg width="66" height="12" viewBox="0 0 66 12" fill="#f5f5f4"><rect x="0" y="7" width="3" height="5" rx="1"/><rect x="5" y="5" width="3" height="7" rx="1"/><rect x="10" y="2.5" width="3" height="9.5" rx="1"/><rect x="15" y="0" width="3" height="12" rx="1"/><rect x="26" y="1" width="26" height="11" rx="3.5" fill="none" stroke="#f5f5f4" stroke-opacity=".5"/><rect x="28" y="3" width="19" height="7" rx="2"/></svg>
      </div>

      <!-- TODAY -->
      <section class="pane on" data-pane="today">
        <div class="dayhead"><b>Monday</b><span class="mlabel">Oct 26</span></div>
        <div class="orbwrap" data-anchor="today.orb">
          <svg viewBox="0 0 250 250" aria-hidden="true"><circle cx="125" cy="125" r="118" fill="none" stroke="rgba(255,255,255,.07)" stroke-width="5"/><circle cx="125" cy="125" r="118" fill="none" stroke="#ffb86b" stroke-width="5" stroke-linecap="round" stroke-dasharray="208 742" transform="rotate(-90 125 125)"/></svg>
          <div class="orb3d"><div><div class="num">880</div><div class="of">of 3,100 kcal</div></div></div>
        </div>
        <div class="pacepill" data-anchor="today.pace"><i></i>A bit behind <span>·</span> <span>3 meals</span>
          <svg width="8" height="13" viewBox="0 0 8 14" fill="none" stroke="#a1a1aa" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M1 1l6 6-6 6"/></svg></div>
        <div class="glass nextcard" data-anchor="today.next">
          <div class="top"><span class="mlabel">Top-up · back 13:55</span><span class="kc">~488 kcal</span></div>
          <h2>Lunch was light. <span>A little more now keeps the day on pace.</span></h2>
          <div class="acts"><span class="outline"><svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"><circle cx="8" cy="4" r="2"/><path d="M8 6v8M4 14h8M5 10c-2 .5-3 1-3 2s2.5 2 6 2 6-1 6-2-1-1.5-3-2"/></svg>Order nearby</span><span class="link">Log it →</span></div>
        </div>
        <div class="daydots" data-anchor="today.dots">
          <div class="ln"></div>
          <div class="d on" style="left:12%"></div><div class="d on" style="left:50%"></div><div class="d off" style="left:88%"></div>
          <span class="t" style="left:12%">08:00</span><span class="t" style="left:50%">13:00</span><span class="t" style="left:88%">19:00</span>
        </div>
        <div class="mealrow"><small>8:05 AM</small><b>Overnight oats</b><span>420</span></div>
        <div class="mealrow"><small>10:10 AM</small><b>Coffee and a banana</b><span>180</span></div>
      </section>

      <!-- TRAIN -->
      <section class="pane" data-pane="train">
        <div class="topbar"><span class="circle"><svg width="10" height="16" viewBox="0 0 10 16" fill="none" stroke="#f5f5f4" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M8 2L2 8l6 6"/></svg></span><span class="mlabel">Train</span></div>
        <div class="trhead"><span class="mlabel">Today · Monday, Oct 26</span>
          <span class="addc" data-anchor="train.add"><svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M8 2v12M2 8h12"/></svg></span></div>
        <div class="glass weekcard" data-anchor="train.week">
          <div class="hd"><div><b>This week</b><span class="mlabel" style="letter-spacing:.1em">25 — Oct 31</span></div>
            <div style="display:flex;gap:8px"><span class="circle"><svg width="9" height="14" viewBox="0 0 10 16" fill="none" stroke="#f5f5f4" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M8 2L2 8l6 6"/></svg></span><span class="circle"><svg width="9" height="14" viewBox="0 0 10 16" fill="none" stroke="#f5f5f4" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M2 2l6 6-6 6"/></svg></span></div></div>
          <div class="wk">
            <div><span class="l">S</span><span class="n">25</span><i class="a"></i></div>
            <div class="sel"><span class="l">M</span><span class="n">26</span><i class="r"></i></div>
            <div><span class="l">T</span><span class="n">27</span><i></i></div>
            <div><span class="l">W</span><span class="n">28</span><i class="h"></i></div>
            <div><span class="l">T</span><span class="n">29</span><i></i></div>
            <div><span class="l">F</span><span class="n">30</span><i></i></div>
            <div><span class="l">S</span><span class="n">31</span><i></i></div>
          </div>
          <div class="sum">3 sessions · refueled after 0 of 2 · 1 planned</div>
        </div>
        <div class="glass daycard" data-anchor="train.day">
          <div class="hd"><span class="ic"><svg width="22" height="22" viewBox="0 0 22 22" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><circle cx="13" cy="4" r="2"/><path d="M9 20l2-6-3-2 2-5 4 1 3 3M8 9l-3 2"/></svg></span><div><b>Cardio · 17:00–18:00</b><span>Done · added by you</span></div></div>
          <h2>Eat 550 more today.</h2>
          <div class="stack"><i class="n"></i><i class="t"></i></div>
          <div class="stackl"><span>3,100 normal day</span><span class="tr">+550 training</span><span class="td">3,650 today</span></div>
          <div class="tl">
            <div class="r"><span class="tm">15:30</span><span class="st w">!</span><div><b>Snack before</b><p>Nothing logged before. The refuel matters more.</p></div><span class="k">~250</span></div>
            <div class="r"><span class="tm">17:00</span><span class="st ok">✓</span><div><b style="color:var(--soft)">Cardio</b></div><span class="k">60 min</span></div>
            <div class="r"><span class="tm">19:30</span><span class="st o"></span><div><b>Dinner, a bit bigger</b><p style="color:var(--soft)">Your usual dinner plus a side.</p></div><span class="k"></span></div>
          </div>
        </div>
      </section>

      <!-- PROGRESS -->
      <section class="pane" data-pane="progress">
        <div class="glass wcard" data-anchor="progress.weight">
          <div class="hd"><span class="mlabel" style="color:var(--amber)">Gaining · to 80.0 kg</span><span class="pill">Weigh in</span></div>
          <div class="big"><b>76.4</b><span>kg &nbsp; 3.6 to go</span></div>
          <svg viewBox="0 0 340 130" aria-hidden="true">
            <path d="M14 112 L40 106 L58 100 L80 86 L104 78 L124 64" fill="none" stroke="#ffb86b" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"/>
            <path d="M124 64 L296 26" fill="none" stroke="rgba(255,255,255,.35)" stroke-width="1.5" stroke-dasharray="4 5"/>
            <circle cx="124" cy="64" r="12" fill="url(#og)"/><circle cx="306" cy="24" r="13" fill="none" stroke="#ffb86b" stroke-width="1.5" stroke-dasharray="3 3"/>
            <text x="262" y="22" fill="#ffb86b" font-family="Geist Mono, monospace" font-size="11">80.0</text>
            <defs><radialGradient id="og" cx=".35" cy=".3"><stop offset="0" stop-color="#ffe0b8"/><stop offset=".6" stop-color="#ff7a3d"/><stop offset="1" stop-color="#c2410c"/></radialGradient></defs>
          </svg>
          <div class="ft"><span>74.0 · SEP 14</span><span>~15 WEEKS TO GO</span></div>
          <div class="pace">+0.40 / WK NOW <span>ON PACE</span></div>
        </div>
        <div class="glass closed" data-anchor="progress.days">
          <h2>4 of 6 days closed. <span>Short days ran 1,870 under.</span></h2>
          <div class="orbs">
            <div><i class="f"></i>W</div><div><i class="h"></i>T</div><div><i class="f"></i>F</div><div><i class="e"></i>S</div><div><i class="f"></i>S</div><div><i class="f"></i>M</div><div><i class="h" style="background:linear-gradient(#1a1a1d 70%,#8a4a25 70%)"></i>T</div>
          </div>
          <div class="legend"><span style="color:var(--amber)">●</span> Closed <span style="margin-left:6px;color:var(--amber)">◐</span> Short, filled to how much</div>
        </div>
      </section>

      <!-- YOU -->
      <section class="pane" data-pane="you">
        <div class="ident"><span class="me"><i>A</i>Alex<svg width="7" height="12" viewBox="0 0 8 14" fill="none" stroke="#a1a1aa" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M1 1l6 6-6 6"/></svg></span><span class="editplan">Edit plan</span></div>
        <div class="glass goalcard" data-anchor="you.goal">
          <div class="gr"><svg viewBox="0 0 112 112" aria-hidden="true"><circle cx="56" cy="56" r="52" fill="none" stroke="rgba(255,255,255,.08)" stroke-width="4"/><circle cx="56" cy="56" r="52" fill="none" stroke="#ffb86b" stroke-width="4" stroke-linecap="round" stroke-dasharray="88 327" transform="rotate(-90 56 56)"/></svg>
            <div class="orb3d"><div><b>79.6</b><small>kg NOW</small></div></div></div>
          <div><span class="mlabel" style="color:var(--amber)">Gaining · 27% there</span><h3>To 84 kg</h3><div class="m">3,100 kcal a day<br>Steady · ~19 weeks left</div></div>
        </div>
        <div data-anchor="you.setup">
          <div class="mlabel" style="margin:4px 4px 10px">Your setup</div>
          <div class="grid2">
            <div class="tile"><div class="ic"><u></u><u></u><u></u></div><div><b>Meal times</b></div></div>
            <div class="tile"><span class="new">NEW</span><div class="ic"><u class="o"></u><u class="g"></u><u class="e"></u></div><div><b>Appetite</b><small>Normal plates</small></div></div>
            <div class="tile"><div class="ic"><u class="e"></u><span style="color:#f87171;font-size:18px">⊘</span></div><div><b>Foods I avoid</b></div></div>
            <div class="tile"><div class="ic"><u></u><u class="e"></u><u class="o"></u></div><div><b>My meals</b></div></div>
          </div>
        </div>
        <div class="dest" data-anchor="you.help"><div><b>How SetPoint works</b><span>A quick tour</span></div>
          <svg width="8" height="14" viewBox="0 0 8 14" fill="none" stroke="#8b8b94" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M1 1l6 6-6 6"/></svg></div>
      </section>

      <nav class="nav" >
        <button class="tab on" data-tab="today"><svg viewBox="0 0 26 26" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"><circle cx="13" cy="13" r="4.4"/><path d="M13 3v2.4M13 20.6V23M3 13h2.4M20.6 13H23M5.9 5.9l1.7 1.7M18.4 18.4l1.7 1.7M5.9 20.1l1.7-1.7M18.4 7.6l1.7-1.7"/></svg>Today</button>
        <button class="tab" data-tab="train"><svg viewBox="0 0 26 26" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><circle cx="13" cy="6" r="2.4"/><path d="M5 9h16M3 9v4M23 9v4M13 9v6l-4 7M13 15l4 7M9 9l1 4h6l1-4"/></svg>Train</button>
        <button class="plus" data-anchor="nav.plus" aria-label="Log a meal"><svg width="26" height="26" viewBox="0 0 26 26" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round"><path d="M13 4v18M4 13h18"/></svg></button>
        <button class="tab" data-tab="progress"><svg viewBox="0 0 26 26" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><path d="M3 20l7-7 4 4 9-10M17 7h6v6"/></svg>Progress</button>
        <button class="tab" data-tab="you"><svg viewBox="0 0 26 26" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"><circle cx="13" cy="9" r="4.2"/><path d="M4.5 22c1.2-4.6 4.6-6.4 8.5-6.4s7.3 1.8 8.5 6.4"/></svg>You</button>
      </nav>
      <div class="pickbar" id="pickbar" hidden><span id="pickmsg">Click an element on the phone</span><button id="pickcancel">Cancel</button></div>
      <div class="home"></div>

      <!-- the tour layer -->
      <div class="tour" id="tour" hidden>
        <div class="hl" id="hl"></div>
        <div class="pop" id="pop" role="dialog" aria-live="polite">
          <button class="x" id="pop-x" aria-label="Close tour"><svg width="10" height="10" viewBox="0 0 10 10" stroke="#09090b" stroke-width="1.6" stroke-linecap="round"><path d="M1 1l8 8M9 1L1 9"/></svg></button>
          <div class="dots" id="pop-dots"></div>
          <h4 id="pop-title"></h4>
          <p id="pop-body"></p>
          <div class="foot">
            <span class="count" id="pop-count"></span>
            <button class="b ghost" id="pop-back"></button>
            <button class="b dark" id="pop-next"></button>
          </div>
          <span class="arrow" id="pop-arrow"></span>
        </div>
      </div>
    </div>
  </div></div>`;
