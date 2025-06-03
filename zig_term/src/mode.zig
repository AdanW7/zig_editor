//! modes in this Vim like editor, 

/// Mode is defined non exhaustively for ability to add different modes in the future
pub const Mode = enum(u8) {
    normal,
    insert,
    command,
    leader,
    delete,
    visual,
    _,
};
