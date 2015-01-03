import Foundation
import Cocoa

internal let RegistryIndex = Int(SDegutisLuaRegistryIndex)
private let GlobalsTable = Int(LUA_RIDX_GLOBALS)

public enum MaybeFunction {
    case Value(Function)
    case Error(String)
}

public typealias ErrorHandler = (String) -> Void

public class VirtualMachine {
    
    internal let vm = luaL_newstate()
    internal var storedSwiftValues = [UserdataPointer : Userdata]()
    
    public var errorHandler: ErrorHandler? = { println("error: \($0)") }
    
    public init(openLibs: Bool = true) {
        if openLibs { luaL_openlibs(vm) }
    }
    
    deinit {
        println("lua state is dead.")
        lua_close(vm)
    }
    
    internal func value(pos: Int) -> Value? {
        moveToStackTop(pos)
        var v: Value?
        switch lua_type(vm, -1) {
        case LUA_TSTRING: v = String(self)
        case LUA_TNUMBER: v = Double(self)
        case LUA_TBOOLEAN: v = Bool(self)
        case LUA_TFUNCTION: v = Function(self)
        case LUA_TTABLE: v = Table(self)
        case LUA_TUSERDATA: v = Userdata(self)
        case LUA_TLIGHTUSERDATA: v = LightUserdata(self)
        case LUA_TTHREAD: v = Thread(self)
        case LUA_TNIL: v = Nil()
        default: break
        }
        pop()
        return v
    }
    
    public func globalTable() -> Table {
        rawGet(tablePosition: RegistryIndex, index: GlobalsTable)
        return value(-1) as Table
    }
    
    public func registryTable() -> Table {
        pushFromStack(RegistryIndex)
        return value(-1) as Table
    }
    
    public func createFunction(body: String) -> MaybeFunction {
        if luaL_loadstring(vm, (body as NSString).UTF8String) == LUA_OK {
            return .Value(Function(self))
        }
        else {
            return .Error(popError())
        }
    }
    
    public func createTable(sequenceCapacity: Int = 0, keyCapacity: Int = 0) -> Table {
        lua_createtable(vm, Int32(sequenceCapacity), Int32(keyCapacity))
        return Table(self)
    }
    
    internal func popError() -> String {
        let err = String(self)
        if let fn = errorHandler { fn(err) }
        return err
    }
    
    public func createUserdata<T: CustomType>(o: T) -> Userdata {
        // Note: we just alloc 1 byte cuz malloc prolly needs > 0 but we dun use it
        
        let ptr = lua_newuserdata(vm, 1) // also pushes ptr onto stack
        let ud = Userdata(self) // this pops ptr off stack
        setMetatable(T.metatableName())
        storedSwiftValues[ptr] = ud
        return ud
    }
    
    public func createFunction(fn: SwiftFunction, upvalues: Int = 0) -> Function {
        let f: @objc_block (COpaquePointer) -> Int32 = { [weak self] _ in
            if self == nil { return 0 }
            
            var args = [Value]()
            for _ in 0 ..< self!.stackSize() {
                args.append(self!.value(1)!)
            }
            
            switch fn(args) {
            case .Nothing:
                return 0
            case let .Value(value):
                if let v = value {
                    v.push(self!)
                }
                else {
                    Nil().push(self!)
                }
                return 1
            case let .Values(values):
                for value in values {
                    value.push(self!)
                }
                return Int32(values.count)
            case let .Error(error):
                println("pushing error: \(error)")
                error.push(self!)
                lua_error(self!.vm)
                return 0 // uhh, we don't actually get here
            }
        }
        let block: AnyObject = unsafeBitCast(f, AnyObject.self)
        let imp = imp_implementationWithBlock(block)
        let fp = CFunctionPointer<(COpaquePointer) -> Int32>(imp)
        lua_pushcclosure(vm, fp, Int32(upvalues))
        let function = Function(self)
        pop()
        return function
    }
    
//    func argError(expectedType: String, argPosition: Int) -> ReturnValue {
//        luaL_typeerror(vm, Int32(argPosition), (expectedType as NSString).UTF8String)
//        return .Nothing
//        // TODO: return .Error instead
//    }
//    
//    public func pushMethod(name: String, _ types: [TypeChecker], _ fn: Function, tablePosition: Int = -1) {
//        pushString(name)
//        pushFunction { [weak self] in
//            if self == nil { return .Nothing }
//            for (i, (nameFn, testFn)) in enumerate(types) {
//                if !testFn(self!, i+1) {
//                    return self!.argError(nameFn, argPosition: i+1)
//                }
//            }
//            
//            return fn()
//        }
//        setTable(tablePosition - 2)
//    }
    
//    public func insert(position: Int) {
//        rotate(position, n: 1)
//    }
//    
//    // custom types
//    
////    func getUserdataPointer(position: Int) -> UserdataPointer? {
////        if kind(position) != .Userdata { return nil }
////        return lua_touserdata(vm, Int32(position))
////    }
////    
////    func pushUserdataBox<T: CustomType>(ud: UserdataBox<T>) -> UserdataPointer {
////        let ptr = lua_newuserdata(vm, 1)
////        setMetatable(T.metatableName())
////        storedSwiftValues[ptr] = ud
////        return ptr
////    }
////    
////    func getUserdata<T: CustomType>(position: Int) -> UserdataBox<T>? {
////        if let ptr = getUserdataPointer(position) {
////            return storedSwiftValues[ptr]! as? UserdataBox<T>
////        }
////        return nil
////    }
    
