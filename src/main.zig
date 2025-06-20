const std = @import("std");
const rl = @import("raylib");
const rg = @import("raygui");
const c = @cImport({
    @cInclude("pdfgen.h");
});

const fonts = @import("fonts.zig");
const parser = @import("parser.zig");
const renderer = @import("renderer.zig");
const slides = @import("slides.zig");
const SlideShow = slides.SlideShow;

const log = std.log.scoped(.main);

const ExportController = struct {
    gpa: std.mem.Allocator,
    running: bool,
    return_to_slide_number: i32,
    current_slide_number: i32,
    num_slides: usize,
    export_dir: []const u8,

    ready_toggle: bool = false,
    exported_imgs: ?std.ArrayListUnmanaged([]const u8) = null,
    final_messagebox_message: ?[:0]const u8 = null,

    pub fn init(gpa: std.mem.Allocator, export_dir: ?[]const u8) !ExportController {
        const ex_dir = export_dir orelse ",rayslides-export";
        std.fs.cwd().makePath(ex_dir) catch |err| {
            std.process.fatal("Could not prepare export dir {s} : {any}", .{ ex_dir, err });
        };

        return .{
            .gpa = gpa,
            .running = false,
            .export_dir = try gpa.dupe(u8, ex_dir),
            .return_to_slide_number = 0,
            .current_slide_number = 0,
            .num_slides = 0,
        };
    }

    pub fn deinit(self: *ExportController) void {
        self.gpa.free(self.export_dir);
        self.clean_img_list();
        if (self.final_messagebox_message) |msg| {
            self.gpa.free(msg);
        }
    }

    fn clean_img_list(self: *ExportController) void {
        if (self.exported_imgs) |*img_list| {
            for (img_list.items) |img| {
                log.info("cleaning {s}", .{img});
                self.gpa.free(img);
            }
            img_list.deinit(self.gpa);
        }
        self.exported_imgs = null;
    }

    pub fn start(self: *ExportController, current_slide_number: i32, num_slides: usize) void {
        self.running = true;
        self.return_to_slide_number = current_slide_number;
        self.current_slide_number = 0;
        self.num_slides = num_slides;
        self.exported_imgs = std.ArrayListUnmanaged([]const u8).empty;
        self.ready_toggle = false;
    }

    /// signals if it's done
    pub fn advance(self: *ExportController) bool {
        self.current_slide_number += 1;
        if (self.current_slide_number >= self.num_slides) {
            self.running = false;
            return true;
        }
        return false;
    }

    pub fn ready(self: *ExportController) bool {
        self.ready_toggle = !self.ready_toggle;
        return !self.ready_toggle;
    }

    // PDF snapshotting
    pub fn snapshot(self: *ExportController) !void {
        if (!self.running) return;
        if (self.exported_imgs == null) return error.InvalidState;

        const img_path = try std.fmt.allocPrintZ(self.gpa, "{s}/slide-{d}.png", .{ self.export_dir, self.current_slide_number });
        defer self.gpa.free(img_path);

        try self.exported_imgs.?.append(self.gpa, try self.gpa.dupe(u8, img_path));
        var img = try rl.loadImageFromScreen();
        img.setFormat(.uncompressed_r8g8b8);
        if (!img.exportToFile(img_path)) {
            log.err("Could not export screenshot to {s}", .{img_path});
        }
    }

    // single screenshot
    pub fn screenshot(self: *ExportController, slideshow_filename: ?[]const u8) !void {
        if (slideshow_filename) |filp| {
            const img_path = try std.fmt.allocPrintZ(self.gpa, "{s}.png", .{filp});
            defer self.gpa.free(img_path);

            var img = try rl.loadImageFromScreen();
            if (!img.exportToFile(img_path)) {
                log.err("Could not export screenshot to {s}", .{img_path});
            }
            self.final_messagebox_message = try std.fmt.allocPrintZ(self.gpa, "Screenshot saved to {s}", .{img_path});
        }
    }

    pub fn to_pdf(self: *ExportController, slideshow_name: []const u8) !void {
        if (self.exported_imgs == null) return error.InvalidState;
        const pdf_name = try std.fmt.allocPrintZ(self.gpa, "{s}.pdf", .{slideshow_name});
        defer self.gpa.free(pdf_name);

        var info: c.pdf_info = .{};
        _ = try std.fmt.bufPrintZ(&info.producer, "{s}", .{"rayslides"});

        if (c.pdf_create(1920, 1080, &info)) |pdf| {
            defer c.pdf_destroy(pdf);

            for (self.exported_imgs.?.items) |img_file| {
                if (c.pdf_append_page(pdf) == null) {
                    return error.PdfAppendPage;
                }

                if (c.pdf_add_image_file(pdf, null, 0.0, 0.0, 1920.0, 1080.0, @ptrCast(img_file)) < 0) {
                    return error.PdfAddImage;
                }
            }
            if (c.pdf_save(pdf, pdf_name) < 0) {
                return error.PdfSave;
            }
        } else {
            return error.PdfCreate;
        }

        self.final_messagebox_message = try std.fmt.allocPrintZ(self.gpa, "Slideshow exported to {s}", .{pdf_name});
    }
};

