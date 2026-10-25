import Foundation

/// The C functions Lua calls; each hands its work to a ScriptEngine method.
enum LuaAPI {
    static let hook: lua_Hook = { L, _ in
        guard let L, Date() > ScriptEngine.engine(of: L).deadline else { return }
        Lua.pushString(L, L10n.string("The script took too long and was stopped"))
        _ = lua_error(L)
    }

    static let alert: lua_CFunction = { L in luaCall(L) { try $0.alert($1) } }
    static let appIndex: lua_CFunction = { L in luaCall(L) { try $0.appIndex($1) } }
    static let appNewIndex: lua_CFunction = { L in luaCall(L) { try $0.appNewIndex($1) } }
    static let commandIndex: lua_CFunction = { L in luaCall(L) { try $0.commandIndex($1) } }
    static let command: lua_CFunction = { L in luaCall(L) { try $0.command($1) } }

    static let newColor: lua_CFunction = { L in luaCall(L) { try $0.newColor($1) } }
    static let colorIndex: lua_CFunction = { L in luaCall(L) { try $0.colorIndex($1) } }
    static let colorNewIndex: lua_CFunction = { L in luaCall(L) { try $0.colorNewIndex($1) } }
    static let colorEquals: lua_CFunction = { L in luaCall(L) { $0.colorEquals($1) } }
    static let colorString: lua_CFunction = { L in luaCall(L) { $0.colorString($1) } }

    static let objectIndex: lua_CFunction = { L in luaCall(L) { try $0.objectIndex($1) } }
    static let objectNewIndex: lua_CFunction = { L in luaCall(L) { try $0.objectNewIndex($1) } }
    static let objectEquals: lua_CFunction = { L in luaCall(L) { $0.objectEquals($1) } }
    static let objectString: lua_CFunction = { L in luaCall(L) { $0.objectString($1) } }
    static let objectLength: lua_CFunction = { L in luaCall(L) { try $0.objectLength($1) } }
    static let getColor: lua_CFunction = { L in luaCall(L) { try $0.getColor($1) } }
    static let setColor: lua_CFunction = { L in luaCall(L) { try $0.setColor($1) } }
    static let resizePalette: lua_CFunction = { L in luaCall(L) { try $0.resizePalette($1) } }

    static let newLayer: lua_CFunction = { L in luaCall(L) { try $0.newLayer($1) } }
    static let newCel: lua_CFunction = { L in luaCall(L) { try $0.newCel($1) } }
    static let deleteLayer: lua_CFunction = { L in luaCall(L) { try $0.deleteLayer($1) } }
    static let deleteCel: lua_CFunction = { L in luaCall(L) { try $0.deleteCel($1) } }
    static let newFrame: lua_CFunction = { L in luaCall(L) { try $0.newFrame($1, empty: false) } }
    static let newEmptyFrame: lua_CFunction = { L in luaCall(L) { try $0.newFrame($1, empty: true) } }
    static let layerCel: lua_CFunction = { L in luaCall(L) { try $0.layerCel($1) } }

    static let newImage: lua_CFunction = { L in luaCall(L) { try $0.newImage($1) } }
    static let getPixel: lua_CFunction = { L in luaCall(L) { try $0.getPixel($1) } }
    static let putPixel: lua_CFunction = { L in luaCall(L) { try $0.putPixel($1) } }
    static let clearImage: lua_CFunction = { L in luaCall(L) { try $0.clearImage($1) } }
    static let cloneImage: lua_CFunction = { L in luaCall(L) { try $0.cloneImage($1) } }
    static let drawImage: lua_CFunction = { L in luaCall(L) { try $0.drawImage($1) } }
    static let isEmptyImage: lua_CFunction = { L in luaCall(L) { try $0.isEmptyImage($1) } }

    static let newDialog: lua_CFunction = { L in luaCall(L) { try $0.newDialog($1) } }
    static let dialogWidget: lua_CFunction = { L in luaCall(L) { try $0.dialogWidget($1) } }
    static let dialogShow: lua_CFunction = { L in luaCall(L) { try $0.dialogShow($1) } }
    static let dialogClose: lua_CFunction = { L in luaCall(L) { try $0.dialogClose($1) } }
    static let dialogModify: lua_CFunction = { L in luaCall(L) { try $0.dialogModify($1) } }
    static let dialogRepaint: lua_CFunction = { L in luaCall(L) { _, L in lua_settop(L, 1); return 1 } }
}

extension ScriptEngine {
    // MARK: - Arguments

    func number(_ L: Lua.State, _ index: Int32, _ what: String) throws -> Double {
        guard let value = Lua.number(L, index), value.isFinite else { throw Failure(L10n.string("%@ must be a number", what)) }
        return value
    }

    func int(_ L: Lua.State, _ index: Int32, _ what: String) throws -> Int {
        let value = try number(L, index, what)
        guard abs(value) < 1e9 else { throw Failure(L10n.string("%@ must be a number", what)) }
        return Int(value.rounded(.down))
    }

    /// A field of the table at `table`, under the first of `keys` it has.
    func field(_ L: Lua.State, _ table: Int32, _ keys: String...) -> Double? {
        guard Lua.type(L, table) == LUA_TTABLE else { return nil }
        for key in keys {
            Lua.getField(L, table, key)
            defer { Lua.pop(L) }
            if let value = Lua.number(L, -1) { return value }
        }
        return nil
    }

    func stringField(_ L: Lua.State, _ table: Int32, _ key: String) -> String? {
        guard Lua.type(L, table) == LUA_TTABLE else { return nil }
        Lua.getField(L, table, key)
        defer { Lua.pop(L) }
        return Lua.string(L, -1)
    }

    func boolField(_ L: Lua.State, _ table: Int32, _ key: String) -> Bool? {
        guard Lua.type(L, table) == LUA_TTABLE else { return nil }
        Lua.getField(L, table, key)
        defer { Lua.pop(L) }
        return Lua.isNoneOrNil(L, -1) ? nil : Lua.bool(L, -1)
    }

