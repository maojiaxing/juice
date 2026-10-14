#import "Basic";
#import "Testing";
#import "member_lib";

// monorepo test E2E（票 0046）：root 的测试程序经依赖 shim 引用 lib member。
test "root test imports the member" {
    expect_eq(member_lib_greeting(), "hello from member_lib");
}
