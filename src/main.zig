const std = @import("std");
const rl = @import("raylib");
const rg = @import("raygui");

const fonts = @import("fonts.zig");
const parser = @import("parser.zig");
const renderer = @import("renderer.zig");
const slides = @import("slides.zig");
const SlideShow = slides.SlideShow;

const log = std.log.scoped(.main);

pub fn main() anyerror!void {
    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .{};
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();

    try G.init(gpa);
    defer G.deinit();

    // Initialization
    //--------------------------------------------------------------------------------------
    const screenWidth = 1920;
    const screenHeight = 1080;

    rl.initWindow(screenWidth, screenHeight, "rayslides");
    defer rl.closeWindow(); // Close window and OpenGL context

    // rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    //--------------------------------------------------------------------------------------

    // get arg
    const args = try std.process.argsAlloc(gpa);
    defer std.process.argsFree(gpa, args);
    if (args.len > 1) {
        log.debug("loading... {s}", .{args[1]});
        G.slideshow_filp_to_load = try std.fmt.bufPrint(&G.slideshow_filp_to_load_buffer, "{s}", .{args[1]});
    } else {
        std.process.fatal("No slideshow arg given!", .{});
    }
    // Main game loop
    var is_pre_rendered: bool = false;

    rl.setTargetFPS(61);
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        //----------------------------------------------------------------------------------
        // TODO: Update your variables here
        //----------------------------------------------------------------------------------
        G.content_window_size = .{ .x = 1920, .y = 1080 };
        if (G.content_window_size.x != G.last_window_size.x or G.content_window_size.y != G.last_window_size.y) {
            // window size changed
            std.log.debug("win size changed from {} to {}", .{ G.last_window_size, G.content_window_size });
            G.last_window_size = G.content_window_size;
        }

        // Draw
        //----------------------------------------------------------------------------------
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.white);

        // (re-) load slideshow
        if (G.slideshow_filp_to_load) |filp| {
            try loadSlideshow(filp);
            is_pre_rendered = false;
        }

        if (is_pre_rendered == false) {
            if (G.slideshow_filp) |slideshow_filp| {
                log.info("LOADED!!!", .{});
                log.debug("I AM GOING TO PRE-RENDER!", .{});
                G.slide_renderer.preRender(G.slideshow, slideshow_filp) catch |err| {
                    log.err("Pre-rendering failed: {any}", .{err});
                };
                log.info("PRE-RENDERED!!!!", .{});
                is_pre_rendered = true;
            }
        }

        // render slide
        // G.slide_render_width = G.internal_render_size.x - ed_anim.current_size.x;
        // try G.slide_renderer.render(G.current_slide, slideAreaTL(), slideSizeInWindow(), G.internal_render_size);
        try G.slide_renderer.render(G.current_slide, .{ .x = 0.0, .y = 0.0 }, .{ .x = 1920, .y = 1080 }, .{ .x = 1920, .y = 1080 });
        // std.log.debug("slideAreaTL: {any}, slideSizeInWindow: {any}, internal_render_size: {any}", .{ slideAreaTL(), slideSizeInWindow(), G.internal_render_size });
        rl.drawFPS(20, 20);

        if (rl.isKeyPressed(.space)) {
            G.current_slide += 1;
            if (G.current_slide >= G.slideshow.slides.items.len) {
                G.current_slide -= 1;
            }
        }

        if (rl.isKeyPressed(.backspace)) {
            G.current_slide -= 1;
            if (G.current_slide < 0) {
                G.current_slide = 0;
            }
        }

        if (rl.isKeyPressed(.f)) {
            rl.toggleFullscreen();
        }

        if (rl.isKeyPressed(.q)) {
            break;
        }

        const do_reload = checkAutoReload() catch false;
        if (do_reload) {
            G.slideshow_filp_to_load = G.slideshow_filp; // signal that we need to load
        }
    }
}

