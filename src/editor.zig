const std = @import("std");

const raw = @import("Raw.zig");

const TermSize = @import("TermSize.zig");

const Mode = @import("mode.zig").Mode;

const EscapeSequence = @import("escape_seq.zig").EscapeSequence;
const Cursor = EscapeSequence.Cursor;
const Screen = EscapeSequence.Screen;
const Line = EscapeSequence.Line;
const Color = EscapeSequence.Color;

const Visual = @import("Visual.zig");

const PasteBuffer = @import("PasteBuffer.zig").PasteBuffer;

/// provide it with a writertype for example @TypeOf(std.io.getStdOut().writer())
pub fn Editor(comptime WriterType: type) type {
    return struct {
        allocator: std.mem.Allocator,
        mode: Mode,
        lines: std.ArrayList(std.ArrayList(u8)),
        cursor_row: usize,
        cursor_col: usize,
        filename: ?[]const u8,
        modified: bool,
        status_message: [256]u8, // very bottom line of the screen
        status_len: usize,
        row_offset: usize, // offsets are used for scroll and draw
        col_offset: usize,
        screen_rows: usize,
        screen_cols: usize,
        writer: WriterType,
        leader: ?u8,
        exist: bool,
        visual_mode: Visual.Mode,
        visual_anchor_row: usize, //anchors indicate starting positions of visual mode
        visual_anchor_col: usize,
        paste_buffer: PasteBuffer,

        const Self = @This();

        pub fn init(allocator: std.mem.Allocator, writer: WriterType) !Self {
            var lines = std.ArrayList(std.ArrayList(u8)).init(allocator);
            try lines.append(std.ArrayList(u8).init(allocator)); // init row 1

            const term_size = try TermSize.getTerminalSize();

            const paste_buffer = PasteBuffer.init(allocator);

            return Self{
                .allocator = allocator,
                .mode = .normal,
                .lines = lines,
                .cursor_row = 0,
                .cursor_col = 0,
                .filename = null,
                .modified = false,
                .status_message = undefined,
                .status_len = 0,
                .row_offset = 0,
                .col_offset = 0,
                .screen_rows = if (term_size.rows >= 2) term_size.rows - 2 else 1, // reserve 2 rows for status
                .screen_cols = term_size.cols,
                .writer = writer,
                .leader = ' ',
                .exist = true,

                .visual_mode = .none,
                .visual_anchor_col = 0,
                .visual_anchor_row = 0,
                .paste_buffer = paste_buffer,
            };
        }

        pub fn deinit(self: *Self) void {
            for (self.lines.items) |*line| {
                line.deinit();
            }
            self.lines.deinit();
            if (self.filename) |filename| {
                self.allocator.free(filename);
            }
            self.paste_buffer.deinit();
        }

        pub fn EnterEditor(self: *Self) !void {
            try self.writer.print("{s}", .{Screen(.enter_alt).toEscape()});
        }

        pub fn exitEditor(self: *Self) !void {
            try self.writer.print("{s}", .{Cursor(.show).toEscape()});
            try self.writer.print("{s}", .{Screen(.exit_alt).toEscape()});
            try raw.disableRawMode();
        }

        pub fn updateScreenSize(self: *Self) !void {
            const term_size = try TermSize.getTerminalSize();
            self.screen_rows = if (term_size.rows >= 2) term_size.rows - 2 else 1;
            self.screen_cols = term_size.cols;
        }

        pub fn setStatusMessage(self: *Self, message: []const u8) void {
            const len = @min(message.len, self.status_message.len - 1);
            @memcpy(self.status_message[0..len], message[0..len]);
            self.status_len = len;
        }

        pub fn loadFile(self: *Self, filename: []const u8) !void {
            const file = std.fs.cwd().openFile(filename, .{}) catch |err| switch (err) {
                error.FileNotFound => {
                    self.setStatusMessage("New file");
                    if (self.filename) |old_name| {
                        self.allocator.free(old_name);
                    }
                    self.filename = try self.allocator.dupe(u8, filename);
                    return;
                },
                else => return err,
            };
            defer file.close();

            for (self.lines.items) |*line| {
                line.deinit();
            }
            self.lines.clearAndFree();

            // const content = try file.readToEndAlloc(self.allocator, 1024 * 1024); // 1MB max
            const file_size = try file.stat();
            const content = try file.readToEndAlloc(self.allocator, file_size.size);
            defer self.allocator.free(content);

            var lines = std.mem.splitAny(u8, content, "\n");
            while (lines.next()) |line| {
                var new_line = std.ArrayList(u8).init(self.allocator);
                try new_line.appendSlice(line);
                try self.lines.append(new_line);
            }

            if (self.lines.items.len == 0) {
                try self.lines.append(std.ArrayList(u8).init(self.allocator));
            }

            if (self.filename) |old_name| {
                self.allocator.free(old_name);
            }
            self.filename = try self.allocator.dupe(u8, filename);
            self.modified = false;

            var msg_buf: [512]u8 = undefined;
            const msg = try std.fmt.bufPrint(msg_buf[0..], "Loaded {s} ({d} lines)", .{ filename, self.lines.items.len });
            self.setStatusMessage(msg);
        }

        pub fn saveFile(self: *Self) !void {
            const filename = self.filename orelse {
                return error.NoFilenameProvided;
            };

            var has_valid_chars = false;
            for (filename) |c| {
                if (c != ' ' and c != '\t' and c != '\n' and c != '\r') {
                    has_valid_chars = true;
                    break;
                }
            }

            if (!has_valid_chars) {
                return error.NotValidFileName;
            }

            const file = try std.fs.cwd().createFile(filename, .{});
            defer file.close();

            for (self.lines.items, 0..) |line, i| {
                try file.writeAll(line.items);
                if (i < self.lines.items.len - 1) {
                    try file.writeAll("\n");
                }
            }

            self.modified = false;

            var msg_buf: [512]u8 = undefined;
            const msg = try std.fmt.bufPrint(msg_buf[0..], "Saved {s} ({d} lines)", .{ filename, self.lines.items.len });
            self.setStatusMessage(msg);
        }

        pub fn insertChar(self: *Self, c: u8) !void {
            if (self.cursor_row >= self.lines.items.len) return;

            var line = &self.lines.items[self.cursor_row];
            if (self.cursor_col > line.items.len) {
                self.cursor_col = line.items.len;
            }

            try line.insert(self.cursor_col, c);
            self.cursor_col += 1;
            self.modified = true;
        }

        pub fn deleteChar(self: *Self, backward: bool) !void {
            if (self.cursor_row >= self.lines.items.len) return;
            var line = &self.lines.items[self.cursor_row];
            if (backward) {
                // delete character behind cursor
                if (self.cursor_col > 0 and self.cursor_col <= line.items.len) {
                    const deleted_char = line.items[self.cursor_col - 1];
                    try self.paste_buffer.storeChar(deleted_char);
                    _ = line.orderedRemove(self.cursor_col - 1);
                    self.cursor_col -= 1;
                    self.modified = true;
                } else {
                    self.modified = false;
                    return;
                }
            } else {
                // delete character in front of/under cursor
                if (self.cursor_col < line.items.len) {
                    const deleted_char = line.items[self.cursor_col];
                    try self.paste_buffer.storeChar(deleted_char);
                    _ = line.orderedRemove(self.cursor_col);
                    self.modified = true;
                } else {
                    self.modified = false;
                    return;
                }
            }
        }

        pub fn deleteLine(self: *Self) !void {
            if (self.lines.items.len == 0) return;

            if (self.cursor_row >= self.lines.items.len) return;

            const line_to_store = [_]std.ArrayList(u8){self.lines.items[self.cursor_row]};
            try self.paste_buffer.storeLines(&line_to_store, true); // true = line-wise

            var line_to_delete = self.lines.orderedRemove(self.cursor_row);
            line_to_delete.deinit();

            if (self.lines.items.len == 0) {
                try self.lines.append(std.ArrayList(u8).init(self.allocator));
                self.cursor_row = 0;
                self.cursor_col = 0;
            } else if (self.cursor_row >= self.lines.items.len) {
                self.cursor_row = self.lines.items.len - 1;
                self.cursor_col = 0;
            } else {
                self.cursor_col = 0;
            }
            self.modified = true;
        }

        pub fn insertNewLine(self: *Self) !void {
            if (self.cursor_row >= self.lines.items.len) return;

            var current_line = &self.lines.items[self.cursor_row];
            var new_line = std.ArrayList(u8).init(self.allocator);

            if (self.cursor_col < current_line.items.len) {
                try new_line.appendSlice(current_line.items[self.cursor_col..]);
                current_line.shrinkRetainingCapacity(self.cursor_col);
            }

            try self.lines.insert(self.cursor_row + 1, new_line);
            self.cursor_row += 1;
            self.cursor_col = 0;
            self.modified = true;
        }

        pub fn scroll(self: *Self) void {
            if (self.cursor_row < self.row_offset) {
                self.row_offset = self.cursor_row;
            }
            if (self.cursor_row >= self.row_offset + self.screen_rows) {
                self.row_offset = self.cursor_row - self.screen_rows + 1;
            }

            if (self.cursor_col < self.col_offset) {
                self.col_offset = self.cursor_col;
            }
            if (self.cursor_col >= self.col_offset + self.screen_cols) {
                self.col_offset = self.cursor_col - self.screen_cols + 1;
            }
        }

        pub fn moveCursor(self: *Self, direction: u8) void {
            switch (direction) {
                'h' => {
                    if (self.cursor_col > 0) {
                        self.cursor_col -= 1;
                    } else if (self.cursor_row > 0) {
                        self.cursor_row -= 1;
                        if (self.cursor_row < self.lines.items.len) {
                            self.cursor_col = self.lines.items[self.cursor_row].items.len;
                        }
                    }
                },
                'j' => {
                    if (self.cursor_row < self.lines.items.len - 1) {
                        self.cursor_row += 1;
                        const line_len = self.lines.items[self.cursor_row].items.len;
                        if (self.cursor_col > line_len) {
                            self.cursor_col = line_len;
                        }
                    }
                },
                'k' => {
                    if (self.cursor_row > 0) {
                        self.cursor_row -= 1;
                        const line_len = self.lines.items[self.cursor_row].items.len;
                        if (self.cursor_col > line_len) {
                            self.cursor_col = line_len;
                        }
                    }
                },
                'l' => {
                    if (self.cursor_row < self.lines.items.len) {
                        const line_len = self.lines.items[self.cursor_row].items.len;
                        if (self.cursor_col < line_len) {
                            self.cursor_col += 1;
                        } else if (self.cursor_row < self.lines.items.len - 1) {
                            self.cursor_row += 1;
                            self.cursor_col = 0;
                        }
                    }
                },
                else => {},
            }
        }

        pub fn draw(self: *Self) !void {
            try self.updateScreenSize();
            self.scroll();

            try self.writer.print("{s}{s}", .{ Screen(.clear).toEscape(), Cursor(.pos_top).toEscape() });

            var y: usize = 0;
            while (y < self.screen_rows) : (y += 1) {
                const file_row = y + self.row_offset;

                if (file_row >= self.lines.items.len) {
                    try self.writer.print("{s}~", .{Color(.fg_cyan_bold).toEscape()});
                } else {
                    const line = self.lines.items[file_row];
                    var x: usize = 0;
                    var rendered_chars: usize = 0;

                    while (x < line.items.len and x < self.col_offset) : (x += 1) {}

                    while (x < line.items.len and rendered_chars < self.screen_cols) {
                        const c = line.items[x];

                        const should_highlight = self.isCharacterSelected(file_row, x);
                        if (should_highlight) {
                            try self.writer.print("{s}", .{Color(.bg_black_bold).toEscape()});
                        }

                        if (c == '\t') {
                            var tab_spaces: usize = 4 - (rendered_chars % 4);
                            while (tab_spaces > 0 and rendered_chars < self.screen_cols) {
                                try self.writer.print(" ", .{});
                                rendered_chars += 1;
                                tab_spaces -= 1;
                            }
                        } else if (c >= 32 and c < 127) {
                            try self.writer.print("{c}", .{c});
                            rendered_chars += 1;
                        } else {
                            try self.writer.print(".", .{});
                            rendered_chars += 1;
                        }

                        if (should_highlight) {
                            try self.writer.print("{s}", .{Color(.reset).toEscape()});
                        }

                        x += 1;
                    }
                }

                try self.writer.print("{s}", .{Line(.clear_remaining).toEscape()});
                if (y < self.screen_rows - 1) {
                    try self.writer.print("\r\n", .{});
                }
            }

            // status line at second to last row
            try self.writer.print("\x1b[{d};1H", .{self.screen_rows + 1});
            try self.writer.print("{s}{s}", .{ Color(.bg_yellow_bold).toEscape(), Color(.fg_black_bold).toEscape() });

            const mode_str = switch (self.mode) {
                .normal => "NORMAL",
                .insert => "INSERT",
                .command => "COMMAND",
                .leader => "Leader",
                .delete => "Delete",
                .visual => "Visual",
                else => "UNDEFINED_MODE",
            };

            const filename = self.filename orelse "[No Name]";
            const modified_indicator = if (self.modified) " [+]" else "";

            try self.writer.print(" {s} | {s}{s} | {d}%->{d} | {d},{d} ", .{
                mode_str,
                filename,
                modified_indicator,
                @as(usize, @intFromFloat((@as(f32, @floatFromInt(self.cursor_row + 1)) / @as(f32, @floatFromInt(self.lines.items.len))) * 100)),
                self.lines.items.len,
                self.cursor_row + 1,
                self.cursor_col + 1,
            });

            try self.writer.print("{s}{s}", .{ Line(.clear_remaining).toEscape(), Color(.reset).toEscape() });

            // message line at bottom
            try self.writer.print("\x1b[{d};1H", .{self.screen_rows + 2});
            if (self.status_len > 0) {
                try self.writer.print("{s}", .{self.status_message[0..self.status_len]});
            }
            try self.writer.print("{s}", .{Line(.clear_remaining).toEscape()});

            const screen_row = self.cursor_row - self.row_offset + 1;
            const screen_col = self.cursor_col - self.col_offset + 1;
            try self.writer.print("\x1b[{d};{d}H", .{ screen_row, screen_col });
        }

        pub fn handleNormalMode(self: *Self, c: u8) !void {
            try self.writer.print("{s}", .{Cursor(.steady_block).toEscape()});
            if (c == self.leader.?) {
                self.mode = .leader;
                self.setStatusMessage("-- LEADER --");
                return;
            }
            switch (c) {
                'i' => {
                    self.mode = .insert;
                    self.setStatusMessage("-- INSERT --");
                },
                'a' => {
                    self.mode = .insert;
                    if (self.cursor_row < self.lines.items.len) {
                        const line_len = self.lines.items[self.cursor_row].items.len;
                        if (self.cursor_col < line_len) {
                            self.cursor_col += 1;
                        }
                    }
                    self.setStatusMessage("-- INSERT --");
                },
                'A' => {
                    self.mode = .insert;
                    if (self.cursor_row < self.lines.items.len) {
                        self.cursor_col = self.lines.items[self.cursor_row].items.len;
                    }
                    self.setStatusMessage("-- INSERT --");
                },
                'o' => {
                    self.mode = .insert;
                    try self.insertNewLine();
                    self.setStatusMessage("-- INSERT --");
                },
                'O' => {
                    self.mode = .insert;
                    self.cursor_col = 0;
                    try self.lines.insert(self.cursor_row, std.ArrayList(u8).init(self.allocator));
                    self.setStatusMessage("-- INSERT --");
                },
                'h', 'j', 'k', 'l' => {
                    self.moveCursor(c);
                },
                'w' => {
                    while (self.cursor_row < self.lines.items.len) {
                        const line = self.lines.items[self.cursor_row];
                        if (self.cursor_col >= line.items.len) {
                            if (self.cursor_row < self.lines.items.len - 1) {
                                self.cursor_row += 1;
                                self.cursor_col = 0;
                            }
                            break;
                        }

                        while (self.cursor_col < line.items.len and line.items[self.cursor_col] != ' ') {
                            self.cursor_col += 1;
                        }

                        while (self.cursor_col < line.items.len and line.items[self.cursor_col] == ' ') {
                            self.cursor_col += 1;
                        }
                        break;
                    }
                },
                'b' => {
                    if (self.cursor_col > 0) {
                        self.cursor_col -= 1;
                        const line = self.lines.items[self.cursor_row];

                        while (self.cursor_col > 0 and line.items[self.cursor_col] == ' ') {
                            self.cursor_col -= 1;
                        }

                        while (self.cursor_col > 0 and line.items[self.cursor_col] != ' ') {
                            self.cursor_col -= 1;
                        }
                        if (self.cursor_col > 0 and line.items[self.cursor_col] == ' ') {
                            self.cursor_col += 1;
                        }
                    } else if (self.cursor_row > 0) {
                        self.cursor_row -= 1;
                        self.cursor_col = self.lines.items[self.cursor_row].items.len;
                    }
                },
                '0' => {
                    self.cursor_col = 0;
                },
                '$' => {
                    if (self.cursor_row < self.lines.items.len) {
                        self.cursor_col = self.lines.items[self.cursor_row].items.len;
                        if (self.cursor_col > 0) {
                            self.cursor_col -= 1;
                        }
                    }
                },
                'G' => {
                    if (self.lines.items.len > 0) {
                        self.cursor_row = self.lines.items.len - 1;
                        self.cursor_col = 0;
                    }
                },
                'x' => {
                    try self.deleteChar(false);
                },
                'X' => {
                    try self.deleteChar(true);
                },
                'd' => {
                    self.setStatusMessage("d");
                    self.mode = .delete;
                },
                ':' => {
                    self.mode = .command;
                    self.setStatusMessage(":");
                },
                'v' => {
                    self.mode = .visual;
                    self.visual_mode = .character;
                    self.visual_anchor_row = self.cursor_row;
                    self.visual_anchor_col = self.cursor_col;
                    self.setStatusMessage("-- Visual --");
                },
                'V' => {
                    self.mode = .visual;
                    self.visual_mode = .line;
                    self.visual_anchor_row = self.cursor_row;
                    self.visual_anchor_col = self.cursor_col;
                    self.setStatusMessage("-- Visual Line --");
                },
                0x16 => { // Ctrl+V
                    self.mode = .visual;
                    self.visual_mode = .block;
                    self.visual_anchor_row = self.cursor_row;
                    self.visual_anchor_col = self.cursor_col;
                    self.setStatusMessage("-- Visual Block --");
                },
                'p' => {
                    try self.paste(false); // false = paste after
                },
                'P' => {
                    try self.paste(true); // true = paste before
                },
                3 => {
                    self.setStatusMessage("Type :q! from Normal mode and press <Enter> to force quit this editor");
                },
                'y' => {
                    self.setStatusMessage(" havent created yank yet");
                },
                else => {
                    self.setStatusMessage(" undefined normal command");
                },
            }
        }

        pub fn handleInsertMode(self: *Self, c: u8) !void {
            try self.writer.print("{s}", .{Cursor(.steady_bar).toEscape()});
            switch (c) {
                27 => { // ESC
                    self.mode = .normal;
                    self.setStatusMessage("");
                    if (self.cursor_col > 0) {
                        self.cursor_col -= 1;
                    }
                },
                127, 8 => { // Backspace
                    try self.deleteChar(true);
                },
                '\r', '\n' => {
                    try self.insertNewLine();
                },
                '\t' => { // tab becomes 4 spaces
                    inline for (0..4) |_| {
                        try self.insertChar(' ');
                    }
                },
                else => {
                    if (c >= 32 and c < 127) { // std printable ascii chars
                        try self.insertChar(c);
                    }
                },
            }
        }

        pub fn handleLeaderMode(self: *Self, c: u8) !void {
            try self.writer.print("{s}", .{Cursor(.steady_block).toEscape()});
            switch (c) {
                'w' => {
                    try self.handleCommandMode("w");
                    self.mode = .normal;
                },
                'q' => {
                    try self.handleCommandMode("q");
                },
                else => {
                    self.mode = .normal;
                    var msg_buf: [64]u8 = undefined;
                    const msg = try std.fmt.bufPrint(msg_buf[0..], "Unknown leader sequence: {c}", .{c});
                    self.setStatusMessage(msg);
                },
            }
        }

        pub fn handleCommandMode(self: *Self, command: []const u8) !void {
            try self.writer.print("{s}", .{Cursor(.blinking_bar).toEscape()});
            if (std.mem.eql(u8, command, "q")) {
                if (self.modified) {
                    self.setStatusMessage("File modified. Use :q! to quit without saving or :w to save");
                    return;
                }
                self.exist = false;
            } else if (std.mem.eql(u8, command, "q!")) {
                self.exist = false;
            } else if (std.mem.eql(u8, command, "w")) {
                self.saveFile() catch |err| switch (err) {
                    error.NoFilenameProvided => {
                        self.setStatusMessage("File modified. Use :q! to quit without saving or :w to save");
                    },
                    error.NotValidFileName => {
                        self.setStatusMessage("Invalid filename - cannot save file");
                    },
                    else => return err,
                };
            } else if (std.mem.eql(u8, command, "wq")) {
                self.saveFile() catch |err| switch (err) {
                    error.NoFilenameProvided => {
                        self.setStatusMessage("File modified. Use :q! to quit without saving or :w to save");
                        return;
                    },
                    error.NotValidFileName => {
                        self.setStatusMessage("Invalid filename - cannot save file");
                        return;
                    },
                    else => return err,
                };
                self.exist = false;
            } else if (std.mem.startsWith(u8, command, "w ")) {
                const filename = std.mem.trim(u8, command[2..], " ");
                if (self.filename) |old_name| {
                    self.allocator.free(old_name);
                }
                self.filename = try self.allocator.dupe(u8, filename);
                self.saveFile() catch |err| switch (err) {
                    error.NotValidFileName => {
                        self.setStatusMessage("Invalid filename - cannot save file");
                    },
                    else => return err,
                };
            } else {
                var msg_buf: [256]u8 = undefined;
                const msg = try std.fmt.bufPrint(msg_buf[0..], "Unknown command: {s}", .{command});
                self.setStatusMessage(msg);
            }
            self.mode = .normal;
        }

        /// current iteration only allows for single char options not strings of commands ("d5k":delete up 5lines)
        pub fn handleDeleteMode(self: *Self, c: u8) !void {
            try self.writer.print("{s}", .{Cursor(.steady_block).toEscape()});
            switch (c) {
                'd' => {
                    try self.deleteLine();
                },
                else => {
                    var msg_buf: [64]u8 = undefined;
                    const msg = try std.fmt.bufPrint(msg_buf[0..], "Unknown delete command: d{c}", .{c});
                    self.setStatusMessage(msg);
                },
            }
            self.mode = .normal;
        }

        pub fn handleVisualMode(self: *Self, c: u8) !void {
            try self.writer.print("{s}", .{Cursor(.steady_block).toEscape()});
            switch (c) {
                'h', 'j', 'k', 'l' => {
                    self.moveCursor(c);
                },
                'v' => {
                    switch (self.visual_mode) {
                        .character => {
                            self.mode = .normal;
                            self.visual_mode = .none;
                            self.setStatusMessage("");
                            return;
                        },
                        .line => {
                            self.mode = .visual;
                            self.visual_mode = .character;
                            self.setStatusMessage("-- Visual --");
                            return;
                        },
                        .block => {
                            self.mode = .visual;
                            self.visual_mode = .character;
                            self.setStatusMessage("-- Visual --");
                            return;
                        },
                        .none => {
                            self.mode = .normal;
                            self.visual_mode = .none;
                            self.setStatusMessage("");
                        },
                    }
                },
                'V' => {
                    switch (self.visual_mode) {
                        .character => {
                            self.mode = .visual;
                            self.visual_mode = .line;
                            self.setStatusMessage("-- Visual Line --");
                            return;
                        },
                        .line => {
                            self.mode = .normal;
                            self.visual_mode = .none;
                            self.setStatusMessage("");
                            return;
                        },
                        .block => {
                            self.mode = .visual;
                            self.visual_mode = .line;
                            self.setStatusMessage("-- Visual Line --");
                            return;
                        },
                        .none => {
                            self.mode = .normal;
                            self.visual_mode = .none;
                            self.setStatusMessage("");
                        },
                    }
                },
                0x16 => { // Ctrl+V
                    switch (self.visual_mode) {
                        .character => {
                            self.mode = .visual;
                            self.visual_mode = .block;
                            self.setStatusMessage("-- Visual Block --");
                            return;
                        },
                        .line => {
                            self.mode = .visual;
                            self.visual_mode = .block;
                            self.setStatusMessage("-- Visual Block --");
                            return;
                        },
                        .block => {
                            self.mode = .normal;
                            self.visual_mode = .none;
                            self.setStatusMessage("");
                            return;
                        },
                        .none => {
                            self.mode = .normal;
                            self.visual_mode = .none;
                            self.setStatusMessage("");
                        },
                    }
                },
                27 => { // ESC
                    self.mode = .normal;
                    self.visual_mode = .none;
                    self.setStatusMessage("");
                },
                'd' => {
                    self.setStatusMessage("Visual Command not enabled yet");
                },
                'p' => {
                    self.setStatusMessage("Visual Command not enabled yet");
                },
                'y' => {
                    self.setStatusMessage(" havent created yank yet");
                },

                else => {
                    self.setStatusMessage("Unknown Visual Command");
                },
            }
        }

        pub fn getSelectionRange(self: *Self) Visual.Selection {
            var range = Visual.Selection{
                .start_row = self.visual_anchor_row,
                .start_col = self.visual_anchor_col,
                .end_row = self.cursor_row,
                .end_col = self.cursor_col,
            };
            range = Visual.normalizeSelection(range);
            return range;
        }

        fn isCharacterSelected(self: *Self, row: usize, col: usize) bool { //used in draw
            if (self.visual_mode == .none) return false;

            const range = self.getSelectionRange();

            switch (self.visual_mode) {
                .character => {
                    if (row < range.start_row or row > range.end_row) return false;
                    if (row == range.start_row and row == range.end_row) {
                        return col >= range.start_col and col <= range.end_col;
                    } else if (row == range.start_row) {
                        return col >= range.start_col;
                    } else if (row == range.end_row) {
                        return col <= range.end_col;
                    } else {
                        return true;
                    }
                },
                .line => {
                    return row >= range.start_row and row <= range.end_row;
                },
                .block => {
                    return row >= range.start_row and row <= range.end_row and
                        col >= range.start_col and col <= range.end_col;
                },
                .none => return false,
            }
        }

        pub fn paste(self: *Self, before: bool) !void {
            if (self.paste_buffer.content.items.len == 0) return;
            if (self.cursor_row >= self.lines.items.len) return;

            if (self.paste_buffer.is_line_wise) {
                // Line-wise paste
                const insert_row = if (before) self.cursor_row else self.cursor_row + 1;

                for (self.paste_buffer.content.items, 0..) |paste_line, i| {
                    var new_line = std.ArrayList(u8).init(self.allocator);
                    try new_line.appendSlice(paste_line.items);
                    try self.lines.insert(insert_row + i, new_line);
                }

                if (!before) {
                    self.cursor_row += 1;
                    if (self.cursor_row >= self.lines.items.len) {
                        self.cursor_row = self.lines.items.len - 1;
                    }
                }
                self.cursor_col = 0;
            } else {
                // Character-wise paste
                if (self.paste_buffer.content.items.len > 0) {
                    const paste_line = self.paste_buffer.content.items[0];
                    const current_line = &self.lines.items[self.cursor_row];
                    const line_len = current_line.items.len;
                    var insert_col = if (before) self.cursor_col else self.cursor_col + 1;
                    if (insert_col > line_len) {
                        insert_col = line_len;
                    }
                    for (paste_line.items, 0..) |char, i| {
                        try current_line.insert(insert_col + i, char);
                    }
                    if (!before) {
                        self.cursor_col += paste_line.items.len;
                        if (self.cursor_col > current_line.items.len) {
                            self.cursor_col = current_line.items.len;
                        }
                    }
                }
            }
            self.modified = true;
        }
    };
}
