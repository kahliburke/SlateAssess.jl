# The examiner's half: read submissions back, check they are intact, and mark them.
#
# This runs on the examiner's machine, long after the sitting, against files that arrived by email or a
# hand-in folder. It is the only place the correct answers ever exist.

"""
    Submission

One candidate's returned paper: their identity fields, their answers, when they started and submitted,
the signature the browser produced, and where the file came from.
"""
struct Submission
    identity::Dict{String,String}
    answers::Dict{String,Int}          # numeric codes — see `answer_code`
    env::Dict{String,String}           # environment facts captured at submission (Safe Exam Browser)
    started_at::String
    submitted_at::String
    signature::String
    source::String
end

"""
    sat_in_seb(s::Submission) -> Bool

Whether the browser reported a Safe Exam Browser environment when the paper was submitted.

A `false` here is a strong signal that the paper was completed in an ordinary browser. A `true` is
weaker evidence than it looks — with no server there is nothing to validate the reported keys against,
so treat it as "consistent with having been sat under the exam configuration", and compare
`s.env["seb_config_key"]` against the Config Key of the `.seb` file you actually issued.
"""
sat_in_seb(s::Submission) = !isempty(get(s.env, "seb_version", ""))

"""
    config_key_matches(s::Submission, expected) -> Bool

Whether the recorded Safe Exam Browser Config Key equals `expected` (the Config Key of the `.seb` file
issued for this sitting). `false` when nothing was recorded.
"""
function config_key_matches(s::Submission, expected::AbstractString)
    got = get(s.env, "seb_config_key", "")
    return !isempty(got) && got == String(expected)
end

"""
    read_submission(path, a::Assessment) -> Submission

Parse one submission CSV produced by the paper.

Throws if the file is not a submission for THIS assessment — a missing question column means the file
belongs to a different paper (or was truncated), and silently marking it would be worse than failing.
"""
function read_submission(path::AbstractString, a::Assessment)
    header, rows = read_csv(path)
    isempty(rows) && throw(ArgumentError("$(basename(path)): no data row"))
    length(rows) > 1 && @warn "$(basename(path)): $(length(rows)) data rows; using the first"
    row = rows[1]
    col = Dict(h => i for (i, h) in enumerate(header))
    get_(name, default = "") = (i = get(col, name, 0); i == 0 || i > length(row) ? default : row[i])

    missing_qs = [q for q in a.questions if !haskey(col, q)]
    isempty(missing_qs) || throw(ArgumentError(
        "$(basename(path)): not a submission for assessment '$(a.id)' — missing $(length(missing_qs)) " *
        "question column(s), first few: $(join(first(missing_qs, 5), ", "))"))

    identity = Dict{String,String}(String(f.key) => get_(String(f.key)) for f in a.identity)
    # Cells are numeric codes; a label is still accepted so a hand-corrected file, or one produced by
    # an older paper, reads without ceremony.
    answers = Dict{String,Int}(q => answer_code(a, get_(q)) for q in a.questions)
    env = Dict{String,String}(k => get_(k) for k in ENV_FIELDS)
    return Submission(identity, answers, env, get_("started_at"), get_("submitted_at"),
                      get_("signature"), String(path))
end

"""
    verify(s::Submission, a::Assessment) -> Bool

Recompute the signature and compare. `false` means the file changed after the browser produced it — or
that it was produced under a different `session_key`.

A submission signed in a non-secure browsing context carries an explicit `unsigned-…` marker instead of
a signature; that is reported as unverified rather than treated as tampering. See `src/hmac.jl` for what
a valid signature does and does not prove.
"""
function verify(s::Submission, a::Assessment)
    startswith(s.signature, "unsigned") && return false
    expected = sign_submission(a, s.identity, s.answers, s.submitted_at, s.env)
    # Constant-time-ish compare. Not security-critical here (the key is in the artifact anyway), but
    # there's no reason to write the leaky version.
    length(expected) == length(s.signature) || return false
    diff = 0
    for (x, y) in zip(codeunits(expected), codeunits(s.signature)); diff |= xor(x, y); end
    return diff == 0
end

"""
    Result

A marked submission: per-question correctness, the totals, and whether the file verified.
"""
struct Result
    submission::Submission
    correct::Int
    wrong::Int
    blank::Int
    flagged::Int
    score::Float64
    max_score::Float64
    verified::Bool
    per_question::Dict{String,Symbol}    # :correct | :wrong | :blank
end