fn checkAutoReload() !bool {
    G.hot_reload_ticker += 1;
    if (G.slideshow_filp) |filp| {
        if (filp.len > 0) {
            if (G.hot_reload_ticker > G.hot_reload_interval_ticks) {
                std.log.debug("Checking for auto-reload of `{s}`", .{filp});
                G.hot_reload_ticker = 0;
                var f = try std.fs.cwd().openFile(filp, .{});
                defer f.close();
                const x = try f.stat();
                if (G.hot_reload_last_stat) |last| {
                    if (x.mtime != last.mtime) {
                        std.log.debug("RELOAD {s}", .{filp});
                        return true;
                    }
                } else {
                    G.hot_reload_last_stat = x;
                }
            }
        }
    }
    return false;
}

// .
// App State
// .
const AppState = enum {
    mainmenu,
    presenting,
    slide_overview,
};

const SaveAsReason = enum {
    none,
    quit,
    load,
    new,
    newtemplate,
};

const AppData = struct {
    allocator: std.mem.Allocator = undefined,
    slideshow_arena: std.heap.ArenaAllocator = undefined,
    slideshow_allocator: std.mem.Allocator = undefined,
    app_state: AppState = .mainmenu,
    fonts: fonts.AvailableFonts = .{},
    editor_memory: []u8 = undefined,
    loaded_content: []u8 = undefined, // we will check for dirty editor against this
    last_window_size: rl.Vector2 = .{ .x = 0.0, .y = 0.0 },
    content_window_size: rl.Vector2 = .{ .x = 0.0, .y = 0.0 },
    content_window_size_before_fullscreen: rl.Vector2 = .{ .x = 0.0, .y = 0.0 },
    internal_render_size: rl.Vector2 = .{ .x = 1920.0, .y = 1080.0 },
    slide_render_width: f32 = 1920.0,
    slide_render_height: f32 = 1080.0, // TODO: ditto: 1064
    slide_renderer: *renderer.SlideshowRenderer = undefined,
    img_tint_col: rl.Vector4 = .{ .x = 1.0, .y = 1.0, .z = 1.0, .w = 1.0 }, // No tint
    img_border_col: rl.Color = .{ .r = 0, .g = 0, .b = 0, .a = 127 },
    slideshow_filp_buffer: [std.fs.max_path_bytes]u8 = undefined,
    slideshow_filp_to_load_buffer: [std.fs.max_path_bytes]u8 = undefined,
    slideshow_filp: ?[]const u8 = undefined,
    slideshow_filp_to_load: ?[]const u8 = null,
    status_msg: [*c]const u8 = "",
    slideshow: *SlideShow = undefined,
    current_slide: i32 = 0,
    hot_reload_ticker: usize = 0,
    hot_reload_interval_ticks: usize = 1500 / 16,
    hot_reload_last_stat: ?std.fs.File.Stat = undefined,
    show_saveas: bool = true,
    show_saveas_reason: SaveAsReason = .none,
    did_post_init: bool = false,
    is_fullscreen: bool = false,
    openfiledialog_context: ?*anyopaque = null,
    saveas_dialog_context: ?*anyopaque = null,
    keyRepeat: i32 = 0,
    elementInspectorIndex: i32 = 0,
    showElementInspector: bool = false,
    autoRunTriggeredByPowerpointExport: bool = false,
    doZipIt: bool = false,
    showWindowBorder: bool = true,

    fn init(self: *AppData, gpa: std.mem.Allocator) !void {
        self.allocator = gpa;

        self.slideshow_arena = std.heap.ArenaAllocator.init(gpa);
        self.slideshow_allocator = self.slideshow_arena.allocator();

        self.fonts = try fonts.AvailableFonts.init(.{});
        self.slideshow = try SlideShow.new(self.slideshow_allocator);
        self.slide_renderer = try renderer.SlideshowRenderer.new(self.slideshow_allocator, &self.fonts);

        self.editor_memory = try self.allocator.alloc(u8, 128 * 1024);
        self.loaded_content = try self.allocator.alloc(u8, 128 * 1024);
        @memset(self.editor_memory, 0);
        @memset(self.loaded_content, 0);
    }

    fn deinit(self: *AppData) void {
        self.fonts.deinit();
        self.allocator.free(self.editor_memory);
        self.allocator.free(self.loaded_content);
        self.slideshow_arena.deinit();
    }

    fn reinit(self: *AppData) !void {
        self.deinit();
        try self.init(self.allocator);
    }
};

