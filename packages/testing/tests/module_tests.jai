#import "Basic";
#import "Testing";
#import "File";
#import "String";

// Only successful outer assertions touch the runner's Testing state. All
// intentional failures and run/finish calls execute in a separate compiler.
testing_behavior_isolated_child :: () {
    result, output, errors := run_testing_behavior_child();
    expect(result.type == .EXITED && result.exit_code == 0,
        "behavior child failed: %\n%\n%", result.exit_code, output, errors);
    fixture_path := replace(tprint("%/tests/data/scenarios.jai", JUICE_TEST_PACKAGE_ROOT), "\\", "/");
    fixture_source, source_ok := read_entire_file(fixture_path);
    expect(source_ok, "could not read %", fixture_path);

    expected: String_Builder;
    append(*expected, "default-mapping=0\n[test] pass\npass-continued\n");
    scenarios: [] struct { name: string; needle: string; message: string; } = .[
        .{"default-failure", "expect(false);", "expect failed"},
        .{"equality-failure", "expect_eq(3, 5);", "expect_eq failed: expected 3, got 5"},
        .{"explicit-failure", "fail(\"boom\");", "boom"},
        .{"message-failure", "expect(false, \"got % and %\", 7, 9);", "got 7 and 9"},
        .{"custom-equality-failure", "expect_eq(3, 5, \"custom mismatch\");", "custom mismatch"},
        .{"deferred-failure", "expect(false, \"deferred failure\");", "deferred failure"},
    ];
    for scenario: scenarios {
        line, column := testing_fixture_coordinates(fixture_source, scenario.needle);
        expect(line > 0 && column > 0, "missing fixture invocation: %", scenario.needle);
        print_to_builder(*expected, "[test] %\nsrc/scenarios.jai:%:%: %\n", scenario.name, line, column, scenario.message);
    }
    append(*expected, "defer-ran\n[test] next-test\nnext-test-continued\n[test] bare-return\n3 passed, 6 failed\nfailures=6\n0 passed, 0 failed\nempty-failures=0\n[test] fresh-suite\nnext-test-continued\n1 passed, 0 failed\nfresh-failures=0\n");
    mapped_line, mapped_column := testing_fixture_coordinates(fixture_source, "expect(2 + 2 == 5);");
    expect(mapped_line > 0 && mapped_column > 0);
    print_to_builder(*expected,
        "[test] mapped\nsrc/scenarios.jai:%:%: expect failed\n0 passed, 1 failed\nmapped-failures=1\nreset-mapping=0\n",
        mapped_line, mapped_column);
    print_to_builder(*expected,
        "[test] passthrough\n%:%:%: expect failed\n0 passed, 1 failed\npassthrough-failures=1\n0 passed, 0 failed\nfinal-failures=0\n",
        fixture_path, mapped_line, mapped_column);
    // -quiet can still print compiler notices; require the whole contiguous
    // semantic transcript, not a loose collection of unrelated substrings.
    transcript := builder_to_string(*expected);
    expect(find_index_from_left(output, transcript) >= 0,
        "behavior transcript mismatch\nexpected:\n%\nactual:\n%\n%", transcript, output, errors);
    expect(find_index_from_left(output, "UNREACHABLE") < 0, "failed assertion or bare return continued");
    expect(find_index_from_left(output, "not printed") < 0, "passing assertion printed a failure message");
    expect(find_index_from_left(output, "wrong.jai") < 0, "path mapping matched an unrelated path");
} @test
