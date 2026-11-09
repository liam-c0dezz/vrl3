"""Turn the onboarding preview into a standalone EasyBid onboarding page:
full screen (no phone frame or preview controls), onboarding only, ending on the
"Building your custom estimator" screen."""
import json
import re
import sys

src, out = sys.argv[1], sys.argv[2]
s = open(src).read()


def r(a, b, count=1):
    global s
    assert s.count(a) == count, (s.count(a), a[:90])
    s = s.replace(a, b)


def cut(start, end, keep_end=True, replacement=""):
    """Remove s[start:end) where start/end are marker strings."""
    global s
    i = s.index(start)
    j = s.index(end, i)
    s = s[:i] + replacement + (s[j:] if keep_end else s[j + len(end):])


r("<title>EasyBid Onboarding</title>", "<title>EasyBid</title>")

# ---- CSS: drop the app, the wallet and the preview chrome ----
i = s.index("/* ===== app (ContentView) ===== */")
j = s.index("</style>", i)
s = s[:i] + "#root.still .fade{animation:none}\n@media (prefers-reduced-motion: reduce){*{animation:none!important;transition:none!important}}\n" + s[j:]
cut('<style id="liquid">', "</style>\n", keep_end=False)
r("<style>.strip button.ba{border-style:dashed;margin-left:6px}i.halo,span.zipok{display:none}</style>",
  """<style>i.halo,span.zipok{display:none}
/* Full screen: the 402 x 874 pt layout is scaled to fill the window; the page behind
   it carries the same colours as the current screen, so there is no frame. */
html,body{height:100%;margin:0;overflow:hidden}
body{background:linear-gradient(#0B2E5A,#347FE5);transition:background .4s}
body.light{background:linear-gradient(160deg,#DCE8F8,#F2F6FC 38%,#E6EEF9 70%,#F7F9FC)}
.stage{position:fixed;inset:0;overflow:hidden}
.stage .dev{position:absolute;left:0;top:0;border-radius:0;transform-origin:0 0;touch-action:manipulation}
@supports (height:100dvh){.stage{height:100dvh}}
</style>""")

# ---- Markup: just the screen ----
i = s.index('<div class="wrap">')
j = s.index("</div>\n\n<script>", i) + len("</div>\n")
s = s[:i] + '<main class="stage" id="stage"><div class="dev" id="dev"><div id="root" class="screen"></div></div></main>\n' + s[j:]

# ---- JS: onboarding only ----
s = re.sub(r"const ES_LIQUID=\{.*?\};\n", "", s, count=1)
r("const ES = Object.assign(ES_LIQUID, {", "const ES = Object.assign({")
cut("const PROJECTS=[", "const OB_COUNT=")
r('const S={mode:"onboarding",ob:0,zip:"",answers:{},build:0,tab:0,project:null,ptab:"Dashboard",filter:"All",gsOpen:true,overlay:null};',
  'const S={mode:"onboarding",ob:0,zip:"",answers:{},build:0};')
cut("/* ===================== app ===================== */", "/* ===================== shell ===================== */")

# chrome(): no status bar or home indicator; the page colour follows the screen.
i = s.index("function chrome(){")
j = s.index("let lastKey=", i)
s = s[:i] + '''function chrome(){
  const light = S.ob>=PAGES.length+3 && S.ob<PAGES.length+3+QUESTIONS.length;
  document.body.classList.toggle("light", light);
}
''' + s[j:]
r('const key=[S.mode,S.ob,S.tab,S.project,S.overlay].join("|");', 'const key=String(S.ob);')
r('root.innerHTML = S.mode==="onboarding" ? renderOnboarding() : renderApp(); chrome();', "root.innerHTML = renderOnboarding(); chrome();")
r('root.innerHTML = S.mode==="onboarding" ? renderOnboarding() : renderApp();', "root.innerHTML = renderOnboarding();")
r("  renderStrip();\n  startPageAnimations();", "  startPageAnimations();")
r("    renderStrip(); dev.classList.remove(\"switching\");", "    dev.classList.remove(\"switching\");")

