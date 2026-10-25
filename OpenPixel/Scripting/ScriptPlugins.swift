import Foundation

/// Something that happened in the document that scripts can listen to.
enum ScriptEvent {
    /// The sprite changed: a stroke (neither flag), a command, or an undo or redo.
    case change(fromUndo: Bool, command: Bool)
    /// The active sprite, layer or frame changed.
    case site
    case foregroundColor
    case backgroundColor
}

/// Extensions' scripts (plugins), `dofile`, events, timers and selections.
/// https://www.aseprite.org/api/plugin
extension ScriptEngine {
    // MARK: - Plugins

    /// Runs an extension's script, then `init(plugin)`, then the command, if any.
    func startPlugin(entry: String, command: String?) {
        begin()
        defer {
            end()
            mainFinished = true
            finishIfDone()
        }
        let source: String
        do {
            source = try readFile(entry)
        } catch {
            return report(error.localizedDescription)
        }
        if let error = load(source, chunkName: "@\(entry)") ?? Lua.protectedCall(L, arguments: 0, results: 0) {
            return report(error)
        }
        guard Lua.getGlobal(L, "init") == LUA_TFUNCTION else { return Lua.pop(L) }
        pushPlugin()
        if let error = Lua.protectedCall(L, arguments: 1, results: 0) { return report(error) }
        if let command, let found = commands.first(where: { $0.id == command }) { call(found.onClick) }
    }

    /// The commands an extension's script adds, found by running its `init` on a blank sprite.
    static func commands(of entry: String, in folder: URL, name: String) -> [(id: String, title: String)] {
        let document = SpriteDocument(name: name, sprite: .blank(width: 16, height: 16, background: nil, palette: []))
        let engine = ScriptEngine(name: name, document: document, folder: folder)
        engine.discovering = true
        engine.startPlugin(entry: entry, command: nil)
        let found = engine.commands.map { ($0.id, $0.title) }
        engine.stop()
        return found
    }

    private func pushPlugin() {
        Lua.newTable(L)
        Lua.pushString(L, name)
        Lua.setField(L, -2, "name")
        Lua.pushString(L, "")
        Lua.setField(L, -2, "path")
        pushPreferences()
        lua_pushvalue(L, -1)
        preferencesReference = luaL_ref(L, Lua.registryIndex)
        Lua.setField(L, -2, "preferences")
        Lua.pushFunction(L, LuaAPI.newCommand)
        Lua.setField(L, -2, "newCommand")
        // Menus are OpenPixel's: groups and separators have nothing to do.
        for method in ["newMenuGroup", "newMenuSeparator", "deleteCommand", "deleteMenuGroup"] {
            Lua.pushFunction(L, LuaAPI.ignore)
            Lua.setField(L, -2, method)
        }
    }

    /// `plugin:newCommand{ id=, title=, onclick= }`: shown in … > Scripts.
    func newCommand(_ L: Lua.State) throws -> Int32 {
        guard let id = stringField(L, 2, "id"), let onClick = functionField(L, 2, "onclick") else {
            throw Failure(L10n.string("%@ needs an id and an onclick function", "newCommand"))
        }
        commands.append((id, stringField(L, 2, "title") ?? id, onClick))
        return 0
    }

    // MARK: Preferences

    /// `plugin.preferences`, kept between runs (numbers, booleans and strings).
    private func pushPreferences() {
        Lua.newTable(L)
        guard let key = preferencesKey, let saved = UserDefaults.standard.dictionary(forKey: key) else { return }
        for (name, value) in saved {
            switch value {
            case let flag as Bool: lua_pushboolean(L, flag ? 1 : 0)
            case let number as Double: lua_pushnumber(L, number)
            case let text as String: Lua.pushString(L, text)
            default: continue
            }
            Lua.setField(L, -2, name)
        }
    }

