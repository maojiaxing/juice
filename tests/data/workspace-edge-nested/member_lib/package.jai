#import "Juice";

// 边界用例：member 自身的 manifest 再声明 workspace member。
// 当前实现只迭代 root package 的 members 清单，此嵌套声明应被忽略。
PACKAGE :: Package.{
    name    = "member_lib",
    version = "0.1.0",
    type    = .LIB,
    workspace = .{
        members = string.["sub_member"],
    },
};
