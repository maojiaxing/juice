#import "Basic";
#import "member_lib";
#import "member_extra";

main :: () {
    print("ws_root: % | %\n", member_lib_greeting(), member_extra_greeting());
}
