-- Writes the math of each document in a JSON list, after the front end, as { path = formulas }.

local harness = dofile(pandoc.path.join({ pandoc.path.directory(arg[0]), "harness.lua" }))
local frontend = require("frontend")

local out = {}
for _, path in ipairs(harness.read_json(arg[1])) do
  local h = assert(io.open(path))
  local text = h:read("a"):gsub("^%-%-%-\n.-\n%-%-%-\n", "")
  h:close()
  local formulas = {}
  pandoc.read(text, "markdown"):walk({
    Math = function(el)
      formulas[#formulas + 1] = frontend.expand(el.text, el.mathtype == "DisplayMath")
    end,
  })
  out[path] = formulas
end
harness.write_json(arg[2], out)
