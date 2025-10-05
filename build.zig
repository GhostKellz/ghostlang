const std = @import("std");

// Although this function looks imperative, it does not perform the build
// directly and instead it mutates the build graph (`b`) that will be then
// executed by an external runner. The functions in `std.Build` implement a DSL
// for defining build steps and express dependencies between them, allowing the
// build runner to parallelize the build automatically (and the cache system to
// know when a step doesn't need to be re-run).
pub fn build(b: *std.Build) void {
    // Standard target options allow the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});
    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});
    const grove_path = b.option([]const u8, "grove-path", "Path to a Grove checkout used for integration testing");
    const tree_sitter_lib = b.option([]const u8, "tree-sitter-lib", "Path to a prebuilt Tree-sitter static library");

    const build_options = b.addOptions();
    build_options.addOption(bool, "grove_enabled", grove_path != null);
    build_options.addOption([]const u8, "grove_path", grove_path orelse "");
    build_options.addOption([]const u8, "tree_sitter_lib", tree_sitter_lib orelse "");
    // It's also possible to define more custom flags to toggle optional features
    // of this build script using `b.option()`. All defined flags (including
    // target and optimize options) will be listed when running `zig build --help`
    // in this directory.

    // This creates a module, which represents a collection of source files alongside
    // some compilation options, such as optimization mode and linked system libraries.
    // Zig modules are the preferred way of making Zig code available to consumers.
    // addModule defines a module that we intend to make available for importing
    // to our consumers. We must give it a name because a Zig package can expose
    // multiple modules and consumers will need to be able to specify which
    // module they want to access.
    const mod = b.addModule("ghostlang", .{
        // The root source file is the "entry point" of this module. Users of
        // this module will only be able to access public declarations contained
        // in this file, which means that if you have declarations that you
        // intend to expose to consumers that were defined in other files part
        // of this module, you will have to make sure to re-export them from
        // the root file.
        .root_source_file = b.path("src/root.zig"),
        // Later on we'll use this module as the root module of a test executable
        // which requires us to specify a target.
        .target = target,
    });
    mod.addOptions("build_options", build_options);

    // Here we define an executable. An executable needs to have a root module
    // which needs to expose a `main` function. While we could add a main function
    // to the module defined above, it's sometimes preferable to split business
    // logic and the CLI into two separate modules.
    //
    // If your goal is to create a Zig library for others to use, consider if
    // it might benefit from also exposing a CLI tool. A parser library for a
    // data serialization format could also bundle a CLI syntax checker, for example.
    //
    // If instead your goal is to create an executable, consider if users might
    // be interested in also being able to embed the core functionality of your
    // program in their own executable in order to avoid the overhead involved in
    // subprocessing your CLI tool.
    //
    // If neither case applies to you, feel free to delete the declaration you
    // don't need and to put everything under a single module.
    const exe = b.addExecutable(.{
        .name = "ghostlang",
        .root_module = b.createModule(.{
            // b.createModule defines a new module just like b.addModule but,
            // unlike b.addModule, it does not expose the module to consumers of
            // this package, which is why in this case we don't have to give it a name.
            .root_source_file = b.path("src/main.zig"),
            // Target and optimization levels must be explicitly wired in when
            // defining an executable or library (in the root module), and you
            // can also hardcode a specific target for an executable or library
            // definition if desireable (e.g. firmware for embedded devices).
            .target = target,
            .optimize = optimize,
            // List of modules available for import in source files part of the
            // root module.
            .imports = &.{
                // Here "ghostlang" is the name you will use in your source code to
                // import this module (e.g. `@import("ghostlang")`). The name is
                // repeated because you are allowed to rename your imports, which
                // can be extremely useful in case of collisions (which can happen
                // importing modules from different packages).
                .{ .name = "ghostlang", .module = mod },
            },
        }),
    });
    exe.root_module.addOptions("build_options", build_options);

    // This declares intent for the executable to be installed into the
    // install prefix when running `zig build` (i.e. when executing the default
    // step). By default the install prefix is `zig-out/` but can be overridden
    // by passing `--prefix` or `-p`.
    b.installArtifact(exe);

    // This creates a top level step. Top level steps have a name and can be
    // invoked by name when running `zig build` (e.g. `zig build run`).
    // This will evaluate the `run` step rather than the default step.
    // For a top level step to actually do something, it must depend on other
    // steps (e.g. a Run step, as we will see in a moment).
    const run_step = b.step("run", "Run the app");

    // This creates a RunArtifact step in the build graph. A RunArtifact step
    // invokes an executable compiled by Zig. Steps will only be executed by the
    // runner if invoked directly by the user (in the case of top level steps)
    // or if another step depends on it, so it's up to you to define when and
    // how this Run step will be executed. In our case we want to run it when
    // the user runs `zig build run`, so we create a dependency link.
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    // By making the run step depend on the default step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // Creates an executable that will run `test` blocks from the provided module.
    // Here `mod` needs to define a target, which is why earlier we made sure to
    // set the releative field.
    const mod_tests = b.addTest(.{
        .root_module = mod,
    });
    mod_tests.root_module.addOptions("build_options", build_options);

    // A run step that will run the test executable.
    const run_mod_tests = b.addRunArtifact(mod_tests);

    // Creates an executable that will run `test` blocks from the executable's
    // root module. Note that test executables only test one module at a time,
    // hence why we have to create two separate ones.
    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });
    exe_tests.root_module.addOptions("build_options", build_options);

    // A run step that will run the second test executable.
    const run_exe_tests = b.addRunArtifact(exe_tests);

    // A top level step for running all tests. dependOn can be called multiple
    // times and since the two run steps do not depend on one another, this will
    // make the two of them run in parallel.
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);

    // Safety demo executable
    const safety_demo = b.addExecutable(.{
        .name = "safety_demo",
        .root_module = b.createModule(.{
            .root_source_file = b.path("safety_demo_simple.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "ghostlang", .module = mod },
            },
        }),
    });
    safety_demo.root_module.addOptions("build_options", build_options);
    b.installArtifact(safety_demo);

    const run_safety_demo_cmd = b.addRunArtifact(safety_demo);
    const run_safety_demo = b.step("safety-demo", "Run the safety demonstration");
    run_safety_demo.dependOn(&run_safety_demo_cmd.step);

    // Phase 2 integration test
    const phase2_test = b.addExecutable(.{
        .name = "phase2_test",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/complete_plugin_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "ghostlang", .module = mod },
            },
        }),
    });
    phase2_test.root_module.addOptions("build_options", build_options);
    b.installArtifact(phase2_test);

    const run_phase2_cmd = b.addRunArtifact(phase2_test);
    const run_phase2 = b.step("phase2-test", "Run Phase 2 integration test");
    run_phase2.dependOn(&run_phase2_cmd.step);

    // Fuzzing target
    const simple_fuzz = b.addExecutable(.{
        .name = "simple_fuzz",
        .root_module = b.createModule(.{
            .root_source_file = b.path("fuzz/simple_fuzz.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "ghostlang", .module = mod },
            },
        }),
    });
    simple_fuzz.root_module.addOptions("build_options", build_options);
    b.installArtifact(simple_fuzz);

    const run_simple_fuzz_cmd = b.addRunArtifact(simple_fuzz);
    const run_fuzz = b.step("fuzz", "Run fuzzing tests");
    run_fuzz.dependOn(&run_simple_fuzz_cmd.step);

    // Benchmarking
    const plugin_bench = b.addExecutable(.{
        .name = "plugin_bench",
        .root_module = b.createModule(.{
            .root_source_file = b.path("benchmarks/plugin_bench.zig"),
            .target = target,
            .optimize = .ReleaseFast, // Use optimized build for benchmarks
            .imports = &.{
                .{ .name = "ghostlang", .module = mod },
            },
        }),
    });
    plugin_bench.root_module.addOptions("build_options", build_options);
    b.installArtifact(plugin_bench);

    const run_plugin_bench_cmd = b.addRunArtifact(plugin_bench);
    const run_bench = b.step("bench", "Run performance benchmarks");
    run_bench.dependOn(&run_plugin_bench_cmd.step);

    // Memory limit test
    const memory_test = b.addExecutable(.{
        .name = "memory_limit_test",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/memory_limit_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "ghostlang", .module = mod },
            },
        }),
    });
    memory_test.root_module.addOptions("build_options", build_options);
    b.installArtifact(memory_test);

    const run_memory_test_cmd = b.addRunArtifact(memory_test);
    const run_memory_test = b.step("test-memory", "Test memory limit allocator");
    run_memory_test.dependOn(&run_memory_test_cmd.step);

    // Security audit
    const security_audit = b.addExecutable(.{
        .name = "sandbox_audit",
        .root_module = b.createModule(.{
            .root_source_file = b.path("security/sandbox_audit.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "ghostlang", .module = mod },
            },
        }),
    });
    security_audit.root_module.addOptions("build_options", build_options);
    b.installArtifact(security_audit);

    const run_security_audit_cmd = b.addRunArtifact(security_audit);
    const run_security = b.step("security", "Run security audit suite");
    run_security.dependOn(&run_security_audit_cmd.step);

    // Integration test
    const integration_test = b.addExecutable(.{
        .name = "integration_test",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/integration_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "ghostlang", .module = mod },
            },
        }),
    });
    integration_test.root_module.addOptions("build_options", build_options);
    b.installArtifact(integration_test);

    const run_integration_test_cmd = b.addRunArtifact(integration_test);
    const run_integration = b.step("test-integration", "Run integration test suite");
    run_integration.dependOn(&run_integration_test_cmd.step);

    // VM Profiler
    const vm_profiler = b.addExecutable(.{
        .name = "vm_profiler",
        .root_module = b.createModule(.{
            .root_source_file = b.path("benchmarks/vm_profiler.zig"),
            .target = target,
            .optimize = .ReleaseFast,
            .imports = &.{
                .{ .name = "ghostlang", .module = mod },
            },
        }),
    });
    vm_profiler.root_module.addOptions("build_options", build_options);
    b.installArtifact(vm_profiler);

    const run_vm_profiler_cmd = b.addRunArtifact(vm_profiler);
    const run_profile = b.step("profile", "Run VM performance profiler");
    run_profile.dependOn(&run_vm_profiler_cmd.step);

    // Plugin scenarios test
    const plugin_scenarios = b.addExecutable(.{
        .name = "plugin_scenarios",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/plugin_scenarios.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "ghostlang", .module = mod },
            },
        }),
    });
    plugin_scenarios.root_module.addOptions("build_options", build_options);
    b.installArtifact(plugin_scenarios);

    const run_plugin_scenarios_cmd = b.addRunArtifact(plugin_scenarios);
    const run_scenarios = b.step("test-plugins", "Run plugin scenario tests");
    run_scenarios.dependOn(&run_plugin_scenarios_cmd.step);

    // C-style syntax test
    const c_style_test = b.addExecutable(.{
        .name = "c_style_syntax_test",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/c_style_syntax_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "ghostlang", .module = mod },
            },
        }),
    });
    c_style_test.root_module.addOptions("build_options", build_options);
    b.installArtifact(c_style_test);

    const run_c_style_test_cmd = b.addRunArtifact(c_style_test);
    const run_c_style = b.step("test-c-style", "Run C-style syntax tests");
    run_c_style.dependOn(&run_c_style_test_cmd.step);

    // String and pattern matching benchmark
    const string_bench = b.addExecutable(.{
        .name = "string_bench",
        .root_module = b.createModule(.{
            .root_source_file = b.path("benchmarks/string_bench.zig"),
            .target = target,
            .optimize = .ReleaseFast,
            .imports = &.{
                .{ .name = "ghostlang", .module = mod },
            },
        }),
    });
    string_bench.root_module.addOptions("build_options", build_options);
    b.installArtifact(string_bench);

    const run_string_bench_cmd = b.addRunArtifact(string_bench);
    const run_string_bench = b.step("bench-string", "Run string and pattern matching benchmarks");
    run_string_bench.dependOn(&run_string_bench_cmd.step);

    // Just like flags, top level steps are also listed in the `--help` menu.
    //
    // The Zig build system is entirely implemented in userland, which means
    // that it cannot hook into private compiler APIs. All compilation work
    // orchestrated by the build system will result in other Zig compiler
    // subcommands being invoked with the right flags defined. You can observe
    // these invocations when one fails (or you pass a flag to increase
    // verbosity) to validate assumptions and diagnose problems.
    //
    // Lastly, the Zig build system is relatively simple and self-contained,
    // and reading its source code will allow you to master it.
}
