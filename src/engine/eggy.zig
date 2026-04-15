// const sdl = @import("sdl3");
// const vk = @import("vulkan");

const std = @import("std");
const signal = @import("signal.zig");

pub const ecs = @import("eggyecs/ecs.zig");
pub const context = @import("ctx.zig");

var previous_time = 0;

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
            
            // default init all modules
            inline for (&self.modules, 0..) |*m, i| {
                m.* = modules[i]{};
            }
            
            self.runSchedule(.startup);
            
            return self;
        }
        
        pub fn deinit(self: *Self) void {
            self.runSchedule(.shutdown);
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