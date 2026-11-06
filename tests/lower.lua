-- Passes a JSON list of formulas through the front end and both target filters.

local harness = dofile(pandoc.path.join({ pandoc.path.directory(arg[0]), "harness.lua" }))
local frontend = require("frontend")
local mathjax = harness.filter("target-mathjax.lua", "html")[1].Math
local typst = harness.filter("target-typst.lua", "typst")[1].Math

local function typst_source(latex)
  local el = typst(pandoc.Math("DisplayMath", latex))
  if el.t == "RawInline" then
    return el.text
  end
  return pandoc.write(pandoc.Pandoc({ pandoc.Plain({ el }) }), "typst")
end

local out = {}
for i, latex in ipairs(harness.read_json(arg[1])) do
  out[i] = {
    frontend = frontend.expand(latex, true),
    mathjax = mathjax(pandoc.Math("DisplayMath", latex)).text,
    typst = typst_source(latex),
  }
end
harness.write_json(arg[2], out)
