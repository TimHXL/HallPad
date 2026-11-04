#!/usr/bin/env python3
"""Batch converter: capture child errors without PowerShell's NativeCommandError."""
import argparse,csv,subprocess,sys,tempfile,os
from pathlib import Path

def convert_all(input_folder,output_folder,track=-1,font=None,converter=None):
    source=Path(input_folder).resolve();output=Path(output_folder).resolve()
    if not source.is_dir():raise ValueError(f'Input folder does not exist: {source}')
    converter=Path(converter) if converter else Path(__file__).with_name('midi_to_hpg3.py')
    if not converter.is_file():raise ValueError(f'Converter does not exist: {converter}')
    output.mkdir(parents=True,exist_ok=True)
    files=sorted((p for p in source.rglob('*') if p.is_file() and p.suffix.lower() in ('.mid','.midi')),key=lambda p:str(p).casefold())
    success=0;report=output/'conversion_report.csv'
    with report.open('w',encoding='utf-8-sig',newline='') as handle:
        writer=csv.DictWriter(handle,fieldnames=['Input','Output','Success','Detail']);writer.writeheader();handle.flush()
        for number,path in enumerate(files,1):
            folder=output/f'BANK{success//256+1:03d}';folder.mkdir(exist_ok=True)
            destination=folder/f'S{number:07d}.HPG'
            ok=False;log=''
            try:
                # Stage each result so a failed converter never leaves a partial HPG.
                with tempfile.TemporaryDirectory(prefix='hpg_batch_',dir=folder) as temporary:
                    staged=Path(temporary)/destination.name
                    args=[sys.executable,'-u',str(converter),str(path),str(staged),'--title',path.stem[:32]]
                    if track>=0:args+=['--track',str(track)]
                    if font:args+=['--font',str(font)]
                    env=dict(os.environ,PYTHONIOENCODING='utf-8')
                    result=subprocess.run(args,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,encoding='utf-8',errors='replace',env=env)
                    log=result.stdout.strip();ok=result.returncode==0 and staged.is_file()
                    if ok:
                        staged.replace(destination)
                        metadata=staged.with_suffix('.json')
                        if metadata.exists():metadata.replace(destination.with_suffix('.json'))
                    elif result.returncode==0:log+='\nConverter returned success without an HPG file.'
            except Exception as exc:
                log=f'{type(exc).__name__}: {exc}'
            if ok:success+=1
            writer.writerow(dict(Input=str(path),Output=str(destination),Success=ok,Detail=log));handle.flush()
            print(f'[{number}/{len(files)}] {path.name} : {ok}',flush=True)
            if not ok:
                lines=[line for line in log.splitlines() if line.strip()]
                print('  '+(lines[-1] if lines else 'Unknown conversion error'),flush=True)
    print(f'Success: {success} / {len(files)}. Report: {report}',flush=True)
    print('Copy the contents of ONE BANK folder to the FAT32 SD root (max 256 HPG files).',flush=True)
    return success,len(files)

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input-folder',required=True);parser.add_argument('--output-folder',required=True)
    parser.add_argument('--track',type=int,default=-1);parser.add_argument('--font')
    args=parser.parse_args()
    try:convert_all(args.input_folder,args.output_folder,args.track,args.font)
    except (OSError,ValueError) as exc:
        print(f'Batch error: {exc}',flush=True);return 2
    return 0
if __name__=='__main__':raise SystemExit(main())
