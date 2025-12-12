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
- **Compilers tested**:
  - GCC with libgomp (e.g., `g++-15` from Homebrew) - crashes
  - Apple Clang with Homebrew libomp - crashes
  - Apple Clang with MATLAB's bundled libomp - **works**

## OpenMP Implementation Comparison

| OpenMP Implementation | Behavior |
|-----------------------|----------|
| GCC + libgomp (Homebrew) | ✅ Executes successfully, ❌ Crashes on **exit** (TLS cleanup) |
| Apple Clang + libomp (Homebrew) | ❌ Crashes during **execution** (mutex init: `Invalid argument`) |
| Apple Clang + **MATLAB's libomp** | ✅ Works correctly, ✅ No crash on exit |

The key insight is that MATLAB bundles its own OpenMP library (`libomp.dylib`) and **linking against external OpenMP implementations causes incompatibilities**. See [MathWorks Solution](#solution-use-matlabs-bundled-openmp-recommended).

## Files

### Bug Reproducers (crash with external OpenMP)
- `openmp_tls_crash.cpp` - Minimal MEX reproducer
- `compile_mex.m` - Compilation script (GCC/libgomp) - **crashes on exit**
- `compile_mex_clang.m` - Compilation script (Apple Clang + Homebrew libomp) - **crashes during execution**
- `test_crash.m` - MATLAB test script (run `test_crash` or `test_crash('fix')`)

### Working Solution (Recommended: MATLAB's bundled OpenMP)
- `compile_mex_matlab_omp.m` - Compilation script using MATLAB's bundled libomp - **works correctly** (solves both crashes)

### Alternative Workaround (mexLock for GCC)
- `openmp_tls_crash_fixed.cpp` - MEX with conditional mexLock() fix
- `compile_mex_fixed.m` - Compile fixed version (GCC/libgomp) - **works** (prevents exit crash)
- `compile_mex_clang_fixed.m` - Compile fixed version (Apple Clang/Homebrew libomp) - **still crashes** (mutex error not fixed by lock)

## Quick Reproduction

### Reproduce the Crash (GCC/libgomp)

```bash
# One-liner (crashes on exit with code 137)
cd /path/to/this/folder
/Applications/MATLAB_R2025b.app/bin/matlab -nodisplay -batch "run('compile_mex.m'); openmp_tls_crash(1000000)"
# Crash dump will appear in $HOME
```

### Verify the Solution (MATLAB's libomp)

```bash
# One-liner (exits cleanly with code 0)
cd /path/to/this/folder
/Applications/MATLAB_R2025b.app/bin/matlab -nodisplay -batch "run('compile_mex_matlab_omp.m'); openmp_tls_crash(1000000)"
# No crash!
```

### Interactive Testing

```matlab
% In MATLAB
cd /path/to/this/folder

% Option A: Use the test script
test_crash           % Compile with GCC, crash on exit
test_crash('fix')    % Compile with MATLAB's libomp, no crash

% Option B: Manual testing
compile_mex                   % GCC/libgomp (crashes on exit)
compile_mex_matlab_omp        % MATLAB's libomp (works!)
openmp_tls_crash(1000000)     % Runs successfully
exit                          % Crash or clean exit depending on compilation
```

## Compilation

### Recommended: Use MATLAB's OpenMP (no crash)

```matlab
% Uses Apple Clang + MATLAB's bundled libomp
compile_mex_matlab_omp
```

### For Reproduction: GCC/libgomp (crashes on exit)

```matlab
% Using GCC from Homebrew - will crash on MATLAB exit
compile_mex
```

Or manually:
```matlab
mex CXX="/opt/homebrew/bin/g++-15" ...
    CXXFLAGS="-fPIC -fopenmp" ...
    LDFLAGS="-fopenmp" ...
    openmp_tls_crash.cpp
```

**Note**: Do NOT inherit `$CXXFLAGS`/`$LDFLAGS` as MATLAB's defaults contain macOS Clang-specific flags (`-fobjc-arc`) that GCC doesn't understand.

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

## Solution: Use MATLAB's Bundled OpenMP (Recommended)

MathWorks provides guidance on using OpenMP in MEX files in [MATLAB Answers #237411](https://de.mathworks.com/matlabcentral/answers/237411-can-i-make-use-of-openmp-in-my-matlab-mex-files). The key recommendation is:

> *"MATLAB uses Intel's OpenMP implementation. Linking your MEX-files against other OpenMP implementations, like Microsoft's or GNU's (libgomp), can lead to incompatibilities. It's recommended to link against Intel's OpenMP libraries, which are included with MATLAB."*

MATLAB R2024b+ on macOS ARM64 bundles its own OpenMP runtime:

```
$MATLABROOT/bin/maca64/libomp.dylib
$MATLABROOT/toolbox/eml/externalDependency/omp/maca64/include/omp.h
$MATLABROOT/toolbox/eml/externalDependency/omp/maca64/lib/libomp.dylib
```

### Compilation with MATLAB's OpenMP

Use Apple Clang and link against MATLAB's bundled `libomp.dylib`:

```bash
# Compile (use Homebrew's omp.h header or MATLAB's)
/usr/bin/clang++ -c -fPIC -Xclang -fopenmp -std=c++17 \
    -I"$MATLABROOT/extern/include" \
    -I"/opt/homebrew/opt/libomp/include" \
    -DMATLAB_MEX_FILE \
    -o openmp_tls_crash.o openmp_tls_crash.cpp

# Link against MATLAB's libomp (NOT Homebrew's)
# Note: Check for libomp.dylib or libiomp5.dylib in bin/maca64
/usr/bin/clang++ -shared \
    -L"$MATLABROOT/bin/maca64" -lomp \
    -L"$MATLABROOT/bin/maca64" -Wl,-rpath,"$MATLABROOT/bin/maca64" \
    -lmx -lmex -lmat \
    -o openmp_tls_crash.mexmaca64 openmp_tls_crash.o
```

Or use the provided script:

```matlab
compile_mex_matlab_omp
openmp_tls_crash(1000000)
exit  % No crash!
```

### Test Results

| Compilation Method | Exit Behavior |
|-------------------|---------------|
| `compile_mex.m` (GCC/libgomp) | ❌ Exit code 137, segfault in `_pthread_tsd_cleanup` |
| `compile_mex_clang.m` (Homebrew libomp) | ❌ Crash during execution |
| `compile_mex_matlab_omp.m` (MATLAB's libomp) | ✅ Exit code 0, clean exit |

**Advantages of this solution:**
- No code changes required (no `mexLock()`)
- MEX files properly unload/reload during development
- Follows MathWorks' official recommendation

**Requirements:**
- Apple Clang (system default `/usr/bin/clang++`)
- Homebrew's libomp for the `omp.h` header: `brew install libomp`
- MATLAB R2024b+ (which bundles `libomp.dylib`)

---

## Alternative Workaround: mexLock()

If you cannot switch compilers (e.g., must use GCC for other reasons), use `mexLock()` to prevent the MEX file from being unloaded:

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

**Downside**: MEX files are no longer automatically reloaded when recompiled, which affects the development workflow. You must call `clear mex` or restart MATLAB to pick up changes.

### Testing the mexLock Workaround

**Test with GCC/libgomp (should NOT crash):**
```bash
/Applications/MATLAB_R2025b.app/bin/matlab -nodisplay -batch "run('compile_mex_fixed.m'); openmp_tls_crash_fixed(1000000)"
```

Note: The `mexLock()` fix resolves the GCC/libgomp exit crash. The Apple Clang + Homebrew libomp crash occurs during execution (mutex initialization failure), which is a different issue that `mexLock()` does not address.

## Questions for MathWorks

1. Is this a known issue with external OpenMP implementations on macOS ARM64?
   * *Update: Yes, documented in MATLAB Answers #237411.*
2. Was there a change in MEX unloading behavior or threading infrastructure in R2024b that could cause this?
3. Is linking against MATLAB's bundled `libomp.dylib` the officially supported way to use OpenMP on macOS ARM64?
   * *Update: Yes, it is recommended to link against MATLAB's OpenMP libraries.*
4. Why does Homebrew's libomp fail during execution (mutex init: Invalid argument) while MATLAB's libomp works?
5. Should MATLAB document the location of the bundled OpenMP headers and libraries for MEX development?
6. Will future MATLAB releases continue to bundle `libomp.dylib` on macOS ARM64?

## Summary

| Approach | Compiler | OpenMP Library | Result |
|----------|----------|----------------|--------|
| External libgomp | GCC (Homebrew) | libgomp | ❌ Crash on exit |
| External libomp | Apple Clang | libomp (Homebrew) | ❌ Crash during execution |
| **MATLAB's libomp** | Apple Clang | libomp (MATLAB bundled) | ✅ Works |
| mexLock workaround | GCC (Homebrew) | libgomp | ✅ Works (with limitations) |

**Recommended solution**: Use Apple Clang with MATLAB's bundled `libomp.dylib` via `compile_mex_matlab_omp.m`.

## Related

- [MathWorks Answers #237411](https://de.mathworks.com/matlabcentral/answers/237411-can-i-make-use-of-openmp-in-my-matlab-mex-files) - Official guidance on OpenMP in MEX files
- [MathWorks Answers #125117](https://de.mathworks.com/matlabcentral/answers/125117-openmp-mex-files-static-tls-problem) - Discussion of static TLS problems with OpenMP MEX files
- [Dynare Issue #2000](https://git.dynare.org/Dynare/dynare/-/issues/2000) - Original issue that prompted this investigation
- This issue affects any MEX file using external OpenMP libraries on macOS ARM64
- The issue is specific to macOS ARM64; Intel Macs and other platforms appear unaffected
- Regression introduced in MATLAB ≥R2024b; R2023b and R2024a work correctly with external OpenMP
