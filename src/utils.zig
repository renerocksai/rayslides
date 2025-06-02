const std = @import("std");

var static_buffer: [1024]u8 = undefined;

/// note that you need to dupe this if you store it somewhere
pub fn pathRelativeTo(path: []const u8, refpath: ?[]const u8) ![]const u8 {
    var absp: []const u8 = undefined;

    if (refpath) |rp| {
        const pwd = std.fs.path.dirname(rp);
        if (pwd == null) {
            absp = path;
        } else {
            absp = try std.fmt.bufPrint(&static_buffer, "{s}{c}{s}", .{ pwd.?, std.fs.path.sep, path });
        }
    } else {
        absp = path;
    }
    return absp;
}
