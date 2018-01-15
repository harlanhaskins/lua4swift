// swift-tools-version:4.0
import PackageDescription

let package = Package(
    name: "Lua",
    products: [
      .library(name: "Lua", targets: ["Lua"])
    ],
    dependencies: [
    ],
    targets: [
      .target(name: "Lua", dependencies: ["LuaSource"], path: "Lua",
              exclude: ["Lua/Lua.h"]),
      .target(name: "LuaSource", dependencies: [], path: "LuaSource",
              exclude: [
                "include/lua/LuaSource.h",
                "src/LuaSource.m"
              ]),
    ]
)
