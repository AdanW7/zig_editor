const std = @import("std");

pub const PasteBuffer = struct {
    content: std.ArrayList(std.ArrayList(u8)),
    allocator: std.mem.Allocator,
    is_line_wise: bool, // true if content represents complete lines, false for character-wise
    
    pub fn init(allocator: std.mem.Allocator) PasteBuffer {
        return PasteBuffer{
            .content = std.ArrayList(std.ArrayList(u8)).init(allocator),
            .allocator = allocator,
            .is_line_wise = false,
        };
    }
    
    pub fn deinit(self: *PasteBuffer) void {
        for (self.content.items) |line| {
            line.deinit();
        }
        self.content.deinit();
    }
    
    // Clear the buffer and prepare for new content
    pub fn clear(self: *PasteBuffer) void {
        for (self.content.items) |line| {
            line.deinit();
        }
        self.content.clearRetainingCapacity();
    }
    
    // Store a single character
    pub fn storeChar(self: *PasteBuffer, char: u8) !void {
        self.clear();
        self.is_line_wise = false;
        
        var line = std.ArrayList(u8).init(self.allocator);
        try line.append(char);
        try self.content.append(line);
    }
    
    // Store multiple lines (for line deletion, visual selection, etc.)
    pub fn storeLines(self: *PasteBuffer, lines: []const std.ArrayList(u8), line_wise: bool) !void {
        self.clear();
        self.is_line_wise = line_wise;
        
        for (lines) |source_line| {
            var new_line = std.ArrayList(u8).init(self.allocator);
            try new_line.appendSlice(source_line.items);
            try self.content.append(new_line);
        }
    }
    
    // Store a portion of a line (for character-wise operations)
    pub fn storeText(self: *PasteBuffer, text: []const u8) !void { 
        self.clear();
        self.is_line_wise = false;
        
        var line = std.ArrayList(u8).init(self.allocator);
        if(text.len == 0){
            try line.append('\n');
        }
        else {
            try line.appendSlice(text);
        }
        try self.content.append(line);
    }
};
