using Test
using SlateAssess
using SlateAssess: canonical_value, canonical_message, _config, _domid, AssessWidget

# A small paper reused across the tests.
const EXAM = Assessment("t-2026";
    title = "Test Paper",
    questions = questions("q", 5),
    choices = ["a)", "b)", "c)", "d)"],
    marks = Marks(correct = 2.0, wrong = -0.5),
    duration = 45,
    session_key = "test-key")

const KEY = AnswerKey("q01" => "c)", "q02" => "a)", "q03" => "d)", "q04" => "b)", "q05" => "a)")

render_html(w::AssessWidget) = sprint(show, MIME"text/html"(), w)

@testset "SlateAssess" begin

@testset "assessment construction" begin
    @test length(EXAM.questions) == 5
    @test EXAM.questions == ["q01", "q02", "q03", "q04", "q05"]
    @test questions("item", 12)[1] == "item01" && questions("item", 12)[12] == "item12"
    @test_throws ArgumentError Assessment("x"; questions = ["a", "a"])
    @test_throws ArgumentError Assessment("x"; identity = IdField[])
    @test_throws ArgumentError Assessment("x"; duration = 0)
end

@testset "the delivered paper contains no answers" begin
    # The single most important property of the whole design: nothing a candidate receives reveals the
    # key. Render every widget and assert the correct answers appear nowhere in the output.
    html = join([render_html(exam_header(EXAM)),
                 join(render_html(answer_box(EXAM, q)) for q in EXAM.questions),
                 render_html(status_strip(EXAM)),
                 render_html(submission_panel(EXAM))])
    cfg = _config(EXAM)
    @test !haskey(cfg, "key") && !haskey(cfg, "answers")
    # Every keyed answer, in a form that could only come from the key being embedded.
    for q in EXAM.questions
        @test !occursin("\"$q\":\"$(KEY[q])\"", html)
        @test !occursin("$q=$(KEY[q])", html)
    end
    @test !occursin("AnswerKey", html)
end

@testset "widget rendering" begin
    h = render_html(exam_header(EXAM))
    @test occursin("<style>", h) && occursin("<script>", h)         # self-contained: css + markup + js
    @test occursin("window.SlateAssess", h)                          # runtime rides with the header
    @test occursin("\"session_key\":\"test-key\"", h)                # signing key must reach the browser
    @test occursin(_domid(EXAM, "header"), h)

    q = render_html(answer_box(EXAM, "q03"))
    # Registration is QUEUED, never a direct call guarded on the runtime existing — a question cell
    # whose script runs before the header's must still mount once the header arrives.
    @test occursin("__saQueue", q) && occursin("[\"question\",el,\"q03\"]", q)
    @test !occursin("if(el&&window.SlateAssess)", q)
    @test !occursin("window.SlateAssess=", q)                        # runtime emitted ONCE, not per question
    @test length(q) < 1000                                           # a 50-question paper must stay small
    @test_throws ArgumentError answer_box(EXAM, "q99")

    # A `</script>` inside any injected content must not be able to close the tag early.
    tricky = Assessment("x</script><script>alert(1)</script>"; questions = ["q1"])
    @test !occursin("</script><script>alert", render_html(exam_header(tricky)))
end

@testset "answer codes" begin
    @test answer_code(EXAM, "a)") == 1 && answer_code(EXAM, "d)") == 4
    @test answer_code(EXAM, "NR") == ANSWER_NR == 0
    @test answer_code(EXAM, "🚩") == ANSWER_FLAG == -1
    @test answer_code(EXAM, "") == ANSWER_NR && answer_code(EXAM, nothing) == ANSWER_NR
    @test answer_code(EXAM, 3) == 3                  # already a code
    @test answer_code(EXAM, "3") == 3                # a code that came back as text from a CSV
    @test_throws ArgumentError answer_code(EXAM, "z)")
    @test answer_label(EXAM, 3) == "c)"
    @test answer_label(EXAM, ANSWER_NR) == "NR" && answer_label(EXAM, ANSWER_FLAG) == "🚩"
    @test answer_label(EXAM, 99) == "?"              # corrupt file reports rather than throws
    @test all(answer_code(EXAM, answer_label(EXAM, c)) == c for c in [-1, 0, 1, 2, 3, 4])
end

