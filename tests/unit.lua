-- Invariants of the filters that need no engine beyond LaTeX: takes a JSON file with the probes
-- of vocabulary.tsv, the forms to lower and the commands the .sty files define.

local harness = dofile(pandoc.path.join({ pandoc.path.directory(arg[0]), "harness.lua" }))
local frontend = require("frontend")
local input = harness.read_json(arg[1])

local failures = 0

local function check(ok, name, detail)
  if not ok then
    failures = failures + 1
    print("FAIL " .. name .. ": " .. tostring(detail))
  end
end

local function equal(got, want, name)
  check(got == want, name, "got " .. tostring(got) .. ", want " .. tostring(want))
end

local function replace(s, placeholder, value)
  return (s:gsub(placeholder:gsub("%p", "%%%0"), (value:gsub("%%", "%%%%"))))
end

local function tokens_round_trip()
  for _, list in ipairs({ input.probes, input.forms }) do
    for _, latex in ipairs(list) do
      equal(table.concat(frontend.tokens(latex)), latex, "tokens round trip")
    end
  end
end

local function argument_parsing()
  local toks = frontend.tokens("\\c*[a,{b]}]{x{y}}z w")
  local starred, opt, args, next = frontend.arguments(toks, 1, { star = true, opt = true, args = { "math", "math" } })
  equal(starred, true, "star")
  equal(opt, "a,{b]}", "optional argument")
  equal(args[1], "x{y}", "brace argument")
  equal(args[2], "z", "bare argument")
  equal(toks[next], " ", "next index")
  equal(pandoc.json.encode(frontend.split_commas("a,{b,c},d")), '["a","{b,c}","d"]', "split_commas")
end

local function allowed_commands_pass_through()
  for _, latex in ipairs(input.probes) do
    equal(frontend.expand(latex, true), latex, "pass through")
  end
end

local function every_defined_command_expands()
  for _, name in ipairs(input.defined) do
    local out = frontend.tokens(frontend.expand("\\" .. name .. "{a}{b}", true))
    check(not pandoc.List(out):includes("\\" .. name), "defined command expands", name)
  end
end

local function expansion_composes()
  local inner = frontend.expand("\\R", true)
  for _, form in ipairs(input.forms) do
    if form:find("#", 1, true) then
      local outer = frontend.expand(replace(form, "#", "\\R"), true)
      local rule = frontend.expand(replace(form, "#", "Q"), true)
      equal(outer:gsub("%s", ""), replace(rule, "Q", inner):gsub("%s", ""), "composition of " .. form)
    end
  end
end

local function stays_balanced()
  for _, form in ipairs(input.forms) do
    local depth, lefts = 0, 0
    for _, tok in ipairs(frontend.tokens(frontend.expand(replace(form, "#", input.argument), true))) do
      depth = depth + (tok == "{" and 1 or tok == "}" and -1 or 0)
      lefts = lefts + (tok == "\\left" and 1 or tok == "\\right" and -1 or 0)
      check(depth >= 0 and lefts >= 0, "balance", form)
    end
    check(depth == 0 and lefts == 0, "balance", form)
  end
end

local function every_rule_has_a_form()
  local text = table.concat(input.forms, "\n")
  for name in pairs(frontend.commands) do
    check(text:find("\\" .. name, 1, true), "no lowering form for command", name)
  end
  for open in pairs(frontend.delimiters) do
    check(text:find("\\ab" .. open, 1, true), "no lowering form for delimiter", open)
  end
end

local function theorems()
  for _, sty in ipairs({ "math.sty", "stat.sty" }) do
    for line in io.lines(pandoc.path.join({ harness.filters, "..", sty })) do
      local opts, env = line:match("^\\declaretheorem%[(.-)%]{(%a+)}")
      if env then
        local name = opts:match("name=([^,]+)")
        local div = pandoc.Div({ pandoc.Para({ pandoc.Str("body") }) }, { class = env, title = "T" })
        local out = pandoc.utils.stringify(frontend.theorem(div))
        equal(out, name .. " (T): body", "theorem " .. env)
      end
    end
  end
  equal(frontend.theorem(pandoc.Div({}, { class = "other" })), nil, "other divs")
end

local function code_output()
  local filters = harness.filter("target-typst.lua", "typst")
  local block = pandoc.CodeBlock("\n\nout\n\nmore")
  local div = pandoc.Div({ block }, { class = "cell-output" })
  local out = filters[3].Div(div)
  equal(out.content[1].text, "out\n\nmore", "blank lines before code output")
end

local function count(doc, kind)
  local n = 0
  doc:walk({ [kind] = function() n = n + 1 end })
  return n
end