    /// A registry reference to the function in field `key`, if there is one.
    func functionField(_ L: Lua.State, _ table: Int32, _ key: String) -> Int32? {
        guard Lua.type(L, table) == LUA_TTABLE else { return nil }
        Lua.getField(L, table, key)
        guard Lua.type(L, -1) == LUA_TFUNCTION else { Lua.pop(L); return nil }
        return luaL_ref(L, Lua.registryIndex)
    }

    // MARK: - Colors

    /// Pixel values pack RGBA with red in the low byte, as in Aseprite.
    static func pack(_ c: PixelColor) -> lua_Integer {
        lua_Integer(c.r) | lua_Integer(c.g) << 8 | lua_Integer(c.b) << 16 | lua_Integer(c.a) << 24
    }

    static func unpack(_ value: lua_Integer) -> PixelColor {
        PixelColor(r: UInt8(value & 255), g: UInt8(value >> 8 & 255), b: UInt8(value >> 16 & 255), a: UInt8(value >> 24 & 255))
    }

    private func colorBytes(_ L: Lua.State, _ index: Int32) -> UnsafeMutablePointer<UInt8>? {
        "Color".withCString { luaL_testudata(L, index, $0) }?.assumingMemoryBound(to: UInt8.self)
    }

    /// A Color, or a pixel value.
    func color(_ L: Lua.State, _ index: Int32) -> PixelColor? {
        if let bytes = colorBytes(L, index) { return PixelColor(r: bytes[0], g: bytes[1], b: bytes[2], a: bytes[3]) }
        if lua_isinteger(L, index) != 0 { return Self.unpack(lua_tointegerx(L, index, nil)) }
        return nil
    }

    func pushColor(_ c: PixelColor, on L: Lua.State) {
        let bytes = lua_newuserdatauv(L, 4, 0)!.assumingMemoryBound(to: UInt8.self)
        bytes[0] = c.r
        bytes[1] = c.g
        bytes[2] = c.b
        bytes[3] = c.a
        Lua.setMetatable(L, "Color")
    }

    func newColor(_ L: Lua.State) throws -> Int32 {
        func byte(_ v: Double?) -> UInt8 { UInt8(min(255, max(0, (v ?? 255).rounded()))) }
        let count = lua_gettop(L)
        var result = PixelColor.clear
        if count >= 3 {
            result = PixelColor(r: byte(try number(L, 1, "red")), g: byte(try number(L, 2, "green")),
                                b: byte(try number(L, 3, "blue")), a: byte(count >= 4 ? try number(L, 4, "alpha") : 255))
        } else if count >= 1, let c = color(L, 1) {
            result = c
        } else if count >= 1, Lua.type(L, 1) == LUA_TTABLE {
            let alpha = byte(field(L, 1, "a", "alpha"))
            if let r = field(L, 1, "r", "red") {
                result = PixelColor(r: byte(r), g: byte(field(L, 1, "g", "green") ?? 0), b: byte(field(L, 1, "b", "blue") ?? 0), a: alpha)
            } else if let h = field(L, 1, "h", "hue", "hsvHue", "hslHue") {
                let s = field(L, 1, "s", "saturation", "hsvSaturation", "hslSaturation") ?? 0
                if let l = field(L, 1, "l", "lightness", "hslLightness") {
                    result = PixelColor(hsl: HSL(h: h, s: s, l: l), alpha: alpha)
                } else {
                    result = PixelColor(hsv: HSV(h: h, s: s, v: field(L, 1, "v", "value", "hsvValue") ?? 0), alpha: alpha)
                }
            } else if let gray = field(L, 1, "gray") {
                result = PixelColor(r: byte(gray), g: byte(gray), b: byte(gray), a: alpha)
            } else if let index = field(L, 1, "index") {
                let palette = try sprite().palette
                result = palette.indices.contains(Int(index)) ? palette[Int(index)] : .clear
            }
        } else if count >= 1 {
            throw Failure(L10n.string("%@ must be a number", "Color"))
        }
        pushColor(result, on: L)
        return 1
    }

    func colorIndex(_ L: Lua.State) throws -> Int32 {
        guard let c = color(L, 1), let key = Lua.string(L, 2) else { return 0 }
        switch key {
        case "red", "r": lua_pushinteger(L, lua_Integer(c.r))
        case "green", "g": lua_pushinteger(L, lua_Integer(c.g))
        case "blue", "b": lua_pushinteger(L, lua_Integer(c.b))
        case "alpha", "a": lua_pushinteger(L, lua_Integer(c.a))
        case "hue", "hsvHue": lua_pushnumber(L, c.hsv.h)
        case "saturation", "hsvSaturation": lua_pushnumber(L, c.hsv.s)
        case "value", "hsvValue": lua_pushnumber(L, c.hsv.v)
        case "hslHue": lua_pushnumber(L, c.hsl.h)
        case "hslSaturation": lua_pushnumber(L, c.hsl.s)
        case "lightness", "hslLightness": lua_pushnumber(L, c.hsl.l)
        case "gray": lua_pushinteger(L, lua_Integer((c.luminance * 255).rounded()))
        case "rgbaPixel": lua_pushinteger(L, Self.pack(c))
        case "index": lua_pushinteger(L, lua_Integer(try sprite().palette.firstIndex(of: c) ?? 0))
        default: throw Failure.unsupported("Color.\(key)")
        }
        return 1
    }

