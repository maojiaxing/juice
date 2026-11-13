#import "Basic";
#import "Testing";

// ---------------------------------------------------------------------------
// Version command tests (ticket 013): the two-line output contract — juice's
// own version (the JUICE_VERSION constant, kept in sync with package.jai's
// PACKAGE.version) and the jai compiler version baked into the executable at
// compile time (compiler_get_version_info via the #run constant form, 002
// decision 5). The argument guard is locked by the CLI E2E suite.
// ---------------------------------------------------------------------------

// The rendered contract, byte for byte: line 1 = juice's own version, line
// 2 = the jai compiler triple.
EXPECTED_VERSION_OUTPUT :: "juice 0.1.0\njai 0.2.9\n";

the_version_constants_match_the_contract :: () -> () {
    // The contract's tool version: the hardcoded constant in
    // src/commands/version.jai. The jai compiler triple (the #run constant
    // baked during the build) is locked by the E2E child below — its real
    // exe output IS the baked value. The suite deliberately never
    // references JAI_COMPILER_VERSION in-process: the #run-constant
    // evaluation deadlocks against the old juice test driver's own #run
    // when triggered from a late-typechecked test body ("stalled waiting
    // for another directive" — ticket 016 deviation 2's race, retired by
    // ticket 017: the test-block anchor and the top-level anchor both lost
    // the race as the suite grew, and the E2E already pins the contract
    // byte for byte).
    expect(JUICE_VERSION == "0.1.0");
} @test

e2e_version_prints_the_two_line_version_contract :: () -> () {
    result, output, _ := run_otter_child(string.["version"]);
    expect(expect_exit("version", result, 0));
    expect(child_output_equals("version", output, EXPECTED_VERSION_OUTPUT));
} @test
