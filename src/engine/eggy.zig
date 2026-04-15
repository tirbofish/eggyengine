// const sdl = @import("sdl3");
// const vk = @import("vulkan");

const std = @import("std");
pub const ecs = @import("eggyecs/ecs.zig");
pub const context = @import("ctx.zig");

pub fn EggyApp(comptime modules: []const type) type {
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
        
        pub fn init(allocator: std.mem.Allocator) Self {
            var self = Self{
                .allocator = allocator,
                .world = ecs.World.init(allocator),
                .modules = undefined,
                .running = true,
                .delta_time = 0,
            };
            
            // Default-initialize all modules
            inline for (&self.modules, 0..) |*m, i| {
                m.* = modules[i]{};
            }
            
            // Run startup schedule
            self.runSchedule(.startup);
            
            return self;
        }
        
        pub fn deinit(self: *Self) void {
            self.runSchedule(.shutdown);
            self.world.deinit();
        }
        
        pub fn run(self: *Self) void {
            while (self.running) {
                self.delta_time = 1.0 / 60.0; // TODO: real delta time
                self.runSchedule(.update);
                self.runSchedule(.render);
            }
        }
        
        pub fn runSchedule(self: *Self, comptime schedule: ecs.Schedule) void {
            var ctx = context.Context{
                .world = &self.world,
                .allocator = self.allocator,
                .delta_time = self.delta_time,
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
                            func(m, &ctx);
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