#import "Basic";
#import "Testing";

// 只在 member 作为自身 root 跑测试时执行；root 的 `juice test` 不得发现它
// （票 0046 的 E2E 以此断言 member 边界）。
test "member test must not run in root" {
    expect(member_lib_greeting() == "hello from member_lib");
}
