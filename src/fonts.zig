const std = @import("std");
const rl = @import("raylib");
const relpathToAbspath = @import("utils.zig").relpathToAbspath;

const log = std.log.scoped(.fonts);

pub const FontStyle = enum {
    normal,
    bold,
    italic,
    bolditalic,
    zig,
};

pub const FontLoadDesc = struct {
    ttf_filn: []const u8,
};

pub const FontConfig = struct {
    pub const Opts = struct {
        fontSize: i32 = 32,
        fontChars: ?[]i32 = null,
    };
    opts: Opts,
    gui_font_size: ?i32 = null,
    normal: ?FontLoadDesc = null,
    bold: ?FontLoadDesc = null,
    italic: ?FontLoadDesc = null,
    bolditalic: ?FontLoadDesc = null,
    zig: ?FontLoadDesc = null,
};

// rl.loadFontFromMemory(".ttf", fileData: ?[]const u8, fontSize: i32, null);
// rl.TextureFilter.bilinear

const fontdata_normal = @embedFile("assets/Calibri Light.ttf");
const fontdata_bold = @embedFile("assets/Calibri Regular.ttf"); // Calibri is the bold version of Calibri Light for us
const fontdata_italic = @embedFile("assets/Calibri Light Italic.ttf");
const fontdata_bolditalic = @embedFile("assets/Calibri Italic.ttf"); // Calibri is the bold version of Calibri Light for us
const fontdata_zig = @embedFile("assets/press-start-2p.ttf");

// gui font = try rl.getDefaultFont()

pub const AvailableFonts = struct {
    normal: rl.Font = undefined,
    bold: rl.Font = undefined,
    italic: rl.Font = undefined,
    bolditalic: rl.Font = undefined,
    zig: rl.Font = undefined,

    pub fn init(opts: FontConfig.Opts) !AvailableFonts {
        const ret: AvailableFonts = .{
            .normal = try rl.loadFontFromMemory(".ttf", fontdata_normal, opts.fontSize, opts.fontChars),
            .bold = try rl.loadFontFromMemory(".ttf", fontdata_bold, opts.fontSize, opts.fontChars),
            .italic = try rl.loadFontFromMemory(".ttf", fontdata_italic, opts.fontSize, opts.fontChars),
            .bolditalic = try rl.loadFontFromMemory(".ttf", fontdata_bolditalic, opts.fontSize, opts.fontChars),
            .zig = try rl.loadFontFromMemory(".ttf", fontdata_zig, opts.fontSize, opts.fontChars),
        };

        return ret;
    }

    pub fn loadCustomFonts(self: *AvailableFonts, fontConfig: FontConfig, slideshow_filp: []const u8) !void {
        _ = slideshow_filp; // FIXME: relpath shit
        //
        log.info("LOADING CUSTOM FONTS", .{});
        var temp_buf: [std.fs.max_path_bytes]u8 = undefined;
        if (fontConfig.normal) |fontfile| {
            rl.unloadFont(self.normal);
            const path = try std.fmt.bufPrintZ(&temp_buf, "{s}", .{fontfile.ttf_filn});
            self.normal = try rl.loadFontEx(path, fontConfig.opts.fontSize, fontConfig.opts.fontChars);
            log.debug("Font {s} is ready: {}", .{ fontfile.ttf_filn, self.normal.isReady() });
        }

        if (fontConfig.bold) |fontfile| {
            rl.unloadFont(self.bold);
            const path = try std.fmt.bufPrintZ(&temp_buf, "{s}", .{fontfile.ttf_filn});
            self.bold = try rl.loadFontEx(path, fontConfig.opts.fontSize, fontConfig.opts.fontChars);
        }

        if (fontConfig.italic) |fontfile| {
            rl.unloadFont(self.italic);
            const path = try std.fmt.bufPrintZ(&temp_buf, "{s}", .{fontfile.ttf_filn});
            self.italic = try rl.loadFontEx(path, fontConfig.opts.fontSize, fontConfig.opts.fontChars);
        }

        if (fontConfig.bolditalic) |fontfile| {
            rl.unloadFont(self.bolditalic);
            const path = try std.fmt.bufPrintZ(&temp_buf, "{s}", .{fontfile.ttf_filn});
            self.bolditalic = try rl.loadFontEx(path, fontConfig.opts.fontSize, fontConfig.opts.fontChars);
        }

        if (fontConfig.zig) |fontfile| {
            rl.unloadFont(self.zig);
            const path = try std.fmt.bufPrintZ(&temp_buf, "{s}", .{fontfile.ttf_filn});
            self.zig = try rl.loadFontEx(path, fontConfig.opts.fontSize, fontConfig.opts.fontChars);
        }
        rl.setTextureFilter(self.normal.texture, .bilinear);
        rl.setTextureFilter(self.bold.texture, .bilinear);
        rl.setTextureFilter(self.italic.texture, .bilinear);
        rl.setTextureFilter(self.bolditalic.texture, .bilinear);
        rl.setTextureFilter(self.zig.texture, .bilinear);
    }

    pub fn deinit(self: *AvailableFonts) void {
        rl.unloadFont(self.normal);
        rl.unloadFont(self.bold);
        rl.unloadFont(self.italic);
        rl.unloadFont(self.bolditalic);
        rl.unloadFont(self.zig);
    }
};
