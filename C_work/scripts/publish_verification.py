"""Archive only explicitly selected passing runs as the C integration evidence."""
from pathlib import Path
import argparse
import hashlib
import json
import shutil
from run_soc import ROOT,TEAM

def publish(folder,label,report_dir):
    folder=folder.resolve()
    summary=json.loads((folder/'summary.json').read_text())
    if summary['status']!='PASS':raise ValueError('Cannot publish a non-passing run')
    for rel,wanted in summary.get('source_sha256',{}).items():
        if hashlib.sha256((TEAM/rel).read_bytes()).hexdigest()!=wanted:
            raise ValueError('Source no longer matches the passing run: '+rel)
    for name in ('summary.json','simulation.log','observed.txt','firmware.elf','compile.log','firmware_build.log'):
        source=folder/name
        if source.is_file():shutil.copyfile(source,report_dir/(label+'_'+name))
    return summary

def main():
    p=argparse.ArgumentParser()
    p.add_argument('--full',type=Path,required=True)
    p.add_argument('--layers',type=Path,required=True)
    p.add_argument('--unit',type=Path,required=True)
    a=p.parse_args();target=ROOT/'reports';target.mkdir(exist_ok=True)
    full=publish(a.full,'soc_full',target)
    layers=publish(a.layers,'soc_12_layers',target)
    unit=publish(a.unit,'interfaces',target)
    if (full['rows'],full['cols'])!=(99,256):raise ValueError('Full run dimensions are wrong')
    if layers['layers']!=list(range(12)):raise ValueError('Layer switch evidence must cover all 12 layers')
    status={'status':'PASS','scope':'Public E203 reference SoC integration; not official platform or ASIC signoff',
            'full_matrix_layers':full['layers'],'full_matrix_outputs':full['outputs_compared'],
            'layer_switch_dimensions':[layers['rows'],64,layers['cols']],
            'layer_switch_layers':layers['layers'],'layer_switch_outputs':layers['outputs_compared'],
            'interface_unit':unit['status'],'upstream_commit':full['upstream_commit'],
            'A_B_sources_modified':False,'official_platform_verified':False,
            'asic_sram_verified':False,'asic_timing_area_power_verified':False}
    (target/'VERIFICATION.json').write_text(json.dumps(status,indent=2),encoding='utf-8')
    (target/'MANIFEST.sha256').write_text(''.join(f'{hashlib.sha256(f.read_bytes()).hexdigest()}  {f.name}\n'
        for f in sorted(target.iterdir()) if f.is_file() and f.name!='MANIFEST.sha256'))
    print(json.dumps(status,indent=2))

if __name__=='__main__':main()
