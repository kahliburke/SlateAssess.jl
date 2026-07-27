# SlateAssess.jl

Multiple-choice assessments authored as [Kaimon Slate](https://github.com/kahliburke/KaimonSlate.jl)
notebooks, delivered as **one self-contained HTML file** that runs the whole paper in a browser with no
Julia, no server and no network.

Built for invigilated exams run under [Safe Exam Browser](https://safeexambrowser.org).

---

## The two properties that matter

**1. The correct answers are never in the delivered file.**

Nothing is marked in the browser. Candidates produce a signed submission; marking happens afterwards on
your machine against an `AnswerKey` that never left it. There is nothing in the artifact to extract —
not obfuscated, not hashed, simply absent.

**2. A submission is signed, so post-hoc edits are detectable.**

Each submission carries an HMAC-SHA256 over its identity fields, answers, environment and timestamp.
Open the CSV, change an answer, and it stops verifying.

Be clear-eyed about what this is: the signing key is embedded in the paper, because there is no server
to call. So the signature is **tamper-evidence**, not proof against a determined forger who reads the
page source. What it catches completely is the realistic case — a file opened in a spreadsheet and
adjusted, or passed between candidates and edited. Use a fresh `session_key` per sitting so a key
learned in one exam is worthless in the next.

---

## What survives the export

Slate's HTML export is static in the sense that **no Julia runs** — but it is not a picture of the
notebook:

| | In the exported file |
|---|---|
| ECharts figures | **live** — tooltips, legend toggles, zoom/pan, geo maps |
| Data tables | **live** — sortable, filterable, paged, CSV download |
| Math (KaTeX) | rendered |
| Makie figures | embedded as images (CairoMakie rasters) |
| `@bind` reactivity | **not available** — it needs the kernel |

Export with **Offline** ticked and the page inlines KaTeX, ECharts and the widget stack, so it has zero
external subresources and renders with no network at all. That matters for a locked-down exam machine,
and it means the paper still renders years later when a CDN has moved on.

---

## Authoring

Question *prose* lives in ordinary markdown cells, where you have the whole document available —
figures, tables, math. `SlateAssess` only supplies the answer controls.

```julia
using SlateAssess

exam = Assessment("macro-resit-2026";
    title     = "Macroeconomics — Resit",
    questions = questions("q", 50),          # ["q01", …, "q50"]
    choices   = ["a)", "b)", "c)", "d)", "e)"],
    marks     = Marks(correct = 0.4, wrong = -0.1),
    duration  = 90,                          # minutes; the header counts down and locks at zero
    identity  = [IdField(:number, "Student number"; pattern = raw"^\d{4,10}$"),
                 IdField(:name,   "Full name")],
    session_key = ENV["EXAM_KEY"])
```

Three widgets:

```julia
exam_header(exam)         # first cell — carries the runtime; the paper is locked until identity is confirmed
status_strip(exam)        # optional: a clickable grid of every question, coloured by state
answer_box(exam, "q01")   # under each question's markdown
submission_panel(exam)    # last cell — produces the signed submission
```

See `notebooks/demo_exam.jl` for a working five-question paper with a live chart and two data tables.

### What a candidate sees

- The paper stays locked until required identity fields are filled and validated.
- Each question offers the options plus **NR** (no response, the default) and 🚩 (flag for review).
  A flagged question is recorded as unanswered — the submission panel says so explicitly.
- Answers are written to `localStorage` on every change, so a crash or accidental reload does not cost
  the candidate their paper.
- With a `duration` set, the header counts down from the candidate's **first** confirmation and locks
  the paper at zero. The start stamp is persisted, so reloading does not hand back extra time, and
  re-opening the identity form to fix a typo does not reset the clock.

> **The countdown is a courtesy, not an enforcement mechanism.** With no server there is nothing
> authoritative to time against, and anyone who can open a browser console can clear the stored state.
> What actually evidences timing is `started_at` / `submitted_at` in the *signed* submission, read
> against the wall-clock window the sitting was invigilated over.

While **authoring**, that persistence is simply in the way — an expired clock from a test run leaves the
paper locked with no route back. Reset it from the console:

```js
SlateAssess.reset()      // clears identity, answers and the start stamp
SlateAssess._state()     // inspect what the paper currently holds
```
- The submission is offered both as a **download** and as **copy-out text**, because a locked-down
  browser may refuse downloads. The copy box is not a nicety; it is the fallback that keeps the paper
  submittable.

---

## The submission file

One row, numeric answers:

```
number,name,started_at,submitted_at,q01,q02,q03,...,seb_version,seb_config_key,seb_browser_exam_key,signature
104857,Ada Lovelace,2026-06-26T09:00:00Z,2026-06-26T10:28:11Z,3,1,-1,...,3.5.0,abc123…,def456…,955e5d86…
```

Answers are recorded as the **1-based option index**, with `0` = no response and `-1` = flagged.
Numbers tabulate and sort properly, survive a spreadsheet without becoming dates, and carry no
assumption that options are lettered — and with shuffled variants the *position* is the meaningful
thing anyway.

`answer_label(exam, code)` converts back for reading.

---

## Marking

```julia
key = AnswerKey("q01" => "c)", "q02" => 2, ...)     # a label or a code, whichever reads better
results = grade("submissions/", exam, key)

write_csv("marks.csv", report(results, exam)...)
write_csv("items.csv", item_analysis(results, exam, key)...)
```

or from the command line:

```console
$ julia --project scripts/grade.jl --spec exam.jl --submissions ./submissions --out ./marks
marked        : 214 submissions against 50 keyed questions
score         : mean 12.84  min -1.20  max 19.60  out of 20.0
verified      : 213 of 214
written to    : /path/to/marks

⚠ 1 submission(s) did NOT verify — see marks/unverified.txt
```

Exit status is `0` when everything verified and `1` when something did not, so it drops into a script
that should stop and ask a human.

`item_analysis` is worth reading before releasing marks — a question everyone gets wrong, or where a
distractor beats the key, is usually a question with a problem rather than a cohort with one.

---

## Anti-fraud tools

Beyond the two properties above:

**Safe Exam Browser detection.** SEB injects a `SafeExamBrowser` object exposing its version and (3.x+)
the Config Key and Browser Exam Key of the `.seb` configuration that launched it. The paper records
these into the *signed* submission, so `report` can tell you which candidates sat the paper under the
configuration you issued:

```julia
sat_in_seb(s)                        # was any exam-browser environment reported?
config_key_matches(s, expected)      # does it match the .seb file you distributed?
```

The limit, stated plainly: with no server there is nothing to validate these against at the time, and a
determined candidate can fake the object. It reliably distinguishes the ordinary cases — a paper sat in
Chrome, a paper sat under last year's config — and raises the effort required for the rest.

**Per-candidate variant papers.** `shuffled_key(exam, key, seed)` permutes the option order
deterministically and rewrites the key to match. Seed on the student number and copying a neighbour's
letters stops working. The same seed reproduces the same paper months later, so a queried mark can be
re-derived from the seed alone.

**Timing evidence.** `started_at` and `submitted_at` are both signed, so implausibly fast completions
are visible in `report`.

---

## Installation

```julia
import Pkg
Pkg.add(url = "https://github.com/kahliburke/SlateAssess.jl")
```

Runtime dependencies are `JSON` plus stdlibs. `DataFrames` and `StatsBase` are present for the demo
notebook.

## Tests

```console
$ julia --project -e 'using Pkg; Pkg.test()'
```

The suite checks the things that would be expensive to get wrong: that no answer key appears anywhere in
the rendered paper, that the HMAC matches RFC 4231 vectors, that a tampered submission fails
verification, and that a submission from a different paper is refused rather than mismarked.

## A note on the JavaScript

The client runtime (`assets/assess.js`) is a dependency-free classic script with its own SHA-256/HMAC in
plain JavaScript. That is deliberate: `crypto.subtle` is exposed only in a *secure context*, and a
`file://` origin is not one in Chrome or in the WKWebView that exam browsers embed — WebCrypto would be
`undefined` in exactly the delivery this package exists for. The portable implementation is validated
against Julia's `SHA` and RFC 4231 in the test suite.

## Licence

MIT.
