/*
 * Fixed version of the OpenMP TLS crash reproducer
 *
 * This version includes the mexLock() workaround that prevents the crash
 * by keeping the MEX file (and OpenMP runtime) loaded in memory.
 *
 * The fix is conditionally compiled only for macOS ARM64 MATLAB builds.
 */

#include "mex.h"
#include <omp.h>
#include <cmath>

void mexFunction(int nlhs, mxArray *plhs[], int nrhs, const mxArray *prhs[])
{
#if defined(__APPLE__) && defined(MATLAB_MEX_FILE)
    // Prevent MEX from being unloaded to avoid TLS cleanup crash
    static bool locked = false;
    if (!locked)
    {
        mexLock();
        locked = true;
        mexPrintf("FIX APPLIED: mexLock() called to prevent unloading.\n");
    }
#endif

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

    mxFree(data);
}
