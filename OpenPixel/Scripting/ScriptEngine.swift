import Foundation

/// Runs an Aseprite script (Lua 5.4) on a document. Scripts see a subset of
/// Aseprite's API (app, Sprite, Layer, Cel, Frame, Image, Color, Dialog…)
/// built on OpenPixel's model; whatever they reach that isn't there fails with
/// a message naming it. Everything one run changes — the script itself, or
/// one dialog callback — is one undo step.
/// https://www.aseprite.org/api/
@MainActor
final class ScriptEngine {
    struct Failure: Error {
        let message: String
        init(_ message: String) { self.message = message }

        static func unsupported(_ what: String) -> Failure {
            Failure(L10n.string("%@ isn't available in OpenPixel yet", what))
        }
    }

    enum ImageRef: Hashable {
        case cel(CelKey)
        /// One of the script's own images (`Image(w, h)`).
        case own(Int)
    }

    /// What a userdata handle stands for; the handle stores its index in `objects`.
    enum Object: Hashable {
        case sprite
        case layer(UUID)
        case cel(CelKey)
        case frame(UUID)
        case image(ImageRef)
        case dialog(Int)
        case palette

        var typeName: String {
            switch self {
            case .sprite: "Sprite"
            case .layer: "Layer"
            case .cel: "Cel"
            case .frame: "Frame"
            case .image: "Image"
            case .dialog: "Dialog"
            case .palette: "Palette"
            }
        }

        static let typeNames = ["Sprite", "Layer", "Cel", "Frame", "Image", "Dialog", "Palette"]
    }

    /// A C function's result that asks `luaCall` to yield (dlg:show() waiting).
    nonisolated static let yieldResult: Int32 = -2
    /// Scripts that run longer than this are stopped.
    static var timeLimit: TimeInterval = 10

    let name: String
    private(set) weak var document: SpriteDocument?
    nonisolated(unsafe) private let L: Lua.State
    /// The script's main chunk runs as a coroutine, so `dlg:show()` can wait.
    private var main: Lua.State?
    private var mainRef = LUA_NOREF
    private var mainFinished = false
    /// The sprite as the script sees it during a run; committed when the run ends.
    private var work: Sprite?
    var activeLayerID = UUID()
    var activeFrameIndex = 0
    var ownImages: [PixelImage] = []
    private var objects: [Object] = []
    private var objectIndex: [Object: Int32] = [:]
    var allDialogs: [ScriptDialog] = []
    /// The dialog the main chunk waits on.
    private weak var waitingOn: ScriptDialog?
    nonisolated(unsafe) var deadline = Date.distantFuture

    init(name: String, document: SpriteDocument) {
        self.name = name
        self.document = document
        L = luaL_newstate()
        // Only the libraries that can't reach outside the sprite (Vendor/Lua/README.md).
        let libraries: [(String, lua_CFunction)] = [
            ("_G", luaopen_base), ("coroutine", luaopen_coroutine), ("table", luaopen_table),
            ("string", luaopen_string), ("math", luaopen_math), ("utf8", luaopen_utf8),
        ]
        for (name, open) in libraries {
            name.withCString { luaL_requiref(L, $0, open, 1) }
            Lua.pop(L)
        }
        lua_pushlightuserdata(L, Unmanaged.passUnretained(self).toOpaque())
        Lua.setField(L, Lua.registryIndex, "OpenPixel.engine")
        registerAPI()
        lua_sethook(L, LuaAPI.hook, Lua.maskCount, 10_000)
        if let error = load(ScriptPrelude.source, chunkName: "=prelude") ?? Lua.protectedCall(L, arguments: 0, results: 0) {
            assertionFailure("Script prelude: \(error)")
        }
    }

    deinit {
        lua_close(L)
    }

    nonisolated static func engine(of L: Lua.State) -> ScriptEngine {
        Lua.getField(L, Lua.registryIndex, "OpenPixel.engine")
        let pointer = lua_touserdata(L, -1)!
        Lua.pop(L)
        return Unmanaged<ScriptEngine>.fromOpaque(pointer).takeUnretainedValue()
    }

    /// Loads a chunk onto `L`'s stack: nil, or the syntax error.
    private func load(_ source: String, chunkName: String, into state: Lua.State? = nil) -> String? {
        let state = state ?? L
        let bytes = Array(source.utf8)
        let status = bytes.withUnsafeBufferPointer { buffer in
            buffer.baseAddress!.withMemoryRebound(to: CChar.self, capacity: buffer.count) { chars in
                chunkName.withCString { luaL_loadbufferx(state, chars, buffer.count, $0, "t") }
            }
        }
        guard status != LUA_OK else { return nil }
        defer { Lua.pop(state) }
        return Lua.string(state, -1) ?? "error"
    }