const LaserPointer = struct {
    show: bool = false,
    color: rl.Color = .red,
    size: f32 = 20,
    size_index: usize = 0,
    sizes: [6]f32 = .{ 10, 20, 30, 50, 70, 100 },

    draw_state: struct {
        thick: f32 = 5.0,
        vertices: std.ArrayList(rl.Vector2),
        mousepos_prev: rl.Vector2 = .{ .x = 0, .y = 0 },
    },

    pub fn init(gpa: std.mem.Allocator) !LaserPointer {
        return .{
            .draw_state = .{
                .vertices = try std.ArrayList(rl.Vector2).initCapacity(gpa, 1000),
            },
        };
    }

    pub fn deinit(self: *LaserPointer) void {
        self.draw_state.vertices.deinit();
    }

    pub fn toggle(self: *LaserPointer) void {
        self.show = !self.show;
        if (self.show) {
            self.clearDrawing();
        }
    }

    fn clearDrawing(self: *LaserPointer) void {
        self.draw_state.vertices.shrinkRetainingCapacity(0);
    }

    pub fn draw(self: *LaserPointer) !void {
        const pos = rl.getMousePosition();
        rl.drawCircleV(pos, self.size, self.color);

        // add vertex only if mousepos has changed
        if (pos.x != self.draw_state.mousepos_prev.x or pos.y != self.draw_state.mousepos_prev.y) {
            const mouse_down = rl.isMouseButtonDown(.left);
            if (mouse_down) {
                try self.draw_state.vertices.append(pos);
            }

            // if mouse released, add sentinel value
            if (rl.isMouseButtonReleased(.left)) {
                try self.draw_state.vertices.append(.{ .x = 0, .y = 0 });
            }

            // draw vertices
            for (self.draw_state.vertices.items, 0..) |vertex, i| {
                if (i == 0) continue;

                // draw a line from A to B
                const pos_a = self.draw_state.vertices.items[i - 1];
                if (vertex.x != 0.0 and vertex.y != 0.0 and pos_a.x != 0.0 and pos_a.y != 0.0) {
                    rl.drawLineEx(pos_a, vertex, self.draw_state.thick, self.color);
                }
            }
        }
    }

    pub fn changeSize(self: *LaserPointer) void {
        self.size_index += 1;
        if (self.size_index >= self.sizes.len) {
            self.size_index = 0;
        }
        self.size = self.sizes[self.size_index];
    }
};

