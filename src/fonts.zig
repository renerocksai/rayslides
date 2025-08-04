const std = @import("std");
const rl = @import("raylib");
const pathRelativeTo = @import("utils.zig").pathRelativeTo;

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

// this is a var because raylib wrapper demands a []u32
// The character set to load
pub var default_fontchars = [_]i32{
    // 95 standard printable ASCII chars
    32,  33,  34,  35,  36,  37,  38,  39,  40,  41,  42,  43,  44,  45,  46,
    47,  48,  49,  50,  51,  52,  53,  54,  55,  56,  57,  58,  59,  60,  61,
    62,  63,  64,  65,  66,  67,  68,  69,  70,  71,  72,  73,  74,  75,  76,
    77,  78,  79,  80,  81,  82,  83,  84,  85,  86,  87,  88,  89,  90,  91,
    92,  93,  94,  95,  96,  97,  98,  99,  100, 101, 102, 103, 104, 105, 106,
    107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121,
    122, 123, 124, 125,
    126,

    // Custom characters (German umlauts, Eszett, Euro, Bullet)
    196, // Ä
    214, // Ö
    220, // Ü
    228, // ä
    246, // ö
    252, // ü
    223, // ß
    8364, // €
    8226, // •,

    // --- Common Punctuation & Symbols ---
    8211, // – (en dash)
    8212, // — (em dash)
    8216, // ‘ (left single quote)
    8217, // ’ (right single quote)
    8220, // “ (left double quote)
    8221, // ” (right double quote)
    8230, // … (ellipsis)
    169, // © (copyright)
    174, // ® (registered trademark)
    8482, // ™ (trademark)

    // --- Mathematical & Scientific ---
    176, // ° (degree symbol)
    177, // ± (plus-minus)
    181, // µ (micro sign / mu)
    215, // × (multiplication sign)
    247, // ÷ (division sign)
    8730, // √ (square root)
    8734, // ∞ (infinity)
    8747, // ∫ (integral)
    8776, // ≈ (almost equal to)
    8800, // ≠ (not equal to)
    8804, // ≤ (less than or equal to)
    8805, // ≥ (greater than or equal to)
    916, // Δ (uppercase delta)
    960, // π (lowercase pi)
    8592, // ← (left arrow)
    8594, // → (right arrow)
    8593, // ↑ (up arrow)
    8595, // ↓ (down arrow)
};

pub const FontConfig = struct {
    pub const Opts = struct {
        fontSize: i32 = 32,
        fontChars: ?[]i32 = default_fontchars[0..],
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
        log.info("LOADING CUSTOM FONTS", .{});
        var temp_buf: [std.fs.max_path_bytes]u8 = undefined;
        if (fontConfig.normal) |fontfile| {
            rl.unloadFont(self.normal);
            const realpath = try pathRelativeTo(fontfile.ttf_filn, slideshow_filp);
            const path = try std.fmt.bufPrintZ(&temp_buf, "{s}", .{realpath});
            self.normal = try rl.loadFontEx(path, fontConfig.opts.fontSize, fontConfig.opts.fontChars);
            log.debug("Font {s} is ready: {}", .{ fontfile.ttf_filn, self.normal.isReady() });
        }

        if (fontConfig.bold) |fontfile| {
            rl.unloadFont(self.bold);
            const realpath = try pathRelativeTo(fontfile.ttf_filn, slideshow_filp);
            const path = try std.fmt.bufPrintZ(&temp_buf, "{s}", .{realpath});
            self.bold = try rl.loadFontEx(path, fontConfig.opts.fontSize, fontConfig.opts.fontChars);
        }

        if (fontConfig.italic) |fontfile| {
            rl.unloadFont(self.italic);
            const realpath = try pathRelativeTo(fontfile.ttf_filn, slideshow_filp);
            const path = try std.fmt.bufPrintZ(&temp_buf, "{s}", .{realpath});
            self.italic = try rl.loadFontEx(path, fontConfig.opts.fontSize, fontConfig.opts.fontChars);
        }

        if (fontConfig.bolditalic) |fontfile| {
            rl.unloadFont(self.bolditalic);
            const realpath = try pathRelativeTo(fontfile.ttf_filn, slideshow_filp);
            const path = try std.fmt.bufPrintZ(&temp_buf, "{s}", .{realpath});
            self.bolditalic = try rl.loadFontEx(path, fontConfig.opts.fontSize, fontConfig.opts.fontChars);
        }

        if (fontConfig.zig) |fontfile| {
            rl.unloadFont(self.zig);
            const realpath = try pathRelativeTo(fontfile.ttf_filn, slideshow_filp);
            const path = try std.fmt.bufPrintZ(&temp_buf, "{s}", .{realpath});
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