    func savePreferences() {
        guard let key = preferencesKey, let reference = preferencesReference, !discovering else { return }
        lua_rawgeti(L, Lua.registryIndex, lua_Integer(reference))
        var saved: [String: Any] = [:]
        lua_pushnil(L)
        while lua_next(L, -2) != 0 {
            if lua_type(L, -2) == LUA_TSTRING, let name = Lua.string(L, -2) {
                switch lua_type(L, -1) {
                case LUA_TBOOLEAN: saved[name] = Lua.bool(L, -1)
                case LUA_TNUMBER: saved[name] = Lua.number(L, -1)
                case LUA_TSTRING: saved[name] = Lua.string(L, -1)
                default: break
                }
            }
            Lua.pop(L)
        }
        Lua.pop(L)
        UserDefaults.standard.set(saved, forKey: key)
    }

    // MARK: - dofile

    /// A file of the script's folder, by its path from there.
    private func readFile(_ path: String) throws -> String {
        guard let folder else { throw Failure(L10n.string("%@ isn't available in OpenPixel yet", "dofile")) }
        return try String(contentsOf: folder.appendingPathComponent(path), encoding: .utf8)
    }

    /// `dofile("./Other.lua")`, relative to the file that calls it and kept inside the script's folder.
    func doFile(_ L: Lua.State) throws -> Int32 {
        guard let path = Lua.string(L, 1) else { throw Failure(L10n.string("%@ must be a string", "dofile")) }
        var info = lua_Debug()
        var directory: [String] = []
        if lua_getstack(L, 1, &info) != 0, lua_getinfo(L, "S", &info) != 0, let source = info.source {
            let caller = String(cString: source)
            if caller.hasPrefix("@") { directory = caller.dropFirst().split(separator: "/").dropLast().map(String.init) }
        }
        var parts = path.hasPrefix("/") ? [] : directory
        for part in path.split(separator: "/").map(String.init) {
            switch part {
            case ".", "": continue
            case "..":
                guard !parts.isEmpty else { throw Failure(L10n.string("Scripts can only read files in their own folder")) }
                parts.removeLast()
            default: parts.append(part)
            }
        }
        let resolved = parts.joined(separator: "/")
        let source: String
        do {
            source = try readFile(resolved)
        } catch let failure as Failure {
            throw failure
        } catch {
            throw Failure(L10n.string("Couldn't read %@", resolved))
        }
        lua_settop(L, 0)
        if let error = load(source, chunkName: "@\(resolved)") ?? Lua.protectedCall(L, arguments: 0, results: LUA_MULTRET) {
            throw Failure(error, isLocated: true)
        }
        return lua_gettop(L)
    }

    // MARK: - Events

    func eventsIndex(_ L: Lua.State, _ key: String) throws -> Int32 {
        switch key {
        case "on": Lua.pushFunction(L, LuaAPI.eventsOn)
        case "off": Lua.pushFunction(L, LuaAPI.eventsOff)
        default: throw Failure.unsupported("events.\(key)")
        }
        return 1
    }

    static let supportedEvents: Set<String> = ["change", "sitechange", "fgcolorchange", "bgcolorchange", "beforecommand", "aftercommand"]

    /// `events:on("change", function(ev) … end)` returns an id for `events:off`.
    func eventsOn(_ L: Lua.State) throws -> Int32 {
        guard case .events(let onSprite) = object(L, 1, "Events"), let event = Lua.string(L, 2), Lua.type(L, 3) == LUA_TFUNCTION else {
            throw Failure(L10n.string("%@ needs an event name and a function", "events:on"))
        }
        guard Self.supportedEvents.contains(event) else { throw Failure.unsupported("events \"\(event)\"") }
        lua_pushvalue(L, 3)
        let listener = Listener(id: nextListenerID, event: event, onSprite: onSprite, function: luaL_ref(L, Lua.registryIndex))
        nextListenerID += 1
        listeners.append(listener)
        lua_pushinteger(L, lua_Integer(listener.id))
        return 1
    }

