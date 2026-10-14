#import "Juice";

// 票 0049 缺陷修正 fixture：LIB member 自身声明对另一 member 的依赖——
// member 自为 root 测试时 0 plans，force_dependencies 使依赖准备照常执行，
// 测试程序经 shim #import "member_lib"（source 相对 CWD=member 目录解析；
// 从 root 侧消费时按名 member-link、source 忽略）。
PACKAGE :: Package.{
    name    = "member_extra",
    version = "0.1.0",
    type    = .LIB,
    dependencies = Dependency.[
        .{name = "member_lib", version = "0.1.0", source = "../member_lib"},
    ],
};
