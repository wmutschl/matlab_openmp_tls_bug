% test_crash.m - Test script for OpenMP TLS crash reproducer
%
% Run this script, then exit MATLAB to observe the crash.
% The crash occurs on exit, not during execution.

fprintf('=== OpenMP TLS Crash Reproducer ===\n\n');

% Display environment info
fprintf('MATLAB Version: %s\n', version);
fprintf('Architecture: %s\n', computer('arch'));
if ismac
    [~, os_info] = system('sw_vers -productVersion');
    fprintf('macOS Version: %s', os_info);
end
fprintf('\n');

% Compile if needed
if ~isfile('openmp_tls_crash.mexmaca64') && ~isfile('openmp_tls_crash.mexmaci64')
    fprintf('MEX file not found. Compiling...\n');
    compile_mex;
    fprintf('\n');
end

% Run the MEX function
fprintf('Running MEX function...\n');
fprintf('----------------------------------------\n');
result = openmp_tls_crash(1000000);
fprintf('----------------------------------------\n');
fprintf('Returned value: %f\n\n', result);

fprintf('MEX function executed successfully.\n');
fprintf('The crash will occur when you exit MATLAB.\n\n');
fprintf('To exit and trigger the crash, type: exit\n');
