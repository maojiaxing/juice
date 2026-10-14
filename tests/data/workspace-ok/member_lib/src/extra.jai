#import "Basic";
#import "Testing";

// 票 0049：入口闭包内的非入口源文件同样含 test block——整闭包视图化
// （ADR 0004 全有全无语义），入口视图的 #load 改写指向本文件的剥离视图。
member_lib_helper :: () -> s32 { return 1; }

test "member extra inline test" {
    expect_eq(member_lib_helper(), 1);
}
