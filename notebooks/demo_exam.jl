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

#%% code id=setup
using SlateAssess
using DataFrames, StatsBase

"SlateAssess $(pkgversion(SlateAssess)) · DataFrames $(pkgversion(DataFrames))"

#%% code id=examdef
# The paper. Note what is NOT here: the answer key. It lives only in the marking script.
exam = Assessment("demo-macro-2026";
    title = "Macroeconomics — Sample Assessment",
    subtitle = "5 questions · 20 minutes · each question 2 marks, −0.5 for a wrong answer",
    questions = questions("q", 5),
    choices = ["a)", "b)", "c)", "d)"],
    marks = Marks(correct = 2.0, wrong = -0.5),
    duration = 20,
    identity = [
        IdField(:number, "Student number"; pattern = raw"^\d{4,10}$", placeholder = "e.g. 104857"),
        IdField(:name, "Full name"; placeholder = "As it appears on your student card"),
        IdField(:room, "Room code"; required = false, placeholder = "e.g. C4.07"),
    ],
    session_key = "demo-session-key-2026")

#%% code id=header
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

The chart below plots the unemployment rate against the inflation rate for the same economy.
Hover a point to read its year. **Which period is most consistent with a stable short-run
Phillips curve?**

**a)** 2010–2013, where falling inflation accompanies rising unemployment

**b)** 2014–2019, where inflation is broadly flat while unemployment falls steadily

**c)** 2020–2022, where inflation rises sharply while unemployment falls

**d)** 2022–2024, where inflation falls while unemployment also falls
"""

#%% code id=q2chart hidecode
years = 2010:2024
unemp = [8.1, 9.4, 11.2, 12.8, 11.9, 10.4, 9.1, 8.0, 7.2, 6.7, 8.9, 7.4, 6.1, 5.8, 5.5]
infl  = [1.4, 3.6, 2.8, 0.4, -0.3, 0.5, 0.6, 1.4, 1.0, 0.3, -0.1, 1.3, 7.8, 5.3, 2.4]

echart(Dict(
    "__size" => Dict("height" => 380),          # Slate extension: the chart div's height
    # String templates only — an echart spec is serialised to JSON with no reviver, so a JS
    # function formatter would render as literal text. `{@[n]}` indexes the data dimensions.
    "tooltip" => Dict("trigger" => "item",
        "formatter" => "<b>{@[2]}</b><br/>Unemployment {@[0]}%<br/>Inflation {@[1]}%"),
    "grid" => Dict("left" => 60, "right" => 30, "top" => 40, "bottom" => 50),
    "xAxis" => Dict("type" => "value", "name" => "Unemployment (%)", "nameLocation" => "middle",
                    "nameGap" => 28),
    "yAxis" => Dict("type" => "value", "name" => "Inflation (%)", "nameLocation" => "middle",
                    "nameGap" => 38),
    "series" => [Dict(
        "type" => "scatter",
        "name" => "year",
        "symbolSize" => 14,
        "data" => [[u, i, string(y)] for (y, u, i) in zip(years, unemp, infl)],
        "label" => Dict("show" => true, "position" => "top", "formatter" => "{@[2]}",
                        "fontSize" => 12, "distance" => 7, "color" => "#c8cdd6"),
        # Years cluster tightly in the middle of this scatter; without this the labels overprint
        # each other into an illegible smudge. ECharts drops whichever would collide.
        "labelLayout" => Dict("hideOverlap" => true),
    )],
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
