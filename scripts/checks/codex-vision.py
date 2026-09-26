import zlib,struct,subprocess,os,tempfile,json
from pathlib import Path
p=Path(tempfile.mkdtemp(prefix='speek-vision-test-'))
def chunk(t,d): return struct.pack('!I',len(d))+t+d+struct.pack('!I',zlib.crc32(t+d)&0xffffffff)
raw=b''.join(b'\0'+b'\xff\0\0'*100+b'\0\0\xff'*100 for _ in range(100))
(p/'fixture.png').write_bytes(b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('!2I5B',200,100,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(raw))+chunk(b'IEND',b''))
env=dict(os.environ);env.pop('OPENAI_API_KEY',None);env.pop('CODEX_API_KEY',None)
for name,home in [('local',str(Path.home()/'.codex')),('subscription',str(Path.home()/'Library/Application Support/com.aveekpatra.speek/codex'))]:
 env['CODEX_HOME']=home
 result=subprocess.run(['/opt/homebrew/bin/codex','exec','--ignore-user-config','--skip-git-repo-check','--ephemeral','-s','read-only','-c','approval_policy="never"','-c','model_provider="openai"','-o',str(p/(name+'.txt')),'-i',str(p/'fixture.png'),'--','Name the left and right colors in the attached image. Do not use tools.'],cwd=p,env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=90)
 print(name,'exit',result.returncode,'answer', (p/(name+'.txt')).read_text() if (p/(name+'.txt')).exists() else result.stdout.decode()[-1500:])
