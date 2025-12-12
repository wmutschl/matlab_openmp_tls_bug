% test_crash.m - Test script for OpenMP TLS crash reproducer
%
% This script demonstrates the crash and the solution.
%
% Usage:
%   test_crash         - Test the crash case (GCC/libgomp, crashes on exit)
%   test_crash('fix')  - Test the solution (MATLAB's libomp, no crash)

function test_crash(mode)

if nargin < 1
    mode = 'crash';
end

fprintf('=== OpenMP TLS Crash Reproducer ===\n\n');

% Display environment info
fprintf('MATLAB Version: %s\n', version);
fprintf('Architecture: %s\n', computer('arch'));
if ismac
    [~, os_info] = system('sw_vers -productVersion');
    fprintf('macOS Version: %s', os_info);
end
fprintf('\n');

% Determine which test to run
if strcmpi(mode, 'fix') || strcmpi(mode, 'solution')
    fprintf('Mode: SOLUTION (using MATLAB''s bundled libomp)\n\n');
    compile_script = 'compile_mex_matlab_omp';
    expect_crash = false;
else
    fprintf('Mode: CRASH REPRODUCTION (using GCC/libgomp)\n\n');
    compile_script = 'compile_mex';
    expect_crash = true;
end

% Compile
fprintf('Compiling with %s...\n', compile_script);
eval(compile_script);
fprintf('\n');

% Run the MEX function
fprintf('Running MEX function...\n');
fprintf('----------------------------------------\n');
result = openmp_tls_crash(1000000);
fprintf('----------------------------------------\n');
fprintf('Returned value: %f\n\n', result);

fprintf('MEX function executed successfully.\n\n');

if expect_crash
    fprintf('*** CRASH EXPECTED ***\n');
    fprintf('The crash will occur when you exit MATLAB.\n');
    fprintf('To exit and trigger the crash, type: exit\n\n');
    fprintf('To test the SOLUTION instead, run: test_crash(''fix'')\n');
else
    fprintf('*** NO CRASH EXPECTED ***\n');
    fprintf('This uses MATLAB''s bundled libomp (recommended solution).\n');
    fprintf('You can safely exit MATLAB: exit\n\n');
    fprintf('To test the CRASH case, run: test_crash(''crash'')\n');
end

end
