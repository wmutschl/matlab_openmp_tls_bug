% compile_mex.m - Compile the OpenMP TLS crash reproducer (GCC/libgomp)
%
% WARNING: MEX files compiled with this script will crash on MATLAB exit!
% The crash occurs during TLS cleanup when MATLAB unloads the MEX file.
%
% RECOMMENDED: Use compile_mex_matlab_omp.m instead, which links against
% MATLAB's bundled libomp and works correctly.
%
% Requires GCC with OpenMP (libgomp) installed via Homebrew.

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
           '  brew install gcc\n' ...
           'Then update gcc_paths in this script if needed.']);
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
output_file = ['openmp_tls_crash.' mex_ext];

% Build compile command manually to avoid MATLAB's mex injecting incompatible flags
% Step 1: Compile object file
compile_cmd = sprintf(['%s -c -fPIC -fopenmp -std=c++17 ' ...
    '-I"%s" ' ...
    '-DMATLAB_MEX_FILE ' ...
    '-o openmp_tls_crash.o openmp_tls_crash.cpp'], ...
    gpp, matlab_include_dir);

fprintf('Compiling: %s\n', compile_cmd);
[status, output] = system(compile_cmd);
if status ~= 0
    error('Compilation failed:\n%s', output);
end

% Step 2: Link as shared library (bundle on macOS)
link_cmd = sprintf(['%s -shared -fopenmp ' ...
    '-L"%s" -Wl,-rpath,"%s" ' ...
    '-lmx -lmex -lmat ' ...
    '-o %s openmp_tls_crash.o'], ...
    gpp, matlab_lib_dir, matlab_lib_dir, output_file);

fprintf('Linking: %s\n', link_cmd);
[status, output] = system(link_cmd);
if status ~= 0
    error('Linking failed:\n%s', output);
end

% Clean up object file
delete('openmp_tls_crash.o');

fprintf('Compilation successful!\n');
fprintf('\nTo reproduce the crash:\n');
fprintf('  1. Run: openmp_tls_crash(1000000)\n');
fprintf('  2. Exit MATLAB: exit\n');
fprintf('  3. Observe segmentation fault on exit\n');
fprintf('\nFor the fix (MATLAB bundled OpenMP), use: compile_mex_matlab_omp\n');
