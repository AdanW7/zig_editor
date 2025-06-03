pub const Mode = enum {
    none,
    character,  
    line,       
    block,      
};

pub const Selection = struct {
    start_row: usize,
    start_col: usize,
    end_row: usize,
    end_col: usize,
};

pub fn normalizeSelection(selection: Selection) Selection {
    var result = selection;
    if (selection.start_row > selection.end_row or 
        (selection.start_row == selection.end_row and selection.start_col > selection.end_col)) {
        result.start_row = selection.end_row;
        result.start_col = selection.end_col;
        result.end_row = selection.start_row;
        result.end_col = selection.start_col;
    }
    return result;
}
