"""Reversible hardware round-trip: lower by one, read back, restore in finally."""
import subprocess, json, sys
helper = sys.argv[1]
uuid = sys.argv[2]
def run(*args):
    return subprocess.check_output([helper, 'display', uuid, *map(str,args)], timeout=5, text=True).strip()
results = {}
for key in ['luminance','volume']:
    before = int(run('get',key))
    maximum = int(run('max',key))
    target = before - 1 if before > 0 else min(1, maximum)
    try:
        run('set', key, target)
        after = int(run('get',key))
        if after != target:
            raise RuntimeError(f'{key}: expected {target}, got {after}')
    finally:
        run('set',key,before)
        restored = int(run('get',key))
        if restored != before:
            raise RuntimeError(f'{key}: restore failed: {restored} != {before}')
    results[key] = {'before':before,'testValue':target,'readBack':after,'restored':restored,'maximum':maximum,'passed':True}
print(json.dumps(results, indent=2))