var G = AppData{};

var slicetocbuf: [1024]u8 = undefined;
fn sliceToC(input: []const u8) [:0]u8 {
    var input_cut = input;
    if (input.len > slicetocbuf.len) {
        input_cut = input[0 .. slicetocbuf.len - 1];
    }
    std.mem.copy(u8, slicetocbuf[0..], input_cut);
    slicetocbuf[input_cut.len] = 0;
    const xx = slicetocbuf[0 .. input_cut.len + 1];
    const yy = xx[0..input_cut.len :0];
    return yy;
}

fn loadSlideshow(filp: []const u8) !void {
    std.log.debug("LOAD {s}", .{filp});
    defer G.slideshow_filp_to_load = null;
    if (std.fs.cwd().openFile(filp, .{})) |f| {
        defer f.close();
        G.hot_reload_last_stat = try f.stat();

        const input = try f.readToEndAlloc(G.allocator, G.editor_memory.len);
        defer G.allocator.free(input);

        log.info("Read {d} bytes", .{input.len});

        if (input.len > G.editor_memory.len) {
            // setStatusMsg("Loading failed!");
            std.log.err("Loading failed: File too large ({d} > {d})", .{ input.len, G.editor_memory.len });
            return;
        }
        // setStatusMsg(sliceToC(input));

        // parse the shit
        if (G.reinit()) |_| {
            // after reinit, the buffers are memset to zeros
            @memcpy(G.editor_memory[0..input.len], input);
            @memcpy(G.loaded_content[0..input.len], input);
            G.editor_memory[input.len] = 0;
            G.loaded_content[input.len] = 0;
            G.app_state = .presenting;
            G.slideshow_filp = blk: {
                if (G.slideshow_filp) |existing| {
                    if (existing.ptr == filp.ptr) {
                        break :blk filp;
                    }
                }
                break :blk try std.fmt.bufPrint(&G.slideshow_filp_buffer, "{s}", .{filp});
            };
            std.log.debug("filp is now {s}", .{G.slideshow_filp.?});
            if (parser.constructSlidesFromBuf(G.editor_memory, G.slideshow, G.slideshow_allocator)) |pcontext| {
                // ed_anim.parser_context = pcontext;
                // now reload fonts
                if (pcontext.custom_fonts_present) {
                    std.log.debug("reloading fonts", .{});
                    // FIXME: this needs to be done after GL has been initialized
                    //        so, loadSlideshow() must not be called before
                    //        raylib's update loop
                    try G.fonts.loadCustomFonts(pcontext.fontConfig, G.slideshow_filp.?);
                    std.log.debug("reloaded fonts", .{});
                }
            } else |err| {
                std.log.err("{any}", .{err});
                // setStatusMsg("Loading failed!");
            }

            if (true) {
                std.log.info("=================================", .{});
                std.log.info("          Load Summary:", .{});
                std.log.info("=================================", .{});
                std.log.info("Constructed {d} slides:", .{G.slideshow.slides.items.len});
                for (G.slideshow.slides.items, 0..) |slide, i| {
                    std.log.info("================================================", .{});
                    std.log.info("   slide {d} pos in editor: {}", .{ i, slide.pos_in_editor });
                    if (slide.items) |items| {
                        std.log.info("   slide {d} has {d} items", .{ i, items.items.len });
                        for (items.items) |item| {
                            item.printToLog();
                        }
                    } else {
                        std.log.info("   slide {d} has 0 items", .{i});
                    }
                }
            }
        } else |err| {
            // setStatusMsg("Loading failed!");
            std.log.err("Loading failed: {any}", .{err});
        }
    } else |err| {
        // setStatusMsg("Loading failed!");
        std.log.err("Loading failed: {any}", .{err});
    }
}
