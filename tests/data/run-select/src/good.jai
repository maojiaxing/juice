#import "Basic";

main :: () {
    arguments := get_command_line_arguments();
    print("GOOD RUN\n");
    for index: 1..arguments.count-1 {
        print("ARG %\n", arguments[index]);
    }
}
