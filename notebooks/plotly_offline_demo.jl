try; import KaimonSlate; catch; error("This is a Kaimon Slate notebook — running it as plain Julia needs the KaimonSlate runtime in this environment. Add it with `import Pkg; Pkg.add(\"KaimonSlate\")`, or open it in Kaimon Slate."); end; KaimonSlate.standalone!(@__MODULE__; dir=@__DIR__)

#%% md id=intro title
@md"""
# Plotly in a standalone Slate notebook
"""

#%% md id=abstract abstract
@md"""
Existing `PlotlyJS.jl` code, rendered by Slate and exported to **one HTML file** that opens with no
Julia, no server and no network — figures fully interactive, `plotly.js` inlined, zero external requests.

Three levels of interactivity, in increasing order of what they ask of the author.
"""

#%% code id=setup
using PlotlyJS, SlatePlotly
"PlotlyJS $(pkgversion(PlotlyJS)) · SlatePlotly $(pkgversion(SlatePlotly))"

#%% code id=data
# Monthly inflation: a mild cycle plus one sharp episode, narrow enough that the smoothing window
# visibly changes the peak.
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
## A `@bind` control that still works with no kernel

The control is an ordinary Slate `@bind` — it looks and behaves like every other control in the
notebook, and other cells can read `w` too.

**Live**, moving the slider re-runs the cell below in Julia: `movavg(infl, w)` is genuinely recomputed.

**In a standalone export** there is no kernel, so `@replay` computes the series for every position the
control can take, packs them as one binary array, and ships it with the page. Moving the slider then
indexes into that data.

The whole extra ask is the macro. The author never names a trace or a field, and never restates the
domain — it is read from the control, so it cannot drift out of sync with it.
"""

#%% code id=wbind
@bind w Slider(1:1:15; label = "Moving-average window")

#%% code id=fig_bound controls=w
# The smoothed series is REPLAYABLE: `@replay` computes it for every position the slider can take, ships
# the lot as one packed binary array, and returns the slice for the current `w`. Live this is ordinary
# Julia; in a standalone export the slider indexes the shipped data instead.
#
# Note what is NOT written here: the domain. It comes from the control itself, so it cannot drift.
Plot([scatter(x = xs, y = infl, mode = "lines", name = "monthly",
              line = attr(width = 1), opacity = 0.45),
      scatter(x = xs, y = @replay(w, movavg(infl, w)), mode = "lines",
              name = "smoothed", line = attr(width = 3))],
     Layout(title = "Centred moving average",
            height = 420,
            xaxis = attr(title = "month"),
            yaxis = attr(title = "inflation (%)", range = [0, 7])))

#%% md id=s4
@md"""
---
## Pushing on it — a matrix, and a different kind of control

`@replay` is not limited to a series or to a slider. Here a whole **matrix** (a heatmap's `z`) is
replayed, driven by a `Select`. The slices stack along a new trailing dimension, so one control value is
still a contiguous run in the shipped buffer — the page takes a view and reshapes it, never a gather.
"""

#%% code id=kbind
@bind kern Select(["gaussian", "ripple", "saddle", "well"]; label = "Field")

#%% code id=fig_heat controls=kern
field(k) = [k == "gaussian" ? exp(-((x - 40)^2 + (y - 30)^2) / 320) :
            k == "ripple"   ? sin(hypot(x - 40, y - 30) / 4) :
            k == "saddle"   ? ((x - 40)^2 - (y - 30)^2) / 1600 :
                              -exp(-((x - 40)^2 + (y - 30)^2) / 900)
            for y in 1:60, x in 1:80]

Plot(heatmap(z = @replay(kern, field(kern)), colorscale = "Viridis"),
     Layout(title = "60 × 80 field, replayed across 4 options", height = 420,
            xaxis = attr(title = "x"), yaxis = attr(title = "y")))

#%% md id=s5
@md"""
---
## How far does this go?

The cost is the whole shipped array: `points × domain size × 8` bytes for `Float64`. That is the only
limit — there is no per-position figure, no duplicated spec, and nothing recomputed at export time.

Below: a **2 000-point** series over a **100-position** slider. That is 200 000 values, 1.6 MB packed —
and the control still moves at full speed, because switching position is a contiguous read, not a
recomputation.
"""

#%% code id=nbind
@bind σ Slider(1:100; label = "Smoothing σ")

#%% code id=fig_scale controls=σ
using Random

big_x = collect(1:2000)
big_y = cumsum(randn(Random.Xoshiro(42), 2000)) .+ 40

# A 100-position control over a 2000-point series: 200 000 values, 1.6 MB packed.
smooth(v, σ) = [sum(@view v[max(1, i - σ):min(length(v), i + σ)]) /
                (min(length(v), i + σ) - max(1, i - σ) + 1) for i in eachindex(v)]

Plot([scatter(x = big_x, y = big_y, mode = "lines", name = "raw",
              line = attr(width = 0.7), opacity = 0.4),
      scatter(x = big_x, y = @replay(σ, smooth(big_y, σ)), mode = "lines",
              name = "smoothed", line = attr(width = 2.5))],
     Layout(title = "2 000 points × 100 slider positions", height = 400,
            xaxis = attr(title = "t"), yaxis = attr(title = "level")))

#%% md id=closing
@md"""
---
## What survives the export

Export with **Offline** ticked for a single file with no external subresources. When the notebook has
`@replay` marks, a second dialog appears first: each one lists what it will compute and how many bytes
it will carry — measured from a real value, not estimated — and lets you lower a slider's resolution to
carry less. That choice is stored in the notebook, so it travels with the file.

| | In the exported file |
|---|---|
| Plotly figures | **live** — hover, legend, zoom/pan, modebar |
| `plotly.js` itself | inlined from a version-pinned artifact |
| A `@bind` with `@replay` data | **live** — the control indexes shipped data |
| A `@bind` with no replay data | rendered, but **disabled** — visibly inert rather than silently dead |
| Any other `@bind` reactivity | not available; it needs the kernel |

A control is enabled only when data for it actually shipped, so a reader can tell at a glance which
knobs still do something.

### What it costs

The shipped array is `points × values × 4` bytes once narrowed to 32-bit at export. The three figures
above carry ~1.7 MB at full resolution; at *every 5th* on the largest one, ~470 kB. Compression is
optional — it saves roughly a further 18% but needs a 2023-or-newer browser to read, so a page bound for
an old locked-down machine should leave it off.
"""

# ╔═╡ Slate.config · per-notebook settings (Settings panel)
#   replaystrides = fig_scale%3A%CF%83:4
#   docid = 90249a87-d08e-4633-80b1-fc56cc855edd
# ╚═╡
