# teenygltf

a zig version of the [tinygltf_v3](https://github.com/syoyo/tinygltf) library. 

to use this with the zig build system, import as so:
```bash
zig fetch --save 
```

then in `build.zig`:
```zig
const teenygltf = b.dependency("teenygltf", .{
    .target = target,
    .optimize = optimize,
});

exe.root_module.addImport("teenygltf", teenygltf.module("teenygltf"));
```

and in source:
```zig
const teenygltf = @import("teenygltf");
```