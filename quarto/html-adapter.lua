-- Renders what MathJax cannot typeset as inline SVG. List it before target-mathjax.lua.

if not quarto.doc.is_format("html") then
  return {}
end

local latex_svg = require("latex-svg")

local math_patterns = { "\\inferrule" }
local environments = { "bnf" }

-- TeX's x-height in pt: sizing in ex matches the SVG to the page font.
local tex_ex = 4.30554

local style = [[
<style>
.latex-svg svg { vertical-align: middle; }
.latex-svg.display, .latex-svg.block { display: block; margin: 1em 0; overflow-x: auto; }
.latex-svg.display { text-align: center; }
</style>
]]

local function matches_math(text)
  for _, pattern in ipairs(math_patterns) do
    if text:find(pattern, 1, true) then
      return true
    end
  end
end

local function environment(text)
  for _, env in ipairs(environments) do
    if text:match("^%s*\\begin{" .. env .. "}") then
      return env
    end
  end
end

-- Inline SVGs on one page share an id space.
local function inline_svg(svg, prefix)
  svg = svg:gsub("^.-(<svg)", "%1")
  svg = svg:gsub("id='([^']*)'", "id='" .. prefix .. "-%1'")
  svg = svg:gsub("href='#([^']*)'", "href='#" .. prefix .. "-%1'")
  svg = svg:gsub("(<svg[^>]-) width='([%d.]+)pt' height='([%d.]+)pt'", function(head, w, h)
    return string.format("%s width='%.4fex' height='%.4fex'", head, w / tex_ex, h / tex_ex)
  end, 1)
  return svg
end

local function render(doc)
  local items = {}
  local function collect(source, kind)
    items[#items + 1] = { source = source, kind = kind }
    return #items
  end

  local marked = doc:walk({
    Math = function(el)
      if matches_math(el.text) then
        local source = el.mathtype == "DisplayMath" and "$\\displaystyle " .. el.text .. "$" or "$" .. el.text .. "$"
        local i = collect(source, el.mathtype == "DisplayMath" and "display" or "inline")
        return pandoc.Span({}, { ["latex-svg-item"] = tostring(i) })
      end
    end,
    RawBlock = function(el)
      if (el.format == "tex" or el.format == "latex") and environment(el.text) then
        local i = collect(el.text, "block")
        return pandoc.Div({}, { ["latex-svg-item"] = tostring(i) })
      end
    end,
  })
  if #items == 0 then
    return nil
  end

  local svgs, message = latex_svg.render(pandoc.List(items):map(function(item) return item.source end))
  if not svgs then
    quarto.log.warning("latex-svg: " .. message)
    return nil
  end

  local function html(i)
    local item, svg = items[i], svgs[i]
    local class = item.kind == "inline" and "latex-svg" or "latex-svg " .. item.kind
    local tag = item.kind == "block" and "div" or "span"
    local label = item.source:gsub("%s+", " "):gsub("[&'<>]", { ["&"] = "&amp;", ["'"] = "&#39;", ["<"] = "&lt;", [">"] = "&gt;" })
    return string.format("<%s class='%s' role='img' aria-label='%s'>%s</%s>", tag, class, label,
      inline_svg(svg.svg, "s" .. svg.key:sub(1, 8)), tag)
  end

  quarto.doc.include_text("in-header", style)
  return marked:walk({
    Span = function(el)
      local i = tonumber(el.attributes["latex-svg-item"])
      if i then
        return pandoc.RawInline("html", html(i))
      end
    end,
    Div = function(el)
      local i = tonumber(el.attributes["latex-svg-item"])
      if i then
        return pandoc.RawBlock("html", html(i))
      end
    end,
  })
end

return { { Pandoc = render } }
