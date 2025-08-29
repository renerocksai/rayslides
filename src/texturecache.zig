const std = @import("std");
const rl = @import("raylib");
const pathRelativeTo = @import("utils.zig").pathRelativeTo;

allocator: std.mem.Allocator,
path2tex: std.StringHashMap(rl.Texture2D),

const Self = @This();

pub fn init(alloc: std.mem.Allocator) Self {
    return .{
        .allocator = alloc,
        .path2tex = std.StringHashMap(rl.Texture2D).init(alloc),
    };
}

pub fn getImageTexture(self: *Self, p: []const u8, refpath: ?[]const u8) !?rl.Texture2D {
    const realpath = try pathRelativeTo(p, refpath);
    if (self.path2tex.contains(realpath)) {
        return self.path2tex.get(realpath);
    }

    // new image, needs to be loaded first
    var path_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const zpath = try std.fmt.bufPrintZ(&path_buffer, "{s}", .{realpath});
    const image = try rl.loadImage(zpath);
    defer rl.unloadImage(image);
    const texture = try rl.loadTextureFromImage(image);
    try self.path2tex.put(try self.allocator.dupe(u8, realpath), texture);
    return texture;
}

pub fn deinit(self: *Self) void {
    var it = self.path2tex.iterator();
    while (it.next()) |entry| {
        const texture = entry.value_ptr.*;
        const path = entry.key_ptr.*;
        rl.unloadTexture(texture);
        self.allocator.free(path);
    }
    self.path2tex.deinit(self.allocator);
}
