
import os
import sys
import requests
import subprocess
import re
import json
import platform
import hashlib
import shutil
import glob
import zipfile
from datetime import datetime
from datetime import timedelta

def sys_type():
    p = platform.system()
    if p == 'Darwin':  return 'mac'
    if p == 'Windows': return 'win'
    if p == 'Linux':   return 'lin'
    exit(1)

p         = sys_type()
src_dir   = os.environ.get('CMAKE_SOURCE_DIR')
build_dir = os.environ.get('CMAKE_BINARY_DIR')
cfg       = os.environ.get('CMAKE_BUILD_TYPE') if p != 'win' else 'Release' # externals are Release-built on windows
js_path   = os.environ.get('JSON_IMPORT_INDEX')
io_res    = f'{build_dir}/io/res'
cm_build  = 'ion-build'

if 'CMAKE_SOURCE_DIR' in os.environ: del os.environ['CMAKE_SOURCE_DIR']
if 'CMAKE_BINARY_DIR' in os.environ: del os.environ['CMAKE_BINARY_DIR']
if 'CMAKE_BUILD_TYPE' in os.environ: del os.environ['CMAKE_BUILD_TYPE']
#if 'SDKROOT'          in os.environ: del os.environ['SDKROOT']
if 'CPATH'            in os.environ: del os.environ['CPATH']
if 'LIBRARY_PATH'     in os.environ: del os.environ['LIBRARY_PATH']

pf_repo        = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
install_prefix = f'{pf_repo}/install'
extern_dir     = f'{pf_repo}/extern'
mingw_cmake    = f'{pf_repo}/ci/mingw-cmake.sh'
gen_only       = os.environ.get('GEN_ONLY')
exe            = ('.exe' if p == 'win' else '')
dir            = os.path.dirname(os.path.abspath(__file__))
common         = ['.cc',  '.c',   '.cpp', '.cxx', '.h',  '.hpp',
                  '.ixx', '.hxx', '.rs',  '.py',  '.sh', '.txt', '.ini', '.json']

everything = ["prefix"] # prefix with prefix.
prefix_sym = f'{extern_dir}/prefix'

os.environ['INSTALL_PREFIX'] = install_prefix
os.environ["PKG_CONFIG_PATH"] = install_prefix + '/lib/pkgconfig'

os.chdir(pf_repo)

if not os.path.exists('extern'):                 os.mkdir('extern')
if not os.path.exists('install'):                os.mkdir('install')
if not os.path.exists('install/lib'):            os.mkdir('install/lib')
if not os.path.exists('install/lib/Frameworks'): os.mkdir('install/lib/Frameworks')

if not os.path.exists(prefix_sym): os.symlink(pf_repo, prefix_sym, True)




# Function to replace %NAME% with corresponding environment variable
def replace_env_variables(match):
    var_name = match.group(1)  # Extract NAME from %NAME%
    return os.environ.get(var_name, match.group(0))  # Replace with env var, or leave unchanged if not found

def sha256_file(file_path):
    sha256_hash = hashlib.sha256()
    with open(file_path, "rb") as file:
        for chunk in iter(lambda: file.read(4096), b""):
            sha256_hash.update(chunk)
    return sha256_hash.hexdigest()

def replace_env(input_string):
    def repl(match):
        var_name = match.group(1)
        return os.environ.get(var_name, match.group(0))
    return re.sub(r'%([^%]+)%', repl, input_string)

# this only builds with cmake using a url with commit-id, optional diff
def check(a):
    assert(a)
    return a

def parse(f):
    return f['name'], f['name'], f['version'], f.get('res'), f.get('sha256'), f.get('url'), f.get('commit'), f.get('branch'), f.get('libs'), f.get('includes'), f.get('bins')

def git(fields, *args):
    print(' --> current dir: ', os.getcwd())
    cmd = ['git' + exe] + list(args)
    shell_cmd = ' '.join(cmd)
    print('> ', shell_cmd)
    return subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0

def cmake(fields, *args):
    print(' --> current dir: ', os.getcwd())
    cmd = ['cmake' + exe] + list(args)
    shell_cmd = ' '.join(cmd)
    print('> ', shell_cmd)
    return subprocess.run(cmd, capture_output=True, text=True)

