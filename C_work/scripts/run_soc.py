"""Compile real RV32 firmware and simulate upstream E203 + unchanged A/B RTL."""
from pathlib import Path
import argparse
from datetime import datetime
import hashlib
import json
import os
import re
import shutil
import struct
import subprocess
import sys
import time

ROOT=Path(__file__).resolve().parents[1]
TEAM=ROOT.parent
sys.path.insert(0,str(TEAM/'B_work/scripts'))
from a_vectors import load_tasks,crop_task

def run(command,folder,log,timeout=180):
    started=time.time()
    with (folder/log).open('w',encoding='utf-8') as output:
        output.write('COMMAND: '+subprocess.list2cmdline(list(map(str,command)))+'\n');output.flush()
        p=subprocess.Popen(list(map(str,command)),cwd=folder,stdout=output,stderr=subprocess.STDOUT)
        try:code=p.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            p.kill();p.wait();raise RuntimeError(f'Timeout; see {folder/log}')
    if code:raise RuntimeError(f'Exit {code}; see {folder/log}\n'+(folder/log).read_text(errors='replace')[-7000:])
    return {'seconds':round(time.time()-started,3),'command':list(map(str,command))}

def sources():
    vendor=ROOT/'vendor/e203_hbirdv2'
    names=[]
    for filename in ('e203_core.core','e203_soc.core'):
        for relative in re.findall(r'^\s+- (rtl/[^\s:]+)',(vendor/filename).read_text(),re.M):
            path=vendor/relative
            if path.name in ('config.v','e203_defines.v','i2c_master_defines.v'):continue
            if path not in names:names.append(path)
    nice=vendor/'rtl/e203/subsys/e203_subsys_nice_core.v'
    if nice not in names:names.append(nice)
    names.extend(TEAM/'A_work'/name for name in ('rtl/compute/dot64_mac.sv','rtl/compute/bias_requant.sv','rtl/compute/compute_lane.sv'))
    names.extend(TEAM/'B_work'/name for name in ('rtl/memory/sram_wrapper.sv','rtl/memory/tensor_buffer.sv','rtl/control/linear_ctrl.sv','rtl/linear_accel_top.sv','rtl/integration/a_compute_adapter.sv','rtl/linear_accel_a_top.sv'))
    names.extend(sorted((ROOT/'rtl').glob('*.sv')))
    return names

def elf_image(path):
    data=path.read_bytes()
    if data[:5]!=b'\x7fELF\x01':raise ValueError('Expected ELF32')
    phoff=struct.unpack_from('<I',data,28)[0];phsize,phnum=struct.unpack_from('<HH',data,42)
    result=bytearray()
    for i in range(phnum):
        kind,off,va,pa,filesize,memsize,flags,align=struct.unpack_from('<8I',data,phoff+i*phsize)
        if kind!=1 or not filesize:continue
        start=pa-0xa0070000
        if not 0<=start<65536 or start+memsize>65536:raise ValueError('Firmware outside boot region')
        end=start+memsize
        if end>len(result):result.extend(b'\0'*(end-len(result)))
        result[start:start+filesize]=data[off:off+filesize]
    result.extend(b'\0'*((-len(result))%4))
    return bytes(result)

