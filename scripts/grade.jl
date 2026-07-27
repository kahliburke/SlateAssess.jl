#!/usr/bin/env julia
#
# Mark a folder of submissions from the command line.
#
#     julia --project scripts/grade.jl --spec exam.jl --submissions ./submissions --out ./marks
#
# The spec file is plain Julia that defines two names — `exam` (an `Assessment`) and `key` (an
# `AnswerKey`). Keeping it as code rather than a config format means the paper definition can be the very
# same file the authoring notebook includes, so the marking run cannot drift from the paper that was sat.
# `scripts/example_spec.jl` is a working one.
#
# Writes three files into `--out`:
#   marks.csv          one row per candidate: identity, totals, score, and whether the file verified
#   item_analysis.csv  per-question facility and option counts — read this before releasing marks
#   unverified.txt     the submissions whose signature did not check out, if any
#
# Exit status is 0 when every submission verified, 1 when at least one did not, 2 on a usage error, so it
# can be dropped into a script that should stop and ask a human.

using SlateAssess

function usage(msg = "")
    isempty(msg) || println(stderr, "error: ", msg, "\n")
    println(stderr, """
    Mark a folder of SlateAssess submissions.

      julia --project scripts/grade.jl [options]

    Options:
      --spec PATH           Julia file defining `exam` and `key`      (default: exam.jl)
      --submissions PATH    folder of submitted .csv files            (default: submissions)
      --out PATH            folder to write the reports into          (default: marks)
      --quiet               only print the summary line
      -h, --help            show this

    The spec file must define:
      exam = Assessment("id"; questions = questions("q", 50), ...)
      key  = AnswerKey("q01" => "c)", ...)
    """)
    exit(isempty(msg) ? 0 : 2)
end

function parse_args(argv)
    opts = Dict{String,String}("spec" => "exam.jl", "submissions" => "submissions", "out" => "marks")
    quiet = false
    i = 1
    while i <= length(argv)
        a = argv[i]
        if a in ("-h", "--help")
            usage()
        elseif a == "--quiet"
            quiet = true
        elseif startswith(a, "--")
            name = a[3:end]
            haskey(opts, name) || usage("unknown option: $a")
            i + 1 <= length(argv) || usage("$a needs a value")
            opts[name] = argv[i + 1]
            i += 1
        else
            usage("unexpected argument: $a")
        end
        i += 1
    end
    return opts, quiet
end

function load_spec(path)
    isfile(path) || usage("spec file not found: $path")
    m = Module(:ExamSpec)
    Core.eval(m, :(using SlateAssess))
    try
        Base.include(m, abspath(path))
    catch e
        println(stderr, "error: could not load spec $path")
        rethrow(e)
    end
    isdefined(m, :exam) || usage("$path defines no `exam`")
    isdefined(m, :key) || usage("$path defines no `key`")
    return (getfield(m, :exam), getfield(m, :key))
end

function main(argv)
    opts, quiet = parse_args(argv)
    exam, key = load_spec(opts["spec"])
    isdir(opts["submissions"]) || usage("no such folder: $(opts["submissions"])")

    results = grade(opts["submissions"], exam, key)
    if isempty(results)
        println(stderr, "error: no submissions found in $(opts["submissions"])")
        exit(2)
    end

    mkpath(opts["out"])
    write_csv(joinpath(opts["out"], "marks.csv"), report(results, exam)...)
    write_csv(joinpath(opts["out"], "item_analysis.csv"), item_analysis(results, exam, key)...)

    bad = [r for r in results if !r.verified]
    unver = joinpath(opts["out"], "unverified.txt")
    if isempty(bad)
        rm(unver; force = true)
    else
        open(unver, "w") do io
            println(io, "Submissions whose signature did not verify — the file changed after the browser")
            println(io, "produced it, or it was signed with a different session key. Check each by hand.\n")
            for r in bad
                id = join((get(r.submission.identity, String(f.key), "") for f in exam.identity), " / ")
                println(io, basename(r.submission.source), "  ", id)
            end
        end
    end

    if !quiet
        scores = [r.score for r in results]
        maxs = isempty(results) ? 0.0 : first(results).max_score
        println("marked        : ", length(results), " submissions against ", length(key), " keyed questions")
        println("score         : mean ", round(sum(scores) / length(scores); digits = 2),
                "  min ", round(minimum(scores); digits = 2),
                "  max ", round(maximum(scores); digits = 2),
                "  out of ", maxs)
        println("verified      : ", count(r -> r.verified, results), " of ", length(results))
        println("written to    : ", abspath(opts["out"]))
    end
    if !isempty(bad)
        println(stderr, "\n⚠ ", length(bad), " submission(s) did NOT verify — see ", unver)
        exit(1)
    end
    exit(0)
end

abspath(PROGRAM_FILE) == abspath(@__FILE__) && main(ARGS)
