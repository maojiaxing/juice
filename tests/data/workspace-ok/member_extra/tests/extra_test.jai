#import "Basic";
#import "Testing";
#import "member_lib";

// 票 0049 缺陷修正：LIB member（0 effective target）自为 root 跑测试时，
// force_dependencies 使依赖准备照常执行，测试程序经 shim 引用 member_lib。
test "lib member test imports its dependency" {
    expect_eq(member_lib_greeting(), "hello from member_lib");
}
