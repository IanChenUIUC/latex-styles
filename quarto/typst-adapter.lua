-- Quarto filter for Typst output: expands the math.sty and stat.sty macros in
-- math, translates the package commands in `commands` to Typst, and renders
-- the theorem environments. Covers math and theorem divs only.

local sty_files = { "../math.sty", "../stat.sty" }

local builtins = {}
for name in ([[arccos arcsin arctan arg cos cosh cot coth csc deg det dim exp gcd
    hom inf ker lg lim liminf limsup ln log max min Pr sec sin sinh sup tan tanh]]):gmatch("%a+") do
  builtins[name] = true
end

-- Commands translated directly to Typst. `args` lists the brace arguments, each
-- "math" (converted to Typst), "list" (comma-separated, each item converted and
-- passed as its own Typst argument) or "raw" (copied as is). In `typst`, %1, %2, ...
-- are the arguments and %o is ", <optional argument>" when `opt` is set and
-- the optional argument is given. `star` is the template for the starred form.
-- `import` names the Typst package and the function the template uses.
local physica = "@preview/physica:0.9.8"
local commands = {
  textcolor = { args = { "raw", "math" }, typst = "text(fill: #%1, %2)" },
  vb = { args = { "math" }, typst = "bold(%1)", star = "bold(%1)" },
  va = { args = { "math" }, typst = "arrow(upright(%1))", star = "arrow(%1)" },
  vu = { args = { "math" }, typst = "hat(upright(bold(%1)))", star = "hat(bold(%1))" },
  abs = { args = { "math" }, typst = "abs(%1)" },
  norm = { args = { "math" }, typst = "norm(%1)" },
  eval = { args = { "math" }, typst = "evaluated(%1)", import = { physica, "evaluated" } },
  odv = { opt = true, args = { "math", "math" }, typst = "dv(%1, %2%o)", import = { physica, "dv" } },
  pdv = { opt = true, args = { "math", "list" }, typst = "pdv(%1, %2%o)", import = { physica, "pdv" } },
  odif = { opt = true, args = { "list" }, typst = "dd(%1%o)", import = { physica, "dd" } },
  pdif = { args = { "math" }, typst = "partial_(%1)" },
  mathop = { args = { "math" }, typst = "op(%1, limits: #true)" },
  operatorname = {
    args = { "math" }, typst = "op(upright(%1))", star = "op(upright(%1), limits: #true)",
  },
  ["!"] = { args = {}, typst = "#h(-3em/18)" },
}

