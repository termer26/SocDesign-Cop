"""Linux/WSL helper; all generated files remain in the selected C_work build."""
from pathlib import Path
import argparse
import os
import subprocess
from run_soc import ROOT,sources,run

def main():
    p=argparse.ArgumentParser()
    p.add_argument('--folder',type=Path,required=True)
    for name in ('rows','cols','jobs','sram-wait','fw-words','load-words'):p.add_argument('--'+name,type=int,required=True)
    p.add_argument('--compile-only',action='store_true')
    a=p.parse_args();folder=a.folder
    runtime=ROOT/'.tools/verilator_linux/verilator'
    exe=runtime/'bin/verilator'
    for file in (runtime/'bin').iterdir():file.chmod(0o755)
    os.environ['VERILATOR_ROOT']=str(runtime)
    vendor=ROOT/'vendor/e203_hbirdv2'
    command=['perl',str(exe),'--binary','--timing','--timescale','1ns/1ps',
             '--top-module','tb_e203_ffn_soc','-Wno-fatal','-DDISABLE_SV_ASSERTION',
             '-CFLAGS','-std=c++20 -fcoroutines',
             '-MAKEFLAGS','CFG_CXXFLAGS_PCH_I=-include',
             '-I'+str(vendor/'rtl/e203/core'),'-I'+str(vendor/'rtl/e203/perips/apb_i2c'),
             '--Mdir',str(folder/'obj_dir'),'-j','4',
             '-GROWS='+str(a.rows),'-GCOLS='+str(a.cols),'-GJOBS='+str(a.jobs),'-GSRAM_WAIT='+str(a.sram_wait)]
    command+=sources()+[ROOT/'tb/tb_e203_ffn_soc.sv']
    print('Compiling E203 SoC with Verilator...',flush=True)
    run(command,folder,'compile.log',600)
    if not a.compile_only:
        print('Executing E203 firmware...',flush=True)
        run([folder/'obj_dir/Vtb_e203_ffn_soc',f'+FW_WORDS={a.fw_words}',f'+LOAD_WORDS={a.load_words}'],folder,'simulation.log',7200)
        print((folder/'simulation.log').read_text()[-4000:],flush=True)

if __name__=='__main__':main()
