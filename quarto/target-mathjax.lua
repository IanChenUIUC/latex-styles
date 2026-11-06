-- Quarto filter for HTML: passes frontend.lua's output to MathJax. List it after html-adapter.lua.

if not quarto.doc.is_format("html") then
  return {}
end

local frontend = require("frontend")

local fixups = {
  ["\\llbracket"] = "\\mathopen{\\unicode{x27E6}}",
  ["\\rrbracket"] = "\\mathclose{\\unicode{x27E7}}",
}

local function expand(el)
  local toks = frontend.tokens(frontend.expand(el.text, el.mathtype == "DisplayMath"))
  for i, tok in ipairs(toks) do
    toks[i] = fixups[tok] or tok
  end
  el.text = table.concat(toks)
  return el
end

return {
  { Math = expand },
  { Div = frontend.theorem },
}
