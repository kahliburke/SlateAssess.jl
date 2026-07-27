# The authoring model: what an assessment IS, independent of how it is rendered or graded.
#
# Deliberately small. An assessment carries the things that must be identical across the three places
# this data shows up — the live notebook, the exported HTML, and the marking script — and nothing else.
# Question PROSE is not modelled at all: it lives in the notebook's markdown cells, where the author can
# use the full document (figures, tables, math) instead of squeezing it into a string field.

"""
    IdField(key, label; required=true, pattern="", placeholder="", help="")

One field of the candidate identity form (student number, name, room code…).

`pattern` is a JavaScript regular expression *source* string, applied in the browser to validate the
entry — e.g. `raw"^\\d{5,8}\$"` for a numeric student number. An empty pattern accepts anything.
`required` fields must all be filled before the paper unlocks.
"""
struct IdField
    key::Symbol
    label::String
    required::Bool
    pattern::String
    placeholder::String
    help::String
end
IdField(key, label; required::Bool = true, pattern::AbstractString = "",
        placeholder::AbstractString = "", help::AbstractString = "") =
    IdField(Symbol(key), String(label), required, String(pattern), String(placeholder), String(help))

"""
    Marks(; correct=1.0, wrong=0.0, blank=0.0)

The mark scheme. Carried with the paper and used by [`grade`](@ref); `wrong` is normally negative when
the assessment corrects for guessing (a 5-option question guessed at random is neutral when
`wrong == -correct/4`).

These values are metadata only — **no marking happens in the browser**, so they can be edited after the
fact without reissuing the paper.
"""
struct Marks
    correct::Float64
    wrong::Float64
    blank::Float64
end
Marks(; correct::Real = 1.0, wrong::Real = 0.0, blank::Real = 0.0) =
    Marks(Float64(correct), Float64(wrong), Float64(blank))

"""
    Assessment(id; title, ...)

A paper: its identity, the shape of an answer, and how a submission is signed.

Note what is NOT here: **the correct answers.** They never enter the artifact a candidate receives, so
there is nothing in the delivered file to extract. Marking happens afterwards, from a separate
[`AnswerKey`](@ref) held by the examiner — see [`grade`](@ref).

# Keywords
- `title`, `subtitle` — shown in the fixed header.
- `questions` — the question ids, in order (e.g. `["q01", …, "q50"]`). See [`questions`](@ref).
- `choices` — the options offered per question (default `["a)", "b)", "c)", "d)", "e)"]`).
- `no_response` — the label for *not answered*, and always the recorded default (code `0`).
- `show_no_response` — whether to offer it as an explicit option. `true` (default) lets a candidate
  actively take an answer back, which matters on a long paper. `false` drops the control and leaves
  "unanswered" as simply not having picked anything — simpler, but then a choice can't be undone.
  Either way, unanswered records as `0` and reports as `no_response`.
- `flag` — an optional "come back to this" marker. Recorded distinctly, but counts as unanswered.
  Pass `flag = ""` to leave it out entirely.
- `identity` — the [`IdField`](@ref)s a candidate fills in before the paper unlocks.
- `marks` — the [`Marks`](@ref) scheme.
- `duration` — optional wall-clock limit; the header counts down and locks the paper at zero.
- `session_key` — the key the submission is signed with (see [`sign_submission`](@ref)). **This key is
  embedded in the delivered file**, so the signature is tamper-EVIDENCE against casual editing, not
  proof against a determined forger. Use a fresh key per sitting.
"""
struct Assessment
    id::String
    title::String
    subtitle::String
    questions::Vector{String}
    choices::Vector{String}
    no_response::String
    show_no_response::Bool
    flag::String
    identity::Vector{IdField}
    marks::Marks
    duration::Union{Nothing,Int}     # minutes
    session_key::String
end

const DEFAULT_IDENTITY = [
    IdField(:number, "Student number"; required = true, pattern = raw"^\d{4,10}$",
            placeholder = "e.g. 104857"),
    IdField(:name, "Full name"; required = true, placeholder = "As it appears on your student card"),
]

