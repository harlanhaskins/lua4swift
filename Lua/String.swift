import LuaSource
import Foundation

extension String: Value {
    
    public func push(_ vm: VirtualMachine) {
        lua_pushstring(vm.vm, self)
    }
    
    public func kind() -> Kind { return .string }
    
    public static func arg(_ vm: VirtualMachine, value: Value) -> String? {
        if value.kind() != .string { return "string" }
        return nil
    }
    
}
