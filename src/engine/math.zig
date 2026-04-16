//! eggy math types


pub fn Vector2(comptime T: type) type {
    return struct {
        x: T,
        y: T,

        const Self = @This();

        pub fn add(self: Self, other: Self) Self {
            return .{ 
                .x = self.x + other.x, 
                .y = self.y + other.y,
            };
        }
        
        pub fn scale(self: Self, scalar: T) Self {
            return .{
                .x = self.x * scalar,
                .y = self.y * scalar,
            };
        }
    };
}