//! posix compabtible way to get window size of terminal
const std = @import("std");
const posix = std.posix;
const stdout_fd = posix.STDOUT_FILENO;

pub const TermSize = struct {
    rows: usize,
    cols: usize,
};

pub fn getTerminalSize() !TermSize {
    var winsz: posix.winsize = .{ .col = 0, .row = 0, .xpixel = 0, .ypixel = 0 };
    const result = posix.system.ioctl(stdout_fd, posix.T.IOCGWINSZ, @intFromPtr(&winsz));
    if (result == -1) {
        return TermSize{ .rows = 24, .cols = 80 };
    }
    if (winsz.row == 0 or winsz.col == 0) {
        return TermSize{ .rows = 24, .cols = 80 };
    }
    return TermSize{
        .rows = @intCast(winsz.row),
        .cols = @intCast(winsz.col),
    };
}
