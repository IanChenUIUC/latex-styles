-- Quarto filter for Typst output: renders mathpartir \inferrule in math with curryst,
-- and simplebnf bnf environments with simplebnf. List it before typst-adapter.lua.

if not quarto.doc.is_format("typst") then
  return {}
end

local imports = [[
#import "@preview/curryst:0.6.0": rule, prooftree
#import "@preview/simplebnf:0.2.0": bnf, Prod, Or
]]

local used = false

local function raw(s)
  return pandoc.RawInline("typst", s)
end

local function trim(s)
  return s:match("^%s*(.-)%s*$")
end

local function text(s)
  local inlines = pandoc.utils.blocks_to_inlines(pandoc.read(s, "latex").blocks)
  return inlines:walk({
    Span = function(span)
      if span.classes:includes("sans-serif") then
        return { raw('#text(font: "Latin Modern Sans")['), span, raw("]") }
      end
    end,
  })
end

local function balanced(s, i, open, close)
  local depth, j = 0, i
  while j <= #s do
    local c = s:sub(j, j)
    if c == "\\" then
      j = j + 2
    else
      if c == open then
        depth = depth + 1
      elseif c == close then
        depth = depth - 1
        if depth == 0 then
          return s:sub(i + 1, j - 1), j + 1
        end
      end
      j = j + 1
    end
  end
  error("unbalanced " .. open .. close .. " in: " .. s)
end

