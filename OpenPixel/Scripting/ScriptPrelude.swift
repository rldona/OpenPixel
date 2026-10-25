/// The parts of Aseprite's API that are plain Lua, run before every script.
/// Swift adds `app`, `Color`, `Image` and `Dialog` (ScriptEngine).
enum ScriptPrelude {
    static let source = #"""
    -- Scripts can't reach files or load bytecode (dofile only reads the script's own folder).
    loadfile = nil
    do
      local textOnly = load
      load = function(chunk, name, _, env) return textOnly(chunk, name, "t", env) end
    end
    print = function(...) end

    ColorMode = { RGB = 0, GRAYSCALE = 1, INDEXED = 2, TILEMAP = 4 }

    -- Pixel values are 32-bit RGBA, red in the low byte, as in Aseprite.
    local pixelColor = {}
    function pixelColor.rgba(r, g, b, a)
      a = a or 255
      return (r & 255) | (g & 255) << 8 | (b & 255) << 16 | (a & 255) << 24
    end
    function pixelColor.rgbaR(p) return p & 255 end
    function pixelColor.rgbaG(p) return (p >> 8) & 255 end
    function pixelColor.rgbaB(p) return (p >> 16) & 255 end
    function pixelColor.rgbaA(p) return (p >> 24) & 255 end
    function pixelColor.graya(v, a) return (v & 255) | ((a or 255) & 255) << 8 end
    function pixelColor.grayaV(p) return p & 255 end
    function pixelColor.grayaA(p) return (p >> 8) & 255 end
    app.pixelColor = pixelColor

    -- One script run is already one undo step.
    function app.transaction(a, b)
      local f = type(a) == "function" and a or b
      return f()
    end
    function app.refresh() end
    function app.undo() app.command.Undo() end
    function app.redo() app.command.Redo() end
    -- Aseprite 1.3's: change events say whether they come from undo.
    app.apiVersion = 21

    local function class(name, make)
      local mt = { __name = name }
      mt.__index = mt
      local cls = setmetatable({}, { __call = function(_, ...) return setmetatable(make(...), mt) end })
      return cls, mt
    end

    local pointMT
    Point, pointMT = class("Point", function(x, y)
      if type(x) == "table" then return { x = x.x or x[1] or 0, y = x.y or x[2] or 0 } end
      return { x = x or 0, y = y or 0 }
    end)
    pointMT.__add = function(a, b) return Point(a.x + b.x, a.y + b.y) end
    pointMT.__sub = function(a, b) return Point(a.x - b.x, a.y - b.y) end
    pointMT.__eq = function(a, b) return a.x == b.x and a.y == b.y end
    pointMT.__tostring = function(p) return "Point{ x=" .. p.x .. ", y=" .. p.y .. " }" end

    local sizeMT
    Size, sizeMT = class("Size", function(w, h)
      if type(w) == "table" then return { width = w.width or w.w or w[1] or 0, height = w.height or w.h or w[2] or 0 } end
      return { width = w or 0, height = h or 0 }
    end)
    sizeMT.__eq = function(a, b) return a.width == b.width and a.height == b.height end
    sizeMT.__index = function(s, k)
      if k == "w" then return s.width elseif k == "h" then return s.height end
      return rawget(sizeMT, k)
    end

    local rectMT
    Rectangle, rectMT = class("Rectangle", function(x, y, w, h)
      if type(x) == "table" then
        local t = x
        return { x = t.x or t[1] or 0, y = t.y or t[2] or 0,
                 width = t.width or t.w or t[3] or 0, height = t.height or t.h or t[4] or 0 }
      end
      return { x = x or 0, y = y or 0, width = w or 0, height = h or 0 }
    end)
    rectMT.__eq = function(a, b) return a.x == b.x and a.y == b.y and a.width == b.width and a.height == b.height end
    rectMT.__index = function(r, k)
      if k == "w" then return r.width elseif k == "h" then return r.height
      elseif k == "isEmpty" then return r.width <= 0 or r.height <= 0
      elseif k == "origin" then return Point(r.x, r.y)
      elseif k == "size" then return Size(r.width, r.height) end
      return rawget(rectMT, k)
    end
    function rectMT:union(o)
      if self.width <= 0 or self.height <= 0 then return Rectangle(o) end
      if o.width <= 0 or o.height <= 0 then return Rectangle(self) end
      local x, y = math.min(self.x, o.x), math.min(self.y, o.y)
      return Rectangle(x, y, math.max(self.x + self.width, o.x + o.width) - x, math.max(self.y + self.height, o.y + o.height) - y)
    end
    function rectMT:intersect(o)
      local x, y = math.max(self.x, o.x), math.max(self.y, o.y)
      local x2, y2 = math.min(self.x + self.width, o.x + o.width), math.min(self.y + self.height, o.y + o.height)
      if x2 <= x or y2 <= y then return Rectangle(0, 0, 0, 0) end
      return Rectangle(x, y, x2 - x, y2 - y)
    end
    function rectMT:intersects(o) return not self:intersect(o).isEmpty end
    function rectMT:contains(o)
      local w, h = o.width or 0, o.height or 0
      return o.x >= self.x and o.y >= self.y and o.x + w <= self.x + self.width and o.y + h <= self.y + self.height
    end
    """#
}
