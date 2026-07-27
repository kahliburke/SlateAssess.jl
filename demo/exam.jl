# Must match the paper that was sat — same id, questions, choices and session_key.
exam = Assessment("demo-macro-2026";
    title = "Macroeconomics — Sample Assessment",
    questions = questions("q", 6),
    choices = ["a)", "b)", "c)", "d)"],
    show_no_response = false, flag = "",
    marks = Marks(correct = 2.0, wrong = -0.5),
    duration = 20,
    identity = [IdField(:number, "Student number"; pattern = raw"^\d{4,10}$"),
                IdField(:name, "Full name"),
                IdField(:room, "Room code"; required = false)],
    session_key = "demo-session-key-2026")

# The examiner's half — never present in the delivered paper.
key = AnswerKey(
    "q01" => "b)",   # 2020: output gap −6.54%, the only large negative
    "q02" => "a)",   # 2010–2013: the one monotone downward-sloping path
    "q03" => "b)",   # higher n ⇒ lower steady-state k* and y*
    "q04" => "b)",   # 2005–2014: cv 13.95, far the highest
    "q05" => "b)",   # negative supply shock, no tightening ⇒ output falls, prices rise
    "q06" => "c)",   # 7-month window is the smallest holding the peak ≤ 4%
)
