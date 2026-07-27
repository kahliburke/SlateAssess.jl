# Rendering: turning an `Assessment` into cell output that behaves identically live and in a static export.
#
# The output shape — one `text/html` chunk holding `<style>`, markup, and a classic `<script>` — is the
# same one Slate's own `WebPage` produces, and is handled by the same paths: the front end revives the
# script in the live notebook, and it runs natively when the page is opened as a file. Reimplementing it
# in four lines here (rather than depending on the extension SDK) keeps this package installable with
# nothing but `Pkg.add` and a URL.

const _ASSETS = normpath(joinpath(@__DIR__, "..", "assets"))
_asset(name) = read(joinpath(_ASSETS, name), String)

"""
    AssessWidget

A rendered piece of an assessment. Displays as a single self-contained `text/html` output.
"""
struct AssessWidget
    html::String
    css::String
    js::String
end

function Base.show(io::IO, ::MIME"text/html", w::AssessWidget)
    isempty(w.css) || print(io, "<style>", replace(w.css, "</style>" => "<\\/style>"), "</style>")
    print(io, w.html)
    isempty(w.js) || print(io, "<script>", replace(w.js, "</script>" => "<\\/script>"), "</script>")
    return nothing
end
Base.show(io::IO, ::MIME"text/plain", w::AssessWidget) = print(io, "AssessWidget(", length(w.html) +
    length(w.css) + length(w.js), " bytes)")

# A stable DOM id per (assessment, role, subject). Deterministic so re-running a cell reuses the same
# node instead of accumulating duplicates, and so an exported page's ids match the live one's.
_domid(a::Assessment, role::AbstractString, sub::AbstractString = "") =
    "sa-" * replace(string(a.id, "-", role, isempty(sub) ? "" : "-" * sub),
                    r"[^A-Za-z0-9_-]" => "_")

# The config handed to the browser. Note what is absent: no answers, no key, no marking. `marks` rides
# along only so a paper can show candidates what a question is worth.
function _config(a::Assessment)
    return Dict{String,Any}(
        "id" => a.id,
        "title" => a.title,
        "subtitle" => a.subtitle,
        "questions" => a.questions,
        "choices" => a.choices,
        "no_response" => a.no_response,
        "flag" => a.flag,
        "identity" => [Dict{String,Any}("key" => String(f.key), "label" => f.label,
                                        "required" => f.required, "pattern" => f.pattern,
                                        "placeholder" => f.placeholder, "help" => f.help)
                       for f in a.identity],
        "marks" => Dict("correct" => a.marks.correct, "wrong" => a.marks.wrong, "blank" => a.marks.blank),
        "duration" => a.duration === nothing ? nothing : a.duration,
        "session_key" => a.session_key,
    )
end

# Mount one widget: a container div, then a script that hands the element to the runtime. Registration
# goes through the runtime's queue, so cells may be run in any order.
# `kind` is the queue tag the runtime dispatches on ("header" / "question" / "status" / "submission");
# `arg` is an optional extra the mount needs (a question id).
function _mount(a::Assessment, role::AbstractString, kind::AbstractString; sub::AbstractString = "",
                arg = nothing, runtime::Bool = false, css::Bool = false)
    id = _domid(a, role, sub)
    entry = string("[", JSON.json(kind), ",el", arg === nothing ? "" : "," * JSON.json(arg), "]")
    # Registration goes onto the queue UNCONDITIONALLY, then drains if the runtime is already up. The
    # tempting `if (window.SlateAssess) …mount…` guard is wrong: a cell whose script runs before the
    # header's would silently do nothing and never be retried, leaving a dead widget on the page.
    js = string(runtime ? _asset("assess.js") * "\n" : "",
                runtime ? string("window.SlateAssess.init(", JSON.json(_config(a)), ");\n") : "",
                "(function(){var el=document.getElementById(", JSON.json(id), ");if(!el)return;",
                "(window.__saQueue=window.__saQueue||[]).push(", entry, ");",
                "if(window.SlateAssess)window.SlateAssess._drain();})();")
    return AssessWidget(string("<div id=\"", id, "\"></div>"), css ? _asset("assess.css") : "", js)
end

"""
    exam_header(a::Assessment) -> AssessWidget

The top of the paper: title, the identity form, the confirm control, a live tally, and the countdown
when the assessment has a duration.

**Put this in the first cell.** It carries the runtime and the styling for every other widget, and the
paper stays locked until a candidate confirms valid details here.
"""
exam_header(a::Assessment) = _mount(a, "header", "header"; runtime = true, css = true)

"""
    answer_box(a::Assessment, qid) -> AssessWidget

The answer control for one question: the options, plus "no response" and the review flag.

Put it in a code cell directly below the markdown cell holding the question. The question's PROSE stays
in markdown, where you have the whole document available — figures, tables, math — rather than being
squeezed into a string.

```julia
answer_box(exam, "q01")
```
"""
function answer_box(a::Assessment, qid::AbstractString)
    q = String(qid)
    q in a.questions || throw(ArgumentError(
        "question id \"$q\" is not in this assessment; known ids: " *
        (length(a.questions) > 6 ? join(first(a.questions, 6), ", ") * ", …" : join(a.questions, ", "))))
    return _mount(a, "q", "question"; sub = q, arg = q)
end

"""
    status_strip(a::Assessment) -> AssessWidget

A clickable grid of every question, coloured by answered / flagged / blank. Handy near the top or bottom
of a long paper — a candidate can see what is left and jump straight to it.
"""
status_strip(a::Assessment) = _mount(a, "status", "status")

"""
    submission_panel(a::Assessment) -> AssessWidget

The end of the paper: a summary of what has been answered, and the control that produces the signed
submission file.

Offers the submission both as a download and as copy-out text, because a locked-down browser may refuse
downloads — the copy box is the fallback that keeps the paper submittable when it does.
"""
submission_panel(a::Assessment) = _mount(a, "submit", "submission")