    func colorNewIndex(_ L: Lua.State) throws -> Int32 {
        guard let bytes = colorBytes(L, 1), let key = Lua.string(L, 2) else { return 0 }
        let value = try number(L, 3, "Color.\(key)")
        func byte() -> UInt8 { UInt8(min(255, max(0, value.rounded()))) }
        var c = PixelColor(r: bytes[0], g: bytes[1], b: bytes[2], a: bytes[3])
        var hsv = c.hsv, hsl = c.hsl
        switch key {
        case "red", "r": c.r = byte()
        case "green", "g": c.g = byte()
        case "blue", "b": c.b = byte()
        case "alpha", "a": c.a = byte()
        case "hue", "hsvHue": hsv.h = value; c = PixelColor(hsv: hsv, alpha: c.a)
        case "saturation", "hsvSaturation": hsv.s = value; c = PixelColor(hsv: hsv, alpha: c.a)
        case "value", "hsvValue": hsv.v = value; c = PixelColor(hsv: hsv, alpha: c.a)
        case "hslHue": hsl.h = value; c = PixelColor(hsl: hsl, alpha: c.a)
        case "hslSaturation": hsl.s = value; c = PixelColor(hsl: hsl, alpha: c.a)
        case "lightness", "hslLightness": hsl.l = value; c = PixelColor(hsl: hsl, alpha: c.a)
        default: throw Failure.unsupported("Color.\(key)")
        }
        bytes[0] = c.r
        bytes[1] = c.g
        bytes[2] = c.b
        bytes[3] = c.a
        return 0
    }

    func colorEquals(_ L: Lua.State) -> Int32 {
        lua_pushboolean(L, color(L, 1) == color(L, 2) ? 1 : 0)
        return 1
    }

    func colorString(_ L: Lua.State) -> Int32 {
        let c = color(L, 1) ?? .clear
        Lua.pushString(L, "Color{ r=\(c.r), g=\(c.g), b=\(c.b), a=\(c.a) }")
        return 1
    }

    // MARK: - app

    func appIndex(_ L: Lua.State) throws -> Int32 {
        guard let key = Lua.string(L, 2) else { return 0 }
        let sprite = try sprite()
        let frame = sprite.frames[min(activeFrameIndex, sprite.frames.count - 1)]
        let celKey = CelKey(layer: activeLayerID, frame: frame.id)
        switch key {
        case "activeSprite", "sprite": push(.sprite, on: L)
        case "sprites":
            Lua.newTable(L)
            push(.sprite, on: L)
            lua_rawseti(L, -2, 1)
        case "activeLayer", "layer": push(.layer(activeLayerID), on: L)
        case "activeFrame", "frame": push(.frame(frame.id), on: L)
        case "activeCel", "cel":
            if sprite.cels[celKey] != nil { push(.cel(celKey), on: L) } else { lua_pushnil(L) }
        case "activeImage", "image":
            if sprite.cels[celKey] != nil { push(.image(.cel(celKey)), on: L) } else { lua_pushnil(L) }
        case "fgColor": pushColor(document?.primary ?? .black, on: L)
        case "bgColor": pushColor(document?.secondary ?? .white, on: L)
        case "isUIAvailable": lua_pushboolean(L, 1)
        default: throw Failure.unsupported("app.\(key)")
        }
        return 1
    }

    func appNewIndex(_ L: Lua.State) throws -> Int32 {
        guard let key = Lua.string(L, 2) else { return 0 }
        switch key {
        case "fgColor", "bgColor":
            guard let c = color(L, 3) else { throw Failure(L10n.string("%@ must be a Color", "app.\(key)")) }
            if key == "fgColor" { document?.primary = c } else { document?.secondary = c }
        case "activeLayer":
            guard case .layer(let id) = object(L, 3, "Layer") else { throw Failure(L10n.string("%@ must be a Layer", "app.activeLayer")) }
            _ = try sprite()
            activeLayerID = id
        case "activeFrame":
            let sprite = try sprite()
            if case .frame(let id) = object(L, 3, "Frame"), let index = sprite.frames.firstIndex(where: { $0.id == id }) {
                activeFrameIndex = index
            } else {
                activeFrameIndex = min(sprite.frames.count - 1, max(0, try int(L, 3, "app.activeFrame") - 1))
            }
        default:
            // Anything else is a plain field (the prelude adds app.pixelColor this way).
            lua_settop(L, 3)
            lua_rawset(L, 1)
        }
        return 0
    }

    func alert(_ L: Lua.State) throws -> Int32 {
        var title = name, lines: [String] = []
        func readLines(_ index: Int32) {
            if let text = Lua.string(L, index) {
                lines.append(text)
            } else if Lua.type(L, index) == LUA_TTABLE {
                for i in 1...max(1, Int(luaL_len(L, index))) {
                    lua_rawgeti(L, index, lua_Integer(i))
                    if let text = Lua.string(L, -1) { lines.append(text) }
                    Lua.pop(L)
                }
            }
        }
        if Lua.type(L, 1) == LUA_TTABLE {
            title = stringField(L, 1, "title") ?? title
            Lua.getField(L, 1, "text")
            readLines(lua_gettop(L))
            Lua.pop(L)
        } else {
            readLines(1)
        }
        document?.scriptMessage = ScriptMessage(title: title, text: lines.joined(separator: "\n"))
        lua_pushinteger(L, 1)
        return 1
    }

    /// `app.command.Name` is a function; the few OpenPixel has run, the rest fail.
    func commandIndex(_ L: Lua.State) throws -> Int32 {
        lua_pushvalue(L, 2)
        lua_pushcclosure(L, LuaAPI.command, 1)
        return 1
    }

    func command(_ L: Lua.State) throws -> Int32 {
        let name = Lua.string(L, Lua.upvalueIndex(1)) ?? ""
        switch name {
        case "Undo": undo()
        case "Redo": redo()
        case "Refresh": break
        case "NewLayer":
            _ = try newLayer(L)
            Lua.pop(L)
        default: throw Failure.unsupported("app.command.\(name)")
        }
        return 0
    }

    // MARK: - Objects

    func objectIndex(_ L: Lua.State) throws -> Int32 {
        guard let object = object(L, 1), let key = Lua.string(L, 2) else { return 0 }
        switch object {
        case .sprite: return try spriteIndex(L, key)
        case .layer(let id): return try layerIndex(L, id, key)
        case .cel(let celKey): return try celIndex(L, celKey, key)
        case .frame(let id): return try frameIndex(L, id, key)
        case .image(let ref): return try imageIndex(L, ref, key)
        case .dialog(let index): return try dialogIndex(L, allDialogs[index], key)
        case .palette: return try paletteIndex(L, key)
        }
    }

