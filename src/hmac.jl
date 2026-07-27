# Submission signing — HMAC-SHA256 over a canonical serialisation of a submission.
#
# WHAT THIS BUYS YOU, precisely: the delivered paper contains the signing key (it has to — the browser
# does the signing with no server to call), so anyone willing to read the page source can mint a valid
# signature. What the signature reliably catches is a submission that was EDITED AFTER IT WAS PRODUCED:
# a spreadsheet opened and a couple of answers changed, a file passed between candidates and adjusted, a
# timestamp altered. That is the realistic failure mode for an invigilated sitting, and it is caught
# completely. It is not, and cannot be, proof against a candidate who reverse-engineers the page.
#
# Use a fresh `session_key` per sitting so a key learned in one exam is worthless in the next.
#
# The canonical message is built IDENTICALLY here and in assets/assess.js — the two must agree byte for
# byte or verification fails, so they are specified once, here, and the JS mirrors it:
#
#     <field1>=<value1>\n … <fieldN>=<valueN>
#     <q01>=<answer>\n … <qNN>=<answer>
#     seb_version=<v>\nseb_config_key=<v>\nseb_browser_exam_key=<v>
#     submitted_at=<iso8601>
#
# Identity fields come first in `assessment.identity` order, then questions in `assessment.questions`
# order, then the environment fields, then the timestamp. Values are sanitised (see `canonical_value`)
# so no value can contain the separators and forge a different parse. The environment fields are ALWAYS
# present (empty when the paper was not sat under Safe Exam Browser), so the signed shape is fixed.

"""
    canonical_value(s) -> String

Normalise a value for the signed message: collapse anything that could be confused with the record
separators (newlines, tabs, carriage returns) into single spaces, and trim. Applied identically in the
browser, so a name typed with a stray newline still verifies.
"""
canonical_value(s) = strip(replace(String(s), r"[\r\n\t]+" => " "))

"""
    canonical_message(a::Assessment, identity, answers, submitted_at) -> String

The exact string that gets signed. `identity` and `answers` are `Dict`-like, keyed by field key /
question id. A question with no recorded answer serialises as the assessment's `no_response` value, so a
missing key and an explicit "not answered" are the same thing — as they should be.
"""
function canonical_message(a::Assessment, identity, answers, submitted_at, env = Dict{String,String}())
    parts = String[]
    for f in a.identity
        push!(parts, string(f.key, "=", canonical_value(get(identity, String(f.key),
                                                            get(identity, f.key, "")))))
    end
    # Answers are signed as NUMERIC CODES, matching what lands in the file — so the signature covers
    # exactly the bytes an examiner reads, with no label/code translation in between to disagree about.
    for q in a.questions
        push!(parts, string(q, "=", answer_code(a, get(answers, q, get(answers, Symbol(q), nothing)))))
    end
    for k in ENV_FIELDS
        push!(parts, string(k, "=", canonical_value(get(env, k, get(env, Symbol(k), "")))))
    end
    push!(parts, string("submitted_at=", canonical_value(submitted_at)))
    return join(parts, "\n")
end

"""
    hmac_sha256(key, message) -> String

HMAC-SHA256 as lowercase hex. Plain RFC 2104 over SHA-256's 64-byte block.
"""
function hmac_sha256(key::AbstractString, message::AbstractString)
    block = 64
    k = Vector{UInt8}(String(key))
    length(k) > block && (k = SHA.sha256(k))
    length(k) < block && (k = vcat(k, zeros(UInt8, block - length(k))))
    inner = SHA.sha256(vcat(k .⊻ 0x36, Vector{UInt8}(String(message))))
    return bytes2hex(SHA.sha256(vcat(k .⊻ 0x5c, inner)))
end

"""
    sign_submission(a::Assessment, identity, answers, submitted_at) -> String

The signature a browser would produce for this submission. Use it to verify a returned file:

```julia
sign_submission(exam, sub.identity, sub.answers, sub.submitted_at) == sub.signature
```

[`verify`](@ref) does exactly this for a parsed submission.
"""
sign_submission(a::Assessment, identity, answers, submitted_at, env = Dict{String,String}()) =
    hmac_sha256(a.session_key, canonical_message(a, identity, answers, submitted_at, env))
