try; import KaimonSlate; catch; error("This is a Kaimon Slate notebook — running it as plain Julia needs the KaimonSlate runtime in this environment. Add it with `import Pkg; Pkg.add(\"KaimonSlate\")`, or open it in Kaimon Slate."); end; KaimonSlate.standalone!(@__MODULE__; dir=@__DIR__)

#%% md id=ttl title
@md"""
# Macroeconomics — Sample Assessment
"""

#%% md id=sub subtitle
@md"""
A demonstration of SlateAssess: a multiple-choice paper that exports to one HTML file
"""

#%% md id=intro abstract
@md"""
This notebook is an assessment. Exported to standalone HTML with **Offline** ticked, it
becomes a single file that runs the whole paper in a browser with no Julia, no server and
no network — while the charts stay genuinely interactive and the data tables stay sortable.

The correct answers are not in this notebook, and so are not in the exported file. Candidates
produce a signed submission; marking happens afterwards with `scripts/grade.jl`.
"""

#%% code id=setup hidecode
using SlateAssess
using DataFrames, StatsBase

"SlateAssess $(pkgversion(SlateAssess)) · DataFrames $(pkgversion(DataFrames))"

#%% code id=examdef hidecode
# The paper. Note what is NOT here: the answer key. It lives only in the marking script.
exam = Assessment("demo-macro-2026";
    title = "Macroeconomics — Sample Assessment",
    subtitle = "6 questions · 20 minutes · each question 2 marks, −0.5 for a wrong answer",
    questions = questions("q", 6),
    choices = ["a)", "b)", "c)", "d)"],
    show_no_response = false,     # unanswered = nothing picked
    flag = "",                    # no review-flag control
    marks = Marks(correct = 2.0, wrong = -0.5),
    duration = 20,
    identity = [
        IdField(:number, "Student number"; pattern = raw"^\d{4,10}$", placeholder = "e.g. 104857"),
        IdField(:name, "Full name"; placeholder = "As it appears on your student card"),
        IdField(:room, "Room code"; required = false, placeholder = "e.g. C4.07"),
    ],
    session_key = "demo-session-key-2026")

#%% code id=header hidecode
# Carries the runtime and the styling for every other widget — keep it first.
exam_header(exam)

#%% md id=rules
@md"""
!!! note "Before you start"

    Enter your details above and press **Confirm and start**. The paper stays locked until you do,
    and the clock starts on your first confirmation.

    Each question offers **NR** (no response, the default) and 🚩 (flag for review). A question left
    flagged is recorded as **unanswered** — clear the flag and choose an option for it to count.

    Your answers are saved in this browser as you go, so a crash or an accidental reload will not
    lose them. When you have finished, use the panel at the bottom to produce your submission file.
"""

#%% code id=strip hidecode
status_strip(exam)

#%% code id=resetbtn hidecode
# Authoring aid — drop this cell before issuing a real paper.
reset_button(exam)

#%% md id=q1txt
@md"""
---
### Question 1

The table below shows actual and potential output for a small open economy (index, 2015 = 100).
**Which year recorded the largest _negative_ output gap as a share of potential GDP?**

**a)** 2019 $~~~~$ **b)** 2020 $~~~~$ **c)** 2021 $~~~~$ **d)** 2024
"""

#%% code id=q1data hidecode
gap = DataFrame(
    year      = 2018:2024,
    actual    = [102.4, 104.9, 97.1, 103.8, 108.2, 110.1, 111.4],
    potential = [101.0, 103.2, 103.9, 105.1, 106.6, 108.4, 110.2],
)
gap.gap_pct = round.(100 .* (gap.actual .- gap.potential) ./ gap.potential; digits = 2)
slate_table(gap)

#%% code id=q1 hidecode
answer_box(exam, "q01")

#%% md id=q2txt
@md"""
---
### Question 2

The chart below traces unemployment and inflation for the same economy, one connected path per
period. Hover any point for its year.

**A stable short-run Phillips curve implies a downward-sloping trade-off: inflation falls as
unemployment rises, with the curve itself staying put. Which period is most consistent with that?**

**a)** 2010–2013 $~~~~$ **b)** 2014–2019 $~~~~$ **c)** 2020–2022 $~~~~$ **d)** 2022–2024
"""

