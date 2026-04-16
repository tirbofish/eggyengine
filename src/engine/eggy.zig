// const sdl = @import("sdl3");
// const vk = @import("vulkan");

const std = @import("std");
const signal = @import("signal.zig");

pub const ecs = @import("ecs.zig");
pub const Context = @import("ctx.zig").Context;
pub const mod = @import("mod.zig");
pub const math = @import("math.zig");

/// The fixed timestep for `fixed_update` schedules. 
const FIXED_TIMESTEP: f32 = 1.0 / 60.0;

var previous_time = 0;

fn flattenModules(comptime input: []const type) []const type {
    const count = countModules(input);
    
    const result = blk: {
        var r: [count]type = undefined;
        var idx: usize = 0;
        
        for (input) |M| {
            idx = addModule(&r, idx, M);
        }
        
        break :blk r;  // "return" the value from the block
    };
    
    return &result;  // now it's a const, so this works
}

fn addModule(result: anytype, idx: usize, comptime M: type) usize {
    var i = idx;
    
    if (@hasDecl(M, "sub_modules")) {
        for (M.sub_modules) |SubM| {
            i = addModule(result, i, SubM);
        }
    }
    
    result[i] = M;
    i += 1;
    
    return i;
}

fn countModules(comptime input: []const type) usize {
    var count: usize = 0;
    for (input) |M| {
        count += 1; // the current module counts as a module. 

        if (@hasDecl(M, "sub_modules")) {
            count += countModules(M.sub_modules); // recursively count sub_modules
        }
    }

    return count;
}

pub fn EggyApp(comptime user_modules: []const type) type {
    const modules = flattenModules(user_modules);

    comptime {
        for (modules) |M| {
            validateModule(M);
        }
    }
    
    return struct {
        const Self = @This();
        
        allocator: std.mem.Allocator,
        world: ecs.World,
        modules: std.meta.Tuple(modules),
        running: bool,
        delta_time: f32,
        fixed_accumulator: f32 = 0,
        
        pub fn init(allocator: std.mem.Allocator) Self {
            var self = Self{
                .allocator = allocator,
                .world = ecs.World.init(allocator),
                .modules = undefined,
                .running = true,
                .delta_time = 0,
            };
            
            // default init all modules
            inline for (&self.modules, 0..) |*m, i| {
                m.* = modules[i]{};
            }
            
            self.runSchedule(.pre_init);
            self.runSchedule(.init);
            self.runSchedule(.post_init);
            
            return self;
        }
        
        pub fn deinit(self: *Self) void {
            self.runSchedule(.pre_deinit);
            self.runSchedule(.deinit);
            self.runSchedule(.post_deinit);
            self.world.deinit();
        }
        
        pub fn run(self: *Self) void {
            signal.setupDefaults();
            
            var last_time = std.time.nanoTimestamp();
            var frame_count: u32 = 0;
            var fps_timer: i128 = 0;

            while (self.running and !signal.wasInterrupted()) {
                const now = std.time.nanoTimestamp();
                const delta_ns = now - last_time;
                last_time = now;
                
                self.delta_time = @as(f32, @floatFromInt(delta_ns)) / 1_000_000_000.0;
                
                frame_count += 1;
                fps_timer += delta_ns;
                if (fps_timer >= 1_000_000_000) {
                    frame_count = 0;
                    fps_timer = 0;
                }
                
                self.runSchedule(.pre_update);
                self.runSchedule(.update);
                self.runSchedule(.post_update);
                
                self.fixed_accumulator += self.delta_time;
                while (self.fixed_accumulator >= FIXED_TIMESTEP) {
                    self.runSchedule(.pre_fixed_update);
                    self.runSchedule(.fixed_update);
                    self.runSchedule(.post_fixed_update);
                    self.fixed_accumulator -= FIXED_TIMESTEP;
                }
                
                self.runSchedule(.pre_render);
                self.runSchedule(.render);
                self.runSchedule(.post_render);
            }
        }
        
        pub fn runSchedule(self: *Self, comptime schedule: ecs.Schedule) void {
            const dt = switch (schedule) {
                .pre_fixed_update, .fixed_update, .post_fixed_update => FIXED_TIMESTEP,
                else => self.delta_time,
            };
            
            var ctx = Context{
                .world = &self.world,
                .allocator = self.allocator,
                .delta_time = dt,
                .running = &self.running,
            };
            
            inline for (&self.modules, 0..) |*m, i| {
                const M = modules[i];
                if (@hasDecl(M, "schedules")) {
                    const scheds = M.schedules;
                    const schedule_name = @tagName(schedule);
                    
                    if (@hasField(@TypeOf(scheds), schedule_name)) {
                        const funcs = @field(scheds, schedule_name);
                        inline for (funcs) |func| {
                            const FnInfo = @typeInfo(@TypeOf(func)).@"fn";
                            const returns_error = FnInfo.return_type != null and 
                                @typeInfo(FnInfo.return_type.?) == .error_union;
                            
                            const result = switch (FnInfo.params.len) {
                                0 => func(),
                                1 => func(&ctx),
                                2 => func(m, &ctx),
                                else => @compileError("Schedule function must take 0, 1 (*Context), or 2 (*Self, *Context) arguments"),
                            };
                            
                            // todo: potentially just do a log or make it so debug crashes (like that of validation layers)...
                            if (returns_error) {
                                _ = result catch |err| {
                                    std.log.err("[{s}] System '{s}' failed: {}", .{
                                        schedule_name,
                                        @typeName(M),
                                        err,
                                    });
                                };
                            }
                        }
                    }
                }
            }
        }
        
        pub fn getModule(self: *Self, comptime M: type) *M {
            inline for (&self.modules, 0..) |*m, i| {
                if (modules[i] == M) return m;
            }
            @compileError("Module " ++ @typeName(M) ++ " not registered");
        }
    };
}

fn validateModule(comptime M: type) void {
    if (@typeInfo(M) != .@"struct") {
        @compileError(@typeName(M) ++ " must be a struct");
    }
}