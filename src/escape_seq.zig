//! syntactic sugar to avoid rembembering escape sequences

const std = @import("std");

pub const ESC = "\x1b";

pub const LINE = enum {
    clear_remaining,
    clear_whole,
};


pub const SCREEN = enum {
    enter_alt,
    exit_alt,
    clear,
};

pub const CURSOR = enum {
    pos_top,
    save_pos,
    return_pos,
    hide,
    show,
    steady_block,
    blinking_block,
    steady_underline,
    blinking_underline,
    steady_bar,
    blinking_bar,
};

pub const COLOR = enum {
    reset,
    fg_black,
    fg_red,
    fg_green,
    fg_yellow,
    fg_blue,
    fg_magenta,
    fg_cyan,
    fg_white,
    fg_black_bold,
    fg_red_bold,
    fg_green_bold,
    fg_yellow_bold,
    fg_blue_bold,
    fg_magenta_bold,
    fg_cyan_bold,
    fg_white_bold,
    bg_black,
    bg_red,
    bg_green,
    bg_yellow,
    bg_blue,
    bg_magenta,
    bg_cyan,
    bg_white,
    bg_black_bold,
    bg_red_bold,
    bg_green_bold,
    bg_yellow_bold,
    bg_blue_bold,
    bg_magenta_bold,
    bg_cyan_bold,
    bg_white_bold,
};

pub const EscapeSequence = union(enum) {
    line: LINE,
    screen: SCREEN,
    cursor: CURSOR,
    color: COLOR,

    pub fn Screen(s: SCREEN) EscapeSequence {
        return EscapeSequence{ .screen = s };
    }
    
    pub fn Cursor(c: CURSOR) EscapeSequence {
        return EscapeSequence{ .cursor = c };
    }
    
    pub fn Color(c: COLOR) EscapeSequence {
        return EscapeSequence{ .color = c };
    }
    
    pub fn Line(l: LINE) EscapeSequence {
        return EscapeSequence{ .line = l };
    }

    pub fn toEscape(self: EscapeSequence) []const u8 {
        return switch (self) {
            .line => |l| switch (l) {
                .clear_remaining => ESC ++ "[0K",
                .clear_whole => ESC ++ "[2K",
            },
            .screen => |s| switch (s) {
                .enter_alt => ESC ++ "[?1049h",
                .exit_alt => ESC ++ "[?1049l",
                .clear => ESC ++ "[2J",
            },
            .cursor => |c| switch (c) {
                .pos_top => ESC ++ "[H",
                .save_pos => ESC ++ "[S",
                .return_pos => ESC ++ "[u",
                .hide => ESC ++ "[?25l",
                .show => ESC ++ "[?25h",
                .steady_block => ESC ++ "[2 q",
                .blinking_block => ESC ++ "[1 q",
                .steady_underline => ESC ++ "[4 q",
                .blinking_underline => ESC ++ "[3 q",
                .steady_bar => ESC ++ "[6 q",
                .blinking_bar => ESC ++ "[5 q",
            },
            .color => |c| switch (c) {
                .reset => ESC ++ "[0m",
                .fg_black => ESC ++ "[30m",
                .fg_red => ESC ++ "[31m",
                .fg_green => ESC ++ "[32m",
                .fg_yellow => ESC ++ "[33m",
                .fg_blue => ESC ++ "[34m",
                .fg_magenta => ESC ++ "[35m",
                .fg_cyan => ESC ++ "[36m",
                .fg_white => ESC ++ "[37m",
                .fg_black_bold => ESC ++ "[90m",
                .fg_red_bold => ESC ++ "[91m",
                .fg_green_bold => ESC ++ "[92m",
                .fg_yellow_bold => ESC ++ "[93m",
                .fg_blue_bold => ESC ++ "[94m",
                .fg_magenta_bold => ESC ++ "[95m",
                .fg_cyan_bold => ESC ++ "[96m",
                .fg_white_bold => ESC ++ "[97m",
                .bg_black => ESC ++ "[40m",
                .bg_red => ESC ++ "[41m",
                .bg_green => ESC ++ "[42m",
                .bg_yellow => ESC ++ "[43m",
                .bg_blue => ESC ++ "[44m",
                .bg_magenta => ESC ++ "[45m",
                .bg_cyan => ESC ++ "[46m",
                .bg_white => ESC ++ "[47m",
                .bg_black_bold => ESC ++ "[100m",
                .bg_red_bold => ESC ++ "[101m",
                .bg_green_bold => ESC ++ "[102m",
                .bg_yellow_bold => ESC ++ "[103m",
                .bg_blue_bold => ESC ++ "[104m",
                .bg_magenta_bold => ESC ++ "[105m",
                .bg_cyan_bold => ESC ++ "[106m",
                .bg_white_bold => ESC ++ "[107m",
            },
        };
    }
};