#%% code id=q2chart hidecode
# A Phillips-curve question is about MOVEMENT THROUGH TIME, so the figure has to show a trajectory,
# not a cloud of points. Each candidate period is its own connected series, in chronological order,
# so the shape of each era is directly comparable — and the legend lets a reader isolate one.
years = 2010:2024
unemp = [7.0, 8.6, 10.3, 12.0, 11.2, 10.1, 9.2, 8.4, 7.6, 6.9, 8.9, 7.4, 6.1, 5.8, 5.5]
infl  = [3.4, 2.6,  1.7,  0.9,  1.0,  0.9, 1.1, 1.0, 1.2, 1.0, -0.2, 2.9, 7.8, 5.3, 2.4]

at(y) = findfirst(==(y), years)
# Each point is {value, name} — the NAME carries the year, which is what both the on-chart label and
# the tooltip key off. An echart spec is serialised to JSON with no reviver, so a JS function formatter
# would render as literal text, and the only tokens that actually resolve here are `{a}` (series),
# `{b}` (item name) and `{c}` (the whole value). `{c0}`/`{c1}` and `{@dim}` do NOT — verified against
# this ECharts build for both line and scatter — so the pair is labelled in words instead.
period(lo, hi) = [Dict("value" => [unemp[at(y)], infl[at(y)]], "name" => string(y)) for y in lo:hi]

# Periods overlap at their endpoints on purpose: the joint year is where one era hands over to the
# next, and seeing it in both makes the turn legible.
segments = [
    ("2010–2013", period(2010, 2013), "#5fb3f9"),
    ("2014–2019", period(2014, 2019), "#4ec9a0"),
    ("2020–2022", period(2020, 2022), "#e0b341"),
    ("2022–2024", period(2022, 2024), "#f2635f"),
]

echart(Dict(
    "__size" => Dict("height" => 460),
    "tooltip" => Dict("trigger" => "item",
        "formatter" => "<b>{b}</b> &nbsp;·&nbsp; {a}<br/>unemployment, inflation (%): <b>{c}</b>"),
    "legend" => Dict("top" => 8, "data" => [s[1] for s in segments]),
    "grid" => Dict("left" => 62, "right" => 34, "top" => 52, "bottom" => 56),
    "xAxis" => Dict("type" => "value", "name" => "Unemployment (%)", "nameLocation" => "middle",
                    "nameGap" => 30, "min" => 4, "max" => 13,
                    "splitLine" => Dict("show" => true)),
    "yAxis" => Dict("type" => "value", "name" => "Inflation (%)", "nameLocation" => "middle",
                    "nameGap" => 40, "min" => -1, "max" => 9),
    "series" => [Dict(
        "type" => "line",              # line + symbol = a path you can trace, not a scatter cloud
        "name" => name,
        "data" => data,
        "color" => colour,
        "symbolSize" => 11,
        "lineStyle" => Dict("width" => 2.5),
        "label" => Dict("show" => true, "position" => "top", "formatter" => "{b}",
                        "fontSize" => 11, "distance" => 8, "color" => "#c8cdd6"),
        "labelLayout" => Dict("hideOverlap" => true),
        "emphasis" => Dict("focus" => "series"),
    ) for (name, data, colour) in segments],
))

#%% code id=q2 hidecode
answer_box(exam, "q02")

#%% md id=q3txt
@md"""
---
### Question 3

In the Solow model with production function $Y = K^{\alpha} L^{1-\alpha}$, a constant saving
rate $s$, depreciation $\delta$ and no technological progress, the steady-state capital per
worker is

$$k^{*} = \left(\frac{s}{\delta + n}\right)^{\frac{1}{1-\alpha}}$$

**Holding everything else constant, an increase in the population growth rate $n$ will:**

**a)** raise steady-state capital per worker and raise steady-state output per worker

**b)** lower steady-state capital per worker and lower steady-state output per worker

**c)** leave steady-state capital per worker unchanged, since $s$ is unchanged

**d)** lower steady-state capital per worker but raise the steady-state growth rate of output per worker
"""

#%% code id=q3 hidecode
answer_box(exam, "q03")

#%% md id=q4txt
@md"""
---
### Question 4

The summary statistics below describe quarterly GDP growth (%) by decade, where `cv` is the
coefficient of variation. **Which decade shows the greatest volatility relative to its mean growth?**

**a)** 1995–2004 $~~~~$ **b)** 2005–2014 $~~~~$ **c)** 2015–2024 $~~~~$ **d)** 2005–2014 and 2015–2024 are tied
"""

