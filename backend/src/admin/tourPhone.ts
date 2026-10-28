/**
 * The phone drawn in the Tour tab of /admin: screenshots of the app's own screens
 * (src/admin/tourScreens.ts, refreshed by ios/scripts/tour_screens.py) with the tour tip drawn
 * the way the app draws it (ios/SetPoint/Features/Tour/TourOverlay.swift). opsPage.ts runs the
 * spotlight over it. Every style is scoped under `.ph` so nothing leaks into the dashboard,
 * and sizes are in points, one CSS pixel each, like the phone they were taken on.
 */
export const PHONE_CSS = String.raw`
.ph{width:max-content;--sans:-apple-system,"SF Pro Text","SF Pro Display","Geist",ui-sans-serif,system-ui,"Helvetica Neue",sans-serif;--mono:ui-monospace,"SF Mono","Geist Mono",Menlo,monospace;--dim:.72;font-family:var(--sans);font-size:15px;line-height:normal;color:#f5f5f4;-webkit-font-smoothing:antialiased;}
.ph *{box-sizing:border-box}
.ph button{font:inherit;color:inherit;cursor:pointer;padding:0;border:0;background:none}
.ph h4,.ph p{margin:0}
.ph .hl{all:unset}
.ph .screen{position:relative;border-radius:55px;overflow:hidden;background:#09090b;isolation:isolate;box-shadow:0 0 0 1px rgba(255,255,255,.12),0 40px 90px rgba(0,0,0,.6)}
.ph .shot{position:absolute;inset:0;width:100%;height:100%;display:none;user-select:none;-webkit-user-drag:none}
.ph .shot.on{display:block}
.ph .hits{position:absolute;inset:0;z-index:2}
.ph .hit{position:absolute;display:none;border-radius:18px;background:transparent}
.ph .hit.on{display:block}
.ph .screen.picking .hit.on{cursor:crosshair;outline:1.5px dashed rgba(255,184,107,.7);outline-offset:3px}
.ph .screen.picking .hit.on:hover{outline:2.5px solid #ffb86b;background:rgba(255,184,107,.1)}
.ph .tabhit{position:absolute;z-index:3;width:64px;height:56px;border-radius:20px}
.ph .tour{position:absolute;inset:0;z-index:20}
.ph .tour[hidden]{display:none}
.ph .hl{position:absolute;pointer-events:none;border-radius:20px;box-shadow:0 0 0 2000px rgba(5,5,7,var(--dim)),inset 0 0 0 1.5px rgba(255,184,107,.75);transition:left .42s cubic-bezier(.3,.9,.3,1),top .42s cubic-bezier(.3,.9,.3,1),width .42s cubic-bezier(.3,.9,.3,1),height .42s cubic-bezier(.3,.9,.3,1),border-radius .3s}
.ph .pop{position:absolute;width:284px;padding:16px 16px 14px;border-radius:22px;background:#f5f5f4;color:#09090b;box-shadow:0 24px 40px rgba(0,0,0,.5);transition:left .42s cubic-bezier(.3,.9,.3,1),top .42s cubic-bezier(.3,.9,.3,1),opacity .2s}
.ph .pop.fresh{transition:opacity .2s}
.ph .pop{cursor:grab;touch-action:none}
.ph .pop.grabbing{cursor:grabbing}
.ph .pop button{cursor:pointer}
.ph .pop .dots{display:flex;gap:4px;margin:0 0 10px}
.ph .pop .dots[hidden]{display:none}
.ph .pop .dots i{height:3px;flex:1;border-radius:2px;background:rgba(9,9,11,.12)}
.ph .pop .dots i.on{background:#09090b}
.ph .pop h4{margin:0 26px 6px 0;font-size:18px;line-height:20px;font-weight:500;letter-spacing:-.47px}
.ph .pop p{font-size:14px;line-height:18.67px;letter-spacing:.09px;color:#3f3f46}
.ph .pop .x{position:absolute;top:10px;right:10px;width:28px;height:28px;border-radius:50%;background:rgba(9,9,11,.07);display:grid;place-items:center}
.ph .pop .foot{display:flex;align-items:center;gap:8px;margin-top:14px}
.ph .pop .count{margin-right:auto;font-family:var(--mono);font-size:11px;color:#71717a}
.ph .pop .b{height:36px;padding:0 15px;border-radius:999px;font-size:13px;font-weight:500;white-space:nowrap;display:inline-flex;align-items:center;gap:8px}
.ph .pop .b.ghost{background:rgba(9,9,11,.07);color:#09090b}
.ph .pop .b.dark{background:#09090b;color:#f5f5f4}
.ph .pop .b.dark i{width:8px;height:8px;border-radius:50%;background:#ff7a3d;box-shadow:0 0 4px #ff7a3d}
.ph .pop .arrow{position:absolute;width:14px;height:14px;background:#f5f5f4;rotate:45deg;border-radius:3px}
.ph .pop[dir=rtl] h4{margin:0 0 6px 26px}
.ph .pop[dir=rtl] .x{right:auto;left:10px}
.ph .pop[dir=rtl] .count{margin-right:0;margin-left:auto}
.ph .pop[dir=rtl] p{text-align:right}
.ph .pickbar{position:absolute;z-index:30;left:14px;right:14px;top:62px;padding:10px 16px;border-radius:999px;background:#f5f5f4;color:#09090b;font-size:13px;text-align:center;box-shadow:0 12px 34px rgba(0,0,0,.5)}
.ph .pickbar[hidden]{display:none}
@media (prefers-reduced-motion:reduce){.ph .hl,.ph .pop{transition:none}}
`;

const shot = (pane: string, on = false) =>
  `<img class="shot${on ? ' on' : ''}" data-pane="${pane}" alt="The ${pane} screen" draggable="false">`;

export const PHONE_HTML = String.raw`<div class="ph"><div class="screen" id="screen">
${shot('today', true)}${shot('train')}${shot('progress')}${shot('you')}
<div class="hits" id="hits"></div>
<button class="tabhit" data-tab="today" aria-label="Today"></button><button class="tabhit" data-tab="train" aria-label="Train"></button><button class="tabhit" data-tab="progress" aria-label="Progress"></button><button class="tabhit" data-tab="you" aria-label="You"></button>
<div class="tour" id="tour" hidden>
<div class="hl" id="hl"></div>
<div class="pop" id="pop" role="dialog" aria-live="polite">
<button class="x" id="pop-x" aria-label="Close tour"><svg width="10" height="10" viewBox="0 0 10 10" stroke="#09090b" stroke-width="1.8" stroke-linecap="round"><path d="M1 1l8 8M9 1L1 9"/></svg></button>
<div class="dots" id="pop-dots"></div>
<h4 id="pop-title"></h4>
<p id="pop-body"></p>
<div class="foot"><span class="count" id="pop-count"></span><button class="b ghost" id="pop-back"></button><button class="b dark" id="pop-next"></button></div>
<span class="arrow" id="pop-arrow"></span>
</div>
</div>
<div class="pickbar" id="pickbar" hidden><span id="pickmsg"></span></div>
</div></div>`;
