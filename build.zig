const std = @import("std");
const emcc = @import("./emcc.zig");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) !void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    const test_filters = b.option(
        []const []const u8,
        "test-filter",
        "Skip tests that do not match any filter",
    ) orelse &[0][]const u8{};

    // const lib = b.addStaticLibrary(.{
    //     .name = "zigfish",
    //     // In this case the main source file is merely a path, however, in more
    //     // complicated build scripts, this could be a generated file.
    //     .root_source_file = b.path("src/lib/root.zig"),
    //     .target = target,
    //     .optimize = optimize,
    // });

    const zigfish = b.addModule("zigfish", .{
        .root_source_file = b.path("src/lib/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const uciModule = b.addModule("uci", .{
        .root_source_file = b.path("src/uci/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    uciModule.addImport("zigfish", zigfish);

    // This declares intent for the library to be installed into the standard
    // location when the user invokes the "install" step (the default step when
    // running `zig build`).
    // b.installArtifact(lib);

    const exe = b.addExecutable(.{
        .name = "zigfish-gui",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe.root_module.addImport("zigfish", zigfish);

    const raylib_dep = b.dependency("raylib-zig", .{
        .target = target,
        .optimize = optimize,
    });

    const raylib = raylib_dep.module("raylib"); // main raylib module
    const raygui = raylib_dep.module("raygui"); // raygui module
    const raylib_artifact = raylib_dep.artifact("raylib"); // raylib C library

    //web exports are completely separate
    if (target.query.os_tag == .emscripten) {
        // raylib_artifact.addIncludePath(raylib_dep.path("src"));
        // raylib_artifact.addIncludePath(b.path("./tmp/emscripten/cache/sysroot/include/")); // force an include....
        // raylib_artifact.addIncludePath(b.path("./result/share/emscripten/cache/sysroot/include/")); // force an include....
        const includes = b.pathJoin(&.{ b.sysroot.?, "cache/sysroot/include" });
        defer b.allocator.free(includes);

        raylib_artifact.addIncludePath(b.path(includes));
        // raylib_artifact.addIncludePath(raygui_dep.path("src"));

        const exe_lib = emcc.compileForEmscripten(b, "zig-fish-wasm", "src/main.zig", target, optimize);

        exe_lib.linkLibrary(raylib_artifact);
        exe_lib.root_module.addImport("raylib", raylib);
        exe_lib.root_module.addImport("zigfish", zigfish);
        exe_lib.root_module.single_threaded = false;
        // exe_lib.
        // exe_lib.linkLibC();

        // Note that raylib itself is not actually added to the exe_lib output file, so it also needs to be linked with emscripten.
        const link_step = try emcc.linkWithEmscripten(b, &[_]*std.Build.Step.Compile{ exe_lib, raylib_artifact });
        // link_step.addArg("-sMEMORY64=1");
        link_step.addArgs(&[_][]const u8{
            "-sGL_ENABLE_GET_PROC_ADDRESS", // what is this...
            "-sALLOW_MEMORY_GROWTH", // TODO: theres a warning with this and pthreads set, maybe need to mess with heap size?
            // "-sINITIAL_MEMORY=2147483648",
            // "--no-entry",
            "-pthread",
            // "-sPROXY_TO_PTHREAD=1",
            "-sUSE_OFFSET_CONVERTER", // https://ziggit.dev/t/why-suse-offset-converter-is-needed/4131/3
            "-sMINIFY_HTML=0", // npm was sad, nix build might make this work
            // "-sASSERTIONS=2", // error in console said do it for more info...
            "-sPTHREAD_POOL_SIZE=2",
            // https://emscripten.org/docs/tools_reference/settings_reference.html#modularize
            "-sMODULARIZE=1",
            "-sEXPORT_NAME=zigfish",
            // "--shell-file=zigfish.html",
            // add pictures
            "--embed-file",
            "resources/Chess_Pieces_Sprite.png",
            // "-gsource-map",
            // "-g",
        });
        // link_step.addArg("-sGL_ENABLE_GET_PROC_ADDRESS");
        // link_step.addArg("-sMINIFY_HTML=0");
        // link_step.addArg("-sASSERTIONS");
        // link_step.addArg("--embed-file");
        // link_step.addArg("resources/");

        b.getInstallStep().dependOn(&link_step.step);

        // b.installArtifact(&link_step.step);
        const run_step = try emcc.emscriptenRunStep(b);
        run_step.step.dependOn(&link_step.step);
        const run_option = b.step("run", "Run zig-fish-wasm");
        run_option.dependOn(&run_step.step);
        return;
    }

    // exe.linkLibrary(lib);
    // exe.linkLibrary(lib);

    exe.linkLibrary(raylib_artifact);
    exe.root_module.addImport("raylib", raylib);
    exe.root_module.addImport("raygui", raygui);

    const mecha_dep = b.dependency("mecha", .{
        .target = target,
        .optimize = optimize,
    });

    const mecha = mecha_dep.module("mecha");
    exe.root_module.addImport("mecha", mecha);

    // This declares intent for the executable to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).
    // TODO: make this conditional if i want to be able to install the gui
    // b.installArtifact(exe);

    // This *creates* a Run step in the build graph, to be executed when another
    // step is evaluated that depends on it. The next line below will establish
    // such a dependency.
    const run_cmd = b.addRunArtifact(exe);

    // By making the run step depend on the install step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    // This is not necessary, however, if the application depends on other installed
    // files, this ensures they will be present and in the expected location.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    const lib_unit_tests = b.addTest(.{ .name = "lib-tests", .root_source_file = b.path("src/lib/root.zig"), .target = target, .optimize = optimize, .filters = test_filters });
    lib_unit_tests.root_module.addImport("mecha", mecha);

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const exe_unit_tests = b.addTest(.{ .name = "exe-tests", .root_source_file = b.path("src/main.zig"), .target = target, .optimize = optimize, .filters = test_filters });
    exe_unit_tests.linkLibrary(raylib_artifact);
    exe_unit_tests.root_module.addImport("raylib", raylib);
    exe_unit_tests.root_module.addImport("raygui", raygui);
    exe_unit_tests.root_module.addImport("zigfish", zigfish);

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const exe_check = b.addExecutable(.{
        .name = "foo",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe_check.linkLibrary(raylib_artifact);
    exe_check.root_module.addImport("raylib", raylib);
    exe_check.root_module.addImport("raygui", raygui);
    exe_check.root_module.addImport("zigfish", zigfish);
    exe_check.root_module.addImport("uci", uciModule);
    lib_unit_tests.root_module.addImport("mecha", mecha);

    // Any other code to define dependencies would
    // probably be here.

    // These two lines you might want to copy
    // (make sure to rename 'exe_check')
    const check = b.step("check", "Check if foo compiles");
    check.dependOn(&exe_check.step);

    const exe_uci = b.addExecutable(.{
        .name = "zigfish-uci",
        .root_source_file = b.path("src/main_uci.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_uci.root_module.addImport("mecha", mecha);
    exe_uci.root_module.addImport("zigfish", zigfish);
    exe_uci.root_module.addImport("uci", uciModule);

    const exe_uci_unit_tests = b.addTest(.{ .name = "uci-tests", .root_source_file = b.path("src/uci/root.zig"), .target = target, .optimize = optimize, .filters = test_filters });
    exe_uci_unit_tests.root_module.addImport("zigfish", zigfish);

    const run_uci_unit_tests = b.addRunArtifact(exe_uci_unit_tests);

    b.installArtifact(exe_uci);

    // This *creates* a Run step in the build graph, to be executed when another
    // step is evaluated that depends on it. The next line below will establish
    // such a dependency.
    const run_cmd_uci = b.addRunArtifact(exe_uci);

    // By making the run step depend on the install step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    // This is not necessary, however, if the application depends on other installed
    // files, this ensures they will be present and in the expected location.
    run_cmd_uci.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd_uci.addArgs(args);
    }

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    const run_uci_step = b.step("run-uci", "Run uci");
    run_uci_step.dependOn(&run_cmd_uci.step);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
    test_step.dependOn(&run_exe_unit_tests.step);
    test_step.dependOn(&run_uci_unit_tests.step);
}
