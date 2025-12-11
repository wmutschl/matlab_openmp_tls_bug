% compile_mex_clang_fixed.m - Compile the FIXED version with Apple Clang/libomp
%
% This compiles openmp_tls_crash_fixed.cpp which includes the mexLock() fix.
% Note: The libomp crash is a different issue (mutex init failure), so
% mexLock() may not fix it, but let's test to confirm.
%
% Requires: brew install libomp

fprintf('=== Compiling FIXED version with Apple Clang + libomp ===\n');

% Check if libomp is installed
libomp_prefix = '/opt/homebrew/opt/libomp';
if ~isfolder(libomp_prefix)
    libomp_prefix = '/usr/local/opt/libomp';
end
if ~isfolder(libomp_prefix)
    error(['libomp not found. Please install via Homebrew:\n' ...
           '  brew install libomp']);
end

fprintf('Using libomp from: %s\n', libomp_prefix);

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

% Use Apple Clang (system default)
clangpp = '/usr/bin/clang++';
fprintf('Using compiler: %s\n', clangpp);

% Step 1: Compile object file
compile_cmd = sprintf(['%s -c -fPIC -Xclang -fopenmp -std=c++17 ' ...
    '-I"%s" -I"%s/include" ' ...
    '-DMATLAB_MEX_FILE ' ...
    '-o openmp_tls_crash_fixed.o openmp_tls_crash_fixed.cpp'], ...
    clangpp, matlab_include_dir, libomp_prefix);

fprintf('Compiling: %s\n', compile_cmd);
[status, output] = system(compile_cmd);
if status ~= 0
    error('Compilation failed:\n%s', output);
end

% Step 2: Link as shared library
link_cmd = sprintf(['%s -shared ' ...
    '-L"%s/lib" -lomp ' ...
    '-L"%s" -Wl,-rpath,"%s" ' ...
    '-lmx -lmex -lmat ' ...
    '-o %s openmp_tls_crash_fixed.o'], ...
    clangpp, libomp_prefix, matlab_lib_dir, matlab_lib_dir, output_file);

fprintf('Linking: %s\n', link_cmd);
[status, output] = system(link_cmd);
if status ~= 0
    error('Linking failed:\n%s', output);
end

% Clean up object file
delete('openmp_tls_crash_fixed.o');

fprintf('Compilation successful!\n\n');
fprintf('To test the FIX with Apple Clang/libomp:\n');
fprintf('  1. Run: openmp_tls_crash_fixed(1000000)\n');
fprintf('  2. Exit MATLAB: exit\n');
fprintf('  3. Check if crash is prevented\n');
fprintf('\nNote: The libomp crash occurs during execution (mutex init),\n');
fprintf('      so mexLock() may not help for that specific issue.\n');
