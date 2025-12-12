% compile_mex_fixed.m - Compile with GCC/libgomp + mexLock workaround
%
% This compiles openmp_tls_crash_fixed.cpp which includes the mexLock() fix.
% The mexLock() workaround prevents the exit crash by keeping the MEX loaded.
%
% RECOMMENDED: Use compile_mex_matlab_omp.m instead (no code changes needed).
%
% Use this workaround only if you must use GCC (e.g., for C++ features
% or other libraries that require GCC).

fprintf('=== Compiling FIXED version with GCC + libgomp ===\n');

% Detect GCC version (try common Homebrew installations)
if strcmp(mexext,'mexmaca64')
    gcc_paths = {
        '/opt/homebrew/bin/g++-15'
        '/opt/homebrew/bin/g++-14'
        '/opt/homebrew/bin/g++-13'
        '/opt/homebrew/bin/g++-12'
    };
elseif strcmp(mexext,'mexmaci64')
    gcc_paths = {
        '/usr/local/bin/g++-15'
        '/usr/local/bin/g++-14'
        '/usr/local/bin/g++-13'
        '/usr/local/bin/g++-12'
    };
end
gpp = '';
for i = 1:length(gcc_paths)
    if isfile(gcc_paths{i})
        gpp = gcc_paths{i};
        break;
    end
end

if isempty(gpp)
    error(['Could not find GCC. Please install via Homebrew:\n' ...
           '  brew install gcc\n']);
end

fprintf('Using compiler: %s\n', gpp);

% Get MATLAB paths
matlab_root = matlabroot;
matlab_arch = computer('arch');
matlab_lib_dir = fullfile(matlab_root, 'bin', matlab_arch);
matlab_include_dir = fullfile(matlab_root, 'extern', 'include');

% Output MEX file name
if strcmp(matlab_arch, 'maca64')
    mex_ext = 'mexmaca64';
elseif strcmp(matlab_arch, 'maci64')
    mex_ext = 'mexmaci64';
else
    mex_ext = ['mex' matlab_arch];
end
output_file = ['openmp_tls_crash_fixed.' mex_ext];

% Step 1: Compile object file
compile_cmd = sprintf(['%s -c -fPIC -fopenmp -std=c++17 ' ...
    '-I"%s" ' ...
    '-DMATLAB_MEX_FILE ' ...
    '-o openmp_tls_crash_fixed.o openmp_tls_crash_fixed.cpp'], ...
    gpp, matlab_include_dir);

fprintf('Compiling: %s\n', compile_cmd);
[status, output] = system(compile_cmd);
if status ~= 0
    error('Compilation failed:\n%s', output);
end

% Step 2: Link as shared library
link_cmd = sprintf(['%s -shared -fopenmp ' ...
    '-L"%s" -Wl,-rpath,"%s" ' ...
    '-lmx -lmex -lmat ' ...
    '-o %s openmp_tls_crash_fixed.o'], ...
    gpp, matlab_lib_dir, matlab_lib_dir, output_file);

fprintf('Linking: %s\n', link_cmd);
[status, output] = system(link_cmd);
if status ~= 0
    error('Linking failed:\n%s', output);
end

% Clean up object file
delete('openmp_tls_crash_fixed.o');

fprintf('Compilation successful!\n\n');
fprintf('To test the FIX with GCC/libgomp:\n');
fprintf('  1. Run: openmp_tls_crash_fixed(1000000)\n');
fprintf('  2. Exit MATLAB: exit\n');
fprintf('  3. Verify NO crash occurs!\n');
fprintf('\nNote: compile_mex_matlab_omp.m is the recommended solution (no code changes needed).\n');
