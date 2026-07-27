# An example spec for `scripts/grade.jl` — the paper definition plus the answer key.
#
# In practice you want ONE of these shared with the authoring notebook (`include("exam.jl")` at the top
# of the notebook, and point the marking script at the same file), so the paper that was sat and the
# paper that is marked cannot drift apart. Keep the key in a copy the candidates never see.

exam = Assessment("example-2026";
    title = "Example Assessment",
    subtitle = "Sample paper — 10 questions",
    questions = questions("q", 10),
    choices = ["a)", "b)", "c)", "d)", "e)"],
    marks = Marks(correct = 1.0, wrong = -0.25),
    duration = 30,
    # In a real paper read this from the environment so the key is not committed:
    #     session_key = ENV["EXAM_KEY"]
    session_key = "example-session-key")

key = AnswerKey(
    "q01" => "c)",
    "q02" => "a)",
    "q03" => "d)",
    "q04" => "b)",
    "q05" => "e)",
    "q06" => "a)",
    "q07" => "c)",
    "q08" => "b)",
    "q09" => "d)",
    "q10" => "a)",
)