"""
    grade(s::Submission, a::Assessment, key::AnswerKey) -> Result

Mark one submission. A question is `:blank` when the answer is the assessment's `no_response` value or
its flag marker (a flag means "come back to this" — the candidate is told it counts as unanswered), and
otherwise `:correct`/`:wrong` against the key. Questions absent from the key are skipped entirely, so a
partially-built key marks only what it covers.
"""
function grade(s::Submission, a::Assessment, key::AnswerKey)
    per = Dict{String,Symbol}()
    correct = wrong = blank = flagged = 0
    for q in a.questions
        haskey(key, q) || continue
        # The key may be written as a label ("c)") or as a code (3) — both normalise to the same number,
        # so an author can write whichever reads better in their marking script.
        want = answer_code(a, key[q])
        v = get(s.answers, q, ANSWER_NR)
        v == ANSWER_FLAG && (flagged += 1)
        if v == ANSWER_NR || v == ANSWER_FLAG
            per[q] = :blank; blank += 1
        elseif v == want
            per[q] = :correct; correct += 1
        else
            per[q] = :wrong; wrong += 1
        end
    end
    score = correct * a.marks.correct + wrong * a.marks.wrong + blank * a.marks.blank
    maxs = length(per) * a.marks.correct
    return Result(s, correct, wrong, blank, flagged, score, maxs, verify(s, a), per)
end

"""
    grade(dir::AbstractString, a::Assessment, key::AnswerKey; ext=".csv") -> Vector{Result}

Mark every submission in a directory. Files that cannot be read or that belong to another paper are
reported as warnings and skipped rather than aborting the run — one corrupt file should not stop a
cohort from being marked. Results come back sorted by the first identity field.
"""
function grade(dir::AbstractString, a::Assessment, key::AnswerKey; ext::AbstractString = ".csv")
    isdir(dir) || throw(ArgumentError("not a directory: $dir"))
    results = Result[]
    for f in sort(readdir(dir; join = true))
        (isfile(f) && lowercase(splitext(f)[2]) == ext) || continue
        try
            push!(results, grade(read_submission(f, a), a, key))
        catch e
            @warn "skipping $(basename(f))" exception = e
        end
    end
    primary = String(first(a.identity).key)
    sort!(results; by = r -> get(r.submission.identity, primary, ""))
    return results
end

"""
    report(results, a::Assessment) -> (header, rows)

The marks table: one row per candidate — identity fields, totals, score, and the verification flag —
ready for [`write_csv`](@ref).
"""
function report(results::AbstractVector{Result}, a::Assessment)
    idkeys = [String(f.key) for f in a.identity]
    header = vcat(idkeys, ["correct", "wrong", "blank", "flagged", "score", "max_score",
                           "verified", "in_seb", "seb_config_key", "started_at", "submitted_at", "file"])
    rows = Vector{Any}[]
    for r in results
        s = r.submission
        push!(rows, vcat(
            Any[get(s.identity, k, "") for k in idkeys],
            Any[r.correct, r.wrong, r.blank, r.flagged, round(r.score; digits = 3), r.max_score,
                r.verified ? "yes" : "NO", sat_in_seb(s) ? "yes" : "NO",
                get(s.env, "seb_config_key", ""), s.started_at, s.submitted_at,
                basename(s.source)]))
    end
    return (header, rows)
end

"""
    item_analysis(results, a::Assessment, key::AnswerKey) -> (header, rows)

Per-question statistics across the cohort: how many got it right, how many left it blank, how often each
option was chosen, and the facility (proportion correct among those who attempted it).

Worth looking at before releasing marks — a question everyone gets wrong, or where a distractor beats
the key, is usually a question with a problem rather than a cohort with one.
"""
function item_analysis(results::AbstractVector{Result}, a::Assessment, key::AnswerKey)
    codes = vcat(collect(1:length(a.choices)), [ANSWER_NR, ANSWER_FLAG])
    header = vcat(["question", "key", "key_code", "n", "correct", "blank", "facility"],
                  ["chose_" * answer_label(a, c) for c in codes])
    rows = Vector{Any}[]
    for q in a.questions
        haskey(key, q) || continue
        want = answer_code(a, key[q])
        marks = [get(r.per_question, q, :blank) for r in results]
        n = length(marks)
        ncorrect = count(==(:correct), marks)
        nblank = count(==(:blank), marks)
        attempted = n - nblank
        facility = attempted == 0 ? 0.0 : round(ncorrect / attempted; digits = 3)
        chosen = [count(r -> get(r.submission.answers, q, ANSWER_NR) == c, results) for c in codes]
        push!(rows, vcat(Any[q, answer_label(a, want), want, n, ncorrect, nblank, facility],
                         Any[c for c in chosen]))
    end
    return (header, rows)
end
