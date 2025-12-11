# OpenMP TLS Cleanup Crash on MATLAB Exit (macOS ARM64)

## Bug Summary

MATLAB crashes with a segmentation fault **when exiting** after running a MEX file that uses OpenMP on macOS ARM64 (Apple Silicon). The crash occurs only at exit, not during the MEX execution—the computation completes successfully.
This is related to an issue we faced in [Dynare](https://git.dynare.org/Dynare/dynare/-/issues/2000), this repository is a minimal reproducer for the issue.

## Affected Versions

| MATLAB Version | macOS ARM64 | macOS Intel | Linux | Windows |
|----------------|-------------|-------------|-------|---------|
| R2023b         | ✅ OK       | ?        | ? | ?   |
| R2024a         | ✅ OK       | ?        | ? | ?   |
| R2024b         | ❌ CRASH    | ?         | ? | ?   |
| R2025a         | ❌ CRASH    | ?         | ? | ?   |
| R2025b         | ❌ CRASH    | ?         | ? | ?   |
| R2026a (pre)   | ❌ CRASH    | ?         | ? | ?   |

## Environment

- **OS**: macOS 26.x (Tahoe) on Apple Silicon
- **Architecture**: ARM64 (M2 Max and M4 Pro)
- **Compiler**: GCC with libgomp (e.g., `g++-15` from Homebrew)

## OpenMP Implementation Comparison

Both major OpenMP implementations fail on macOS ARM64 with MATLAB R2024b+:

| OpenMP Implementation | Behavior |
|-----------------------|----------|
| GCC + libgomp         | ✅ Executes successfully, ❌ Crashes on **exit** (TLS cleanup)   |
| Apple Clang + libomp  | ❌ Crashes during **execution** (mutex init: `Invalid argument`) |

This suggests a fundamental issue with how MATLAB R2024b+ handles threading libraries on macOS ARM64.

## Files

### Bug Reproducers (without fix)
- `openmp_tls_crash.cpp` - Minimal MEX reproducer (crashes)
- `compile_mex.m` - Compilation script (GCC/libgomp)
- `compile_mex_clang.m` - Compilation script (Apple Clang/libomp)
- `test_crash.m` - MATLAB test script

### Fixed Versions (with mexLock workaround)
- `openmp_tls_crash_fixed.cpp` - MEX with conditional mexLock() fix
- `compile_mex_fixed.m` - Compile fixed version (GCC/libgomp)
- `compile_mex_clang_fixed.m` - Compile fixed version (Apple Clang/libomp)

## Quick Reproduction

### Option 1: One-liner (crashes on exit)

```bash
# in a terminal
cd /path/to/this/folder
/Applications/MATLAB_R2025b.app/bin/matlab -nodisplay -batch "run('compile_mex.m'); openmp_tls_crash(1000000)"
ls $HOME
```
The crash dump pollutes the User's home directory.

### Option 2: Interactive

```matlab
% In MATLAB
cd /path/to/this/folder
compile_mex
openmp_tls_crash(1000000)  % Runs successfully
exit                       % CRASH HERE -> dumps the crash dump in the User's home directory
```

## Compilation

The MEX file must be compiled with OpenMP support using GCC:

```matlab
% Using GCC from Homebrew
mex CXX="/opt/homebrew/bin/g++-15" ...
    CXXFLAGS="-fPIC -fopenmp" ...
    LDFLAGS="-fopenmp" ...
    openmp_tls_crash.cpp
```

**Note**: Do NOT inherit `$CXXFLAGS`/`$LDFLAGS` as MATLAB's defaults contain macOS Clang-specific flags (`-fobjc-arc`) that GCC doesn't understand.

Or use the provided `compile_mex.m` script which auto-detects GCC.

## Crash Logs

### GCC + libgomp (crash on exit)

```
OpenMP threads used: 12
Computation result: -0.124602
MEX function completed successfully.
The crash will occur when MATLAB exits (not now).

--------------------------------------------------------------------------------
          Segmentation violation detected at 2025-12-11 09:25:45 +0100
--------------------------------------------------------------------------------

Configuration:
  MATLAB Architecture      : maca64
  MATLAB Version           : 25.2.0.3042426 (R2025b) Update 1
  Operating System         : Mac OS Version 26.1 (Build 25B78)

Abnormal termination:
Segmentation violation

Current Thread: 'MCR 0 interpreter thread'

Stack Trace (from fault):
[  0] libmwfl.dylib _ZN10foundation4core4diag15stacktrace_base7captureE...
...
[  6] libsystem_platform.dylib _sigtramp
[  7] libsystem_pthread.dylib _pthread_tsd_cleanup+00000488  <-- CRASH HERE
[  8] libsystem_pthread.dylib _pthread_exit
[  9] libsystem_pthread.dylib _pthread_start
```

### Apple Clang + libomp (crash during execution)

```
OMP: Error #179: Function pthread_mutex_init failed:
OMP: System error #22: Invalid argument
[SIGSEGV]
```

## Root Cause Analysis

The crash occurs in `_pthread_tsd_cleanup` during thread-local storage (TLS) cleanup.

OpenMP (libgomp) registers per-thread cleanup handlers for its thread-local data. When MATLAB unloads the MEX file, the OpenMP runtime library is also unloaded. However, if the cleanup handlers are still registered when the threads terminate, they point to unloaded memory, causing a segmentation fault.

This appears to be a regression in how MATLAB R2024b+ handles MEX unloading or thread cleanup ordering on macOS ARM64.

## Workaround

Use `mexLock()` to prevent the MEX file from being unloaded. The fix should be conditionally compiled only for the affected platform:

```cpp
void mexFunction(int nlhs, mxArray *plhs[], int nrhs, const mxArray *prhs[])
{
#if defined(__APPLE__) && defined(__aarch64__) && defined(MATLAB_MEX_FILE)
    // Prevent MEX from being unloaded to avoid TLS cleanup crash (see issue #2000)
    static bool locked = false;
    if (!locked)
    {
        mexLock();
        locked = true;
    }
#endif

    // ... rest of function
}
```

This keeps the MEX file (and the OpenMP runtime) in memory, so the TLS cleanup handlers remain valid.

**Downside**: MEX files are no longer automatically reloaded when recompiled, which affects the development workflow.

### Testing the Fix

**Test with GCC/libgomp (should NOT crash):**
```bash
/Applications/MATLAB_R2025b.app/bin/matlab -nodisplay -batch "run('compile_mex_fixed.m'); openmp_tls_crash_fixed(1000000)"
```

**Test with Apple Clang/libomp:**
```bash
/Applications/MATLAB_R2025b.app/bin/matlab -nodisplay -batch "run('compile_mex_clang_fixed.m'); openmp_tls_crash_fixed(1000000)"
```

Note: The `mexLock()` fix resolves the GCC/libgomp exit crash. The Apple Clang/libomp crash occurs during execution (mutex initialization failure), which is a different issue that `mexLock()` does not address.

## Questions for MathWorks

1. Is this a known issue?
2. Was there a change in MEX unloading behavior or threading infrastructure in R2024b that could cause this?
3. Why do both OpenMP implementations (libgomp and libomp) fail on macOS ARM64?
4. Is there a recommended way to use OpenMP in MEX files on macOS ARM64?
5. Is `mexLock()` the officially recommended workaround for the libgomp crash?
6. Is a fix planned for a future release, because the prerelease of R2026a has the same issue.

## Related

- This issue affects any MEX file using OpenMP on macOS ARM64
- Both GCC/libgomp and Apple Clang/libomp have issues (different failure modes)
- The issue is specific to macOS ARM64; Intel Macs and other platforms appear unaffected
- Regression introduced in MATLAB >=R2024b; R2023b and R2024a work correctly