    // MARK: - Running

    /// Runs the script; it may keep dialogs open after this returns.
    func start(source: String) {
        let thread = lua_newthread(L)!
        main = thread
        mainRef = luaL_ref(L, Lua.registryIndex)
        if let error = load(source, chunkName: "@\(name).lua", into: thread) {
            report(error)
            mainFinished = true
            return finishIfDone()
        }
        resumeMain(arguments: 0)
    }

    private func resumeMain(arguments: Int32) {
        guard let main else { return }
        begin()
        var results: Int32 = 0
        let status = lua_resume(main, L, arguments, &results)
        if status == LUA_YIELD {
            Lua.pop(main, results)
        } else {
            if status != LUA_OK { report(Lua.string(main, -1) ?? "error") }
            lua_settop(main, 0)
            mainFinished = true
        }
        end()
        finishIfDone()
    }

    /// A dialog callback, as its own run.
    func call(_ reference: Int32) {
        begin()
        lua_rawgeti(L, Lua.registryIndex, lua_Integer(reference))
        if let error = Lua.protectedCall(L, arguments: 0, results: 0) { report(error) }
        end()
    }

    private func begin() {
        deadline = Date().addingTimeInterval(Self.timeLimit)
    }

    private func end() {
        deadline = .distantFuture
        commit()
    }

    private func report(_ message: String) {
        document?.scriptMessage = ScriptMessage(title: L10n.string("“%@” stopped", name), text: message)
    }

    private func finishIfDone() {
        guard mainFinished, !allDialogs.contains(where: \.isOpen) else { return }
        if mainRef != LUA_NOREF { luaL_unref(L, Lua.registryIndex, mainRef) }
        mainRef = LUA_NOREF
        main = nil
        document?.scriptFinished(self)
    }

    /// Closes its dialogs without running more of it (the editor is closing).
    func stop() {
        for dialog in allDialogs where dialog.isOpen { dialog.isOpen = false }
        document?.scriptDialogs.removeAll { $0.engine === self }
        mainFinished = true
        finishIfDone()
    }

    // MARK: - The sprite

    /// The sprite the script reads and changes, from the document the first time in a run.
    func sprite() throws -> Sprite {
        if let work { return work }
        guard let document else { throw Failure(L10n.string("The sprite was closed")) }
        work = document.sprite
        activeLayerID = document.activeLayerID
        activeFrameIndex = document.activeFrameIndex
        return work!
    }

    func change<T>(_ body: (inout Sprite) throws -> T) throws -> T {
        _ = try sprite()
        return try body(&work!)
    }

    /// Hands the run's changes to the document as one undo step.
    func commit() {
        guard let sprite = work else { return }
        work = nil
        document?.applyScript(sprite, activeLayer: activeLayerID, frameIndex: activeFrameIndex)
    }

    func undo() {
        commit()
        document?.undo()
    }

    func redo() {
        commit()
        guard let document else { return }
        document.redo()
        // Scripts redo to refresh the screen (Isometric Box does): keep the layer they made active.
        if document.sprite.layers.contains(where: { $0.id == activeLayerID && !$0.isGroup }) { document.activeLayerID = activeLayerID }
    }

    // MARK: - Objects

    func push(_ object: Object, on L: Lua.State) {
        let index: Int32
        if let known = objectIndex[object] {
            index = known
        } else {
            index = Int32(objects.count)
            objects.append(object)
            objectIndex[object] = index
        }
        lua_newuserdatauv(L, MemoryLayout<Int32>.size, 0)!.storeBytes(of: index, as: Int32.self)
        Lua.setMetatable(L, object.typeName)
    }

    /// The object at `index`, if it's one of ours (and of `type`, when given).
    func object(_ L: Lua.State, _ index: Int32, _ type: String? = nil) -> Object? {
        for name in type.map({ [$0] }) ?? Object.typeNames {
            if let pointer = name.withCString({ luaL_testudata(L, index, $0) }) {
                return objects[Int(pointer.load(as: Int32.self))]
            }
        }
        return nil
    }

    // MARK: - Dialogs

