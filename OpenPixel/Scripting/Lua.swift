import Foundation

/// The parts of Lua's C API that are macros, which Swift can't import, and a
/// few readers that fit how the script engine uses the stack.
enum Lua {
    typealias State = OpaquePointer

    /// LUA_REGISTRYINDEX (-LUAI_MAXSTACK - 1000).
    static let registryIndex: Int32 = -1_001_000
    /// LUA_MASKCOUNT.
    static let maskCount: Int32 = 1 << 3

    static func upvalueIndex(_ i: Int32) -> Int32 { registryIndex - i }

    static func pop(_ L: State, _ n: Int32 = 1) { lua_settop(L, -n - 1) }

    static func newTable(_ L: State) { lua_createtable(L, 0, 0) }

    static func isNoneOrNil(_ L: State, _ index: Int32) -> Bool { lua_type(L, index) <= LUA_TNIL }

    static func type(_ L: State, _ index: Int32) -> Int32 { lua_type(L, index) }

    static func pushString(_ L: State, _ string: String) {
        _ = string.withCString { lua_pushstring(L, $0) }
    }

    static func pushFunction(_ L: State, _ function: lua_CFunction) { lua_pushcclosure(L, function, 0) }

    static func setField(_ L: State, _ index: Int32, _ key: String) {
        key.withCString { lua_setfield(L, index, $0) }
    }

    @discardableResult
    static func getField(_ L: State, _ index: Int32, _ key: String) -> Int32 {
        key.withCString { lua_getfield(L, index, $0) }
    }

    static func setGlobal(_ L: State, _ name: String) { name.withCString { lua_setglobal(L, $0) } }

    @discardableResult
    static func getGlobal(_ L: State, _ name: String) -> Int32 { name.withCString { lua_getglobal(L, $0) } }

    /// Sets the metatable registered as `name` on the value at the top.
    static func setMetatable(_ L: State, _ name: String) {
        getField(L, registryIndex, name)
        lua_setmetatable(L, -2)
    }

    static func string(_ L: State, _ index: Int32) -> String? {
        guard lua_type(L, index) == LUA_TSTRING || lua_type(L, index) == LUA_TNUMBER else { return nil }
        var length = 0
        guard let chars = lua_tolstring(L, index, &length) else { return nil }
        return String(decoding: UnsafeRawBufferPointer(start: chars, count: length), as: UTF8.self)
    }

    static func number(_ L: State, _ index: Int32) -> Double? {
        var ok: Int32 = 0
        let value = lua_tonumberx(L, index, &ok)
        return ok != 0 ? value : nil
    }

    static func bool(_ L: State, _ index: Int32) -> Bool { lua_toboolean(L, index) != 0 }

    /// Calls the function below `arguments` values, catching errors: nil on
    /// success, or the error message.
    static func protectedCall(_ L: State, arguments: Int32, results: Int32) -> String? {
        guard lua_pcallk(L, arguments, results, 0, 0, nil) != LUA_OK else { return nil }
        defer { pop(L) }
        return string(L, -1) ?? "error"
    }
}