def build(fields):
    return cmake(fields, '--build', '.', '--config', cfg)

def gen(fields, type, project_root, prefix_path, extra):
    build_type = type[0].upper() + type[1:].lower() 
    args = ['-S', project_root,
            '-B', cm_build, 
           f'-DCI=\'{pf_repo}/ci\'',
           #f'-DCMAKE_SYSTEM_PREFIX_PATH=\'{src_dir}/../ion/ci;{install_prefix}/lib/cmake\'',
           f'-DCMAKE_INSTALL_PREFIX=\'{install_prefix}\'', 
           f'-DCMAKE_INSTALL_DATAROOTDIR=\'{install_prefix}/share\'', 
           f'-DCMAKE_INSTALL_DOCDIR=\'{install_prefix}/doc\'', 
           f'-DCMAKE_INSTALL_INCLUDEDIR=\'{install_prefix}/include\'', 
           f'-DCMAKE_INSTALL_LIBDIR=\'{install_prefix}/lib\'', 
           f'-DCMAKE_INSTALL_BINDIR=\'{install_prefix}/bin\'', 
           f'-DCMAKE_PREFIX_PATH=\'{prefix_path}\'', 
            '-DCMAKE_VERBOSE_MAKEFILE:BOOL=ON', 
           f'-DCMAKE_BUILD_TYPE={build_type}'
    ]
    ## if
    if extra: args.extend(extra)
    ##
    cm = fields.get('cmake')
    if cm:
        gen_key = f'gen-{p}'
        if gen_key in cm:
            print('running gen script:', cm[gen_key])
            return subprocess.run(cm[gen_key], capture_output=True, text=True)
    
    return cmake(fields, *args)

def  cm_install(fields): return cmake(fields, '--install', cm_build, '--config', cfg)

def latest_file(root_path, avoid = None):
    t_latest = 0
    n_latest = None
    ##
    for file_name in os.listdir(root_path):
        file_path = os.path.join(root_path, file_name)
        ##
        if os.path.isdir(file_path):
            if (file_name != '.git') and (not avoid or file_name != avoid):
                ## recurse into subdirectories
                sub_latest, t_sub_latest = latest_file(file_path)
                if sub_latest is not None:
                    if t_sub_latest and t_sub_latest > t_latest:
                        t_latest = t_sub_latest
                        n_latest = sub_latest
        elif os.path.islink(file_path):
            continue # avoiding interference
        elif os.path.islink(file_path) and not os.path.exists(os.path.realpath(file_path)):
            continue
        elif os.path.exists(file_path):
            ext = os.path.splitext(file_path)[1]
            if ext in common:
                ## check file modification time on common extensions
                mt = os.path.getmtime(file_path)
                if mt and mt > t_latest:
                    t_latest = mt
                    n_latest = file_path
    ##
    return n_latest, t_latest

def is_cached(this_src_dir, vname, mt_project):
    dst_build     = f'{this_src_dir}/{cm_build}'
    cached        = os.path.exists(dst_build)
    timestamp     = os.path.join(dst_build, '._build_timestamp')
    ##
    if cached:
        if os.path.exists(timestamp):
            m_name, m_time = latest_file(this_src_dir, cm_build)
            build_time     = os.stat(timestamp).st_mtime
            cached         = m_time <= build_time
            if mt_project > build_time:
                cached = False # regen/rebuild all things with project file updates
            ##
            if cached:
                print(f'skipping {vname:20} (unchanged)')
            else:
                print(f'building {vname:20} (updated: {m_name})')
        else:
            cached = False
    ##
    return dst_build, timestamp, cached
    
def cp_deltree(src, dst, dirs_exist_ok=True):
    shutil.copytree(src, dst, dirs_exist_ok=dirs_exist_ok)
    for root, dirs, files in os.walk(dst):
        for file in files:
            if file.startswith('rm@'):
                rm_cmd = os.path.join(root, file)
                src_rm = os.path.join(root, file[3:])
                os.remove(rm_cmd)
                if os.path.exists(src_rm): # subsequent calls error.  the repo would need deleted files restored but no other changes reverted.  better to just check
                    os.remove(src_rm)

