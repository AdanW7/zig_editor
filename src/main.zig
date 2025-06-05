//! the current version of this edior is unbuffered, (dont need to flush with enter after a line is typed) before you can save
//! havent implemented yank
//! only delete comand is dd
const std = @import("std");
const lib = @import("zig_term_lib");
const os = std.os;
const c = std.c;


pub fn main() !void {

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const stdout = std.io.getStdOut().writer();
    const stdin = std.io.getStdIn().reader();

    const Editor = lib.editor.Editor(@TypeOf(stdout));

    try lib.raw.enableRawMode();
    var zig_editor = try Editor.init(allocator, stdout);
    defer zig_editor.deinit();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len > 1) {
        try zig_editor.loadFile(args[1]);
    } else {
        zig_editor.setStatusMessage("New buffer - use :w filename to save");
    }

    try zig_editor.EnterEditor();
    defer zig_editor.exitEditor() catch {};

    var input_buf: [1]u8 = undefined;
    var command_buf: [256]u8 = undefined;
    var command_len: usize = 0;


    while (zig_editor.exist) {


        try zig_editor.draw();

        const n = try stdin.read(input_buf[0..]);
        if (n == 0) continue;

        const char = input_buf[0];

        switch (zig_editor.mode) {
            .normal => {
                // try zig_editor.writer.print("{s}",.{lib.Cursor.steady_block.toEscape()});
                try zig_editor.writer.print("{s}", .{lib.EscapeSequence.Cursor(.steady_block).toEscape()});

                try zig_editor.handleNormalMode(char);
            },
            .insert => {
                // try zig_editor.writer.print("{s}",.{lib.Cursor.steady_bar.toEscape()});
                try zig_editor.writer.print("{s}", .{lib.EscapeSequence.Cursor(.steady_bar).toEscape()});
                try zig_editor.handleInsertMode(char);
            },
            .leader =>{
                // try zig_editor.writer.print("{s}",.{lib.Cursor.steady_block.toEscape()});
                try zig_editor.writer.print("{s}", .{lib.EscapeSequence.Cursor(.steady_block).toEscape()});
                try zig_editor.handleLeaderMode(char);
            },
            .delete => {
                // try zig_editor.writer.print("{s}",.{lib.Cursor.steady_block.toEscape()});
                try zig_editor.writer.print("{s}", .{lib.EscapeSequence.Cursor(.steady_block).toEscape()});
                try zig_editor.handleDeleteMode(char);
            },
            .visual =>{
                // try zig_editor.writer.print("{s}",.{lib.Cursor.steady_block.toEscape()});
                try zig_editor.writer.print("{s}", .{lib.EscapeSequence.Cursor(.steady_block).toEscape()});
                try zig_editor.handleVisualMode(char);
            },
            .command => {
                // try zig_editor.writer.print("{s}",.{lib.Cursor.blinking_bar.toEscape()});
                try zig_editor.writer.print("{s}", .{lib.EscapeSequence.Cursor(.blinking_bar).toEscape()});
                if (char == '\r' or char == '\n') {
                    const command = command_buf[0..command_len];
                    try zig_editor.handleCommandMode(command);
                    command_len = 0;
                } else if (char == 27) { // ESC
                    zig_editor.mode = .normal;
                    zig_editor.setStatusMessage("");
                    command_len = 0;
                } else if (char == 127 or char == 8) { // backspace
                    if (command_len > 0) {
                        command_len -= 1;
                        var msg_buf: [257]u8 = undefined;
                        msg_buf[0] = ':';
                        @memcpy(msg_buf[1 .. command_len + 1], command_buf[0..command_len]);
                        zig_editor.setStatusMessage(msg_buf[0 .. command_len + 1]);
                    } else {
                        zig_editor.mode = .normal;
                        zig_editor.setStatusMessage("");
                    }
                } else if (char >= 32 and char < 127 and command_len < command_buf.len - 1) {
                    command_buf[command_len] = char;
                    command_len += 1;
                    var msg_buf: [257]u8 = undefined;
                    msg_buf[0] = ':';
                    @memcpy(msg_buf[1 .. command_len + 1], command_buf[0..command_len]);
                    zig_editor.setStatusMessage(msg_buf[0 .. command_len + 1]);
                }
            },
            else => {
                continue;
            },
        }
    }
}
