#!/usr/bin/env julia
#
# Generate a synthetic cohort of signed submissions, for demonstrating and testing the marking side
# without needing a real sitting.
#
#     julia --project scripts/make_demo_submissions.jl --spec exam.jl --out ./submissions --n 200
#
# The responses are not random noise — that would produce a cohort with no structure and therefore no
# interesting statistics. Each candidate gets a latent ability and each question a difficulty, and
# answers are drawn from a Rasch model, so the resulting facilities and item–total correlations behave
# the way real assessment data does. Wrong answers prefer a designated distractor, more strongly for
# weaker candidates, which is what makes distractor analysis worth plotting.
#
# Every file is signed with the spec's `session_key`, so the whole cohort verifies.

using SlateAssess
using Random, Dates, Printf

function usage(msg = "")
    isempty(msg) || println(stderr, "error: ", msg, "\n")
    println(stderr, """
    Generate a synthetic cohort of signed submissions.

      julia --project scripts/make_demo_submissions.jl [options]

    Options:
      --spec PATH     Julia file defining `exam` and `key`   (default: exam.jl)
      --out PATH      folder to write submissions into       (default: submissions)
      --n N           how many candidates                    (default: 200)
      --seed N        RNG seed, for a reproducible cohort    (default: 20260727)
      -h, --help      show this
    """)
    exit(isempty(msg) ? 0 : 2)
end

function parse_args(argv)
    o = Dict{String,String}("spec" => "exam.jl", "out" => "submissions",
                            "n" => "200", "seed" => "20260727")
    i = 1
    while i <= length(argv)
        a = argv[i]
        a in ("-h", "--help") && usage()
        startswith(a, "--") || usage("unexpected argument: $a")
        k = a[3:end]
        haskey(o, k) || usage("unknown option: $a")
        i + 1 <= length(argv) || usage("$a needs a value")
        o[k] = argv[i+1]; i += 2
    end
    return o
end

function load_spec(path)
    isfile(path) || usage("spec file not found: $path")
    m = Module(:ExamSpec)
    Core.eval(m, :(using SlateAssess))
    Base.include(m, abspath(path))
    # See scripts/grade.jl — on Julia 1.12+ these bindings are created in a newer world than this
    # function is running in, so they are invisible without stepping into the current world.
    ok(s) = Base.invokelatest(isdefined, m, s)
    ok(:exam) || usage("$path defines no `exam`")
    ok(:key) || usage("$path defines no `key`")
    return (Base.invokelatest(getfield, m, :exam), Base.invokelatest(getfield, m, :key))
end

const FIRST = ["Ana", "Bruno", "Carla", "Diogo", "Eva", "Filipe", "Gabriela", "Hugo", "Inês",
               "João", "Katia", "Luís", "Mariana", "Nuno", "Olívia", "Pedro", "Quitéria", "Rita",
               "Sofia", "Tiago", "Ursula", "Vasco", "Wanda", "Xavier", "Yara", "Zé", "Beatriz",
               "Carlos", "Daniela", "Eduardo", "Francisca", "Gonçalo", "Helena", "Ivo", "Joana",
               "Leonor", "Miguel", "Nadia", "Otávio", "Patrícia", "Raquel", "Simão", "Teresa"]
const LAST = ["Almeida", "Barbosa", "Costa", "Dias", "Esteves", "Ferreira", "Gomes", "Henriques",
              "Iglesias", "Jesus", "Lopes", "Martins", "Neves", "Oliveira", "Pereira", "Queirós",
              "Ribeiro", "Santos", "Teixeira", "Vieira", "Xavier", "Zambujo", "Cardoso", "Moreira",
              "Fonseca", "Rocha", "Antunes", "Pinto", "Correia", "Marques"]

logistic(x) = 1 / (1 + exp(-x))