    func objectNewIndex(_ L: Lua.State) throws -> Int32 {
        guard let object = object(L, 1), let key = Lua.string(L, 2) else { return 0 }
        switch object {
        case .layer(let id):
            let index = try layerPosition(id)
            try change { sprite in
                switch key {
                case "name": sprite.layers[index].name = Lua.string(L, 3) ?? ""
                case "isVisible": sprite.layers[index].isVisible = Lua.bool(L, 3)
                case "isEditable": sprite.layers[index].isLocked = !Lua.bool(L, 3)
                case "opacity": sprite.layers[index].opacity = min(1, max(0, try number(L, 3, "Layer.opacity") / 255))
                default: throw Failure.unsupported("Layer.\(key)")
                }
            }
        case .cel(let celKey):
            switch key {
            case "image":
                guard case .image(let ref) = self.object(L, 3, "Image") else { throw Failure(L10n.string("%@ must be an Image", "Cel.image")) }
                let source = try image(ref)
                try change { sprite in
                    var image = PixelImage(width: sprite.width, height: sprite.height)
                    image.pasteClipped(source, at: 0, 0)
                    sprite.cels[celKey] = image
                }
            case "opacity":
                let opacity = try number(L, 3, "Cel.opacity") / 255
                try change { $0.celOpacity[celKey] = opacity >= 1 ? nil : max(0, opacity) }
            default: throw Failure.unsupported("Cel.\(key)")
            }
        case .frame(let id):
            guard key == "duration" else { throw Failure.unsupported("Frame.\(key)") }
            let seconds = try number(L, 3, "Frame.duration")
            try change { sprite in
                if let index = sprite.frames.firstIndex(where: { $0.id == id }) { sprite.frames[index].duration = max(1, Int((seconds * 1000).rounded())) }
            }
        case .sprite: throw Failure.unsupported("Sprite.\(key)")
        case .image: throw Failure.unsupported("Image.\(key)")
        case .dialog: throw Failure.unsupported("Dialog.\(key)")
        case .palette: throw Failure.unsupported("Palette.\(key)")
        }
        return 0
    }

    func objectLength(_ L: Lua.State) throws -> Int32 {
        guard let object = object(L, 1) else { return 0 }
        guard object == .palette else { throw Failure.unsupported("#\(object.typeName)") }
        lua_pushinteger(L, lua_Integer(try sprite().palette.count))
        return 1
    }

    func objectEquals(_ L: Lua.State) -> Int32 {
        lua_pushboolean(L, object(L, 1) == object(L, 2) ? 1 : 0)
        return 1
    }

    func objectString(_ L: Lua.State) -> Int32 {
        Lua.pushString(L, object(L, 1)?.typeName ?? "?")
        return 1
    }

    private func pushMethod(_ L: Lua.State, _ function: lua_CFunction) -> Int32 {
        Lua.pushFunction(L, function)
        return 1
    }

    private func pushRectangle(_ L: Lua.State, _ x: Int, _ y: Int, _ width: Int, _ height: Int) {
        Lua.getGlobal(L, "Rectangle")
        for value in [x, y, width, height] { lua_pushinteger(L, lua_Integer(value)) }
        lua_callk(L, 4, 1, 0, nil)
    }

    private func pushPoint(_ L: Lua.State, _ x: Int, _ y: Int) {
        Lua.getGlobal(L, "Point")
        lua_pushinteger(L, lua_Integer(x))
        lua_pushinteger(L, lua_Integer(y))
        lua_callk(L, 2, 1, 0, nil)
    }

    private func pushList(_ L: Lua.State, _ items: [Object]) {
        lua_createtable(L, Int32(items.count), 0)
        for (i, item) in items.enumerated() {
            push(item, on: L)
            lua_rawseti(L, -2, lua_Integer(i + 1))
        }
    }

    // MARK: - Sprite

    private func spriteIndex(_ L: Lua.State, _ key: String) throws -> Int32 {
        let sprite = try sprite()
        switch key {
        case "width": lua_pushinteger(L, lua_Integer(sprite.width))
        case "height": lua_pushinteger(L, lua_Integer(sprite.height))
        case "bounds": pushRectangle(L, 0, 0, sprite.width, sprite.height)
        case "colorMode": lua_pushinteger(L, 0)
        case "filename": Lua.pushString(L, document?.name ?? "")
        case "layers": pushList(L, sprite.layers.filter { $0.parent == nil }.map { .layer($0.id) })
        case "frames": pushList(L, sprite.frames.map { .frame($0.id) })
        case "cels": pushList(L, sprite.cels.keys.sorted { order($0, $1, in: sprite) }.map { .cel($0) })
        case "palettes": pushList(L, [.palette])
        case "newLayer": return pushMethod(L, LuaAPI.newLayer)
        case "newCel": return pushMethod(L, LuaAPI.newCel)
        case "deleteLayer": return pushMethod(L, LuaAPI.deleteLayer)
        case "deleteCel": return pushMethod(L, LuaAPI.deleteCel)
        case "newFrame": return pushMethod(L, LuaAPI.newFrame)
        case "newEmptyFrame": return pushMethod(L, LuaAPI.newEmptyFrame)
        default: throw Failure.unsupported("Sprite.\(key)")
        }
        return 1
    }

    private func order(_ a: CelKey, _ b: CelKey, in sprite: Sprite) -> Bool {
        let fa = sprite.frames.firstIndex { $0.id == a.frame } ?? 0, fb = sprite.frames.firstIndex { $0.id == b.frame } ?? 0
        if fa != fb { return fa < fb }
        return (sprite.layers.firstIndex { $0.id == a.layer } ?? 0) < (sprite.layers.firstIndex { $0.id == b.layer } ?? 0)
    }

    func layerPosition(_ id: UUID) throws -> Int {
        guard let index = try sprite().layers.firstIndex(where: { $0.id == id }) else { throw Failure(L10n.string("The layer was deleted")) }
        return index
    }