    /// `events:off(id)` or `events:off(function)`.
    func eventsOff(_ L: Lua.State) throws -> Int32 {
        let removed = listeners.filter { listener in
            if lua_isinteger(L, 2) != 0 { return lua_tointegerx(L, 2, nil) == listener.id }
            lua_rawgeti(L, Lua.registryIndex, lua_Integer(listener.function))
            defer { Lua.pop(L) }
            return lua_rawequal(L, -1, 2) != 0
        }
        for listener in removed { luaL_unref(L, Lua.registryIndex, listener.function) }
        listeners.removeAll { listener in removed.contains { $0.id == listener.id } }
        return 0
    }

    /// The document tells running scripts what happened (after the change, never during a script's own run).
    func handle(_ event: ScriptEvent) {
        guard !isRunning, !listeners.isEmpty else { return }
        switch event {
        case .change(let fromUndo, let command):
            // Commands come between beforecommand and aftercommand, as Aseprite's do.
            if command { fire("beforecommand", name: "OpenPixel") }
            // A script answering a stroke changes that stroke's undo step (Magic Pencil does).
            fire("change", onSprite: true, fromUndo: fromUndo, merging: !fromUndo && !command)
            if command { fire("aftercommand", name: "OpenPixel") }
        case .site: fire("sitechange")
        case .foregroundColor: fire("fgcolorchange")
        case .backgroundColor: fire("bgcolorchange")
        }
        finishIfDone()
    }

    private func fire(_ event: String, onSprite: Bool = false, name: String? = nil, fromUndo: Bool = false, merging: Bool = false) {
        for listener in listeners where listener.event == event && listener.onSprite == onSprite {
            // A listener before it may have removed it.
            guard listeners.contains(where: { $0.id == listener.id }) else { continue }
            call(listener.function, merging: merging) { L in
                Lua.newTable(L)
                lua_pushboolean(L, fromUndo ? 1 : 0)
                Lua.setField(L, -2, "fromUndo")
                if let name {
                    Lua.pushString(L, name)
                    Lua.setField(L, -2, "name")
                }
            }
        }
    }

    // MARK: - Timer

    /// `Timer{ interval=, ontick= }`.
    func newTimer(_ L: Lua.State) throws -> Int32 {
        guard let onTick = functionField(L, 1, "ontick") else { throw Failure(L10n.string("%@ needs an ontick function", "Timer")) }
        timers.append(ScriptTimer(interval: max(0.01, field(L, 1, "interval") ?? 1), onTick: onTick))
        push(.timer(timers.count - 1), on: L)
        return 1
    }

    func timerIndex(_ L: Lua.State, _ index: Int, _ key: String) throws -> Int32 {
        switch key {
        case "start": Lua.pushFunction(L, LuaAPI.timerStart)
        case "stop": Lua.pushFunction(L, LuaAPI.timerStop)
        case "interval": lua_pushnumber(L, timers[index].interval)
        case "isRunning": lua_pushboolean(L, timers[index].timer != nil ? 1 : 0)
        default: throw Failure.unsupported("Timer.\(key)")
        }
        return 1
    }