#%% code id=q4data hidecode
growth = Dict(
    "1995–2004" => [0.8, 1.1, 0.6, 0.9, 1.2, 0.7, 1.0, 0.5, 0.9, 1.1],
    "2005–2014" => [0.6, -1.8, -2.4, 1.4, 0.2, -0.9, 1.1, 0.4, -0.3, 0.8],
    "2015–2024" => [0.7, 0.9, -5.2, 4.1, 1.3, 0.6, 0.8, 1.0, 0.4, 0.6],
)
stats = DataFrame(
    decade = collect(keys(growth)),
    mean   = [round(mean(v); digits = 2) for v in values(growth)],
    sd     = [round(std(v); digits = 2) for v in values(growth)],
    min    = [minimum(v) for v in values(growth)],
    max    = [maximum(v) for v in values(growth)],
)
sort!(stats, :decade)
stats.cv = round.(stats.sd ./ abs.(stats.mean); digits = 2)
slate_table(stats)

#%% code id=q4 hidecode
answer_box(exam, "q04")

#%% md id=q5txt
@md"""
---
### Question 5

A central bank facing a negative supply shock chooses to hold its policy rate unchanged
rather than tightening. **In the AD–AS framework, the most likely short-run consequence is:**

**a)** output falls and the price level falls

**b)** output falls and the price level rises

**c)** output rises and the price level falls

**d)** output and the price level are both unchanged, since policy did not move
"""

#%% code id=q5 hidecode
answer_box(exam, "q05")

#%% md id=q6txt
@md"""
---
### Question 6

The chart below shows **monthly** inflation over five years. A single sharp episode dominates it, and
month-to-month noise makes the underlying trend hard to read.

Use the slider to apply a **centred moving average** to the series. The faint line is the raw monthly
data; the bold line is the smoothed series, and the dashed line marks 4%.

**What is the smallest window that keeps the smoothed series at or below 4% throughout?**

**a)** 3 months $~~~~$ **b)** 5 months $~~~~$ **c)** 7 months $~~~~$ **d)** 9 months
"""

#%% code id=q6data hidecode
# Monthly inflation: a mild cyclical base plus one sharp episode. The episode is deliberately narrow
# enough that a 7-month window pulls its peak under 4% while a 5-month window does not — so the
# question has exactly one defensible answer and cannot be eyeballed from the raw series.
months = collect(1:60)
infl_monthly = let t = 1:60
    base = 2.0 .+ 0.45 .* sin.(t ./ 3.2) .+ 0.25 .* cos.(t ./ 1.7)
    round.(base .+ 4.5 .* exp.(-((t .- 31.0) .^ 2) ./ (2 * 1.1^2)); digits = 2)
end
"peak monthly inflation: $(maximum(infl_monthly))%"