    /// The frame index a script means: a Frame, or a frame number from 1.
    private func frameIndex(_ L: Lua.State, _ index: Int32) throws -> Int {
        let sprite = try sprite()
        if case .frame(let id) = object(L, index, "Frame"), let i = sprite.frames.firstIndex(where: { $0.id == id }) { return i }
        let number = Lua.isNoneOrNil(L, index) ? activeFrameIndex + 1 : try int(L, index, "frame")
        guard sprite.frames.indices.contains(number - 1) else { throw Failure(L10n.string("There's no frame %lld", number)) }
        return number - 1
    }

    /// Adds a layer above the active one and makes it active, like Aseprite.
    func newLayer(_ L: Lua.State) throws -> Int32 {
        let layer = try change { sprite -> Layer in
            var layer = Layer(name: L10n.string("Layer %d", sprite.layers.filter { !$0.isGroup }.count + 1))
            let index = sprite.layers.firstIndex { $0.id == activeLayerID } ?? sprite.layers.count - 1
            let active = sprite.layers.indices.contains(index) ? sprite.layers[index] : nil
            layer.parent = active?.isGroup == true ? active?.id : active?.parent
            sprite.layers.insert(layer, at: active?.isGroup == true ? index : index + 1)
            return layer
        }
        activeLayerID = layer.id
        push(.layer(layer.id), on: L)
        return 1
    }

    func newCel(_ L: Lua.State) throws -> Int32 {
        guard case .layer(let layerID) = object(L, 2, "Layer") else { throw Failure(L10n.string("%@ must be a Layer", "newCel")) }
        _ = try layerPosition(layerID)
        let frame = try frameIndex(L, 3)
        var source: PixelImage?
        if case .image(let ref) = object(L, 4, "Image") { source = try image(ref) }
        let x = field(L, 5, "x").map { Int($0) } ?? 0, y = field(L, 5, "y").map { Int($0) } ?? 0
        let key = try change { sprite -> CelKey in
            let key = CelKey(layer: layerID, frame: sprite.frames[frame].id)
            var image = PixelImage(width: sprite.width, height: sprite.height)
            if let source { image.pasteClipped(source, at: x, y) }
            sprite.cels[key] = image
            return key
        }
        push(.cel(key), on: L)
        return 1
    }

    func deleteLayer(_ L: Lua.State) throws -> Int32 {
        let sprite = try sprite()
        var id: UUID?
        if case .layer(let layer) = object(L, 2, "Layer") { id = layer }
        if let name = Lua.string(L, 2) { id = sprite.layers.last { $0.name == name }?.id }
        guard let id, let index = sprite.layers.firstIndex(where: { $0.id == id }) else { throw Failure(L10n.string("The layer was deleted")) }
        let removed = Set([id] + sprite.descendants(of: id).map(\.id))
        guard sprite.layers.contains(where: { !removed.contains($0.id) && !$0.isGroup }) else { throw Failure(L10n.string("A sprite needs at least one layer")) }
        try change { s in
            s.layers.removeAll { removed.contains($0.id) }
            s.cels = s.cels.filter { !removed.contains($0.key.layer) }
            s.normalizeLinks()
        }
        if removed.contains(activeLayerID) {
            let remaining = try self.sprite().layers
            activeLayerID = (remaining[..<min(index, remaining.count)].last { !$0.isGroup } ?? remaining.first { !$0.isGroup } ?? remaining[0]).id
        }
        return 0
    }

    func deleteCel(_ L: Lua.State) throws -> Int32 {
        var key: CelKey?
        if case .cel(let celKey) = object(L, 2, "Cel") { key = celKey }
        if case .layer(let layer) = object(L, 2, "Layer") { key = CelKey(layer: layer, frame: try sprite().frames[try frameIndex(L, 3)].id) }
        guard let key else { throw Failure(L10n.string("%@ must be a Cel", "deleteCel")) }
        try change { s in
            s.cels[key] = nil
            s.celOpacity[key] = nil
            s.normalizeLinks()
        }
        return 0
    }

    /// `sprite:newFrame(n)` copies frame n after it; `newEmptyFrame(n)` inserts an empty one at n.
    func newFrame(_ L: Lua.State, empty: Bool) throws -> Int32 {
        let count = try sprite().frames.count
        let number = Lua.isNoneOrNil(L, 2) ? (empty ? count + 1 : activeFrameIndex + 1) : try int(L, 2, "frame")
        let frame = try change { sprite -> Frame in
            if empty {
                let index = min(max(0, number - 1), sprite.frames.count)
                let frame = Frame(duration: sprite.frames[min(index, sprite.frames.count - 1)].duration)
                sprite.insertFrame(frame, at: index)
                return frame
            }
            let source = min(max(0, number - 1), sprite.frames.count - 1)
            let original = sprite.frames[source]
            let frame = Frame(duration: original.duration)
            sprite.insertFrame(frame, at: source + 1)
            for layer in sprite.layers {
                if let image = sprite.cels[CelKey(layer: layer.id, frame: original.id)] {
                    sprite.cels[CelKey(layer: layer.id, frame: frame.id)] = image
                }
            }
            return frame
        }
        if let index = try sprite().frames.firstIndex(where: { $0.id == frame.id }) { activeFrameIndex = index }
        push(.frame(frame.id), on: L)
        return 1
    }

    // MARK: - Layer, Cel, Frame

