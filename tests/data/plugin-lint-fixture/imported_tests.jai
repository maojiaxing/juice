// Fixture imported module (ticket 042): the test program's source imports
// it by name, so its @test procedures enter the inner workspace's
// .TYPECHECKED stream through a module load OUTSIDE the package view set.
// The source-isolation predicate excludes them: the imported module's test
// is neither collected nor executed nor linted (the "imported modules never
// flood the report" acceptance — parent US 15). The deliberately bad name
// would trip the fixture lint rule if isolation ever leaked.
#import "Basic";
#import "Testing";

BadImportedTest :: () {
    expect(true);
} @test