@testset "canonical message + signing" begin
    @test canonical_value(" a\nb\tc ") == "a b c"
    ident = Dict("number" => "12345", "name" => "A Candidate")
    ans = Dict("q01" => "c)", "q03" => "🚩")
    msg = canonical_message(EXAM, ident, ans, "2026-06-26T10:00:00Z")
    lines = split(msg, "\n")
    @test lines[1] == "number=12345"
    @test lines[2] == "name=A Candidate"
    @test lines[3] == "q01=3"                        # NUMERIC in the signed message, as in the file
    @test lines[4] == "q02=0"                        # absent ⇒ no response
    @test lines[5] == "q03=-1"                       # flagged
    @test lines[8] == "seb_version="                 # env fields always present, empty when unknown
    @test lines[end] == "submitted_at=2026-06-26T10:00:00Z"
    # A label and its code are the same submission, so they must sign identically.
    @test canonical_message(EXAM, ident, Dict("q01" => 3, "q03" => -1), "2026-06-26T10:00:00Z") == msg
    # The environment is COVERED by the signature — swapping it changes the message.
    @test canonical_message(EXAM, ident, ans, "2026-06-26T10:00:00Z",
                            Dict("seb_version" => "3.5")) != msg

    # RFC 4231 test case 1 — proves the HMAC itself, not just self-consistency.
    @test SlateAssess.hmac_sha256(String(repeat([0x0b], 20)), "Hi There") ==
          "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7"

    sig = sign_submission(EXAM, ident, ans, "2026-06-26T10:00:00Z")
    @test length(sig) == 64 && all(c -> c in "0123456789abcdef", sig)
    # Any change to any part of the submission changes the signature.
    @test sign_submission(EXAM, ident, merge(ans, Dict("q02" => "a)")), "2026-06-26T10:00:00Z") != sig
    @test sign_submission(EXAM, merge(ident, Dict("number" => "12346")), ans, "2026-06-26T10:00:00Z") != sig
    @test sign_submission(EXAM, ident, ans, "2026-06-26T10:00:01Z") != sig
end

@testset "CSV round-trip" begin
    mktempdir() do dir
        p = joinpath(dir, "t.csv")
        write_csv(p, ["a", "b", "c"], [["1", "x,y", "he said \"hi\""], ["2", "line\nbreak", ""]])
        header, rows = read_csv(p)
        @test header == ["a", "b", "c"]
        @test rows[1] == ["1", "x,y", "he said \"hi\""]
        @test rows[2] == ["2", "line\nbreak", ""]
    end
end

# Build a submission CSV the way the browser would, so the reader/verifier is exercised against the real
# on-the-wire shape rather than a hand-made struct.
function write_submission(dir, exam, ident, answers; at = "2026-06-26T11:00:00Z", tamper = nothing,
                          env = Dict{String,String}())
    sig = sign_submission(exam, ident, answers, at, env)
    header = vcat([String(f.key) for f in exam.identity], ["started_at", "submitted_at"],
                  exam.questions, SlateAssess.ENV_FIELDS, ["signature"])
    tampered = tamper === nothing ? answers : merge(answers, tamper)
    row = vcat([get(ident, String(f.key), "") for f in exam.identity],
               ["2026-06-26T10:00:00Z", at],
               [answer_code(exam, get(tampered, q, nothing)) for q in exam.questions],
               [get(env, k, "") for k in SlateAssess.ENV_FIELDS],
               [sig])
    path = joinpath(dir, get(ident, "number", "x") * ".csv")
    write_csv(path, header, [row])
    return path
end

