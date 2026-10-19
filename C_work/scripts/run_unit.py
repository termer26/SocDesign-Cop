from pathlib import Path
import json
from datetime import datetime
from run_soc import ROOT,run

def main():
    folder=ROOT/'build'/('unit_'+datetime.now().strftime('%Y%m%d_%H%M%S'))
    folder.mkdir(parents=True)
    run(['iverilog','-g2012','-Wall','-s','tb_c_interfaces','-o','unit.vvp',
         ROOT/'rtl/accel_csr.sv',ROOT/'rtl/shared_mem_adapter.sv',ROOT/'tb/tb_c_interfaces.sv'],folder,'compile.log')
    run(['vvp','-N','unit.vvp'],folder,'simulation.log',30)
    log=(folder/'simulation.log').read_text()
    if 'C_INTERFACES_PASS' not in log:raise RuntimeError('Missing unit pass marker')
    summary={'status':'PASS','test':'C_INTERFACES','directory':str(folder)}
    (folder/'summary.json').write_text(json.dumps(summary,indent=2))
    print(log)
    print(folder)

if __name__=='__main__':main()