    func timerStart(_ L: Lua.State) throws -> Int32 {
        guard case .timer(let index) = object(L, 1, "Timer"), timers[index].timer == nil, !discovering else { return 0 }
        timers[index].timer = Timer.scheduledTimer(withTimeInterval: timers[index].interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick(index) }
        }
        return 0
    }

    func timerStop(_ L: Lua.State) throws -> Int32 {
        guard case .timer(let index) = object(L, 1, "Timer") else { return 0 }
        timers[index].timer?.invalidate()
        timers[index].timer = nil
        if !isRunning { finishIfDone() }
        return 0
    }

    private func tick(_ index: Int) {
        guard !isRunning, timers.indices.contains(index), timers[index].timer != nil else { return }
        let failures = failureCount
        call(timers[index].onTick)
        // A timer that keeps failing would keep showing the alert.
        if failureCount != failures {
            timers[index].timer?.invalidate()
            timers[index].timer = nil
        }
        finishIfDone()
    }

    // MARK: - Selection

    func selectionMask(_ ref: SelectionRef) throws -> SelectionMask {
        let sprite = try sprite()
        switch ref {
        case .sprite: return workSelection ?? SelectionMask(width: sprite.width, height: sprite.height)
        case .own(let index): return ownSelections[index]
        }
    }

    func setSelectionMask(_ ref: SelectionRef, _ mask: SelectionMask) {
        switch ref {
        case .sprite: workSelection = mask.bits.contains(true) ? mask : nil
        case .own(let index): ownSelections[index] = mask
        }
    }

    /// `Selection()` or `Selection(rectangle)`.
    func newSelection(_ L: Lua.State) throws -> Int32 {
        let sprite = try sprite()
        var mask = SelectionMask(width: sprite.width, height: sprite.height)
        if let rect = rectangle(L, 1) { mask = mask.combined(with: .rect(rect, width: sprite.width, height: sprite.height), mode: .add) }
        ownSelections.append(mask)
        push(.selection(.own(ownSelections.count - 1)), on: L)
        return 1
    }

    /// A Rectangle (or any table with x, y, width and height).
    func rectangle(_ L: Lua.State, _ index: Int32) -> PixelRect? {
        guard let x = field(L, index, "x"), let y = field(L, index, "y"),
              let width = field(L, index, "width", "w"), let height = field(L, index, "height", "h"), width >= 1, height >= 1 else { return nil }
        return PixelRect(minX: Int(x), minY: Int(y), maxX: Int(x) + Int(width) - 1, maxY: Int(y) + Int(height) - 1)
    }

    func selectionIndex(_ L: Lua.State, _ ref: SelectionRef, _ key: String) throws -> Int32 {
        let mask = try selectionMask(ref)
        switch key {
        case "isEmpty": lua_pushboolean(L, mask.bits.contains(true) ? 0 : 1)
        case "bounds", "origin":
            var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
            for y in 0..<mask.height {
                for x in 0..<mask.width where mask.bits[y * mask.width + x] {
                    minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
                }
            }
            let empty = maxX < 0
            if key == "origin" {
                pushPoint(L, empty ? 0 : minX, empty ? 0 : minY)
            } else {
                pushRectangle(L, empty ? 0 : minX, empty ? 0 : minY, empty ? 0 : maxX - minX + 1, empty ? 0 : maxY - minY + 1)
            }
        case "contains", "add", "subtract", "intersect", "select", "selectAll", "deselect":
            Lua.pushString(L, key)
            lua_pushcclosure(L, LuaAPI.selectionMethod, 1)
        default: throw Failure.unsupported("Selection.\(key)")
        }
        return 1
    }

    func selectionMethod(_ L: Lua.State) throws -> Int32 {
        guard case .selection(let ref) = object(L, 1, "Selection") else { return 0 }
        let method = Lua.string(L, Lua.upvalueIndex(1)) ?? ""
        let mask = try selectionMask(ref)
        let empty = SelectionMask(width: mask.width, height: mask.height)
        /// The argument as a mask: a Selection or a Rectangle.
        func argument() throws -> SelectionMask {
            if case .selection(let other) = object(L, 2, "Selection") { return try selectionMask(other) }
            if let rect = rectangle(L, 2) { return .rect(rect, width: mask.width, height: mask.height) }
            throw Failure(L10n.string("%@ must be a Selection or a Rectangle", "Selection:\(method)"))
        }
        switch method {
        case "contains":
            let x = try field(L, 2, "x").map { Int($0) } ?? int(L, 2, "x")
            let y = try field(L, 2, "y").map { Int($0) } ?? int(L, 3, "y")
            lua_pushboolean(L, x >= 0 && y >= 0 && x < mask.width && y < mask.height && mask.bits[y * mask.width + x] ? 1 : 0)
            return 1
        case "add": setSelectionMask(ref, mask.combined(with: try argument(), mode: .add))
        case "subtract": setSelectionMask(ref, mask.combined(with: try argument(), mode: .subtract))
        case "intersect": setSelectionMask(ref, mask.combined(with: try argument(), mode: .intersect))
        case "select": setSelectionMask(ref, try argument())
        case "selectAll": setSelectionMask(ref, empty.inverted())
        case "deselect": setSelectionMask(ref, empty)
        default: break
        }
        return 0
    }
}
