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
import tarfile
import magic

from datetime import datetime
from datetime import timedelta

def sys_type():
    p = platform.system()
    if p == 'Darwin':  return 'mac'
    if p == 'Windows': return 'win'
    if p == 'Linux':   return 'lin'
    exit(1)

p              = sys_type()
src_dir        = os.environ.get('CMAKE_SOURCE_DIR')
build_dir      = os.environ.get('CMAKE_BINARY_DIR')
sdk            = os.environ.get('SDK') if os.environ.get('SDK') else 'native'
cfg            = os.environ.get('CMAKE_BUILD_TYPE') if p != 'win' else 'Release' # externals are Release-built on windows
js_import_path = os.environ.get('JSON_IMPORT_INDEX')
sdk_cmake      = f'{build_dir}/sdk.cmake'
io_res         = f'{build_dir}/io/res'
cm_build       = 'ion-build' + ('' if sdk == 'native' else f'-{sdk}') # probably call this build or build-sdk

if 'CMAKE_SOURCE_DIR' in os.environ: del os.environ['CMAKE_SOURCE_DIR']
if 'CMAKE_BINARY_DIR' in os.environ: del os.environ['CMAKE_BINARY_DIR']
if 'CMAKE_BUILD_TYPE' in os.environ: del os.environ['CMAKE_BUILD_TYPE']
#if 'SDKROOT'          in os.environ: del os.environ['SDKROOT']
if 'CPATH'            in os.environ: del os.environ['CPATH']
if 'LIBRARY_PATH'     in os.environ: del os.environ['LIBRARY_PATH']

pf_repo        = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
install_dir    = f'install/{sdk}'
sdk_rel        = f'sdk/{sdk}' if sdk != 'native' else ''
install_prefix = f'{pf_repo}/{install_dir}'
sdk_location   = f'{pf_repo}/{sdk_rel}' if sdk_rel else ''
extern_dir     = f'{pf_repo}/extern' # we put different build dirs for the different sdks in here.  it would be ludacrous to checkout more?...
mingw_cmake    = f'{pf_repo}/ci/mingw-cmake.sh' # oh boy we need to properly use mingw on windows, as its just not going to work supporting native land only.  it means the skia overlay we can bring back
gen_only       = os.environ.get('GEN_ONLY')
exe            = ('.exe' if p == 'win' else '')
dir            = os.path.dirname(os.path.abspath(__file__))
common         = ['.cc',  '.c',   '.cpp', '.cxx', '.h',  '.hpp',
                  '.ixx', '.hxx', '.rs',  '.py',  '.sh', '.txt', '.ini', '.json']

every_import = ['prefix'] # prefix with prefix.
every_sdk    = [{'name':'native', 'args':{}}]
sdk_data     = None
prefix_sym   = f'{extern_dir}/prefix'

os.environ['INSTALL_PREFIX'] = install_prefix
os.environ['PKG_CONFIG_PATH'] = install_prefix + '/lib/pkgconfig'

os.chdir(pf_repo)

if not os.path.exists('extern'):             os.mkdir('extern')
if not os.path.exists('install'):            os.mkdir('install')
if not os.path.exists(install_dir):          os.mkdir(install_dir)
if not os.path.exists(f'{install_dir}/lib'): os.mkdir(f'{install_dir}/lib')

if not os.path.exists(f'{install_dir}/lib/Frameworks'):
    os.mkdir(f'{install_dir}/lib/Frameworks')

if not os.path.exists(prefix_sym): os.symlink(pf_repo, prefix_sym, True)

def run_check(cmd, capture_output=False, text=True, stdout=None, stderr=None):
    res = subprocess.run(cmd,
        capture_output=capture_output, text=text,
        stdout=stdout, stderr=stderr)

    print('%s -> %s' % (os.getcwd(), ' '.join(cmd)))
    if res.returncode != 0:
        print(res.stdout)
        print(f'errors:')
        print( '------------------------------------------------')
        if res.stderr: print(res.stderr)
        exit(1)
    return res

