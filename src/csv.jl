# A small RFC 4180 reader.
#
# Deliberately not a CSV.jl dependency: this package parses exactly one shape of file — the one it
# generated itself — and a marking script that a colleague can run should not drag in a data-frame stack
# to do it. If you want the submissions as a `DataFrame`, `DataFrame(read_csv(path))` works fine.

"""
    read_csv(path) -> (header::Vector{String}, rows::Vector{Vector{String}})

Parse an RFC 4180 CSV: comma-separated, `"` quoting, `""` for a literal quote inside a quoted field,
CRLF or LF line endings. Rows shorter than the header are padded with `""`; longer rows keep their extra
cells (the caller decides whether that is an error).
"""
function read_csv(path::AbstractString)
    text = read(path, String)
    startswith(text, '﻿') && (text = text[nextind(text, 1):end])   # strip a spreadsheet's BOM
    rows = Vector{Vector{String}}()
    field = IOBuffer()
    row = String[]
    inquote = false
    i = firstindex(text)
    n = lastindex(text)
    pushfield!() = (push!(row, String(take!(field))))
    pushrow!() = (pushfield!(); push!(rows, row); row = String[])
    while i <= n
        c = text[i]
        if inquote
            if c == '"'
                j = nextind(text, i)
                if j <= n && text[j] == '"'
                    write(field, '"'); i = nextind(text, j); continue
                end
                inquote = false
            else
                write(field, c)
            end
        else
            if c == '"' && position(field) == 0
                inquote = true
            elseif c == ','
                pushfield!()
            elseif c == '\n'
                pushrow!()
            elseif c == '\r'
                # swallow; the '\n' that follows ends the row
            else
                write(field, c)
            end
        end
        i = nextind(text, i)
    end
    (position(field) > 0 || !isempty(row)) && pushrow!()
    isempty(rows) && return (String[], Vector{Vector{String}}())
    header = rows[1]
    body = rows[2:end]
    filter!(r -> !(length(r) == 1 && isempty(r[1])), body)     # drop blank trailing lines
    for r in body
        while length(r) < length(header); push!(r, ""); end
    end
    return (header, body)
end

"""
    write_csv(path, header, rows)

Write an RFC 4180 CSV. Any cell containing a comma, quote or newline is quoted.
"""
function write_csv(path::AbstractString, header::AbstractVector, rows::AbstractVector)
    cell(v) = (s = string(v); occursin(r"[\",\n\r]", s) ? '"' * replace(s, '"' => "\"\"") * '"' : s)
    open(path, "w") do io
        println(io, join((cell(h) for h in header), ","))
        for r in rows
            println(io, join((cell(v) for v in r), ","))
        end
    end
    return path
end
