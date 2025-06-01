const std = @import("std");
const rl = @import("raylib");

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
    _ = refpath; // FIXME: implement refpath stuff
    if (self.path2tex.contains(p)) {
        return self.path2tex.get(p);
    }

    // new image, needs to be loaded first
    var path_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const zpath = try std.fmt.bufPrintZ(&path_buffer, "{s}", .{p});
    const image = try rl.loadImage(zpath);
    defer rl.unloadImage(image);
    const texture = try rl.loadTextureFromImage(image);
    try self.path2tex.put(p, texture);
    return texture;
}

pub fn deinit(self: *Self) void {
    var it = self.path2tex.valueIterator();
    while (it.next()) |texture| {
        rl.unloadTexture(texture);
    }
    self.path2tex.deinit();
}
