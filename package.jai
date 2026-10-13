#import "Juice";

// Juice 自举（ticket 0023）：仓库自身是 BIN package，target 为自身入口，
// 使 `juice test` 于仓库根可运行（test 依赖 prepare-workspace）。
PACKAGE :: Package.{
    name    = "juice",
    version = "0.1.0",
    type    = .BIN,
    targets = Target.[
        .{name = "juice", main_file = "src/main.jai"},
    ],
};
