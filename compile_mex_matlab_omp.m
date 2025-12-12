% compile_mex_matlab_omp.m - RECOMMENDED: Compile with MATLAB's bundled OpenMP
%
% This is the RECOMMENDED compilation method for OpenMP MEX files on macOS ARM64.
%
% Uses Apple Clang and links against MATLAB's internal OpenMP library
% (libomp/libiomp5) instead of external implementations (Homebrew, GCC).
%
% This follows the advice from MathWorks (MATLAB Answers #237411):
%   "Link against Intel's OpenMP libraries, which are included with MATLAB."
%
% Requires: brew install libomp (for the omp.h header only)

fprintf('=== Compiling with Apple Clang + MATLAB OpenMP ===\n');

% Get MATLAB paths
matlab_root = matlabroot;
matlab_arch = computer('arch');
matlab_lib_dir = fullfile(matlab_root, 'bin', matlab_arch);
matlab_include_dir = fullfile(matlab_root, 'extern', 'include');

% Find MATLAB's OpenMP library
omp_lib = '';
if isfile(fullfile(matlab_lib_dir, 'libomp.dylib'))
    omp_lib = 'omp';
    fprintf('Found MATLAB OpenMP: libomp.dylib\n');
elseif isfile(fullfile(matlab_lib_dir, 'libiomp5.dylib'))
    omp_lib = 'iomp5';
    fprintf('Found MATLAB OpenMP: libiomp5.dylib\n');
else
    warning('Could not find libomp.dylib or libiomp5.dylib in MATLAB bin directory.');
    fprintf('Falling back to -lomp (hope linker finds it)\n');
    omp_lib = 'omp';
end

% We still need the header <omp.h>. MATLAB typically doesn't ship it.
% We'll use Homebrew's libomp headers for compilation.
libomp_prefix = '/opt/homebrew/opt/libomp';
if ~isfolder(libomp_prefix)
    libomp_prefix = '/usr/local/opt/libomp';
end
if ~isfolder(libomp_prefix)
    error(['libomp headers not found. Please install via Homebrew to get <omp.h>:\n' ...
           '  brew install libomp']);
end

% Output MEX file name
if strcmp(matlab_arch, 'maca64')
    mex_ext = 'mexmaca64';
elseif strcmp(matlab_arch, 'maci64')
    mex_ext = 'mexmaci64';
else
    mex_ext = ['mex' matlab_arch];
end
output_file = ['openmp_tls_crash.' mex_ext];

% Compiler
clangpp = '/usr/bin/clang++';

% Step 1: Compile object file
% Use Homebrew include path for <omp.h>
compile_cmd = sprintf(['%s -c -fPIC -Xclang -fopenmp -std=c++17 ' ...
    '-I"%s" -I"%s/include" ' ...
    '-DMATLAB_MEX_FILE ' ...
    '-o openmp_tls_crash.o openmp_tls_crash.cpp'], ...
    clangpp, matlab_include_dir, libomp_prefix);

fprintf('Compiling: %s\n', compile_cmd);
[status, output] = system(compile_cmd);
if status ~= 0
    error('Compilation failed:\n%s', output);
end

% Step 2: Link against MATLAB's OpenMP library
% We put matlab_lib_dir FIRST in -L to ensure we pick up MATLAB's lib
link_cmd = sprintf(['%s -shared ' ...
    '-L"%s" -l%s ' ...
    '-L"%s" -Wl,-rpath,"%s" ' ...
    '-lmx -lmex -lmat ' ...
    '-o %s openmp_tls_crash.o'], ...
    clangpp, matlab_lib_dir, omp_lib, ...
    matlab_lib_dir, matlab_lib_dir, output_file);

fprintf('Linking: %s\n', link_cmd);
[status, output] = system(link_cmd);
if status ~= 0
    error('Linking failed:\n%s', output);
end

% Clean up object file
delete('openmp_tls_crash.o');

fprintf('Compilation successful!\n\n');
fprintf('This MEX links against MATLAB''s bundled libomp (recommended solution).\n');
fprintf('To test:\n');
fprintf('  1. Run: openmp_tls_crash(1000000)\n');
fprintf('  2. Exit MATLAB: exit\n');
fprintf('  3. Verify NO crash occurs!\n');
