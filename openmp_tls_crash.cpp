/*
 * Minimal reproducer for OpenMP TLS cleanup crash on MATLAB exit
 *
 * Bug report: Segmentation fault occurs when exiting MATLAB after running
 * a MEX file that uses OpenMP on macOS ARM64 (Apple Silicon).
 *
 * Environment where bug occurs:
 *   - macOS (tested on macOS 26.1 Tahoe)
 *   - Apple Silicon (M1/M2/M3, ARM64)
 *   - MATLAB R2024b, R2025a, R2025b, R2026a (prerelease)
 *
 * Environment where bug does NOT occur:
 *   - MATLAB R2023b, R2024a (same macOS/ARM64 setup)
 *   - Other platforms (Linux, Windows, Intel Mac)
 *
 * The crash occurs only at MATLAB exit, not during MEX execution.
 * The MEX function itself completes successfully.
 *
 * Root cause: OpenMP runtime registers per-thread cleanup handlers for
 * thread-local storage (TLS). When the MEX library is unloaded before
 * the threads fully terminate, the TLS cleanup crashes.
 *
 * Compilation (from MATLAB command window, using GCC from Homebrew):
 *   mex CXX="/opt/homebrew/bin/g++-15" CXXFLAGS="-fPIC -fopenmp" LDFLAGS="-fopenmp" openmp_tls_crash.cpp
 *
 * Note: Do NOT use $CXXFLAGS/$LDFLAGS as they contain macOS Clang flags (-fobjc-arc) that GCC doesn't understand.
 *
 * Reproduction steps:
 *   1. Compile the MEX file
 *   2. Run in MATLAB: openmp_tls_crash(1000000)
 *   3. Exit MATLAB: exit
 *   4. Observe segmentation fault on exit
 *
 * Alternative one-liner to reproduce:
 *   /Applications/MATLAB_R2025b.app/bin/matlab -nodisplay -batch "openmp_tls_crash(1000000)"
 *
 * Workaround: Use mexLock() to prevent MEX unloading (uncomment below)
 */

#include "mex.h"
#include <omp.h>
#include <cmath>

void mexFunction(int nlhs, mxArray *plhs[], int nrhs, const mxArray *prhs[])
{
    /*
     * WORKAROUND: Uncomment the following block to prevent the crash.
     * mexLock() prevents the MEX file from being unloaded, ensuring
     * the OpenMP runtime remains in memory during TLS cleanup at exit.
     *
     * static bool locked = false;
     * if (!locked)
     * {
     *     mexLock();
     *     locked = true;
     * }
     */

    // Input validation
    if (nrhs != 1)
        mexErrMsgIdAndTxt("OpenMP:TLS:nrhs", "One input required: array size N");

    if (!mxIsScalar(prhs[0]))
        mexErrMsgIdAndTxt("OpenMP:TLS:notScalar", "Input must be a scalar");

    // Get array size
    mwSize N = static_cast<mwSize>(mxGetScalar(prhs[0]));

    // Create output array
    plhs[0] = mxCreateDoubleMatrix(1, 1, mxREAL);
    double *result = mxGetPr(plhs[0]);

    // Allocate work array
    double *data = static_cast<double*>(mxMalloc(N * sizeof(double)));

    // Initialize data (sequential)
    for (mwSize i = 0; i < N; i++)
        data[i] = static_cast<double>(i + 1);

    // Parallel computation using OpenMP - this triggers TLS usage
    double sum = 0.0;
    #pragma omp parallel for reduction(+:sum)
    for (mwSize i = 0; i < N; i++)
    {
        sum += std::sin(data[i]) * std::cos(data[i]);
    }

    *result = sum;

    // Report OpenMP info
    mexPrintf("OpenMP threads used: %d\n", omp_get_max_threads());
    mexPrintf("Computation result: %f\n", sum);
    mexPrintf("MEX function completed successfully.\n");
    mexPrintf("The crash will occur when MATLAB exits (not now).\n");

    mxFree(data);
}