function main(argv)
    o = parse_args(argv)
    exam, key = load_spec(o["spec"])
    n = parse(Int, o["n"])
    rng = Random.MersenneTwister(parse(Int, o["seed"]))
    mkpath(o["out"])

    nq = length(exam.questions)
    nopt = length(exam.choices)

    # Item difficulties spread across the ability range, plus for each item the distractor that will
    # attract the most wrong answers (a "near-miss" option, which is what a well-built paper has).
    difficulty = [(-1.6 + 3.2 * (j - 1) / max(1, nq - 1)) for j in 1:nq]
    shuffle!(rng, difficulty)
    attractive = Dict{String,Int}()
    for (j, q) in enumerate(exam.questions)
        correct = answer_code(exam, key[q])
        wrong = [c for c in 1:nopt if c != correct]
        attractive[q] = rand(rng, wrong)
    end

    exam_start = DateTime(2026, 6, 26, 9, 0, 0)
    used = Set{String}()
    written = 0

    for i in 1:n
        ability = randn(rng) * 1.0
        number = ""
        while true
            number = string(100000 + rand(rng, 0:899999))
            number in used || break
        end
        push!(used, number)
        name = string(rand(rng, FIRST), " ", rand(rng, LAST))
        room = rand(rng, ["A2.01", "A2.02", "B1.14", "C4.07"])

        answers = Dict{String,Int}()
        for (j, q) in enumerate(exam.questions)
            correct = answer_code(exam, key[q])
            p = logistic(ability - difficulty[j])
            # Weaker candidates leave more blank, and blanks rise a little over the paper (time pressure).
            p_blank = clamp(0.04 - 0.03 * ability + 0.015 * (j / nq), 0.0, 0.30)
            if rand(rng) < p_blank
                answers[q] = ANSWER_NR
            elseif rand(rng) < p
                answers[q] = correct
            else
                # Wrong: the attractive distractor dominates, and dominates more for weaker candidates.
                wrong = [c for c in 1:nopt if c != correct]
                w = [c == attractive[q] ? (2.6 - 0.5 * ability) : 1.0 for c in wrong]
                w ./= sum(w)
                r = rand(rng); acc = 0.0; pick = wrong[end]
                for (c, wi) in zip(wrong, w)
                    acc += wi
                    if r <= acc; pick = c; break; end
                end
                answers[q] = pick
            end
        end

        # Stronger candidates finish sooner, with plenty of noise; everyone is inside the window.
        minutes = clamp(14.0 - 2.2 * ability + randn(rng) * 3.0, 3.5, 19.8)
        started = exam_start + Millisecond(round(Int, rand(rng) * 90_000))
        submitted = started + Millisecond(round(Int, minutes * 60_000))
        iso(t) = Dates.format(t, dateformat"yyyy-mm-dd\THH:MM:SS.sss\Z")

        identity = Dict("number" => number, "name" => name, "room" => room)
        # This cohort was not sat under an exam browser; the fields are present but empty, which is
        # exactly what a paper taken in an ordinary browser records.
        env = Dict(k => "" for k in SlateAssess.ENV_FIELDS)
        sig = sign_submission(exam, identity, answers, iso(submitted), env)

        header = vcat([String(f.key) for f in exam.identity], ["started_at", "submitted_at"],
                      exam.questions, SlateAssess.ENV_FIELDS, ["signature"])
        row = vcat([get(identity, String(f.key), "") for f in exam.identity],
                   [iso(started), iso(submitted)],
                   [answers[q] for q in exam.questions],
                   ["" for _ in SlateAssess.ENV_FIELDS],
                   [sig])
        write_csv(joinpath(o["out"], number * ".csv"), header, [row])
        written += 1
    end

    @printf("wrote %d signed submissions to %s\n", written, abspath(o["out"]))
    println("item difficulties (Rasch b): ",
            join((@sprintf("%s=%.2f", q, difficulty[j]) for (j, q) in enumerate(exam.questions)), "  "))
end

abspath(PROGRAM_FILE) == abspath(@__FILE__) && main(ARGS)