#%% web id=q6explore
@web(html"""
<div class="mx">
  <div class="mx-bar">
    <label class="mx-lab">Moving-average window
      <input id="win" type="range" min="1" max="15" step="2" value="1" />
    </label>
    <span class="mx-out"><b id="winval">1</b> month<span id="plural"></span></span>
    <span class="mx-out">peak of smoothed series <b id="peak">—</b></span>
  </div>
  <div id="mxchart"></div>
</div>
""",
css"""
.mx { margin: 6px 0 2px; }
.mx-bar { display:flex; align-items:center; gap:20px; flex-wrap:wrap; margin-bottom:6px;
          font-size:.88rem; color:var(--dim,#9aa3b2); }
.mx-lab { display:flex; align-items:center; gap:10px; }
.mx-lab input { width:220px; accent-color:var(--accent,#5fb3f9); cursor:pointer; }
.mx-out b { color:var(--text,#e6e6e6); font-variant-numeric:tabular-nums; }
#mxchart { width:100%; height:400px; }
""",
js"""
// Everything here runs in the browser. No Julia is involved once the page is built, so this works
// identically in the live notebook and in the exported single-file paper, online or offline.
const months = {{ months }};
const raw = {{ infl_monthly }};

const chart = echarts.init(root.querySelector("#mxchart"), "slate");

// Centred moving average; the window shrinks at the ends rather than dropping points, so the line
// spans the whole series instead of stopping short.
function movingAverage(v, w) {
  const half = (w - 1) / 2, out = [];
  for (let i = 0; i < v.length; i++) {
    const lo = Math.max(0, i - half), hi = Math.min(v.length - 1, i + half);
    let sum = 0;
    for (let j = lo; j <= hi; j++) sum += v[j];
    out.push(+(sum / (hi - lo + 1)).toFixed(2));
  }
  return out;
}

function draw(w) {
  const smoothed = movingAverage(raw, w);
  const peak = Math.max.apply(null, smoothed);
  root.querySelector("#winval").textContent = w;
  root.querySelector("#plural").textContent = w === 1 ? "" : "s";
  const peakEl = root.querySelector("#peak");
  peakEl.textContent = peak.toFixed(2) + "%";
  peakEl.style.color = peak > 4 ? "var(--red,#f2635f)" : "var(--green,#4ec9a0)";

  chart.setOption({
    animation: false,
    grid: { left: 58, right: 26, top: 38, bottom: 46 },
    tooltip: { trigger: "axis" },
    legend: { top: 4, data: ["monthly", "smoothed"] },
    xAxis: { type: "category", data: months, name: "month",
             nameLocation: "middle", nameGap: 26,
             axisLabel: { interval: 5 } },
    yAxis: { type: "value", name: "inflation (%)", nameLocation: "middle",
             nameGap: 40, min: 0, max: 7 },
    series: [
      { name: "monthly", type: "line", data: raw, showSymbol: false,
        color: "#8892a4", lineStyle: { width: 1, opacity: 0.5 } },
      { name: "smoothed", type: "line", data: smoothed, showSymbol: false,
        color: "#5fb3f9", lineStyle: { width: 3 },
        markLine: { silent: true, symbol: "none",
          data: [{ yAxis: 4,
                   lineStyle: { color: "#e0b341", type: "dashed", width: 1.5 },
                   label: { formatter: "4%", position: "insideEndTop",
                            color: "#e0b341" } }] } }
    ]
  });
}

const slider = root.querySelector("#win");
slider.addEventListener("input", () => draw(+slider.value));
window.addEventListener("resize", () => chart.resize());
draw(+slider.value);
""")

#%% code id=q6 hidecode
answer_box(exam, "q06")

#%% md id=endtxt
@md"""
---
## Finishing

Check the strip at the top for anything still blank or flagged, then produce your
submission file below and hand it in exactly as it is.
"""

#%% code id=submit hidecode
submission_panel(exam)

#%% code id=ceb69f hidecode
using Base64, Dates
let ffmpeg = "/opt/homebrew/bin/ffmpeg", ffprobe = "/opt/homebrew/bin/ffprobe"
    dur(p) = try; parse(Float64, strip(read(`$ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 $p`, String))); catch; -1.0; end
    bufs = Dict{String,IOBuffer}()
    slate_on("clip_begin", a -> (bufs[String(a.id)] = IOBuffer(); (ok = true)))
    slate_on("clip_chunk", a -> (write(get!(bufs, String(a.id), IOBuffer()), String(a.data)); (ok = true)))
    slate_on("clip_end", a -> begin
        id = String(a.id); mime = String(get(a, :mime, "video/webm"))
        buf = get(bufs, id, nothing); buf === nothing && return (ok = false, error = "no buffer")
        b64 = String(take!(buf)); delete!(bufs, id)
        ext = occursin("mp4", mime) ? "mp4" : "webm"; bytes = base64decode(b64)
        ts = Dates.format(now(), "yyyymmdd-HHMMSS"); dir = expanduser("~/Downloads")
        raw = joinpath(dir, "slate-rec-$ts-raw.$ext"); out = joinpath(dir, "slate-rec-$ts.mp4")
        write(raw, bytes); dr = dur(raw)
        ok = try; run(`$ffmpeg -y -loglevel error -fflags +genpts -i $raw -c:v libx264 -pix_fmt yuv420p -crf 23 -fps_mode cfr -r 30 -movflags +faststart $out`); true; catch e; @warn e; false; end
        dout = ok ? dur(out) : -1.0; ok && rm(raw; force = true)
        (ok = ok, path = (ok ? out : raw), mb = round(length(bytes)/1e6, digits = 1), raw_dur = round(dr, digits = 2), out_dur = round(dout, digits = 2))
    end)
end
"screen-record handlers registered (bookmarklet)"

# ╔═╡ Slate.config · per-notebook settings (Settings panel)
#   docid = a9d1ea77-4e56-4677-bef4-6fb29aae9b82
# ╚═╡