## prepare an { object } of external repo
def prepare_build(this_src_dir, fields, mt_project):
    vname, name, version, res, sha256, url, commit, branch, libs, includes, bins = parse(fields)

    dst = f'{extern_dir}/{vname}'
      
    dst_build, timestamp, cached = is_cached(dst, vname, mt_project)

    if libs:     fields['libs']     = [re.sub(r'%([^%]+)%', replace_env_variables, s) for s in fields['libs']]
    if bins:     fields['bins']     = [re.sub(r'%([^%]+)%', replace_env_variables, s) for s in fields['bins']]
    if includes: fields['includes'] = [re.sub(r'%([^%]+)%', replace_env_variables, s) for s in fields['includes']]

    if not cached:
        first_checkout = False
        ## if there is resource, download it and verify sha256 (required field)
        if res:
            res      = res.replace('%platform%', p)
            response = requests.get(res)
            base     = os.path.basename(res)  # Extract the filename from the URL
            base     = base.split('?')[0] if '?' in base else base
            res_zip  = os.path.join(io_res, base)  # Path to save the downloaded zip file
            os.makedirs(io_res, exist_ok=True)
            ##
            with open(res_zip, "wb") as file: file.write(response.content)
            ##
            digest = sha256_file(res_zip)
            if digest != sha256: print(f'sha256 checksum failure in project {name}: checksum for {res}: {digest}')
            with zipfile.ZipFile(res_zip, 'r') as z: z.extractall(dst)
        elif url:
            os.chdir(extern_dir)
            if not os.path.exists(vname):
                first_checkout = True
                git(fields, 'clone', '--recursive', url, vname)
                if(fields.get('git')):
                    git(fields, *fields['git'])
            os.chdir(vname)
            git(fields, 'fetch')
            diff_find = f'{this_src_dir}/diff/{name}.diff' # it might be of value to store diffs in prefix.
            diff      = None
            ##
            if os.path.exists(diff_find): diff = diff_find
            if diff: git(fields, 'reset', '--hard')
            ##
            
            if branch:
                git(fields, 'checkout', '-b', branch)
            else:
                checkout = commit if commit else 'main'
                git(fields, 'checkout', checkout)
            
            ##
            if diff: git(fields, 'apply', diff)
            
        ## overlay files; not quite as good as diff but its easier to manipulate
        overlay = f'{this_src_dir}/overlays/{name}'
        if os.path.exists(overlay):
            print('copying overlay for project: ', name)
            
            #shutil.copytree(overlay, dst, dirs_exist_ok=True)
            cp_deltree(overlay, dst, dirs_exist_ok=True)

            # include some extra code without needing to copy the CMakeLists.txt
            if os.path.exists(f'{overlay}/mod'):
                file = f'{dst}/CMakeLists.txt'
                print('file = ', file)
                assert(os.path.exists(file)) # if there is a mod overlay, it must be a CMake project because this merely includes after
                with open(file, 'a') as contents:
                    contents.write('\r\ninclude(mod)\r\n')
            
        # run script to process repo if it had just been checked out
        
        # here we have a bit of cache control so we dont have to re-checkout repos when we rerun the script to tune for success
        first_cmd = fields.get('script')
        if first_cmd and not os.path.exists('.script.success'):
            print(f'[{vname}] running: {first_cmd}')
            script = subprocess.run(first_cmd, capture_output=True, text=True)
            print(script.stdout)
            if script.returncode != 0:
                print('error from script')
                exit(1)
            else:
                file = f'.script.success'
                with open(file, 'w') as contents:
                    contents.write(script.stdout)
            

        diff_file = f'{build_dir}/{name}.diff'
        with open(diff_file, 'w') as d:
            subprocess.run(['git' + exe, 'diff'], stdout=d)
        print('diff-gen: ', diff_file)
    else:
        cached = True
    ##
    return dst, dst_build, timestamp, cached, vname, (not res) and url, libs, res, url