def find_sdk(sdk):
    for item in every_sdk:
        if item.get('name') == sdk:
            return item
    print(f'sdk not found: {sdk}')
    exit(1)
    return None

# Function to replace %NAME% with corresponding environment variable
def replace_env_variables(match):
    var_name = match.group(1)  # Extract NAME from %NAME%
    return os.environ.get(var_name, match.group(0))  # Replace with env var, or leave unchanged if not found

def sha256_file(file_path):
    sha256_hash = hashlib.sha256()
    with open(file_path, 'rb') as file:
        for chunk in iter(lambda: file.read(4096), b''):
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
    cmd = ['git' + exe] + list(args)
    return run_check(cmd).returncode == 0

def cmake(fields, *args):
    cmd = ['cmake' + exe] + list(args)
    return run_check(cmd)

def build(fields):
    return cmake(fields, '--build', '.', '--config', cfg)

def gen(fields, type, project_root, prefix_path, extra):
    build_type = type[0].upper() + type[1:].lower() 
    args = ['-S', project_root,
            '-C', sdk_cmake,
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
    # look for generator scripts on specific os's (needed still? -- skia might be only use-case)
    if cm:
        gen_key = f'gen-{p}'
        if gen_key in cm:
            print('running gen script:', cm[gen_key])
            return run_check(cm[gen_key])
    
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
            with open(res_zip, 'wb') as file: file.write(response.content)
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
            if branch:
                git(fields, 'fetch')
            diff_find = f'{this_src_dir}/diff/{name}.diff' # it might be of value to store diffs in prefix.
            diff      = None
            ##
            if os.path.exists(diff_find): diff = diff_find
            if diff: git(fields, 'reset', '--hard')
            if branch:
                cmd = ['git', 'rev-parse', branch]
                commit = subprocess.check_output(cmd).decode('utf-8').strip()
            if not commit:
                commit = 'main'
            
            git(fields, 'checkout', commit)
            if diff: git(fields, 'apply', '--reject', '--ignore-space-change', '--ignore-whitespace', '--whitespace=fix', diff)

        ## overlay files; not quite as good as diff but its easier to manipulate
        overlay = f'{this_src_dir}/overlays/{name}'
        if os.path.exists(overlay):
            print('copying overlay for project: ', name)
            
            #shutil.copytree(overlay, dst, dirs_exist_ok=True)
            cp_deltree(overlay, dst, dirs_exist_ok=True)

            # include some extra code without needing to copy the CMakeLists.txt
            if os.path.exists(f'{overlay}/mod'):
                file = f'{dst}/CMakeLists.txt'
                # this should fail if there is no CMake
                git(fields, 'checkout', commit, '--', 'CMakeLists.txt')
                assert(os.path.exists(file)) # if there is a mod overlay, it must be a CMake project because this merely includes after
                with open(file, 'a') as contents:
                    contents.write('\r\ninclude(mod)\r\n')
            
        # run script to process repo if it had just been checked out
        
        # here we have a bit of cache control so we dont have to re-checkout repos when we rerun the script to tune for success
        first_cmd = fields.get('script')
        if first_cmd and not os.path.exists('.script.success'):
            print(f'[{vname}] running: {first_cmd}')
            script = run_check(first_cmd)
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
            run_check(['git' + exe, 'diff'], stdout=d)
        print('diff-gen: ', diff_file)
    else:
        cached = True
    ##
    return dst, dst_build, timestamp, cached, vname, (not res) and url, libs, res, url

# we are reading json twice but this is not so costly
def prepare_sdk(src_dir):
    project_file = src_dir + '/project.json'
    with open(project_file, 'r') as project_contents:
        print('file: ' + project_file)
        project_json = json.load(project_contents)
        import_list  = project_json.get('import')
        sdk_list     = project_json.get('sdk') 
        if sdk_list:
            for item in sdk_list:
                every_sdk.append(item)
        for fields in import_list:
            if isinstance(fields, str):
                if fields in every_import:
                    continue
                rel_peer = f'{src_dir}/../{fields}'
                prepare_sdk(rel_peer)

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
                if fields in every_import:
                    continue
                rel_peer = f'{src_dir}/../{fields}'
                sym_peer = f'{extern_dir}/{fields}'
                if not os.path.exists(sym_peer): os.symlink(rel_peer, sym_peer, True)
                assert(os.path.islink(sym_peer))
                prepare_project(rel_peer) # recurse into project, pulling its things too
            every_import.append(fields)

        # at this point, it has everything in 
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
                    cmargs = cmake.get('args') # 'string' is a format string in silver? the double quotes block out the expressions?
                if cmargs:
                    cmake_args = cmargs
                    for i in range(len(cmake_args)):
                        v = cmake_args[i]
                        tmpl = '%PREFIX%'
                        v = v.replace('%PREFIX%', install_prefix)
                        if (cmake_args[i] != v):
                            print('setting arg: ', v)
                            cmake_args[i]  = v

                cmake_install_libs = cmake.get('install_libs')
            
            # set environment variables to those with %VAR%
            if environment:
                for key, evalue in environment.items():
                    if '%' in evalue:
                        for env_var, var_value in os.environ.items():
                            tmpl = '%' + env_var + '%'
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
                gen(fields, cfg, project_root, prefix_path, cmake_args)

                prev_cwd = os.getcwd()
                os.chdir(remote_build_path)

                print(f'building {name}...')
                build(fields)

                os.chdir(prev_cwd)
                
                # something with libs is just a declaration with an environment variable usually, already installed in effect if there are libs
                if not libs:
                    cm_install(fields)
                    
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

# sdk are defined by any project used, so we accumulate those first
# if not, we arent generating our cmake correctly because it needs a compiler set along with other args
# we run cmake -C sdk-generated-file-on-our-end.cmake

# not sure if we should empty the dir
def auto_extract(fileobj, path):
    if not os.path.exists(path):
        os.mkdir(path)
    mime = magic.Magic(mime=True)
    mime_type = mime.from_buffer(fileobj.read(1024), mime=True)
    f = None
    if mime_type == 'application/x-xz':
        f = tarfile.open(fileobj=fileobj, mode='r:xz')
    if mime_type == 'application/x-gzip':
        f = tarfile.open(fileobj=fileobj, mode='r:gz')
    elif mime_type == 'application/x-tar':
        f = tarfile.open(fileobj=fileobj, mode='r')
    elif mime_type == 'application/zip':
        f = zipfile.ZipFile(fileobj=fileobj, mode='r')
    else:
        raise Exception('auto_extract [magic] cannot determine mime type for fileobj')
    f.extractall(path)

# generate cmake file with args for sdk
prepare_sdk(src_dir)
sdk_data = find_sdk(sdk)
sdk_args = sdk_data['args']
sdk_args['CMAKE_FIND_ROOT_PATH'] = sdk_location
sdk_src = sdk_args.get('source') # would be nice if we could know if its a repo or a tar file from the content type

if sdk_src:
    if not os.path.exists(sdk_location):
        os.mkdir(sdk_location)
    sdk_cache = f'{sdk_location}-cache' # file we store as cache
    if not sdk_cache:
        with open(sdk_cache, 'w') as sdk_f:
            rdata = requests.get(sdk_src)
        sdk_src = sdk_location + '-src'
        auto_extract(rdata.content, sdk_src)
        os.chdir(sdk_src)
        print(f'configuring sdk {sdk}')
        run_check(['./configure', f'--target={sdk}', f'--prefix={sdk_location}'], capture_output=True, text=True)
        print(f'building sdk {sdk}')
        run_check(['make', '-j8'], capture_output=True, text=True)
        
with open(sdk_cmake, 'w') as f:
    f.write(f'# cmake file generated by prefix for sdk:{sdk}')
    for key, value in sdk_args.items():
        f.write(f'set({key} {value})')

# prepare project recursively
prepare_project(src_dir)

# output everything discovered in original order
with open(js_import_path, 'w') as out:
    json.dump(every_import, out)
