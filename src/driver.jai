// Process-wide driver shared by commands, workspace preparation, dependency
// resolution, and manifest loading. It owns the paths Juice operates on; it
// is not specific to any single command.
Build_Driver :: struct {
    root_dir:     string;
    packages_dir: string;
    cache_dir:    string;
    data_dir:     string;
    config_dir:   string;
}