# create sym-link for each remote as f'{name}' as its first include entry, or the repo path if no includes
# all peers are symlinked and imported first
def prepare_project(src_dir):
    project_file = src_dir + '/project.json'
    with open(project_file, 'r') as project_contents:
        print('loading: ', project_file)
        project_json = json.load(project_contents)
        import_list  = project_json['import']
        mt_project   = os.path.getmtime(project_file)

        ## import the peers first, which have their own index (fetch first!)
        ## it should build while checking out
        for fields in import_list:
            if isinstance(fields, str):
                if fields in everything:
                    continue
                rel_peer = f'{src_dir}/../{fields}'
                sym_peer = f'{extern_dir}/{fields}'
                if not os.path.exists(sym_peer): os.symlink(rel_peer, sym_peer, True)
                assert(os.path.islink(sym_peer))
                prepare_project(rel_peer) # recurse into project, pulling its things too
            everything.append(fields)

        ## now prep gen and build
        prefix_path = install_prefix
        for fields in import_list:
            if isinstance(fields, str):
                continue
            h           = fields.get('hide')
            name        = fields['name']
            url         = fields.get('url')
            cmake       = fields.get('cmake')
            environment = fields.get('environment')
            hide        = h == True or h == sys_type()
            project_root = '.'
            if cmake and cmake.get('path'):
                project_root = cmake.get('path')
            
            cmake_args  = []
            cmake_install_libs = None
            
            if cmake:
                if f'args-{p}' in cmake:
                    cmargs = cmake.get(f'args-{p}')
                else:
                    cmargs = cmake.get('args')
                
                if cmargs:
                    cmake_args = cmargs
                    for i in range(len(cmake_args)):
                        v = cmake_args[i]
                        tmpl = "%PREFIX%"
                        v = v.replace("%PREFIX%", install_prefix)
                        if (cmake_args[i] != v):
                            print('setting arg: ', v)
                            cmake_args[i]  = v

                cmake_install_libs = cmake.get('install_libs')
            
            # set environment variables to those with %VAR%
            if environment:
                for key, evalue in environment.items():
                    if '%' in evalue:
                        for env_var, var_value in os.environ.items():
                            tmpl = "%" + env_var + "%"
                            v    = evalue.replace(tmpl, var_value)
                            if v != evalue:
                                evalue = v
                    os.environ[key] = evalue
            
            platforms = fields.get('platforms')
            if platforms and not p in platforms:
                print(f'skipping {name:20} (platform omit)')
                continue
            
            # dont gen/build resources (depot_tools is one such resource)
            # resources do not contain a version; this is to make it easier to access by the projects
            resource = fields.get('resource')
            
            ## check the timestamp here
            remote_path, remote_build_path, timestamp, cached, vname, is_git, libs, res, url = prepare_build(src_dir, fields, mt_project)
            
            ## only building the src git repos; the resources are system specific builds
            if not cached and is_git and not resource:
                gen_res = gen(fields, cfg, project_root, prefix_path, cmake_args)
                if gen_res.returncode != 0:
                    print(gen_res.stdout)
                    print(f'cmake generation errors for extern: {name}')
                    print( '------------------------------------------------')
                    if gen_res.stderr: print(gen_res.stderr)
                    exit(1)
                
                prev_cwd = os.getcwd()
                os.chdir(remote_build_path)

                print(f'building {name}...')
                build_res = build(fields)
                if build_res.returncode != 0:
                    print(build_res.stdout)
                    print(f'build errors for extern: {name}')
                    print( '------------------------------------------------')
                    if build_res.stderr: print(build_res.stderr)
                    exit(1)
                os.chdir(prev_cwd)
                
                # something with libs is just a declaration with an environment variable usually, already installed in effect if there are libs
                if not libs:
                    install_res = cm_install(fields)
                    if install_res.returncode != 0:
                        print(install_res.stdout)
                        print(f'install errors for extern: {name}')
                        print( '------------------------------------------------')
                        if install_res.stderr: print(install_res.stderr)
                        exit(1)
                    
                    if cmake_install_libs:
                        print(f'installing extra libs, because Python makes sense and CMake installs do not')
                        for pattern in cmake_install_libs:
                            file_list = glob.glob(f'{remote_path}/{pattern}')
                            for file_path in file_list:
                                print(f'installing: {file_path}')
                                shutil.copy(file_path, f'{install_prefix}/lib')
                
                ## update timestamp
                with open(timestamp, 'w') as f:
                    f.write('')

# prepare project recursively
prepare_project(src_dir)

# output everything discovered in original order
with open(js_path, "w") as out:
    json.dump(everything, out)