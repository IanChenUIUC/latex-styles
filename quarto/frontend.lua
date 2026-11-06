-- Shared by the target filters: rewrites math that uses math.sty and stat.sty into standard LaTeX
-- that every target can render, and renders their theorem environments.

local M = {}

local sty_files = { "../math.sty", "../stat.sty" }

local builtins = {}
for name in ([[arccos arcsin arctan arg cos cosh cot coth csc deg det dim exp gcd
    hom inf ker lg lim liminf limsup ln log max min Pr sec sin sinh sup tan tanh]]):gmatch("%a+") do
  builtins[name] = true
end

local function tight(open, inner, close)
  return "\\mathopen{}\\mathclose{\\left" .. open .. " " .. inner .. " \\right" .. close .. "}"
end

local function derivative(d, orders, num, vars)
  local count, symbols, den = 0, {}, {}
  for n, var in ipairs(vars) do
    local order = orders[n] or "1"
    if tonumber(order) then
      count = count + tonumber(order)
    else
      symbols[#symbols + 1] = order
    end
    den[#den + 1] = d .. " " .. var .. (order ~= "1" and "^{" .. order .. "}" or "")
  end
  if count > 0 or #symbols == 0 then
    table.insert(symbols, 1, tostring(count))
  end
  local total = table.concat(symbols, "+")
  local power = total ~= "1" and "^{" .. total .. "}" or ""
  return "\\frac{" .. d .. power .. " " .. num .. "}{" .. table.concat(den, "\\,") .. "}"
end

local function differential(d, orders, vars)
  local out = {}
  for n, var in ipairs(vars) do
    local order = orders[n]
    out[#out + 1] = "\\mathop{}\\!" .. d .. (order and order ~= "1" and "^{" .. order .. "}" or "") .. " " .. var
  end
  return table.concat(out)
end

-- Package commands, lowered to LaTeX that every target understands.
local commands = {
  vb = {
    args = { "math" },
    latex = function(a) return "\\boldsymbol{" .. a[1] .. "}" end,
    star = function(a) return "\\boldsymbol{" .. a[1] .. "}" end,
  },
  va = {
    args = { "math" },
    latex = function(a) return "\\vec{\\mathrm{" .. a[1] .. "}}" end,
    star = function(a) return "\\vec{" .. a[1] .. "}" end,
  },
  vu = {
    args = { "math" },
    latex = function(a) return "\\hat{\\mathbf{" .. a[1] .. "}}" end,
    star = function(a) return "\\hat{\\boldsymbol{" .. a[1] .. "}}" end,
  },
  abs = { args = { "math" }, latex = function(a) return tight("\\vert", a[1], "\\vert") end },
  norm = { args = { "math" }, latex = function(a) return tight("\\Vert", a[1], "\\Vert") end },
  eval = { args = { "math" }, latex = function(a) return tight(".", a[1], "\\vert") end },
  odv = {
    opt = true, args = { "math", "list" },
    latex = function(a, o) return derivative("\\mathrm{d}", o, a[1], a[2]) end,
  },
  pdv = {
    opt = true, args = { "math", "list" },
    latex = function(a, o) return derivative("\\partial", o, a[1], a[2]) end,
  },
  odif = {
    opt = true, args = { "list" },
    latex = function(a, o) return differential("\\mathrm{d}", o, a[1]) end,
  },
  pdif = { args = { "math" }, latex = function(a) return "\\partial_{" .. a[1] .. "}" end },
}

local definitions = {}
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
      definitions[#definitions + 1] = line
    end
    local opts, env = line:match("^\\declaretheorem%[(.-)%]{(%a+)}")
    if env then
      theorems[env] = opts:match("name=([^,]+)")
    end
  end
  h:close()
end
local defs = table.concat(definitions, "\n")

local delimiters = {
  ["("] = ")", ["["] = "]", ["\\{"] = "\\}", ["|"] = "|", ["\\langle"] = "\\rangle",
}

M.commands = commands
M.delimiters = delimiters

function M.tokens(s)
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

local function rewrite(toks, i, stop, open)
  local out, depth = {}, 0
  while i <= #toks do
    local t = toks[i]
    if stop and t == stop then
      if depth == 0 then
        return table.concat(out), i
      end
      depth = depth - 1
    elseif t == open then
      depth = depth + 1
    end
    if t == "\\ab" then
      local j = skip_space(toks, i + 1)
      local open = toks[j]
      local close = open and delimiters[open]
      if close then
        local inner, k = rewrite(toks, j + 1, close, open)
        out[#out + 1] = tight(open, inner, close)
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

function M.split_commas(latex)
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

-- Returns the star, the optional argument, the brace arguments and the next index.
function M.arguments(toks, i, spec)
  i = i + 1
  local starred = false
  if spec.star and toks[i] == "*" then
    starred = true
    i = i + 1
  end
  local opt
  i = skip_space(toks, i)
  if spec.opt and toks[i] == "[" then
    opt, i = group(toks, i, "[", "]")
  end
  local args = {}
  for n = 1, #spec.args do
    i = skip_space(toks, i)
    if toks[i] == "{" then
      args[n], i = group(toks, i, "{", "}")
    else
      args[n], i = toks[i] or "", i + 1
    end
  end
  return starred, opt, args, i
end

local function lower(latex)
  local toks = M.tokens(latex)
  local out, i = {}, 1
  while i <= #toks do
    local name = toks[i]:match("^\\(.+)$")
    local spec = name and commands[name]
    if spec then
      local starred, opt, raw
      starred, opt, raw, i = M.arguments(toks, i, spec)
      local orders = {}
      if opt then
        for n, item in ipairs(M.split_commas(opt)) do
          orders[n] = lower(item):match("^%s*(.-)%s*$")
        end
      end
      local args = {}
      for n, kind in ipairs(spec.args) do
        if kind == "list" then
          args[n] = pandoc.List(M.split_commas(raw[n])):map(lower)
        else
          args[n] = lower(raw[n])
        end
      end
      out[#out + 1] = (starred and spec.star or spec.latex)(args, orders)
    else
      out[#out + 1] = toks[i]
      i = i + 1
    end
  end
  return table.concat(out)
end

function M.expand(latex, display)
  local delim = display and "$$" or "$"
  local doc = pandoc.read(defs .. "\n\n" .. delim .. latex .. delim, "markdown")
  doc:walk({ Math = function(m) latex = m.text end })
  return lower((rewrite(M.tokens(latex), 1)))
end

function M.theorem(div)
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

return M