const Banner = struct {
    logo_texture: ?rl.Texture = null,
    showtime_seconds: f64 = banner_display_time_seconds,
    show: bool = false,

    pub const banner_display_time_seconds: f64 = 4.0;

    pub fn init() !Banner {
        const img = try rl.loadImageFromMemory(".png", @embedFile("assets/raylib_96x96.png"));
        defer rl.unloadImage(img);

        return .{
            .logo_texture = try rl.loadTextureFromImage(img),
            .show = true,
        };
    }

    pub fn reset(self: *Banner) void {
        self.showtime_seconds = rl.getTime() + banner_display_time_seconds;
        self.show = true;
    }

    pub fn render(self: *Banner) void {
        if (self.show) {
            if (rl.getTime() <= self.showtime_seconds) {
                if (self.logo_texture) |logo| {
                    const font_size: i32 = 75;
                    const text1 = "Slides, now with ";
                    const text1_width: i32 = rl.measureText(text1, font_size);
                    const text2 = "100% more ";
                    const text2_width: i32 = rl.measureText(text2, font_size);

                    const w: i32 = 1200;
                    const h: i32 = 350;
                    const l: i32 = (1920 - w) / 2;
                    const t: i32 = (1080 - h) / 2;
                    const border_thick: f32 = 5.0;
                    const border_inset: f32 = 10.0;
                    const padding: i32 = 30;
                    const logo_size: i32 = 96;
                    const font_size_rene: i32 = 30;
                    const backdrop_thick: i32 = 20;
                    const backdrop_color: rl.Color = rl.Color.alpha(rl.Color.white, 0.3);
                    const bg_color: rl.Color = rl.Color.alpha(rl.Color.ray_white, 0.97);

                    rl.drawRectangle(l - backdrop_thick, t - backdrop_thick, w + 2 * backdrop_thick, h + 2 * backdrop_thick, backdrop_color);
                    rl.drawRectangle(l, t, w, h, bg_color);

                    const border_rect: rl.Rectangle = .{
                        .x = l + border_inset,
                        .y = t + border_inset,
                        .width = w - border_inset * 2,
                        .height = h - border_inset * 2,
                    };
                    rl.drawRectangleLinesEx(border_rect, border_thick, rl.Color.sky_blue);

                    rl.drawText(text1, l + padding + border_inset, t + h - padding - font_size, font_size, rl.Color.gold);
                    rl.drawText(text2, text1_width + l + padding + @as(i32, @intFromFloat(border_inset)), t + h - padding - font_size, font_size, rl.Color.red);

                    rl.drawText("@renerocksai", l + padding + border_inset, t + padding + border_inset, font_size_rene, rl.Color.brightness(rl.Color.sky_blue, -0.2));

                    logo.draw(
                        text1_width + text2_width + l + padding + @as(i32, @intFromFloat(border_inset)),
                        t + h - padding - logo_size - 10,
                        rl.Color.white,
                    );
                }
            } else {
                self.show = false;
            }
        }
    }

    pub fn deinit(self: *Banner) void {
        if (self.logo_texture) |logo| {
            rl.unloadTexture(logo);
            self.logo_texture = null;
        }
    }
};

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

    rl.setTargetFPS(61);
    var beast_mode: bool = false;

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
    var export_controller: ExportController = try .init(gpa, null);
    defer export_controller.deinit();
    var laser_pointer: LaserPointer = try .init(gpa);
    defer laser_pointer.deinit();
    var banner: Banner = try .init();
    defer banner.deinit();

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

        if (export_controller.running) {
            if (export_controller.ready()) {
                if (export_controller.snapshot()) |_| {
                    if (export_controller.advance()) {
                        if (G.slideshow_filp) |slideshow_name| {
                            try export_controller.to_pdf(slideshow_name);
                        } else {
                            log.err("PDF-export: could not retrieve slideshow name, it's null!!!", .{});
                        }
                        G.current_slide = export_controller.return_to_slide_number;
                        export_controller.clean_img_list();
                    } else {
                        G.current_slide = export_controller.current_slide_number;
                    }
                } else |err| {
                    log.err("Error while snapshotting: {any}", .{err});
                }
            }
        }

        if (rl.isKeyPressed(.s)) {
            if (rl.isKeyDown(.left_shift) or rl.isKeyDown(.right_shift)) {
                if (export_controller.running == false) {
                    export_controller.start(G.current_slide, G.slideshow.slides.items.len);
                    G.current_slide = 0;
                }
            } else {
                if (export_controller.running == false) {
                    try export_controller.screenshot(G.slideshow_filp);
                }
            }
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

        if (export_controller.final_messagebox_message) |msg| {
            if (rg.messageBox(.{ .x = (1920 - 400) / 2, .y = 300, .width = 400, .height = 100 }, "Slideshow Export", msg, "OK") >= 0) {
                gpa.free(msg);
                export_controller.final_messagebox_message = null;
            }
        }

        if (laser_pointer.show) {
            try laser_pointer.draw();
        }

        if (banner.show) {
            banner.render();
        }

        //
        // hanlde keys
        //
        if (rl.isKeyPressed(.space) or rl.isKeyPressed(.right) or rl.isKeyPressed(.page_down)) {
            G.current_slide += 1;
            if (G.current_slide >= G.slideshow.slides.items.len) {
                G.current_slide -= 1;
            }
        }

        if (rl.isKeyPressed(.backspace) or rl.isKeyPressed(.left) or rl.isKeyPressed(.page_up)) {
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

        if (rl.isKeyPressed(.one)) {
            G.current_slide = 0;
        }

        if (rl.isKeyPressed(.zero)) {
            G.current_slide = @intCast(G.slideshow.slides.items.len - 1);
        }

        if (rl.isKeyPressed(.g)) {
            if (rl.isKeyDown(.left_shift) or rl.isKeyDown(.right_shift)) {
                G.current_slide = @intCast(G.slideshow.slides.items.len - 1);
            } else {
                G.current_slide = 0;
            }
        }

        if (rl.isKeyPressed(.b)) {
            if (rl.isKeyDown(.left_shift) or rl.isKeyDown(.right_shift)) {
                banner.reset();
            } else {
                beast_mode = !beast_mode;
                if (beast_mode) {
                    rl.setTargetFPS(0);
                } else {
                    rl.setTargetFPS(61);
                }
            }
        }

        if (rl.isKeyPressed(.l)) {
            if (rl.isKeyDown(.left_shift) or rl.isKeyDown(.right_shift)) {
                if (laser_pointer.show) {
                    laser_pointer.changeSize();
                }
            } else {
                laser_pointer.toggle();
                if (laser_pointer.show) {
                    rl.hideCursor();
                } else {
                    rl.showCursor();
                }
            }
        }

        if (rl.isKeyPressed(.c)) {
            laser_pointer.clearDrawing();
        }

        const do_reload = checkAutoReload() catch false;
        if (do_reload) {
            G.slideshow_filp_to_load = G.slideshow_filp; // signal that we need to load
        }
    }
}