@testset "reading, verifying and marking" begin
    mktempdir() do dir
        ident = Dict("number" => "10001", "name" => "Alice")
        # 3 correct, 1 wrong, 1 blank
        answers = Dict("q01" => "c)", "q02" => "a)", "q03" => "d)", "q04" => "a)", "q05" => "NR")
        p = write_submission(dir, EXAM, ident, answers)

        s = read_submission(p, EXAM)
        @test s.identity["number"] == "10001"
        @test s.answers["q04"] == 1                  # numeric code for "a)"
        @test verify(s, EXAM)
        @test !sat_in_seb(s)                         # no exam-browser environment recorded

        r = grade(s, EXAM, KEY)
        @test (r.correct, r.wrong, r.blank) == (3, 1, 1)
        @test r.score ≈ 3 * 2.0 + 1 * -0.5
        @test r.max_score ≈ 10.0
        @test r.verified
        @test r.per_question["q01"] == :correct && r.per_question["q04"] == :wrong

        # A flag counts as unanswered, and is reported separately.
        flagged = grade(read_submission(
            write_submission(dir, EXAM, Dict("number" => "10002", "name" => "Bob"),
                             merge(answers, Dict("q01" => "🚩"))), EXAM), EXAM, KEY)
        @test flagged.flagged == 1
        @test flagged.per_question["q01"] == :blank

        # Editing the file after the fact is caught.
        tp = write_submission(dir, EXAM, Dict("number" => "10003", "name" => "Mallory"),
                              answers; tamper = Dict("q04" => "b)"))
        ts = read_submission(tp, EXAM)
        @test !verify(ts, EXAM)
        @test grade(ts, EXAM, KEY).correct == 4          # marked as it reads…
        @test !grade(ts, EXAM, KEY).verified             # …but flagged for a human

        # Whole folder.
        rs = grade(dir, EXAM, KEY)
        @test length(rs) == 3
        @test [r.submission.identity["number"] for r in rs] == ["10001", "10002", "10003"]
        @test count(r -> r.verified, rs) == 2

        hdr, rows = report(rs, EXAM)
        @test hdr[1:2] == ["number", "name"]
        @test "verified" in hdr
        @test rows[3][findfirst(==("verified"), hdr)] == "NO"

        ihdr, irows = item_analysis(rs, EXAM, KEY)
        @test length(irows) == 5
        @test ihdr[1:3] == ["question", "key", "key_code"]
        @test irows[1][findfirst(==("key"), ihdr)] == "c)"
        @test irows[1][findfirst(==("key_code"), ihdr)] == 3

        # A file from a different paper is refused, not silently mismarked.
        other = Assessment("other"; questions = questions("z", 3), session_key = "k")
        @test_throws ArgumentError read_submission(p, other)
    end
end

@testset "exam-browser environment is captured and signed" begin
    mktempdir() do dir
        env = Dict("seb_version" => "3.5.0",
                   "seb_config_key" => "abc123configkey",
                   "seb_browser_exam_key" => "def456bek")
        answers = Dict("q01" => "c)", "q02" => "a)", "q03" => "d)", "q04" => "b)", "q05" => "a)")
        p = write_submission(dir, EXAM, Dict("number" => "20001", "name" => "Sat In SEB"),
                             answers; env = env)
        s = read_submission(p, EXAM)
        @test verify(s, EXAM)
        @test sat_in_seb(s)
        @test s.env["seb_version"] == "3.5.0"
        @test config_key_matches(s, "abc123configkey")
        @test !config_key_matches(s, "a-different-config")

        # The environment is inside the signature: editing it after the fact breaks verification, so a
        # candidate cannot sit the paper in an ordinary browser and paste in a plausible-looking key.
        header, rows = read_csv(p)
        rows[1][findfirst(==("seb_config_key"), header)] = "forged-config-key"
        write_csv(p, header, rows)
        forged = read_submission(p, EXAM)
        @test forged.env["seb_config_key"] == "forged-config-key"
        @test !verify(forged, EXAM)

        # A paper sat with no exam browser at all is plainly distinguishable.
        p2 = write_submission(dir, EXAM, Dict("number" => "20002", "name" => "Sat In Chrome"), answers)
        plain = read_submission(p2, EXAM)
        @test verify(plain, EXAM) && !sat_in_seb(plain)

        hdr, rrows = report([grade(s, EXAM, KEY), grade(plain, EXAM, KEY)], EXAM)
        @test rrows[1][findfirst(==("in_seb"), hdr)] == "yes"
        @test rrows[2][findfirst(==("in_seb"), hdr)] == "NO"
    end
end

@testset "shuffled variants are reproducible" begin
    o1, k1 = shuffled_key(EXAM, KEY, 42)
    o2, k2 = shuffled_key(EXAM, KEY, 42)
    o3, k3 = shuffled_key(EXAM, KEY, 43)
    @test o1 == o2 && k1.answers == k2.answers          # same seed ⇒ same paper, months later
    @test o1 != o3                                       # a different seed really is a different paper
    for q in EXAM.questions
        @test sort(o1[q]) == sort(EXAM.choices)          # a permutation, nothing lost or invented
        @test k1[q] in EXAM.choices
    end
end

@testset "grading script spec loads" begin
    spec = joinpath(@__DIR__, "..", "scripts", "example_spec.jl")
    m = Module(:S)
    Core.eval(m, :(using SlateAssess))
    Base.include(m, abspath(spec))
    @test getfield(m, :exam) isa Assessment
    @test length(getfield(m, :key)) == 10
end

end