    func open(_ dialog: ScriptDialog, wait: Bool, from L: Lua.State) -> Int32 {
        if !dialog.isOpen {
            dialog.isOpen = true
            dialog.closedBy = nil
            document?.scriptDialogs.append(dialog)
        }
        // Waiting needs the main chunk's coroutine; elsewhere the dialog just opens.
        if wait, L == main, lua_isyieldable(L) != 0 {
            waitingOn = dialog
            return Self.yieldResult
        }
        return 1
    }

    func close(_ dialog: ScriptDialog, by button: String? = nil) {
        guard dialog.isOpen else { return }
        dialog.isOpen = false
        dialog.closedBy = button
        document?.scriptDialogs.removeAll { $0 === dialog }
        if let onClose = dialog.onClose { call(onClose) }
        if waitingOn === dialog {
            waitingOn = nil
            // `dlg:show()` returns the dialog; resumed after the current callback, if any.
            Task { @MainActor in
                guard let main = self.main, let index = self.allDialogs.firstIndex(where: { $0 === dialog }) else { return }
                self.push(.dialog(index), on: main)
                self.resumeMain(arguments: 1)
            }
        } else {
            finishIfDone()
        }
    }

    /// A button, check or radio was tapped.
    func clicked(_ widget: ScriptDialog.Widget, in dialog: ScriptDialog) {
        if let onClick = widget.onClick {
            call(onClick)
        } else if widget.kind == .button {
            // A button without onclick closes the dialog, as in Aseprite.
            close(dialog, by: widget.key)
        }
    }

    func changed(_ widget: ScriptDialog.Widget, in dialog: ScriptDialog) {
        if let onChange = widget.onChange { call(onChange) }
    }

    // MARK: - Registration

    private func registerAPI() {
        func metatable(_ name: String, _ fields: [(String, lua_CFunction)]) {
            name.withCString { _ = luaL_newmetatable(L, $0) }
            for (key, function) in fields {
                Lua.pushFunction(L, function)
                Lua.setField(L, -2, key)
            }
            Lua.pop(L)
        }
        metatable("Color", [("__index", LuaAPI.colorIndex), ("__newindex", LuaAPI.colorNewIndex),
                            ("__eq", LuaAPI.colorEquals), ("__tostring", LuaAPI.colorString)])
        for name in Object.typeNames {
            metatable(name, [("__index", LuaAPI.objectIndex), ("__newindex", LuaAPI.objectNewIndex),
                             ("__eq", LuaAPI.objectEquals), ("__tostring", LuaAPI.objectString), ("__len", LuaAPI.objectLength)])
        }

        // app: the active things are read through __index.
        Lua.newTable(L)
        Lua.pushFunction(L, LuaAPI.alert)
        Lua.setField(L, -2, "alert")
        Lua.newTable(L)
        Lua.newTable(L)
        Lua.pushFunction(L, LuaAPI.commandIndex)
        Lua.setField(L, -2, "__index")
        lua_setmetatable(L, -2)
        Lua.setField(L, -2, "command")
        Lua.newTable(L)
        Lua.pushFunction(L, LuaAPI.appIndex)
        Lua.setField(L, -2, "__index")
        Lua.pushFunction(L, LuaAPI.appNewIndex)
        Lua.setField(L, -2, "__newindex")
        lua_setmetatable(L, -2)
        Lua.setGlobal(L, "app")

        for (name, function) in [("Color", LuaAPI.newColor), ("Image", LuaAPI.newImage), ("Dialog", LuaAPI.newDialog)] {
            Lua.pushFunction(L, function)
            Lua.setGlobal(L, name)
        }
    }
}

/// A message from a script: an error or `app.alert`.
struct ScriptMessage: Identifiable {
    let id = UUID()
    let title: String
    let text: String
}

/// Wraps a C function's body: a thrown error becomes a Lua error. Lua errors
/// (and yields) jump over the frames above them, so they happen here, after
/// the body and everything it held are gone.
func luaCall(_ L: OpaquePointer?, _ body: @MainActor (ScriptEngine, Lua.State) throws -> Int32) -> Int32 {
    let L = L!
    let result: Int32 = MainActor.assumeIsolated {
        let engine = ScriptEngine.engine(of: L)
        do {
            return try body(engine, L)
        } catch {
            // With the script's line in front, as luaL_error does.
            luaL_where(L, 1)
            let place = Lua.string(L, -1) ?? ""
            Lua.pop(L)
            Lua.pushString(L, place + ((error as? ScriptEngine.Failure)?.message ?? "\(error)"))
        }
        return -1
    }
    if result == ScriptEngine.yieldResult { return lua_yieldk(L, 0, 0, nil) }
    return result < 0 ? lua_error(L) : result
}
