-- Loads the filters outside Quarto.

local M = {}

local tests = pandoc.path.directory(arg[0])
M.filters = pandoc.path.join({ pandoc.path.directory(tests), "quarto" })

local format

quarto = {
  utils = { resolve_path = function(file) return pandoc.path.join({ M.filters, file }) end },
  doc = {
    is_format = function(name) return name == format end,
    include_text = function() end,
  },
  log = { warning = function(message) error(message) end },
}

package.path = pandoc.path.join({ M.filters, "?.lua" }) .. ";" .. package.path

function M.filter(name, target)
  format = target
  return dofile(pandoc.path.join({ M.filters, name }))
end

function M.read_json(path)
  local h = assert(io.open(path))
  local value = pandoc.json.decode(h:read("a"), false)
  h:close()
  return value
end

function M.write_json(path, value)
  local h = assert(io.open(path, "w"))
  h:write(pandoc.json.encode(value))
  h:close()
end

return M