function Assessment(id::AbstractString;
                    title::AbstractString = "",
                    subtitle::AbstractString = "",
                    questions::AbstractVector = String[],
                    choices::AbstractVector = ["a)", "b)", "c)", "d)", "e)"],
                    no_response::AbstractString = "NR",
                    show_no_response::Bool = true,
                    flag::AbstractString = "🚩",
                    identity::AbstractVector{IdField} = DEFAULT_IDENTITY,
                    marks::Marks = Marks(),
                    duration = nothing,
                    session_key::AbstractString = "")
    qs = String[String(q) for q in questions]
    allunique(qs) || throw(ArgumentError("duplicate question id in `questions`: " *
        join(unique(q for q in qs if count(==(q), qs) > 1), ", ")))
    isempty(identity) && throw(ArgumentError("an assessment needs at least one identity field"))
    dur = duration === nothing ? nothing : Int(duration)
    (dur !== nothing && dur <= 0) && throw(ArgumentError("`duration` must be positive, got $dur"))
    return Assessment(String(id), String(title), String(subtitle), qs,
                      String[String(c) for c in choices], String(no_response), show_no_response,
                      String(flag), collect(identity), marks, dur, String(session_key))
end

"""
    questions(prefix, n) -> Vector{String}

Zero-padded question ids: `questions("q", 50)` → `["q01", …, "q50"]`. Convenience for the common case
of a numbered paper.

Always at least two digits, so a short paper still reads `q01` rather than `q1` — ids sort correctly as
plain strings, and a paper that grows past nine questions doesn't silently renumber the first nine.
"""
questions(prefix::AbstractString, n::Integer) =
    [string(prefix, lpad(i, max(2, ndigits(n)), '0')) for i in 1:n]

# ── How an answer is recorded ────────────────────────────────────────────────────────────────────
# On screen an option is a LABEL ("a)", "b)", …). In the submission it is a NUMBER: the 1-based index
# of the chosen option, with two reserved non-positive codes. Numbers are what you want in the file —
# they sort and tabulate properly, they survive a spreadsheet without becoming a date or losing a
# bracket, and they carry no assumption that options are even lettered.
#
# It also matters for shuffled variants: with per-candidate option orders (see `shuffled_key`) the
# POSITION is the meaningful thing, and a label would be ambiguous between papers.
const ANSWER_NR = 0        # no response — the default for every question
const ANSWER_FLAG = -1     # flagged for review; counts as unanswered, but recorded distinctly

"""
    answer_code(a::Assessment, value) -> Int

The number recorded for `value`: the 1-based option index, [`ANSWER_NR`](@ref) (0) for no response, or
[`ANSWER_FLAG`](@ref) (−1) for a flagged question. Accepts an option label, a code that is already
numeric, or the assessment's `no_response`/`flag` markers.
"""
function answer_code(a::Assessment, value)
    value === nothing && return ANSWER_NR
    if value isa Integer
        return Int(value)
    end
    s = strip(String(value))
    (isempty(s) || s == a.no_response) && return ANSWER_NR
    s == a.flag && return ANSWER_FLAG
    i = findfirst(==(s), a.choices)
    i === nothing || return i
    # A bare number that arrived as text (straight out of a CSV cell).
    n = tryparse(Int, s)
    n === nothing && throw(ArgumentError(
        "\"$s\" is not one of this assessment's options ($(join(a.choices, ", "))), " *
        "nor \"$(a.no_response)\"/\"$(a.flag)\", nor a numeric code"))
    return n
end

"""
    answer_label(a::Assessment, code) -> String

The human-readable option for a recorded code — the inverse of [`answer_code`](@ref). Out-of-range
codes come back as `"?"` rather than throwing, so a corrupt file can still be reported on.
"""
function answer_label(a::Assessment, code::Integer)
    code == ANSWER_NR && return a.no_response
    code == ANSWER_FLAG && return a.flag
    return 1 <= code <= length(a.choices) ? a.choices[code] : "?"
end

# Environment facts captured by the browser at submission time and covered by the signature. Fixed
# shape (empty strings when unavailable) so the signed message has a stable layout.
const ENV_FIELDS = ["seb_version", "seb_config_key", "seb_browser_exam_key"]

"""
    AnswerKey(pairs...)

The correct answer for each question — the examiner's half, kept OUT of the delivered paper.

```julia
key = AnswerKey("q01" => "c)", "q02" => "a)")
```
"""
struct AnswerKey
    answers::Dict{String,String}
end
# `string`, not `String` — a key may be written as a label ("c)") OR as a numeric code (3), and both must
# be accepted. `String(3)` is a MethodError; `string(3)` is "3", which `answer_code` parses back.
AnswerKey(pairs::Pair...) = AnswerKey(Dict{String,String}(string(k) => string(v) for (k, v) in pairs))
AnswerKey(d::AbstractDict) = AnswerKey(Dict{String,String}(string(k) => string(v) for (k, v) in d))

Base.getindex(k::AnswerKey, q::AbstractString) = k.answers[String(q)]
Base.haskey(k::AnswerKey, q::AbstractString) = haskey(k.answers, String(q))
Base.length(k::AnswerKey) = length(k.answers)
