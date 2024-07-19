const mecha = @import("mecha");
const std = @import("std");

//https://gist.github.com/DOBRO/2592c6dad754ba67e6dcaec8c90165bf
// pub const CommandKind = enum {
//     Uci,
//     Debug,
//     // IsReady,
//     // SetOption,
//     // Register,
//     // UciNewGame,
//     // Position,
//     // Go,
//     // Stop,
//     // PonderHit,
//     // Quit,
// };

pub const Command = union(enum) {
    Uci,
    Debug: bool,
};

// mecha.to
