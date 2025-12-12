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
 *   compile_mex
 *   (or see compile_mex.m for manual steps)
 *
 * Recommended Fix: Use MATLAB's bundled OpenMP library.
 *   See compile_mex_matlab_omp.m
 *
 * Workaround (if must use GCC): Use mexLock() to prevent MEX unloading.
 *   See openmp_tls_crash_fixed.cpp
 */

#include "mex.h"
#include <omp.h>
#include <cmath>

void mexFunction(int nlhs, mxArray *plhs[], int nrhs, const mxArray *prhs[])
{
    /*
     * Note: This is the minimal reproducer.
     * For the fixed version with mexLock(), see openmp_tls_crash_fixed.cpp
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