local defs = {}
local theorems = {}
for _, file in ipairs(sty_files) do
  local h = assert(io.open(quarto.utils.resolve_path(file)))
  for line in h:lines() do
    local star, op, body = line:match("^\\DeclareMathOperator(%*?){\\(%a+)}{(.*)}%s*$")
    if op then
      line = "\\newcommand{\\" .. op .. "}{\\operatorname" .. star .. "{" .. body .. "}}"
    end
    local provided = line:match("^\\providecommand{\\(%a+)}")
    local defined = line:match("^\\%a*command%*?{?\\(%a+)")
    if not (provided and builtins[provided]) and not commands[defined] then
      defs[#defs + 1] = line
    end
    local opts, env = line:match("^\\declaretheorem%[(.-)%]{(%a+)}")
    if env then
      theorems[env] = opts:match("name=([^,]+)")
    end
  end
  h:close()
end
defs = table.concat(defs, "\n")

local delimiters = {
  ["("] = ")", ["["] = "]", ["\\{"] = "\\}", ["|"] = "|",
  ["\\lVert"] = "\\rVert", ["\\langle"] = "\\rangle",
}

local sized = { ["\\lVert"] = "\\Vert", ["\\rVert"] = "\\Vert" }

local function tokens(s)
  local out, i = {}, 1
  while i <= #s do
    local tok = s:match("^\\%a+", i) or s:sub(i, s:sub(i, i) == "\\" and i + 1 or i)
    out[#out + 1] = tok
    i = i + #tok
  end
  return out
end

local function skip_space(toks, i)
  while toks[i] and toks[i]:match("^%s$") do
    i = i + 1
  end
  return i
end

local function rewrite(toks, i, stop)
  local out = {}
  while i <= #toks do
    local t = toks[i]
    if stop and t == stop then
      return table.concat(out), i
    end
    if t == "\\ab" then
      local j = skip_space(toks, i + 1)
      local open = toks[j]
      local close = open and delimiters[open]
      if close then
        local inner, k = rewrite(toks, j + 1, close)
        out[#out + 1] = "\\left" .. (sized[open] or open) .. " " .. inner
          .. " \\right" .. (sized[close] or close)
        i = k + 1
      else
        i = i + 1
      end
    elseif t == "{" then
      local inner, k = rewrite(toks, i + 1, "}")
      out[#out + 1] = "{" .. inner .. "}"
      i = k + 1
    else
      out[#out + 1] = t
      i = i + 1
    end
  end
  return table.concat(out), i
end

-- Returns the text between toks[i] == open and its matching close, and the
-- index after the close.
local function group(toks, i, open, close)
  local depth, out = 0, {}
  i = i + 1
  while toks[i] and not (depth == 0 and toks[i] == close) do
    if toks[i] == "{" then
      depth = depth + 1
    elseif toks[i] == "}" then
      depth = depth - 1
    end
    out[#out + 1] = toks[i]
    i = i + 1
  end
  return table.concat(out), i + 1
end

local function split_commas(latex)
  local items, depth, start = {}, 0, 1
  for i = 1, #latex do
    local c = latex:sub(i, i)
    if c == "{" then
      depth = depth + 1
    elseif c == "}" then
      depth = depth - 1
    elseif c == "," and depth == 0 then
      items[#items + 1] = latex:sub(start, i - 1)
      start = i + 1
    end
  end
  items[#items + 1] = latex:sub(start)
  return items
end

local imports = {}

local to_typst

local function convert_arg(kind, arg)
  if kind == "math" then
    return to_typst(arg)
  elseif kind == "list" then
    local items = split_commas(arg)
    for n, item in ipairs(items) do
      items[n] = to_typst(item)
    end
    return table.concat(items, ", ")
  end
  return arg
end

function to_typst(latex)
  if latex:match("^%s*$") then
    return ""
  end
  local toks = tokens(latex)
  local pieces, out, i = {}, {}, 1
  while i <= #toks do
    local name = toks[i]:match("^\\(.+)$")
    local spec = name and commands[name]
    if spec then
      i = i + 1
      local template = spec.typst
      if spec.star and toks[i] == "*" then
        template = spec.star
        i = i + 1
      end
      local opt
      i = skip_space(toks, i)
      if spec.opt and toks[i] == "[" then
        opt, i = group(toks, i, "[", "]")
      end
      local args = {}
      for n, kind in ipairs(spec.args) do
        i = skip_space(toks, i)
        local arg
        if toks[i] == "{" then
          arg, i = group(toks, i, "{", "}")
        else
          arg, i = toks[i] or "", i + 1
        end
        args[n] = convert_arg(kind, arg)
      end
      pieces[#pieces + 1] = template:gsub("%%(%w)", function(k)
        if k == "o" then
          return opt and ", " .. to_typst(opt) or ""
        end
        return args[tonumber(k)]
      end)
      out[#out + 1] = "\\mathrm{QQ" .. #pieces .. "QQ}"
      if spec.import then
        local pkg, fn = table.unpack(spec.import)
        imports[pkg] = imports[pkg] or {}
        imports[pkg][fn] = true
      end
    else
      out[#out + 1] = toks[i]
      i = i + 1
    end
  end
  local elem = pandoc.Math("InlineMath", table.concat(out))
  local typst = pandoc.write(pandoc.Pandoc({ pandoc.Plain({ elem }) }), "typst")
  typst = typst:match("^%$(.*)%$%s*$")
  return (typst:gsub("upright%(Q Q (%d+) Q Q%)", function(n)
    return pieces[tonumber(n)]
  end))
end

local function uses_commands(latex)
  for _, tok in ipairs(tokens(latex)) do
    local name = tok:match("^\\(.+)$")
    if name and commands[name] then
      return true
    end
  end
  return false
end

local function expand(el)
  local delim = el.mathtype == "DisplayMath" and "$$" or "$"
  local doc = pandoc.read(defs .. "\n\n" .. delim .. el.text .. delim, "markdown")
  doc:walk({ Math = function(m) el.text = m.text end })
  el.text = (rewrite(tokens(el.text), 1))
  if not uses_commands(el.text) then
    return el
  end
  local typst = to_typst(el.text)
  if el.mathtype == "DisplayMath" then
    return pandoc.RawInline("typst", "$ " .. typst .. " $")
  end
  return pandoc.RawInline("typst", "$" .. typst .. "$")
end

local function theorem(div)
  for _, class in ipairs(div.classes) do
    local name = theorems[class]
    if name then
      local title = div.attributes.title
      local head = pandoc.Strong(name .. (title and " (" .. title .. ")" or "") .. ":")
      local first = div.content[1]
      if first and (first.t == "Para" or first.t == "Plain") then
        first.content:insert(1, pandoc.Space())
        first.content:insert(1, head)
      else
        div.content:insert(1, pandoc.Para({ head }))
      end
      return div.content
    end
  end
end

local function add_imports(doc)
  for pkg, fns in pairs(imports) do
    local names = {}
    for fn in pairs(fns) do
      names[#names + 1] = fn
    end
    table.sort(names)
    doc.blocks:insert(1, pandoc.RawBlock("typst",
      '#import "' .. pkg .. '": ' .. table.concat(names, ", ")))
  end
  return doc
end

return {
  { Math = expand },
  { Div = theorem },
  { Pandoc = add_imports },
}