def prepare(folder,tasks):
    loads=[]
    for task in tasks:
        x=struct.pack('<'+'H'*len(task['x']),*task['x'])
        w=struct.pack('<'+'H'*len(task['w']),*task['w'])
        b=b''.join(struct.pack('<q',v-(1<<40) if v&(1<<39) else v) for v in task['b'])
        encoded=x+w+b
        loads.extend(struct.unpack('<'+'I'*(len(encoded)//4),encoded))
    (folder/'loads.hex').write_text(''.join(f'{v:08x}\n' for v in loads))
    (folder/'expected.hex').write_text(''.join(f'{v:04x}\n' for task in tasks for v in task['expected']))
    (folder/'layers.hex').write_text(''.join(f"{t['layer']:x}\n" for t in tasks))
    (folder/'shifts.hex').write_text(''.join(f"{t['shift']:02x}\n" for t in tasks))
    return len(loads)//len(tasks)

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--full',action='store_true',help='99x64x256, otherwise real-data 3x64x5 smoke')
    parser.add_argument('--layers',default='0,2,11')
    parser.add_argument('--sram-wait',type=int,default=1)
    parser.add_argument('--timeout',type=int,default=7200)
    parser.add_argument('--zig',type=Path,default=ROOT/'.tools/ziglang/zig.exe')
    parser.add_argument('--compile-only',action='store_true')
    parser.add_argument('--simulator',choices=['verilator','iverilog'],default='verilator')
    parser.add_argument('--wsl-distro',default='Ubuntu-24.04')
    args=parser.parse_args()
    rows,cols=(99,256) if args.full else (3,5)
    layers=[int(x) for x in args.layers.split(',')]
    tasks=load_tasks(TEAM/'A_work/artifacts/real_12_layers',layers)
    if not args.full:tasks=[crop_task(t,[0,49,98],[0,1,127,254,255]) for t in tasks]
    folder=ROOT/'build'/('soc_'+datetime.now().strftime('%Y%m%d_%H%M%S'))
    folder.mkdir(parents=True)
    print('Run directory:',folder,flush=True)
    report={'status':'RUNNING','rows':rows,'cols':cols,'layers':layers,'real_e203':True,
            'simulator':args.simulator,'sram_wait':args.sram_wait,'path':str(folder)}
    try:
        from generate_e203_wrapper import generate
        generate()
        src=sources();vendor=ROOT/'vendor/e203_hbirdv2'
        evidence_sources=src+list((ROOT/'sw').glob('*'))+list((ROOT/'tb').glob('*.sv'))+list((ROOT/'scripts').glob('*.py'))+[ROOT/'dependencies.json']
        evidence_sources+=[vendor/'rtl/e203/core/config.v',vendor/'rtl/e203/core/e203_defines.v',
                           vendor/'rtl/e203/perips/apb_i2c/i2c_master_defines.v',vendor/'e203_core.core',vendor/'e203_soc.core']
        report['source_sha256']={str(p.relative_to(TEAM)).replace('\\','/'):hashlib.sha256(p.read_bytes()).hexdigest() for p in evidence_sources}
        report['data_sources']=[{'layer':t['layer'],'shift':t['shift'],'sha256':t['source_sha256']} for t in tasks]
        report['upstream_commit']=subprocess.check_output(['git','-C',str(vendor),'rev-parse','HEAD'],text=True).strip()
        lock=json.loads((ROOT/'dependencies.json').read_text())
        if report['upstream_commit']!=lock['e203']['commit']:raise RuntimeError('E203 checkout does not match pinned commit')
        if subprocess.check_output(['git','-C',str(vendor),'status','--porcelain'],text=True).strip():raise RuntimeError('E203 dependency is modified')
        zig=args.zig.resolve()
        report['compiler_version']=subprocess.check_output([str(zig),'version'],text=True).strip()
        command=[zig,'cc','-target','riscv32-freestanding-none','-mcpu=generic_rv32+m+zicsr',
                 '-mabi=ilp32','-O2','-ffreestanding','-fno-builtin','-fno-stack-protector','-nostdlib',
                 '-msmall-data-limit=0',f'-DFFN_ROWS={rows}',f'-DFFN_COLS={cols}',
                 '-Wl,-T,'+str(ROOT/'sw/link.ld'),'-Wl,--build-id=none',
                 ROOT/'sw/start.S',ROOT/'sw/main.c',ROOT/'sw/ffn_driver.c','-o','firmware.elf']
        report['firmware']=run(command,folder,'firmware_build.log')
        binary=elf_image(folder/'firmware.elf')
        (folder/'firmware.bin').write_bytes(binary)
        (folder/'firmware.hex').write_text(''.join(f'{v[0]:08x}\n' for v in struct.iter_unpack('<I',binary)))
        load_words=prepare(folder,tasks)
        if args.simulator=='verilator':
            def linux(path):
                path=Path(path).resolve();return '/mnt/'+path.drive[0].lower()+'/'+path.as_posix()[3:]
            command=['wsl','-d',args.wsl_distro,'--','python3',linux(ROOT/'scripts/run_verilator.py'),
                     '--folder',linux(folder),'--rows',str(rows),'--cols',str(cols),'--jobs',str(len(tasks)),
                     '--sram-wait',str(args.sram_wait),'--fw-words',str(len(binary)//4),'--load-words',str(load_words)]
            if args.compile_only:command+=['--compile-only']
            report['verilator']=run(command,folder,'wsl.log',args.timeout)
        else:
            command=['iverilog','-g2012','-gno-assertions','-D','DISABLE_SV_ASSERTION','-s','tb_e203_ffn_soc','-o','soc.vvp',
                     '-I'+str(vendor/'rtl/e203/core'),'-I'+str(vendor/'rtl/e203/perips/apb_i2c')]
            for key,val in dict(ROWS=rows,COLS=cols,JOBS=len(tasks),SRAM_WAIT=args.sram_wait).items():command+=['-P',f'tb_e203_ffn_soc.{key}={val}']
            command+=src+[ROOT/'tb/tb_e203_ffn_soc.sv']
            report['compile']=run(command,folder,'compile.log')
        if args.compile_only:report['status']='COMPILED'
        else:
            print('Running real E203 firmware and A/B RTL...',flush=True)
            if args.simulator=='iverilog':
                report['simulation']=run(['vvp','-i','-N','soc.vvp',f'+FW_WORDS={len(binary)//4}',f'+LOAD_WORDS={load_words}'],folder,'simulation.log',args.timeout)
            log=(folder/'simulation.log').read_text()
            if f'E203_SOC_ALL_PASS jobs={len(tasks)} outputs={len(tasks)*rows*cols}' not in log:raise RuntimeError('Missing SoC success marker')
            records=(folder/'observed.txt').read_text().splitlines()
            if len(records)!=len(tasks)*rows*cols:raise RuntimeError('Incomplete output count')
            seen=set()
            for line in records:
                job,index,value=line.split();job,index=int(job),int(index)
                if (job,index) in seen or int(value,16)!=tasks[job]['expected'][index]:raise RuntimeError('Duplicate or mismatched output')
                seen.add((job,index))
            report['outputs_compared']=len(seen);report['status']='PASS'
            report['jobs']=[dict(zip(('job','layer','outputs','core_cycles','window_cycles'),map(int,m[:5])),checksum=m[5]) for m in re.findall(r'E203_JOB_PASS job=(\d+) layer=(\d+) outputs=(\d+) core_cycles=(\d+) window_cycles=(\d+) checksum=([\da-f]+)',log)]
            print(log[-4000:],flush=True)
        for relative,expected_hash in report['source_sha256'].items():
            if hashlib.sha256((TEAM/relative).read_bytes()).hexdigest()!=expected_hash:
                raise RuntimeError('Source changed during verification: '+relative)
        report['artifact_sha256']={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in folder.iterdir() if p.is_file() and p.suffix in ('.elf','.bin','.hex','.log','.txt')}
    except Exception as e:
        report['status']='FAIL';report['error']=str(e);raise
    finally:
        (folder/'summary.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
        (ROOT/'build/latest_soc.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    print('Status:',report['status'],flush=True)

if __name__=='__main__':main()