    private func layerIndex(_ L: Lua.State, _ id: UUID, _ key: String) throws -> Int32 {
        let sprite = try sprite()
        let layer = sprite.layers[try layerPosition(id)]
        let siblings = sprite.layers.filter { $0.parent == layer.parent }
        switch key {
        case "name": Lua.pushString(L, layer.name)
        case "isVisible": lua_pushboolean(L, layer.isVisible ? 1 : 0)
        case "isEditable": lua_pushboolean(L, layer.isLocked ? 0 : 1)
        case "isGroup": lua_pushboolean(L, layer.isGroup ? 1 : 0)
        case "isImage": lua_pushboolean(L, layer.isGroup ? 0 : 1)
        case "isBackground": lua_pushboolean(L, layer.isBackground ? 1 : 0)
        case "isTilemap": lua_pushboolean(L, layer.isTilemap ? 1 : 0)
        case "isReference": lua_pushboolean(L, layer.isReference ? 1 : 0)
        case "opacity": lua_pushinteger(L, lua_Integer((layer.opacity * 255).rounded()))
        case "stackIndex": lua_pushinteger(L, lua_Integer((siblings.firstIndex { $0.id == id } ?? 0) + 1))
        case "sprite": push(.sprite, on: L)
        case "parent": if let parent = layer.parent { push(.layer(parent), on: L) } else { push(.sprite, on: L) }
        case "layers": pushList(L, sprite.layers.filter { $0.parent == id }.map { .layer($0.id) })
        case "cels": pushList(L, sprite.frames.compactMap { frame in sprite.cels[CelKey(layer: id, frame: frame.id)] != nil ? .cel(CelKey(layer: id, frame: frame.id)) : nil })
        case "cel": return pushMethod(L, LuaAPI.layerCel)
        default: throw Failure.unsupported("Layer.\(key)")
        }
        return 1
    }

    func layerCel(_ L: Lua.State) throws -> Int32 {
        guard case .layer(let id) = object(L, 1, "Layer") else { return 0 }
        let sprite = try sprite()
        let key = CelKey(layer: id, frame: sprite.frames[try frameIndex(L, 2)].id)
        if sprite.cels[key] != nil { push(.cel(key), on: L) } else { lua_pushnil(L) }
        return 1
    }

    private func celIndex(_ L: Lua.State, _ celKey: CelKey, _ key: String) throws -> Int32 {
        let sprite = try sprite()
        guard sprite.cels[celKey] != nil, let frame = sprite.frames.firstIndex(where: { $0.id == celKey.frame }) else {
            throw Failure(L10n.string("The cel was deleted"))
        }
        switch key {
        case "image": push(.image(.cel(celKey)), on: L)
        case "layer": push(.layer(celKey.layer), on: L)
        case "frame": push(.frame(celKey.frame), on: L)
        case "frameNumber": lua_pushinteger(L, lua_Integer(frame + 1))
        case "sprite": push(.sprite, on: L)
        case "position": pushPoint(L, 0, 0)
        case "bounds": pushRectangle(L, 0, 0, sprite.width, sprite.height)
        case "opacity": lua_pushinteger(L, lua_Integer(((sprite.celOpacity[celKey] ?? 1) * 255).rounded()))
        default: throw Failure.unsupported("Cel.\(key)")
        }
        return 1
    }

    private func frameIndex(_ L: Lua.State, _ id: UUID, _ key: String) throws -> Int32 {
        let sprite = try sprite()
        guard let index = sprite.frames.firstIndex(where: { $0.id == id }) else { throw Failure(L10n.string("The frame was deleted")) }
        switch key {
        case "frameNumber": lua_pushinteger(L, lua_Integer(index + 1))
        case "duration": lua_pushnumber(L, Double(sprite.frames[index].duration) / 1000)
        case "sprite": push(.sprite, on: L)
        case "previous": if index > 0 { push(.frame(sprite.frames[index - 1].id), on: L) } else { lua_pushnil(L) }
        case "next": if index + 1 < sprite.frames.count { push(.frame(sprite.frames[index + 1].id), on: L) } else { lua_pushnil(L) }
        default: throw Failure.unsupported("Frame.\(key)")
        }
        return 1
    }

    // MARK: - Palette

    private func paletteIndex(_ L: Lua.State, _ key: String) throws -> Int32 {
        switch key {
        case "getColor": return pushMethod(L, LuaAPI.getColor)
        case "setColor": return pushMethod(L, LuaAPI.setColor)
        case "resize": return pushMethod(L, LuaAPI.resizePalette)
        case "frame": push(.frame(try sprite().frames[0].id), on: L)
        default: throw Failure.unsupported("Palette.\(key)")
        }
        return 1
    }

    /// Palette entries count from 0, as in Aseprite.
    func getColor(_ L: Lua.State) throws -> Int32 {
        let palette = try sprite().palette
        let index = try int(L, 2, "index")
        guard palette.indices.contains(index) else { throw Failure(L10n.string("There's no palette entry %lld", index)) }
        pushColor(palette[index], on: L)
        return 1
    }

    func setColor(_ L: Lua.State) throws -> Int32 {
        let index = try int(L, 2, "index")
        guard let c = color(L, 3) else { throw Failure(L10n.string("%@ must be a Color", "setColor")) }
        try change { sprite in
            guard sprite.palette.indices.contains(index) else { throw Failure(L10n.string("There's no palette entry %lld", index)) }
            sprite.palette[index] = c
        }
        return 0
    }

    func resizePalette(_ L: Lua.State) throws -> Int32 {
        let count = min(PaletteFile.maxColors, max(1, try int(L, 2, "size")))
        try change { sprite in
            if sprite.palette.count > count {
                sprite.palette.removeLast(sprite.palette.count - count)
            } else {
                sprite.palette += Array(repeating: .black, count: count - sprite.palette.count)
            }
        }
        return 0
    }

    // MARK: - Image

    func image(_ ref: ImageRef) throws -> PixelImage {
        switch ref {
        case .cel(let key):
            guard let image = try sprite().cels[key] else { throw Failure(L10n.string("The cel was deleted")) }
            return image
        case .own(let index):
            return ownImages[index]
        }
    }

    func changeImage<T>(_ ref: ImageRef, _ body: (inout PixelImage) throws -> T) throws -> T {
        switch ref {
        case .cel(let key):
            return try change { sprite in
                guard sprite.cels[key] != nil else { throw Failure(L10n.string("The cel was deleted")) }
                return try body(&sprite.cels[key]!)
            }
        case .own(let index):
            return try body(&ownImages[index])
        }
    }

    private func imageRef(_ L: Lua.State, _ index: Int32 = 1) throws -> ImageRef {
        guard case .image(let ref) = object(L, index, "Image") else { throw Failure(L10n.string("%@ must be an Image", "self")) }
        return ref
    }

