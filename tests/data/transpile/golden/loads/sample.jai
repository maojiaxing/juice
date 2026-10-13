#import "Basic";
#load "helper.jai";
#load
"multi.jai";
#load "../../outside.jai";
#load CONST_NAME;
#load "other" + ".jai";

test "uses helpers" {
    #load "inside.jai";
    helper_work();
}