    public func pushCustomType<T: CustomType>(t: T.Type) -> Table {
        
        let lib = createTable()
        
        let registry = registryTable()
        registry[T.metatableName()] = lib
        
        setMetatable(lib, metaTable: lib)
        
        lib["__index"] = lib
        lib["__name"] = T.metatableName()  // TODO: seems broken maybe?
        
        for (name, var kinds, fn) in t.instanceMethods() {
            kinds.insert(Userdata.self, atIndex: 0)
            let f: SwiftFunction = { [weak self] (var args: [Value]) in
                if self == nil { return .Nothing }
                
                let this = args[0] as Userdata
                
                
                
                
                let o: UserdataBox<T> = self!.getUserdata(1)!
                self!.remove(1)
                return fn(o.object)(self!)
            }
//            pushMethod(name, kinds, f)
        }
        
//        for (name, kinds, fn) in t.classMethods() {
//            pushMethod(name, kinds, { [weak self] in
//                if self == nil { return .Nothing }
//                return fn(self!)
//            })
//        }
//        
//        var metaMethods = MetaMethods<T>()
//        T.setMetaMethods(&metaMethods)
//        
//        let gc = metaMethods.gc
//        pushMethod("__gc", [UserdataBox<T>.arg()]) { [weak self] in
//            println("called!")
//            // if self == nil { return .Nothing }
//            let o: UserdataBox<T> = self!.getUserdata(1)!
//            gc?(o.object, self!)
//            self!.storedSwiftValues[self!.getUserdataPointer(1)!] = nil
//            return .Values([])
//        }
//        
//        if let eq = metaMethods.eq {
//            pushMethod("__eq", [UserdataBox<T>.arg(), UserdataBox<T>.arg()]) { [weak self] in
//                if self == nil { return .Nothing }
//                let a: UserdataBox<T> = self!.getUserdata(1)!
//                let b: UserdataBox<T> = self!.getUserdata(2)!
//                return .Values([eq(a.object, b.object)])
//            }
//        }
        
        return lib
        
    }
    
    // stack
    
    internal func moveToStackTop(var position: Int) {
        if position == -1 || position == stackSize() { return }
        position = absolutePosition(position)
        pushFromStack(position)
        remove(position)
    }
    
    internal func setMetatable(thing: Value, metaTable: Value) {
        thing.push(self)
        metaTable.push(self)
        lua_setmetatable(vm, -2)
        pop() // thing
    }
    
    internal func setMetatable(metatableName: String) { luaL_setmetatable(vm, (metatableName as NSString).UTF8String) }
    internal func ref(position: Int) -> Int { return Int(luaL_ref(vm, Int32(position))) }
    internal func unref(table: Int, _ position: Int) { luaL_unref(vm, Int32(table), Int32(position)) }
    internal func absolutePosition(position: Int) -> Int { return Int(lua_absindex(vm, Int32(position))) }
    internal func rawGet(#tablePosition: Int, index: Int) { lua_rawgeti(vm, Int32(tablePosition), lua_Integer(index)) }
    
    internal func pushFromStack(position: Int) {
        lua_pushvalue(vm, Int32(position))
    }
    
    internal func pop(_ n: Int = 1) {
        lua_settop(vm, -Int32(n)-1)
    }
    
    internal func rotate(position: Int, n: Int) {
        lua_rotate(vm, Int32(position), Int32(n))
    }
    
    internal func remove(position: Int) {
        rotate(position, n: -1)
        pop(1)
    }
    
    internal func stackSize() -> Int {
        return Int(lua_gettop(vm))
    }
    
}