local function html_layout()
  local render = harness.filter("html-adapter.lua", "html")[1].Pandoc
  local source = table.concat({
    "Inline $\\inferrule{a}{b}$ and $x$.",
    "$$\\inferrule{\\Gamma \\vdash a}{\\Gamma \\vdash b}$$",
    "\\begin{bnf}\n  $x$ : Var ::= a | b\n\\end{bnf}",
  }, "\n\n")
  local doc = pandoc.read(source, "markdown+raw_tex")
  local html = pandoc.write(render(doc), "html")
  equal(count(render(doc), "Math"), 1, "only other math stays math")
  equal(select(2, html:gsub("<svg", "")), 3, "one SVG per construct")
  check(html:find("currentColor", 1, true), "SVG follows the text colour", "no currentColor")
  check(not html:find("#000", 1, true) and not html:find("black", 1, true), "SVG has no fixed colour", "fixed colour")

  local seen = {}
  for id in html:gmatch("<[^>]- id='([^']+)'") do
    check(not seen[id], "SVG ids are unique", id)
    seen[id] = true
  end
end

local function svg_cache()
  local svg = require("latex-svg")
  local first = assert(svg.render({ "$a$" }))
  local second = assert(svg.render({ "$a$" }))
  local other = assert(svg.render({ "$b$" }))
  equal(first[1].key, second[1].key, "cache key is stable")
  equal(first[1].svg, second[1].svg, "cached SVG")
  check(first[1].key ~= other[1].key, "cache key depends on the source", first[1].key)
  local failed, message = svg.render({ "$\\undefinedcommand$" })
  check(not failed and message and message:find("Undefined", 1, true), "LaTeX failure returns a message", message)
end

local function typst_layout()
  local filters = harness.filter("typst-adapter.lua", "typst")
  local out = filters[1].Math(pandoc.Math("DisplayMath", "\\inferrule{\\R}{\\Gamma \\vdash a}"))
  local inlines = pandoc.Inlines(out)
  local math = 0
  inlines:walk({ Math = function() math = math + 1 end })
  equal(math, 2, "math inside a rule stays math")
  local doc = pandoc.Pandoc({ pandoc.Para({ pandoc.Str("x") }) })
  doc = filters[2].Pandoc(doc)
  local raw = doc.blocks[1]
  check(raw.t == "RawBlock" and raw.text:find("curryst", 1, true), "imports when used", raw.t)
  filters = harness.filter("typst-adapter.lua", "typst")
  doc = filters[2].Pandoc(pandoc.Pandoc({ pandoc.Para({ pandoc.Str("x") }) }))
  equal(doc.blocks[1].t, "Para", "no imports when unused")
end

local function kern_runs()
  local expand = harness.filter("target-typst.lua", "typst")[1].Math
  local typst = expand(pandoc.Math("InlineMath", "a \\perp\\! \\!\\!\\perp b")).text
  equal(select(2, typst:gsub("#h%(", "")), 1, "a run of \\! is one kern")
  check(typst:find("#h(-9em/18)", 1, true), "a run of \\! adds up", typst)
end

local function raw_latex()
  local convert = harness.filter("typst-adapter.lua", "typst")[3].RawBlock
  local function blocks(latex)
    return pandoc.Blocks(convert(pandoc.RawBlock("latex", latex)))
  end

  local inner = "\\begin{tabular}{|c|c|}\n\\hline\n$\\R$ & b \\\\\n\\hline\n\\end{tabular}"
  for _, latex in ipairs({
    inner,
    "\\begin{center}\n" .. inner .. "\n\\end{center}",
    "\\begin{table}\n" .. inner .. "\n\\end{table}",
    "\\begin{tabular*}{\\textwidth}{|c|c|}\n\\hline\na & b \\\\\n\\hline\n\\end{tabular*}",
  }) do
    equal(count(pandoc.Pandoc(blocks(latex)), "Table"), 1, "a tabular becomes a table: " .. latex:sub(1, 20))
  end

  local math = {}
  blocks(inner):walk({ Math = function(m) math[#math + 1] = m.text end })
  equal(math[1], "\\R", "math in a cell stays math")

  equal(convert(pandoc.RawBlock("html", "<hr>")), nil, "other formats pass through")
  check(not pcall(blocks, "\\newpage"), "dropped raw LaTeX warns", "no warning")
end

for _, test in ipairs({
  tokens_round_trip, argument_parsing, allowed_commands_pass_through, every_defined_command_expands,
  expansion_composes, stays_balanced, every_rule_has_a_form, theorems, code_output, html_layout, svg_cache,
  typst_layout, kern_runs, raw_latex,
}) do
  local ok, message = pcall(test)
  check(ok, "error", message)
end

os.exit(failures == 0 and 0 or 1)