    private func imageIndex(_ L: Lua.State, _ ref: ImageRef, _ key: String) throws -> Int32 {
        switch key {
        case "width": lua_pushinteger(L, lua_Integer(try image(ref).width))
        case "height": lua_pushinteger(L, lua_Integer(try image(ref).height))
        case "bounds":
            let image = try image(ref)
            pushRectangle(L, 0, 0, image.width, image.height)
        case "colorMode": lua_pushinteger(L, 0)
        case "cel":
            if case .cel(let key) = ref { push(.cel(key), on: L) } else { lua_pushnil(L) }
        case "getPixel": return pushMethod(L, LuaAPI.getPixel)
        case "putPixel", "drawPixel": return pushMethod(L, LuaAPI.putPixel)
        case "clear": return pushMethod(L, LuaAPI.clearImage)
        case "clone": return pushMethod(L, LuaAPI.cloneImage)
        case "drawImage": return pushMethod(L, LuaAPI.drawImage)
        case "isEmpty": return pushMethod(L, LuaAPI.isEmptyImage)
        default: throw Failure.unsupported("Image.\(key)")
        }
        return 1
    }

    /// `Image(w, h)`, `Image{ width=, height= }` or `Image(otherImage)`.
    func newImage(_ L: Lua.State) throws -> Int32 {
        var image: PixelImage
        if case .image(let ref) = object(L, 1, "Image") {
            image = try self.image(ref)
        } else if Lua.type(L, 1) == LUA_TTABLE {
            image = PixelImage(width: Int(field(L, 1, "width") ?? 1), height: Int(field(L, 1, "height") ?? 1))
        } else {
            image = PixelImage(width: try int(L, 1, "width"), height: try int(L, 2, "height"))
        }
        guard image.width > 0, image.height > 0, image.width * image.height <= 4096 * 4096 else {
            throw Failure(L10n.string("Images must be between 1 and 4096 pixels on each side"))
        }
        ownImages.append(image)
        push(.image(.own(ownImages.count - 1)), on: L)
        return 1
    }

    func getPixel(_ L: Lua.State) throws -> Int32 {
        let image = try image(try imageRef(L))
        let x = try int(L, 2, "x"), y = try int(L, 3, "y")
        let inside = x >= 0 && y >= 0 && x < image.width && y < image.height
        lua_pushinteger(L, inside ? Self.pack(image[x, y]) : 0)
        return 1
    }

    func putPixel(_ L: Lua.State) throws -> Int32 {
        let ref = try imageRef(L)
        let x = try int(L, 2, "x"), y = try int(L, 3, "y")
        guard let c = color(L, 4) else { throw Failure(L10n.string("%@ must be a Color", "putPixel")) }
        try changeImage(ref) { image in
            if x >= 0, y >= 0, x < image.width, y < image.height { image[x, y] = c }
        }
        return 0
    }

    func clearImage(_ L: Lua.State) throws -> Int32 {
        let ref = try imageRef(L)
        let c = color(L, 2) ?? .clear
        try changeImage(ref) { image in image = PixelImage(width: image.width, height: image.height, fill: c) }
        return 0
    }

    func cloneImage(_ L: Lua.State) throws -> Int32 {
        ownImages.append(try image(try imageRef(L)))
        push(.image(.own(ownImages.count - 1)), on: L)
        return 1
    }

    func isEmptyImage(_ L: Lua.State) throws -> Int32 {
        lua_pushboolean(L, try image(try imageRef(L)).isEmpty ? 1 : 0)
        return 1
    }

    /// Draws another image over this one at a position, blending as in normal mode.
    func drawImage(_ L: Lua.State) throws -> Int32 {
        let ref = try imageRef(L)
        guard case .image(let sourceRef) = object(L, 2, "Image") else { throw Failure(L10n.string("%@ must be an Image", "drawImage")) }
        let source = try image(sourceRef)
        let x = Int(field(L, 3, "x") ?? 0), y = Int(field(L, 3, "y") ?? 0)
        try changeImage(ref) { image in
            for sy in 0..<source.height {
                for sx in 0..<source.width {
                    let dx = x + sx, dy = y + sy
                    guard dx >= 0, dy >= 0, dx < image.width, dy < image.height else { continue }
                    image[dx, dy] = source[sx, sy].blended(over: image[dx, dy])
                }
            }
        }
        return 0
    }

    // MARK: - Dialog

    /// `Dialog("Title")` or `Dialog{ title=, onclose= }`.
    func newDialog(_ L: Lua.State) throws -> Int32 {
        let title = Lua.string(L, 1) ?? stringField(L, 1, "title") ?? name
        let dialog = ScriptDialog(title: title, engine: self)
        dialog.onClose = functionField(L, 1, "onclose")
        allDialogs.append(dialog)
        push(.dialog(allDialogs.count - 1), on: L)
        return 1
    }

    private func dialog(_ L: Lua.State) throws -> ScriptDialog {
        guard case .dialog(let index) = object(L, 1, "Dialog") else { throw Failure(L10n.string("%@ must be a Dialog", "self")) }
        return allDialogs[index]
    }

    private func dialogIndex(_ L: Lua.State, _ dialog: ScriptDialog, _ key: String) throws -> Int32 {
        if let kind = ScriptDialog.Kind(rawValue: key) {
            Lua.pushString(L, kind.rawValue)
            lua_pushcclosure(L, LuaAPI.dialogWidget, 1)
            return 1
        }
        switch key {
        case "show": return pushMethod(L, LuaAPI.dialogShow)
        case "close": return pushMethod(L, LuaAPI.dialogClose)
        case "modify": return pushMethod(L, LuaAPI.dialogModify)
        case "repaint": return pushMethod(L, LuaAPI.dialogRepaint)
        case "data": pushData(of: dialog, on: L)
        case "bounds": pushRectangle(L, 0, 0, Int(EditorView.panelWidth - 16), 0)
        default: throw Failure.unsupported("Dialog.\(key)")
        }
        return 1
    }

