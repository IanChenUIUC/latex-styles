-- Quarto filter for Typst: passes frontend.lua's output to pandoc's Typst writer. List it after
-- typst-adapter.lua.

if not quarto.doc.is_format("typst") then
  return {}
end

local frontend = require("frontend")

-- Commands pandoc translates wrongly.
local fixups = {
  textcolor = { args = { "raw", "math" }, typst = "text(fill: #%1, %2)" },
  mathop = { args = { "math" }, typst = "op(%1, limits: #true)" },
  operatorname = {
    args = { "math" }, typst = "op(upright(%1))", star = "op(upright(%1), limits: #true)",
  },
  ["!"] = { args = {}, typst = "#h(-3em/18)" },
  [" "] = { args = {}, typst = "#h(1em/3)" },
  ldots = { args = {}, typst = "#h(1em/6, weak: true) dots.h #h(1em/6, weak: true)" },
  dots = { args = {}, typst = "#h(1em/6, weak: true) dots.h #h(1em/6, weak: true)" },
  cdots = { args = {}, typst = "#h(1em/6, weak: true) dots.h.c #h(1em/6, weak: true)" },
  backslash = { args = {}, typst = 'class("normal", backslash)' },
  Vert = { args = {}, typst = 'class("normal", bar.v.double)' },
  lVert = { args = {}, typst = 'class("normal", bar.v.double)' },
  rVert = { args = {}, typst = 'class("normal", bar.v.double)' },
}

-- A delimiter after \left or \right belongs to pandoc.
local function fixup(toks, i)
  local name = toks[i]:match("^\\(.+)$")
  local j = i - 1
  while toks[j] == " " do
    j = j - 1
  end
  if name and toks[j] ~= "\\left" and toks[j] ~= "\\right" then
    return fixups[name]
  end
end

-- Pandoc does not stretch this bar.
local function is_evaluation(toks, i)
  return toks[i] == "\\left" and toks[i + 1] == "."
end

-- Typst's op("") gives no space, unlike \mathop{}.
local function is_differential_space(toks, i)
  return toks[i] == "\\mathop" and toks[i + 1] == "{" and toks[i + 2] == "}" and toks[i + 3] == "\\!"
end

local function closing_right(toks, i)
  local depth = 0
  for j = i, #toks do
    if toks[j] == "\\left" then
      depth = depth + 1
    elseif toks[j] == "\\right" then
      depth = depth - 1
      if depth == 0 then
        return j
      end
    end
  end
end

local function uses_fixups(toks)
  for i in ipairs(toks) do
    if fixup(toks, i) or is_evaluation(toks, i) then
      return true
    end
  end
  return false
end

-- Fixups pass through pandoc as placeholders.
local function to_typst(latex)
  if latex:match("^%s*$") then
    return ""
  end
  local toks = frontend.tokens(latex)
  local pieces, out, i = {}, {}, 1
  while i <= #toks do
    local spec = fixup(toks, i)
    if is_evaluation(toks, i) then
      local right = closing_right(toks, i)
      pieces[#pieces + 1] = "lr(" .. to_typst(table.concat(toks, "", i + 2, right - 1)) .. " |)"
      out[#out + 1] = "\\mathrm{QQ" .. #pieces .. "QQ}"
      i = right + 2
    elseif is_differential_space(toks, i) then
      pieces[#pieces + 1] = "#h(1em/6, weak: true)"
      out[#out + 1] = "\\mathrm{QQ" .. #pieces .. "QQ}"
      i = i + 4
    elseif spec then
      local starred, _, args
      starred, _, args, i = frontend.arguments(toks, i, spec)
      for n, kind in ipairs(spec.args) do
        if kind == "math" then
          args[n] = to_typst(args[n])
        end
      end
      local template = starred and spec.star or spec.typst
      -- Inline Typst math applies only one of several #h calls after a relation, so a run of \! is
      -- one kern.
      if spec == fixups["!"] then
        local kern = 3
        while toks[i] == "\\!" do
          kern = kern + 3
          _, _, _, i = frontend.arguments(toks, i, spec)
        end
        template = "#h(-" .. kern .. "em/18)"
      end
      pieces[#pieces + 1] = template:gsub("%%(%d)", function(k) return args[tonumber(k)] end)
      out[#out + 1] = "\\mathrm{QQ" .. #pieces .. "QQ}"
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

local function expand(el)
  local latex = frontend.expand(el.text, el.mathtype == "DisplayMath")
  if not uses_fixups(frontend.tokens(latex)) then
    el.text = latex
    return el
  end
  local typst = to_typst(latex)
  if el.mathtype == "DisplayMath" then
    return pandoc.RawInline("typst", "$ " .. typst .. " $")
  end
  return pandoc.RawInline("typst", "$" .. typst .. "$")
end

local function output(div)
  if div.classes:includes("cell-output") then
    return div:walk({
      CodeBlock = function(block)
        block.text = block.text:gsub("^%s*\n", "")
        return block
      end,
    })
  end
end

return {
  { Math = expand },
  { Div = frontend.theorem },
  { Div = output },
}
