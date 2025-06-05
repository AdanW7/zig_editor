
//! posix compatible functions to exit and re-enter canonical terminal mode
const std = @import("std");
pub const posix = std.posix;
var orig_termios: posix.termios = undefined;
pub const stdout_fd = posix.STDOUT_FILENO;
const stdin_fd = posix.STDIN_FILENO;

pub fn enableRawMode() !void {
    orig_termios = try posix.tcgetattr(stdin_fd);
    var raw = orig_termios;
    raw.lflag.ICANON = false; // exit canonical
    raw.lflag.ECHO = false; // typed chars are invis by default that way i can use a draw func later 
    
    raw.lflag.ISIG = false; // disable signal gen for ctrl+C
    raw.lflag.IEXTEN = false; // need to disable if want acess to ctrl + v in one press rather than 2
    // disable ctrl+s and ctrl+Q control flow 
    raw.iflag.IXON = false;
    raw.iflag.IXOFF = false;
    try posix.tcsetattr(stdin_fd, .FLUSH, raw);
}

pub fn disableRawMode() !void {
    try posix.tcsetattr(stdin_fd, .FLUSH, orig_termios);
}
