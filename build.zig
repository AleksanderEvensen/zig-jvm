const std = @import("std");

pub fn build(b: *std.Build) void {
    // The Main Program
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const exe = b.addExecutable(.{
        .name = "zig-jvm",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(exe);

    // Add Java compilation step
    const compile_java = b.addSystemCommand(&.{ "javac", "-d", "java-out", "./java/Main.java" });
    exe.step.dependOn(&compile_java.step);

    // Adding modules
    const mod_javap = b.addModule("java-parser", .{
        .root_source_file = b.path("modules/java-parser/lib.zig"),
        .optimize = optimize,
        .target = target,
    });

    exe.root_module.addImport("java-parser", mod_javap);

    // Add run command
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
