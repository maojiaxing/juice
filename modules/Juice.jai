#import "Basic";


Package_Type :: enum {
	LIB;
	BIN;
}

Binary_Target :: struct {
	name:       string;
	main_file:  string;
	output_dir: string = "";
}

Dependency :: struct {
	name:    string;
	version: string = "";
	source:  string = "";
	package: string = "";
}

Workspace_Config :: struct {
	members: [] string;
	exclude: [] string;
}

Package :: struct {
	name:         string;
	version:      string;
	type:         Package_Type = .BIN;

	targets:      [..] Binary_Target;
	root_file:    string = "modulejai";

    dependencies: [] Dependency;
    workspace:    Workspace_Config;
    build_script: string = "";
}