    private func pushData(of dialog: ScriptDialog, on L: Lua.State) {
        Lua.newTable(L)
        for widget in dialog.widgets {
            guard let key = widget.key else { continue }
            switch widget.kind {
            case .button:
                lua_pushboolean(L, dialog.closedBy == key ? 1 : 0)
            case .slider:
                lua_pushinteger(L, lua_Integer(dialog.number(widget).rounded()))
            case .number:
                lua_pushnumber(L, dialog.number(widget))
            case .check, .radio:
                lua_pushboolean(L, dialog.bool(widget) ? 1 : 0)
            case .color:
                pushColor(dialog.color(widget), on: L)
            case .combobox, .entry, .label:
                Lua.pushString(L, dialog.text(widget))
            case .separator, .newrow:
                continue
            }
            Lua.setField(L, -2, key)
        }
    }

    /// `dlg:slider{ … }` and the other widgets; returns the dialog for chaining.
    func dialogWidget(_ L: Lua.State) throws -> Int32 {
        let dialog = try dialog(L)
        guard let kind = Lua.string(L, Lua.upvalueIndex(1)).flatMap(ScriptDialog.Kind.init) else { return 0 }
        var widget = ScriptDialog.Widget(kind: kind)
        if Lua.type(L, 2) == LUA_TTABLE {
            widget.key = stringField(L, 2, "id")
            widget.label = stringField(L, 2, "label")
            widget.text = stringField(L, 2, "text")
            widget.min = field(L, 2, "min") ?? (kind == .slider ? 0 : -.greatestFiniteMagnitude)
            widget.max = field(L, 2, "max") ?? (kind == .slider ? 100 : .greatestFiniteMagnitude)
            widget.decimals = Int(field(L, 2, "decimals") ?? 0)
            widget.visible = boolField(L, 2, "visible") ?? true
            widget.enabled = boolField(L, 2, "enabled") ?? true
            widget.onClick = functionField(L, 2, "onclick")
            widget.onChange = functionField(L, 2, "onchange")
            if Lua.getField(L, 2, "options") == LUA_TTABLE {
                for i in 1...max(1, Int(luaL_len(L, -1))) {
                    lua_rawgeti(L, -1, lua_Integer(i))
                    if let option = Lua.string(L, -1) { widget.options.append(option) }
                    Lua.pop(L)
                }
            }
            Lua.pop(L)
        } else if kind == .separator, let text = Lua.string(L, 2) {
            widget.text = text
        }
        if kind == .radio {
            let previous = dialog.widgets.last
            widget.group = previous?.kind == .radio ? previous!.group : (dialog.widgets.map(\.group).max() ?? 0) + 1
        }
        dialog.values[widget.valueKey] = initialValue(L, widget)
        dialog.widgets.append(widget)
        if kind == .radio, dialog.bool(widget) { dialog.select(widget) }
        lua_settop(L, 1)
        return 1
    }

    private func initialValue(_ L: Lua.State, _ widget: ScriptDialog.Widget) -> ScriptDialog.Value? {
        let hasTable = Lua.type(L, 2) == LUA_TTABLE
        switch widget.kind {
        case .slider:
            return .number(min(widget.max, max(widget.min, field(L, 2, "value") ?? widget.min)))
        case .number:
            return .number(field(L, 2, "text", "value") ?? 0)
        case .check, .radio:
            return .bool(boolField(L, 2, "selected") ?? false)
        case .color:
            guard hasTable else { return .color(.black) }
            Lua.getField(L, 2, "color")
            defer { Lua.pop(L) }
            return .color(color(L, -1) ?? .black)
        case .combobox:
            return .text(stringField(L, 2, "option") ?? widget.options.first ?? "")
        case .entry, .label:
            return .text(widget.text ?? "")
        case .button:
            return .bool(false)
        case .separator, .newrow:
            return nil
        }
    }

    func dialogShow(_ L: Lua.State) throws -> Int32 {
        let dialog = try dialog(L)
        let wait = boolField(L, 2, "wait") ?? true
        lua_settop(L, 1)
        commit()
        return open(dialog, wait: wait, from: L)
    }

    func dialogClose(_ L: Lua.State) throws -> Int32 {
        close(try dialog(L))
        lua_settop(L, 1)
        return 1
    }

    /// `dlg:modify{ id=, … }` changes a widget's properties or value.
    func dialogModify(_ L: Lua.State) throws -> Int32 {
        let dialog = try dialog(L)
        guard let id = stringField(L, 2, "id"), let index = dialog.widgets.firstIndex(where: { $0.key == id }) else {
            lua_settop(L, 1)
            return 1
        }
        var widget = dialog.widgets[index]
        if let label = stringField(L, 2, "label") { widget.label = label }
        if let text = stringField(L, 2, "text") {
            widget.text = text
            if widget.kind == .entry || widget.kind == .label { dialog.values[widget.valueKey] = .text(text) }
            if widget.kind == .number, let n = Double(text) { dialog.values[widget.valueKey] = .number(n) }
        }
        if let visible = boolField(L, 2, "visible") { widget.visible = visible }
        if let enabled = boolField(L, 2, "enabled") { widget.enabled = enabled }
        if let min = field(L, 2, "min") { widget.min = min }
        if let max = field(L, 2, "max") { widget.max = max }
        if let value = field(L, 2, "value") { dialog.values[widget.valueKey] = .number(value) }
        if let option = stringField(L, 2, "option") { dialog.values[widget.valueKey] = .text(option) }
        if Lua.getField(L, 2, "color") != LUA_TNIL, let c = color(L, -1) { dialog.values[widget.valueKey] = .color(c) }
        Lua.pop(L)
        if Lua.getField(L, 2, "options") == LUA_TTABLE {
            widget.options = []
            for i in 1...max(1, Int(luaL_len(L, -1))) {
                lua_rawgeti(L, -1, lua_Integer(i))
                if let option = Lua.string(L, -1) { widget.options.append(option) }
                Lua.pop(L)
            }
        }
        Lua.pop(L)
        dialog.widgets[index] = widget
        if let selected = boolField(L, 2, "selected") {
            if widget.kind == .radio, selected { dialog.select(widget) } else { dialog.values[widget.valueKey] = .bool(selected) }
        }
        lua_settop(L, 1)
        return 1
    }
}

