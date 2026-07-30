try; import KaimonSlate; catch; error("This is a Kaimon Slate notebook — running it as plain Julia needs the KaimonSlate runtime in this environment. Add it with `import Pkg; Pkg.add(\"KaimonSlate\")`, or open it in Kaimon Slate."); end; KaimonSlate.standalone!(@__MODULE__; dir=@__DIR__)

#%% md id=intro title
@md"""
# The same notebook, drawn with ECharts
"""

#%% md id=abstract abstract
@md"""
A companion to the Plotly demo: the same three figures, the same three controls, the same data —
rendered through Slate's built-in `echart` DSL instead. Nothing is imported, because ECharts is core.

Each figure carries `dataZoom=(type=:inside,)`, so the wheel zooms the chart rather than only the
page. That is deliberate: it is what exercises Slate's chart scroll-zoom gate, which holds the wheel
back until you click into a chart and then scales it by the **Chart scroll-zoom** setting.

`@replay` works here too, so the controls keep working in a standalone export with no kernel — the same
claim the Plotly notebook makes, reached through `setOption` instead of `Plotly.restyle`.
"""

#%% code id=setup
# No imports. `echart` and `series` are Slate builtins, so unlike the Plotly notebook — which opens
# `using PlotlyJS, SlatePlotly` — there is nothing to load and nothing to have installed.
"ECharts · built into Slate, no packages"

#%% code id=data
# Monthly inflation: a mild cycle plus one sharp episode, narrow enough that the smoothing window
# visibly changes the peak. Identical to the Plotly notebook, so the two can be compared directly.
xs = collect(1:60)
infl = round.(2.0 .+ 0.45 .* sin.(xs ./ 3.2) .+ 0.25 .* cos.(xs ./ 1.7) .+
              4.5 .* exp.(-((xs .- 31.0) .^ 2) ./ (2 * 1.1^2)); digits = 2)

# Centred moving average; the window shrinks at the ends rather than dropping points, so the smoothed
# series spans the whole range.
function movavg(v, w)
    half = (w - 1) ÷ 2
    [begin
         lo, hi = max(1, i - half), min(length(v), i + half)
         round(sum(view(v, lo:hi)) / (hi - lo + 1); digits = 2)
     end for i in eachindex(v)]
end

"$(length(xs)) months · peak $(maximum(infl))%"

#%% md id=s3
@md"""
---
## A `@bind` control driving two series

An ordinary Slate `@bind` — other cells can read `w` too.

**Live**, moving the slider re-runs the cell below in Julia: `movavg(infl, w)` is genuinely recomputed,
and ECharts animates the change **in place** rather than redrawing, which is why the smoothed line
slides rather than jumping.

**In a standalone export** there is no kernel, so `@replay` computes the series for every position the
control can take, packs them as one binary array, and ships it with the page. Moving the slider then
indexes into that data. The author never names a series or a field — the option is walked and the
routing worked out from where the marked value ended up.

Try the wheel over this chart before and after clicking into it: outside, the page scrolls; once the
chart has focus its border lights up and the wheel zooms the x range.
"""

#%% code id=wbind
@bind w Slider(1:1:15; label = "Moving-average window")

#%% code id=fig_bound controls=w
echart(series(:line, xs, infl; name = "monthly", lineStyle = (width = 1, opacity = 0.45), symbol = "none"),
       series(:line, xs, @replay(w, movavg(infl, w)); name = "smoothed", lineStyle = (width = 3,), symbol = "none");
       title = "Centred moving average",
       height = 420,
       legend = true,
       xAxis = (name = "month",),
       yAxis = (name = "inflation (%)", min = 0, max = 7),
       dataZoom = [(type = :inside,)])

#%% md id=s4
@md"""
---
## A matrix, and a different kind of control

`@replay` is not limited to a series or to a slider. Here a whole **matrix** is replayed, driven by a
`Select`. The slices stack along a new trailing dimension, so one control value is still a contiguous
run in the shipped buffer — the page takes a view and reshapes it, never a gather.

Both axes take an inside `dataZoom`, so the wheel zooms the field in x and y together.
"""

#%% code id=kbind
@bind kern Select(["gaussian", "ripple", "saddle", "well"]; label = "Field")

#%% code id=fig_heat controls=kern
field(k) = [k == "gaussian" ? exp(-((x - 40)^2 + (y - 30)^2) / 320) :
            k == "ripple"   ? sin(hypot(x - 40, y - 30) / 4) :
            k == "saddle"   ? ((x - 40)^2 - (y - 30)^2) / 1600 :
                              -exp(-((x - 40)^2 + (y - 30)^2) / 900)
            for y in 1:60, x in 1:80]

echart(:heatmap, @replay(kern, field(kern));
       title = "60 × 80 field",
       height = 420,
       dataZoom = [(type = :inside, xAxisIndex = 0), (type = :inside, yAxisIndex = 0)])

#%% md id=s5
@md"""
---
## Scale

A **2 000-point** series over a **100-position** slider: 200 000 values, 1.6 MB packed. The cost is the
whole shipped array — `points × domain size × 8` bytes for `Float64` — and the control still moves at
full speed, because switching position is a contiguous read, not a recomputation.

This is also the chart to zoom hard on: the x axis relabels repeatedly as the range shrinks, which is
exactly the redraw path that made the Plotly figures judder before the margin handling was fixed.
"""

#%% code id=nbind
@bind σ Slider(1:100; label = "Smoothing σ")

#%% code id=fig_scale controls=σ
using Random

big_x = collect(1:2000)
big_y = cumsum(randn(Random.Xoshiro(42), 2000)) .+ 40

smooth(v, σ) = [sum(@view v[max(1, i - σ):min(length(v), i + σ)]) /
                (min(length(v), i + σ) - max(1, i - σ) + 1) for i in eachindex(v)]

echart(series(:line, big_x, big_y; name = "raw", lineStyle = (width = 0.7, opacity = 0.4), symbol = "none"),
       series(:line, big_x, @replay(σ, smooth(big_y, σ)); name = "smoothed", lineStyle = (width = 2.5,), symbol = "none");
       title = "2 000 points × 100 slider positions",
       height = 400,
       legend = true,
       xAxis = (name = "t",),
       yAxis = (name = "level",),
       dataZoom = [(type = :inside,)])

#%% md id=closing
@md"""
---
## What survives the export

Export with **Offline** ticked for a single file with no external subresources. Because the notebook
has `@replay` marks, a second dialog appears first: each one lists what it will compute and how many
bytes it will carry — measured from a real value, not estimated — and lets you lower a slider's
resolution to trade fidelity for size.

Nothing ECharts-specific was written to make that work. The mark, the packed sweep and the export
table are Slate's; what the renderer contributes is knowing where a marked value ended up in its own
option, and one call to put a slice back.

For ECharts that has to be settled while the series is being built, not by inspecting the finished
option: the DSL **zips**, so `(x, y)` becomes `[[x, y], …]` and a matrix becomes `[[x, y, v], …]`, and
the marked array is consumed element by element long before there is an option to walk. So the mark
records which **component** of each drawn entry it fed. The page rewrites just that slot in the
entries already on screen, reusing their coordinates — the zip layout is expressed once, in Julia,
and never restated in JavaScript — and `setOption` merges only that series, so the reader's zoom and
legend state survive every step of a drag.
"""

#%% code id=14e712 hidecode
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
#   docid = 5d017080-b5d9-4b76-85a2-a7b5b003d6cf
# ╚═╡
