
import os
import sys
import requests
import subprocess
import re
import json
import platform
import hashlib
#import requests
import shutil
import zipfile
from datetime import datetime
from datetime import timedelta

src_dir   = os.environ.get('CMAKE_SOURCE_DIR')
build_dir = os.environ.get('CMAKE_BINARY_DIR')
cfg       = os.environ.get('CMAKE_BUILD_TYPE')
js_path   = os.environ.get('JSON_IMPORT_INDEX')
io_res    = f'{build_dir}/io/res'
cm_build  = 'ion-build'

pf_repo        = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
install_prefix = f'{pf_repo}/install';
extern_dir     = f'{pf_repo}/extern';

gen_only  = os.environ.get('GEN_ONLY')

os.environ['INSTALL_PREFIX'] = install_prefix

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

dir = os.path.dirname(os.path.abspath(__file__))

# this only builds with cmake using a url with commit-id, optional diff
def check(a):
    assert(a)
    return a

def      parse(f): return f['name'] + '-' + f['version'], f['name'], f['version'], f.get('res'), f.get('sha256'), f.get('url'), f.get('commit'), f.get('libs'), f.get('includes'), f.get('bins')
def    git(*args): return subprocess.run(['git']   + list(args), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0

def  cmake(*args):
    cmd = ['cmake'] + list(args)
    shell_cmd = ' '.join(cmd)
    print('cmake > ', shell_cmd)
    return subprocess.run(cmd, capture_output=True, text=True)

def       build(): return cmake('--build',   cm_build)
def  cm_install(): return cmake('--install', cm_build)
def         gen(type, cmake_script_root, prefix_path, extra=None):
    build_type = type[0].upper() + type[1:].lower()
    args = ['-S', cmake_script_root,
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
    if extra:
        args.extend(extra)
    return cmake(*args)

os.chdir(pf_repo)

if not os.path.exists('extern'):                 os.mkdir('extern')
if not os.path.exists('install'):                os.mkdir('install')
if not os.path.exists('install/lib'):            os.mkdir('install/lib')
if not os.path.exists('install/lib/Frameworks'): os.mkdir('install/lib/Frameworks')

common = ['.cc',  '.c',   '.cpp', '.cxx', '.h',  '.hpp',
          '.ixx', '.hxx', '.rs',  '.py',  '.sh', '.txt', '.ini', '.json']

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

def sys_type():
    p = platform.system()
    if p == 'Darwin':  return 'mac'
    if p == 'Windows': return 'win'
    if p == 'Linux':   return 'linux'
    exit(1)

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
    vname, name, version, res, sha256, url, commit, libs, includes, bins = parse(fields)

    dst = f'{extern_dir}/{vname}'

    ## overlay files -- this is an effective workflow for getting to a .diff
    ## use overlays while its still being hammered out and once you want 
    ## to forget it just use the generated diff in build folder
    overlay = f'{this_src_dir}/overlays/{name}'
    if os.path.exists(overlay):
        cp_deltree(overlay, dst, dirs_exist_ok=True)
        diff_file = f'{build_dir}/{name}.diff'
        
    dst_build, timestamp, cached = is_cached(dst, vname, mt_project)

    if libs:     fields['libs']     = [re.sub(r'%([^%]+)%', replace_env_variables, s) for s in fields['libs']]
    if bins:     fields['bins']     = [re.sub(r'%([^%]+)%', replace_env_variables, s) for s in fields['bins']]
    if includes: fields['includes'] = [re.sub(r'%([^%]+)%', replace_env_variables, s) for s in fields['includes']]

    if not cached:
        ## if there is resource, download it and verify sha256 (required field)
        if res:
            res      = res.replace('%platform%', sys_type())
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
            if not os.path.exists(vname): git('clone', '--recursive', url, vname)
            os.chdir(vname)
            git('fetch')
            diff_find = f'{this_src_dir}/diff/{name}.diff' # it might be of value to store diffs in prefix.
            diff      = None
            ##
            if os.path.exists(diff_find): diff = diff_find
            if diff: git('reset', '--hard')
            ##
            checkout = commit if commit else 'main'
            git('checkout', checkout)
            ##
            if diff: git('apply', diff)
            
        ## overlay files; not quite as good as diff but its easier to manipulate
        overlay = f'{this_src_dir}/overlays/{name}'
        if os.path.exists(overlay):
            print('copying overlay for project: ', name)
            #shutil.copytree(overlay, dst, dirs_exist_ok=True)
            cp_deltree(overlay, dst, dirs_exist_ok=True)
            diff_file = f'{build_dir}/{name}.diff'
            with open(diff_file, 'w') as d:
                subprocess.run(['git', 'diff'], stdout=d)
            print('diff-gen: ', diff_file)
    else:
        cached = True
    ##
    return dst, dst_build, timestamp, cached, vname, (not res) and url, libs, res, url

# prefix with prefix.
# the basic ci module is implicit here and purely going to just watch the .cmake for changes
# a direct user of this would be ion:core
everything = ["prefix"]
prefix_sym = f'{extern_dir}/prefix'
if not os.path.exists(prefix_sym): os.symlink(pf_repo, prefix_sym, True)

# create sym-link for each remote as f'{name}' as its first include entry, or the repo path if no includes
# all peers are symlinked and imported first
def prepare_project(src_dir):
    project_file = src_dir + '/project.json'
    with open(project_file, 'r') as project_contents:
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
            cmake       = fields.get('cmake')
            environment = fields.get('environment')
            hide        = h == True or h == sys_type() # designed for vulkan things mixing up with wrappers so that you dont expose definitions, includes, etc.  the wrapper does that and knows where this stuff is.
            cmake_script_root = '.'
            cmake_args  = []

            if cmake:
                cmpath = cmake.get('path')
                if cmpath:
                    cmake_script_root = cmpath
                cmargs = cmake.get('args')
                if cmargs:
                    cmake_args = cmargs
            
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
            if platforms:
                p = platform.system()
                keep = False
                if p == 'Darwin'  and 'mac'   in platforms:
                    keep = True
                if p == 'Windows' and 'win'   in platforms:
                    keep = True
                if p == 'Linux'   and 'linux' in platforms:
                    keep = True
                if not keep:
                    print(f'skipping {name:20} (platform omit)')
                    continue
            
            ## check the timestamp here
            remote_path, remote_build_path, timestamp, cached, vname, is_git, libs, res, url = prepare_build(src_dir, fields, mt_project)

            ## only building the src git repos; the resources are system specific builds
            if not cached and is_git:
                gen_res = gen(cfg, cmake_script_root, prefix_path, cmake_args)
                if gen_res.returncode != 0:
                    print(gen_res.stdout)
                    print(f'cmake generation errors for extern: {name}')
                    print( '------------------------------------------------')
                    if gen_res.stderr: print(gen_res.stderr)
                    exit(1)
                
                build_res = build()
                if build_res.returncode != 0:
                    print(build_res.stdout)
                    print(f'build errors for extern: {name}')
                    print( '------------------------------------------------')
                    if build_res.stderr: print(build_res.stderr)
                    exit(1)
                
                # something with libs is just a declaration with an environment variable usually, already installed in effect if there are libs
                if not libs:
                    install_res = cm_install()
                    if install_res.returncode != 0:
                        print(install_res.stdout)
                        print(f'install errors for extern: {name}')
                        print( '------------------------------------------------')
                        if install_res.stderr: print(install_res.stderr)
                        exit(1)
                
                ## update timestamp
                with open(timestamp, 'w') as f:
                    f.write('')

# prepare project recursively
prepare_project(src_dir)

# output everything discovered in original order
with open(js_path, "w") as out:
    json.dump(everything, out)