local function find_top(s, seps, start)
  local depth, math, j = 0, false, start or 1
  while j <= #s do
    if depth == 0 and not math then
      for _, sep in ipairs(seps) do
        local after = s:sub(j + #sep, j + #sep)
        if s:sub(j, j + #sep - 1) == sep and not (sep:match("%a$") and after:match("%a")) then
          return j, sep
        end
      end
    end
    local c = s:sub(j, j)
    if c == "\\" then
      j = j + 2
    else
      if c == "{" then
        depth = depth + 1
      elseif c == "}" then
        depth = depth - 1
      elseif c == "$" then
        math = not math
      end
      j = j + 1
    end
  end
end

local function split(s, seps)
  local pieces, delims, start = {}, {}, 1
  while true do
    local i, sep = find_top(s, seps, start)
    if not i then
      break
    end
    pieces[#pieces + 1] = s:sub(start, i - 1)
    delims[#delims + 1] = sep
    start = i + #sep
  end
  pieces[#pieces + 1] = s:sub(start)
  return pieces, delims
end

local function cut(s, sep)
  local i = find_top(s, { sep })
  if i then
    return trim(s:sub(1, i - 1)), trim(s:sub(i + #sep))
  end
  return trim(s), nil
end

local function parse_rule(s, i)
  local rule = {}
  local star = s:sub(i, i) == "*"
  if star then
    i = i + 1
  end
  i = s:match("^%s*()", i)
  if s:sub(i, i) == "[" then
    local opts
    opts, i = balanced(s, i, "[", "]")
    if star then
      for _, kv in ipairs(split(opts, { "," })) do
        local k, v = kv:match("^%s*(%a+)%s*=%s*(.-)%s*$")
        k = k and k:lower()
        if k == "right" then
          rule.name = v
        elseif k == "left" or k == "lab" then
          rule.label = v
        end
      end
    else
      rule.label = trim(opts)
    end
    i = s:match("^%s*()", i)
  end
  rule.premises, i = balanced(s, i, "{", "}")
  i = s:match("^%s*()", i)
  rule.conclusion, i = balanced(s, i, "{", "}")
  return rule, i
end

local emit_formula

local function emit_rule(rule, out)
  out:insert(raw("rule("))
  for _, key in ipairs({ "name", "label" }) do
    if rule[key] then
      out:insert(raw(key .. ": ["))
      out:insert(pandoc.SmallCaps(text(rule[key])))
      out:insert(raw("], "))
    end
  end
  for _, premise in ipairs(split(rule.premises, { "\\\\", "\\and" })) do
    if trim(premise) ~= "" then
      emit_formula(premise, out)
      out:insert(raw(", "))
    end
  end
  emit_formula(rule.conclusion, out)
  out:insert(raw(")"))
end

emit_formula = function(s, out)
  s = trim(s)
  local i = s:match("^\\inferrule()")
  if i then
    emit_rule((parse_rule(s, i)), out)
  else
    out:insert(pandoc.Math("InlineMath", s))
  end
end

local function is_space(s)
  return (s:gsub("\\q?quad", ""):gsub("\\[,;: ]", "")):match("^%s*$") ~= nil
end

local function derivations(el)
  local s = el.text
  if not s:find("\\inferrule", 1, true) then
    return nil
  end
  used = true
  local out = pandoc.Inlines({})
  if el.mathtype == "DisplayMath" then
    out:insert(raw("#align(center)["))
  end
  local i, first = 1, true
  while true do
    local j, after = s:find("\\inferrule", i, true)
    local glue = s:sub(i, j and j - 1)
    if not is_space(glue) then
      out:insert(pandoc.Math("InlineMath", trim(glue)))
    end
    if not j then
      break
    end
    if not first then
      out:insert(raw("#h(2em)"))
    end
    first = false
    local rule
    rule, i = parse_rule(s, after + 1)
    out:insert(raw("#box(prooftree("))
    emit_rule(rule, out)
    out:insert(raw("))"))
  end
  if el.mathtype == "DisplayMath" then
    out:insert(raw("]"))
  end
  return out
end

local function grammar(el)
  if el.format ~= "tex" and el.format ~= "latex" then
    return nil
  end
  local body = el.text:match("^%s*\\begin{bnf}(.-)\\end{bnf}%s*$")
  if not body then
    return nil
  end
  used = true
  body = trim(body)
  if body:sub(1, 1) == "(" then
    body = trim(body:sub(select(2, balanced(body, 1, "(", ")"))))
  end
  if body:sub(1, 1) == "[" then
    body = trim(body:sub(select(2, balanced(body, 1, "[", "]"))))
  end

  local out = pandoc.Inlines({ raw("#bnf(") })
  for _, production in ipairs(split(body, { ";;" })) do
    local r = find_top(production, { "::=" })
    if r then
      local var, category = cut(production:sub(1, r - 1), "--")
      out:insert(raw("Prod(["))
      out:extend(text(var))
      out:insert(raw("], "))
      if category then
        out:insert(raw("annot: ["))
        out:extend(text(category))
        out:insert(raw("], "))
      end
      local lines = {}
      local alternatives, delims = split(production:sub(r + 3), { "|", "//" })
      for k, alternative in ipairs(alternatives) do
        if trim(alternative) ~= "" then
          if #lines == 0 or delims[k - 1] ~= "//" then
            lines[#lines + 1] = { forms = {} }
          end
          local line = lines[#lines]
          local form, comment = cut(alternative, "--")
          line.forms[#line.forms + 1] = form
          line.comment = comment or line.comment
        end
      end

      out:insert(raw("{ "))
      for _, line in ipairs(lines) do
        out:insert(raw("Or["))
        for f, form in ipairs(line.forms) do
          if f > 1 then
            out:insert(raw(" $|$ "))
          end
          out:extend(text(form))
        end
        out:insert(raw("]["))
        if line.comment then
          out:extend(text(line.comment))
        end
        out:insert(raw("]; "))
      end
      out:insert(raw("}), "))
    end
  end
  out:insert(raw(")"))
  return pandoc.Plain(out)
end

return {
  { Math = derivations, RawBlock = grammar },
  {
    Pandoc = function(doc)
      if used then
        doc.blocks:insert(1, pandoc.RawBlock("typst", imports))
      end
      return doc
    end,
  },
}
