#import "Basic";
#import "Testing";

// 票 0049：依赖剥离前端验证——导入入口自身内联 test block（此前会破坏
// 消费者构建，0046 票注），并 #load 另一个同样含 test block 的源文件。
// 消费者（ws_root 的 build 与 test 程序）经依赖剥离前端以 STRIP 视图编译
// 本闭包；member 自身为 root 跑测试时这些块正常发现执行。
#load "extra.jai";

member_lib_greeting :: () -> string {
    return "hello from member_lib";
}

test "member inline test" {
    expect_eq(member_lib_greeting(), "hello from member_lib");
}
