#import "Basic";
// juice: load stripped: #load "helper.jai";
// juice: load stripped: #load
// juice: load stripped (cont)
#load "../../outside.jai";
#load CONST_NAME;
#load "other" + ".jai";

juice_test_1 :: () -> () {
    // juice: load stripped: #load "inside.jai";
    helper_work();
} @test
