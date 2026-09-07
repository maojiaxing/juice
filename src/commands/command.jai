Command_Handler :: #type (ctx: *Command_Context, arguments: [] string) -> bool;

Command_Context :: struct {
    driver:             *Build_Driver;
    arguments:          [] string;
    root_package:       Package;
    workspace_prepared: bool;
}

Command :: struct {
    name:          string;
    description:   string;
    usage:         string;
    prerequisites: [] string;
    visible:       bool = true;
    handler:       Command_Handler;
}
