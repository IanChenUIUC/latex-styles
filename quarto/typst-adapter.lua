-- Quarto filter for Typst output: expands the math.sty and stat.sty macros in
-- math and renders their theorem environments. Covers math and theorem divs only.

local sty_files = { "../math.sty", "../stat.sty" }

local builtins = {}
for name in ([[arccos arcsin arctan arg cos cosh cot coth csc deg det dim exp gcd
    hom inf ker lg lim liminf limsup ln log max min Pr sec sin sinh sup tan tanh]]):gmatch("%a+") do
  builtins[name] = true
end

local stand_ins = [[
\renewcommand{\vb}[1]{\boldsymbol{#1}}
\renewcommand{\va}[1]{\vec{\mathrm{#1}}}
\renewcommand{\vu}[1]{\hat{\mathbf{#1}}}
]]

local defs = {}
local theorems = {}
for _, file in ipairs(sty_files) do
  local h = assert(io.open(quarto.utils.resolve_path(file)))
  for line in h:lines() do
    local provided = line:match("^\\providecommand{\\(%a+)}")
    if not (provided and builtins[provided]) then
      defs[#defs + 1] = line
    end
    local opts, env = line:match("^\\declaretheorem%[(.-)%]{(%a+)}")
    if env then
      theorems[env] = opts:match("name=([^,]+)")
    end
  end
  h:close()
end
defs = table.concat(defs, "\n") .. "\n" .. stand_ins

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

local function rewrite(toks, i, stop)
  local out = {}
  while i <= #toks do
    local t = toks[i]
    if stop and t == stop then
      return table.concat(out), i
    end
    if t == "\\ab" then
      local j = i + 1
      while toks[j] and toks[j]:match("^%s$") do
        j = j + 1
      end
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

local function expand(el)
  local delim = el.mathtype == "DisplayMath" and "$$" or "$"
  local doc = pandoc.read(defs .. "\n\n" .. delim .. el.text .. delim, "markdown")
  doc:walk({ Math = function(m) el.text = m.text end })
  el.text = (rewrite(tokens(el.text), 1))
  return el
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

return {
  { Math = expand },
  { Div = theorem },
}
