//! childtime provides a helper to run a subprocess, timing from `execve` to
//! the first write to `stdout`.

use std::{
    path::PathBuf,
    process::{Command, Stdio},
    time::Duration,
};

use tempfile::NamedTempFile;

struct TimeResult {
    user: Duration,
    system: Duration,
    perf_trace: PathBuf,
}

/// Runs the child process, collecting the time from `execve` to the first
/// write to `stdout`.
pub fn time(command: Command) -> Result<TimeResult, std::io::Error> {
    // We wrap the provided command in a `perf` invocation, and parse
    // the `perf` output.
    let trace_out = NamedTempFile::new()?;

    let mut wrapper = Command::new("perf");
    wrapper
        .arg("trace")
        .arg("-o")
        .arg(trace_out.path())
        .arg(command.get_program())
        .args(command.get_args())
        .stdout(Stdio::piped())
        .stdin(Stdio::null())
        .stderr(Stdio::null());
    if let Some(path) = command.get_current_dir() {
        wrapper.current_dir(path);
    };

    // Run the command:
    let completion = wrapper.output()?;
    // Check output
    // Extract timings from trace_out

    unimplemented!()
}
