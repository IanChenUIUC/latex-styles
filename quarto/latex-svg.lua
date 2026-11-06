-- Typesets LaTeX snippets as cached SVG, using the real packages.

local M = {}

local here = debug.getinfo(1, "S").source:gsub("^@", "")
local sty_dir = pandoc.path.normalize(pandoc.path.join({
  pandoc.system.get_working_directory(), pandoc.path.directory(here), "..",
}))
local packages = { "math", "stat", "plang" }

local function read(path)
  local h = io.open(path)
  if not h then
    return nil
  end
  local text = h:read("a")
  h:close()
  return text
end

local function write(path, text)
  local h = assert(io.open(path, "w"))
  h:write(text)
  h:close()
end

local preamble = "\\documentclass[multi=snippet,border=1pt]{standalone}\n"
  .. "\\usepackage{amsmath,amssymb}\n"
  .. table.concat(pandoc.List(packages):map(function(p) return "\\usepackage{" .. p .. "}\n" end))
  .. "\\newenvironment{snippet}{}{}\n"

local key_prefix = preamble
for _, p in ipairs(packages) do
  key_prefix = key_prefix .. (read(pandoc.path.join({ sty_dir, p .. ".sty" })) or "")
end

local function cache_dir()
  local base = os.getenv("XDG_CACHE_HOME")
  if not base or base == "" then
    base = pandoc.path.join({ os.getenv("HOME"), ".cache" })
  end
  local dir = pandoc.path.join({ base, "latex-styles-svg" })
  pandoc.system.make_directory(dir, true)
  return dir
end

local function compile(sources)
  local body = {}
  for i, source in ipairs(sources) do
    body[i] = "\\begin{snippet}" .. source .. "\\end{snippet}\n"
  end
  local tex = preamble .. "\\begin{document}\n" .. table.concat(body) .. "\\end{document}\n"
  return pandoc.system.with_temporary_directory("latex-svg", function(dir)
    return pandoc.system.with_working_directory(dir, function()
      write("snippets.tex", tex)
      local texinputs = sty_dir .. "//:" .. (os.getenv("TEXINPUTS") or "")
      local ok = pcall(pandoc.pipe, "env",
        { "TEXINPUTS=" .. texinputs, "latex", "-interaction=nonstopmode", "-halt-on-error", "snippets.tex" }, "")
      if not ok then
        local log = read("snippets.log") or ""
        return nil, "LaTeX failed:\n" .. (log:match("\n(!.-)\n\n") or log:sub(-2000))
      end
      ok = pcall(pandoc.pipe, "dvisvgm",
        { "--no-fonts", "--currentcolor", "--page=1-", "--output=%4p.svg", "snippets.dvi" }, "")
      if not ok then
        return nil, "dvisvgm failed"
      end
      local svgs = {}
      for i = 1, #sources do
        svgs[i] = read(string.format("%04d.svg", i))
        if not svgs[i] then
          return nil, "dvisvgm produced no page " .. i
        end
      end
      return svgs
    end)
  end)
end

-- Returns a list of { svg, key }, or nil and a message.
function M.render(sources)
  local dir = cache_dir()
  local items, missing = {}, {}
  for i, source in ipairs(sources) do
    local key = pandoc.utils.sha1(key_prefix .. source)
    local path = pandoc.path.join({ dir, key .. ".svg" })
    items[i] = { key = key, path = path, svg = read(path) }
    if not items[i].svg then
      missing[#missing + 1] = i
    end
  end
  if #missing > 0 then
    local svgs, message = compile(pandoc.List(missing):map(function(i) return sources[i] end))
    if not svgs then
      return nil, message
    end
    for n, i in ipairs(missing) do
      items[i].svg = svgs[n]
      write(items[i].path, svgs[n])
    end
  end
  return items
end

return M
