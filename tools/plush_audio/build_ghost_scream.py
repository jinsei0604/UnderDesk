"""Standalone review WAV only. No file under the Godot project is written.
Uses an explicitly CC0, self-recorded human scream by AuraVoice / Nocturnal_Vanguard.
"""
from pathlib import Path
import subprocess,json,hashlib,wave
import numpy as np
import argparse,tempfile,shutil
parser=argparse.ArgumentParser()
parser.add_argument('--ffmpeg',default='ffmpeg')
parser.add_argument('--output',type=Path,required=True)
args=parser.parse_args()
FF=args.ffmpeg;O=args.output.resolve();O.mkdir(parents=True,exist_ok=True)
temporary=tempfile.TemporaryDirectory(prefix='plush-scream-');S=Path(temporary.name)
shutil.copy2(Path(__file__).with_name('female_scream_1.ogg'),S/'female_scream_1.ogg')
subprocess.run([FF,'-v','error','-y','-i',str(S/'female_scream_1.ogg'),'-ar','48000','-ac','1',str(S/'source.wav')],check=True)
SR=48000;N=round(1.20*SR)
def layer(name,pitch,tempo,extra):
 filters=f'atrim=start=0.638:end=1.405,asetpts=PTS-STARTPTS,rubberband=pitch={pitch}:tempo={tempo}:transients=crisp:formant=shifted,{extra},afade=t=in:d=0.003,afade=t=out:st=0.78:d=0.12'
 p=subprocess.run([FF,'-v','error','-i',str(S/'source.wav'),'-af',filters,'-ar',str(SR),'-ac','1','-f','f32le','-'],stdout=subprocess.PIPE,stderr=subprocess.PIPE,check=True)
 a=np.frombuffer(p.stdout,dtype='<f4').astype(float)
 x=np.zeros(N);n=min(len(a),N-384);x[384:384+n]=a[:n]
 return x
# Keep the real human vowel/breath articulation in the foreground. Two differently
# pitched versions of that same performance supply the spectral throat layers.
lead=layer('lead',.91,.94,'highpass=f=110,lowpass=f=6700')
low=layer('low',.49,.88,'highpass=f=65,lowpass=f=1750')
high=layer('high',1.17,.96,'highpass=f=620,lowpass=f=5800')
def rms(a):return np.sqrt(np.mean(a*a))
low*=rms(lead)/max(rms(low),1e-9);high*=rms(lead)/max(rms(high),1e-9)
t=np.arange(N)/SR
dry=.94*lead+.46*low+.24*high
# A short rising edge and two overlapping vocal registers, no impact/explosion,
# metallic strike, random noise burst, or synthetic oscillator masking the voice.
dry*=np.interp(t,[0,.008,.018,.09,.38,.62,.85,1.2],[0,.72,.94,1,1.08,1,.25,0])
def delayed(a,seconds):
 n=round(seconds*SR);b=np.zeros(N);b[n:]=a[:-n];return b
left=dry.copy();right=dry.copy()
for seconds,gain in [(.037,.14),(.071,.10),(.113,.065),(.169,.035),(.227,.018)]:
 left+=delayed(dry,seconds)*gain
 right+=delayed(dry,seconds+.009)*gain
stereo=np.stack([left,right],1)
stereo*=np.minimum(1,np.maximum(0,(1.2-t)/.13))[:,None]
# Remove 20 ms of nearly silent source pre-roll so the audible vocal attack fits
# the existing face cue without moving the animation or adding a new timer.
stereo=np.concatenate([stereo[960:],np.zeros((960,2))],axis=0)
stereo*=10**(-4/20)/np.max(np.abs(stereo))
raw=S/'mix-f32le.raw';stereo.astype('<f4').tofile(raw)
dst=O/'awakening_scream.wav'
subprocess.run([FF,'-v','error','-y','-f','f32le','-ar',str(SR),'-ac','2','-i',str(raw),'-c:a','pcm_s16le',str(dst)],check=True)
meta={'file':dst.name,'source_title':'Female Scream 1','source_artist':'AuraVoice / Nocturnal_Vanguard',
 'source_page':'https://opengameart.org/content/female-scream-1','source_file':'https://opengameart.org/sites/default/files/female_scream_1.ogg',
 'source_license':'CC0 1.0 Universal','license_url':'https://creativecommons.org/publicdomain/zero/1.0/',
 'source_permission':'Recording author states use however you like and no credit required; CC0 permits commercial copying, modification, and distribution.',
 'provenance':'Real recorded human scream, edited into layered supernatural voice. NOT a wholly original vocal recording. No film or game extraction.',
 'processing':'Trim silence; foreground natural scream at 0.91 pitch; low throat at 0.49; high scream at 1.17; band limiting; envelope; short stereo reflections. No impact/explosion/noise layer.',
 'credit_required':False,'suggested_credit':'Female Scream 1 by AuraVoice (Nocturnal_Vanguard), CC0; edited for Makers & Challengers.',
 'sample_rate':SR,'channels':2,'bit_depth':16,'duration_seconds':N/SR,
 'peak_dbfs':float(20*np.log10(abs(stereo).max())),'rms_dbfs':float(20*np.log10(rms(stereo))),
 'leading_preroll_removed_ms':20,'strong_vocal_onset_seconds_approx':.010,'integration_status':'Standalone audition only; current game SE, awakening video and cue timing unchanged.',
 'sha256':hashlib.sha256(dst.read_bytes()).hexdigest(),
 'source_sha256':hashlib.sha256((S/'female_scream_1.ogg').read_bytes()).hexdigest()}
(O/'scream-provenance.json').write_text(json.dumps(meta,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(meta,ensure_ascii=False,indent=2))