fn checkAutoReload() !bool {
    if (G.slideshow_filp) |filp| {
        if (filp.len > 0) {
            if (G.hot_reload_next_time <= rl.getTime()) {
                std.log.debug("Checking for auto-reload of `{s}`", .{filp});
                G.hot_reload_next_time += G.hot_reload_interval_seconds;
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

const AppData = struct {
    allocator: std.mem.Allocator = undefined,
    slideshow_arena: std.heap.ArenaAllocator = undefined,
    slideshow_allocator: std.mem.Allocator = undefined,
    fonts: fonts.AvailableFonts = .{},
    editor_memory: []u8 = undefined,
    loaded_content: []u8 = undefined, // we will check for dirty editor against this
    last_window_size: rl.Vector2 = .{ .x = 0.0, .y = 0.0 },
    content_window_size: rl.Vector2 = .{ .x = 0.0, .y = 0.0 },
    slide_renderer: *renderer.SlideshowRenderer = undefined,
    slideshow_filp_buffer: [std.fs.max_path_bytes]u8 = undefined,
    slideshow_filp_to_load_buffer: [std.fs.max_path_bytes]u8 = undefined,
    slideshow_filp: ?[]const u8 = undefined,
    slideshow_filp_to_load: ?[]const u8 = null,
    slideshow: *SlideShow = undefined,
    current_slide: i32 = 0,
    hot_reload_next_time: f64 = 0.0,
    hot_reload_interval_seconds: f64 = 1.0,
    hot_reload_last_stat: ?std.fs.File.Stat = undefined,

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

        // parse the slideshow
        if (G.reinit()) |_| {
            // after reinit, the buffers are memset to zeros
            @memcpy(G.editor_memory[0..input.len], input);
            @memcpy(G.loaded_content[0..input.len], input);
            G.editor_memory[input.len] = 0;
            G.loaded_content[input.len] = 0;
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