# Replace the jump strip, its handlers and the bezel fit with onboarding-only controls.
i = s.index("const JUMPS=")
j = s.index("document.documentElement.lang=lang;", i)
s = s[:i] + '''root.addEventListener("click",e=>{
  const el=e.target.closest("[data-act]"); if(!el||!el.dataset.act) return; const a=el.dataset.act;
  if(a==="next"){ if(S.ob<OB_COUNT-1){S.ob++; if(S.ob===OB_COUNT-1)S.build=0;} }
  else if(a==="obBack"){ if(S.ob>0)S.ob--; }
  else if(a==="answer"){ S.answers[el.dataset.q]=el.dataset.o; }
  else return; // "Get Started" on the last screen ends the onboarding here.
  render();
});
// Phones: the screen fills the window edge to edge - it is scaled to the window's
// width and the layout takes the window's real height. Wider windows show the
// phone-shaped screen at full height in the middle, on the same colours.
function fit(){
  const vw=window.innerWidth, vh=window.innerHeight;
  let s, h;
  if (vw/vh < 0.62) { s=vw/402; h=Math.max(640, vh/s); if (h*s>vh) s=vh/h; }
  else { h=874; s=vh/874; }
  h=Math.round(h);
  const dev=document.getElementById("dev");
  dev.style.height=h+"px";
  // Placed exactly: scaled from its top-left corner, then centred in the window.
  dev.style.transform=`translate(${(vw-402*s)/2}px,${(vh-h*s)/2}px) scale(${s})`;
  if (h!==H) { setLayoutHeight(h); if (window.__started) { root.classList.add("still"); root.innerHTML=renderOnboarding(); if(S.ob===OB_COUNT-1) setBuild(S.build); } }
}
window.addEventListener("resize",fit);
''' + s[j:]

# Layout height follows the window (see fit()).
r("const H=874,W=402,SAFE_T=62,SAFE_B=34;", "let H=874;const W=402,SAFE_T=62,SAFE_B=34;")
r("const PANEL_H=H*0.445, PANEL_TOP=H-PANEL_H, PANEL_PAD_T=Math.max(48,Math.min(68,H*0.075)), PANEL_PAD_B=Math.max(54,SAFE_B+40);",
  "let PANEL_H, PANEL_TOP, PANEL_PAD_T, PANEL_PAD_B;\nfunction setLayoutHeight(h){ H=h; PANEL_H=Math.max(H*0.445, 340); PANEL_TOP=H-PANEL_H; PANEL_PAD_T=Math.max(48,Math.min(68,H*0.075)); PANEL_PAD_B=Math.max(54,SAFE_B+40); }\nsetLayoutHeight(874);")
r("fit(); render();", "fit(); render(); window.__started=true;")

# On short screens the graph and the progress ring fit the space above the panel.
r("const visW=Math.min(W-36,380), vt=Math.max(82,SAFE_T+54)+42, vw=330, vh=270, cx=vw*0.96;",
  "const visW=Math.min(W-36,380), vt=Math.max(82,SAFE_T+54)+42, vw=330, vh=Math.max(150,Math.min(270,PANEL_TOP-vt-34)), cx=vw*0.96;")
r("const vh=Math.min(Math.max(H*0.405,290),340), vt=Math.max(82,SAFE_T+54), p=S.build,",
  "const vt=Math.max(82,SAFE_T+54), vh=Math.max(170,Math.min(Math.min(Math.max(H*0.405,290),340),PANEL_TOP-vt-6)), p=S.build,")

# The estimator page has more copy, so its panel keeps a taller minimum.
i = s.index("function pageBuild(){")
j = s.index("function renderOnboarding", i)
body = s[i:j].replace("PANEL_TOP", "(H-BPH)").replace("PANEL_H", "BPH")
body = body.replace("function pageBuild(){", "function pageBuild(){\n  const BPH=Math.max(PANEL_H,372);", 1)
s = s[:i] + body + s[j:]

# Remove the wallet script.
cut("<script>\n/* ===== Wallet: balance roll-up", "</script>\n", keep_end=False)

# The intro no longer needs a home indicator to sit under.
r('dev.insertBefore(el,document.getElementById("homeind"));', "dev.appendChild(el);")

# ---- Keep only the Spanish strings the onboarding can show ----
m = re.search(r"const ES = Object\.assign\((\{.*\})\);\n", s)
objs = re.findall(r"\{[^{}]*\}", m.group(1))
merged = {}
for o in objs:
    merged.update(json.loads(o))
code = s[s.index("<script>", s.index("</style>")):]
code_wo_es = code.replace(m.group(0), "")
kept = {k: v for k, v in merged.items() if json.dumps(k)[1:-1] in code_wo_es or k in code_wo_es}
s = s.replace(m.group(0), "const ES = " + json.dumps(kept, ensure_ascii=False) + ";\n")

# ---- Keep only the icons the onboarding draws ----
i = s.index("const SYM={\n") + len("const SYM={\n")
j = s.index("\n};", i)
lines = s[i:j].split("\n")
rest = s[:i] + s[j:]
used = [l for l in lines if (m2 := re.match(r'"([^"]+)":', l)) and (f'"{m2.group(1)}"' in rest)]
s = s[:i] + "\n".join(used) + s[j:]

assert "renderApp" not in s and "WALLET" not in s and "renderStrip" not in s and 'id="strip"' not in s
open(out, "w").write(s)
print("ok", len(s), "bytes;", len(merged), "->", len(kept), "Spanish strings")
