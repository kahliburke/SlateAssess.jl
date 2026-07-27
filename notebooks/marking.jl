try; import KaimonSlate; catch; error("This is a Kaimon Slate notebook — running it as plain Julia needs the KaimonSlate runtime in this environment. Add it with `import Pkg; Pkg.add(\"KaimonSlate\")`, or open it in Kaimon Slate."); end; KaimonSlate.standalone!(@__MODULE__; dir=@__DIR__)

#%% code id=setup
using SlateAssess
using DataFrames, StatsBase

#%% code id=paper
exam = Assessment("demo-macro-2026";
    title = "Macroeconomics — Sample Assessment",
    questions = questions("q", 6),
    choices = ["a", "b", "c", "d"],
    show_no_response = false, flag = "",
    marks = Marks(correct = 2.0, wrong = -0.5),
    duration = 20,
    identity = [IdField(:number, "Student number"; pattern = raw"^\d{4,10}$"),
                IdField(:name, "Full name"),
                IdField(:room, "Room code"; required = false)],
    session_key = "demo-session-key-2026")

key = AnswerKey("q01" => "b", "q02" => "a", "q03" => "b",
                "q04" => "b", "q05" => "b", "q06" => "c")
nothing

#%% md id=loadtxt
@md"""
## Submissions
"""

#%% code id=load
results = grade(joinpath(pkgdir(SlateAssess), "demo", "submissions"), exam, key)
scores = [r.score for r in results]
bad = [r for r in results if !r.verified]

isempty(bad) ?
    "$(length(results)) submissions, all signatures verified." :
    "$(length(results)) submissions — ⚠ $(length(bad)) FAILED verification: " *
    join((basename(r.submission.source) for r in bad), ", ")

#%% md id=markstxt
@md"""
## Marks
"""

#%% code id=marks
marks = DataFrame(
    number  = [r.submission.identity["number"] for r in results],
    name    = [r.submission.identity["name"] for r in results],
    correct = [r.correct for r in results],
    wrong   = [r.wrong for r in results],
    blank   = [r.blank for r in results],
    score   = [round(r.score; digits = 2) for r in results],
    percent = [round(100 * r.score / r.max_score; digits = 1) for r in results],
)
sort!(marks, :score; rev = true)
slate_table(marks,
   viz=(percent = :heat,)
)

#%% code id=stats
out_of = first(results).max_score
pass = count(s -> s >= out_of / 2, scores)
slate_table(DataFrame(
    statistic = ["students", "mean", "median", "highest", "lowest",
                 "at or above half marks", "out of"],
    value = [string(length(scores)),
             string(round(mean(scores); digits = 2)),
             string(round(median(scores); digits = 2)),
             string(round(maximum(scores); digits = 2)),
             string(round(minimum(scores); digits = 2)),
             "$pass of $(length(scores))",
             string(round(out_of; digits = 1))]
))

#%% md id=disttxt
@md"""
## Spread of scores
"""

#%% code id=histogram hidecode
# One bar per whole mark; green at or above half marks.
lo, hi = floor(minimum(scores)), ceil(maximum(scores))
bins = collect(lo:1.0:hi)
freq = [count(s -> b <= s < b + 1, scores) for b in bins]
freq[end] += count(==(hi), scores)   # top bin is closed

echart(Dict(
    "__size" => Dict("height" => 320),
    "tooltip" => Dict("trigger" => "item", "formatter" => "score {b} — <b>{c}</b> students"),
    "grid" => Dict("left" => 56, "right" => 24, "top" => 24, "bottom" => 48),
    "xAxis" => Dict("type" => "category", "data" => [string(b) for b in bins], "name" => "score",
                    "nameLocation" => "middle", "nameGap" => 28),
    "yAxis" => Dict("type" => "value", "name" => "students",
                    "nameLocation" => "middle", "nameGap" => 34),
    "series" => [Dict("type" => "bar",
        "data" => [Dict("value" => f,
                        "itemStyle" => Dict("color" => bins[i] >= out_of / 2 ? "#4ec9a0" : "#f2635f"))
                   for (i, f) in enumerate(freq)])],
))

#%% md id=qtxt
@md"""
## How each question went
"""

#%% code id=perq hidecode
qs = exam.questions
nres(q, s) = count(r -> get(r.per_question, q, :blank) == s, results)
pct_correct = [round(100 * nres(q, :correct) / length(results); digits = 1) for q in qs]

slate_table(DataFrame(
    question    = qs,
    answer      = [answer_label(exam, answer_code(exam, key[q])) for q in qs],
    correct     = [nres(q, :correct) for q in qs],
    wrong       = [nres(q, :wrong) for q in qs],
    blank       = [nres(q, :blank) for q in qs],
    pct_correct = pct_correct,
))

#%% code id=qchart hidecode
echart(Dict(
    "__size" => Dict("height" => 300),
    "tooltip" => Dict("trigger" => "item", "formatter" => "{b} — <b>{c}%</b> correct"),
    "grid" => Dict("left" => 56, "right" => 24, "top" => 24, "bottom" => 48),
    "xAxis" => Dict("type" => "category", "data" => qs, "name" => "question",
                    "nameLocation" => "middle", "nameGap" => 28),
    "yAxis" => Dict("type" => "value", "max" => 100, "name" => "% correct",
                    "nameLocation" => "middle", "nameGap" => 38),
    "series" => [Dict("type" => "bar",
        "data" => [Dict("value" => p,
                        "itemStyle" => Dict("color" => p < 30 ? "#f2635f" :
                                                       p < 50 ? "#e0b341" : "#4ec9a0"))
                   for p in pct_correct],
        "label" => Dict("show" => true, "position" => "top", "formatter" => "{c}%",
                        "color" => "#c8cdd6"))],
))

#%% md id=savetxt
@md"""
## Save
"""

#%% code id=save hidecode
outdir = joinpath(pkgdir(SlateAssess), "demo", "marks")
mkpath(outdir)
write_csv(joinpath(outdir, "marks.csv"), report(results, exam)...)
"wrote $(joinpath(outdir, "marks.csv"))"

#%% code id=e7f5d9 hidecode
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
#   docid = 9329413c-d19a-4621-9946-69a6f6330ca1
# ╚═╡
