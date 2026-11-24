import numpy as np, wave
from scipy.signal import butter, sosfilt
SR=44100; DUR=52.0; N=int(SR*DUR); out=np.zeros(N)
rng=np.random.default_rng(1)
def lp(x,f,o=2): return sosfilt(butter(o,f,'low',fs=SR,output='sos'),x)
def bp(x,a,b): return sosfilt(butter(2,[a,b],'band',fs=SR,output='sos'),x)
def env(n,a,r):
    e=np.ones(n); ai=int(a*SR); ri=int(r*SR)
    e[:ai]=np.linspace(0,1,ai); e[-ri:]=np.linspace(1,0,ri); return e
def put(sig,t):
    i=int(t*SR); j=min(N,i+len(sig)); out[i:j]+=sig[:j-i]
tt=lambda d: np.arange(int(d*SR))/SR
# wind ambience 3.0-45.0
d=42.0; w=lp(rng.standard_normal(int(d*SR)),500); w/=np.abs(w).max()
mod=0.55+0.45*np.sin(2*np.pi*0.13*tt(d))*np.sin(2*np.pi*0.047*tt(d)+1)
put(w*mod*env(len(w),2.5,1.5)*0.10,3.0)
# bedroom: quiet room tone 0-3
rt=lp(rng.standard_normal(int(3.2*SR)),200); rt/=np.abs(rt).max(); put(rt*env(len(rt),.5,.6)*0.04,0)
# heartbeat 27.9-30.4 (accelerating), tail into shadow
def thump(f=55,d=0.22,a=1.0):
    x=tt(d); return a*np.sin(2*np.pi*f*x*(1-0.3*x/d))*np.exp(-x*18)
tb=27.9; period=0.6
while tb<30.3:
    put(thump(55,0.25,0.55),tb); put(thump(48,0.25,0.42),tb+0.16); tb+=period; period=max(0.42,period*0.93)
# boom when shadow falls 30.3
d=3.5; x=tt(d); f=70*np.exp(-x*0.6)+28
boom=np.sin(2*np.pi*np.cumsum(f)/SR)*np.exp(-x*1.1)*0.8
boom+=lp(rng.standard_normal(len(x)),150)*np.exp(-x*1.6)*2.5
put(boom*0.6,30.3)
# whoosh / reveal 36.0
d=1.6; x=tt(d); n=rng.standard_normal(len(x))
wh=bp(n,300,3000)*np.sin(np.pi*x/d)**2; put(wh/np.abs(wh).max()*0.18,35.6)
# low drone 36.1-45.0 rising
d=8.9; x=tt(d); dr=(np.sin(2*np.pi*41*x)+0.6*np.sin(2*np.pi*41.7*x)+0.3*np.sin(2*np.pi*82.3*x))
dr*= (0.25+0.75*x/d)*env(len(x),1.5,0.05)*0.11; put(dr,36.1)
# sting on "وجدناه" 43.9
d=1.2; x=tt(d); st=lp(rng.standard_normal(len(x)),400)*np.exp(-x*3); put(st/np.abs(st).max()*0.25,43.9)
out=np.clip(out,-1,1)
with wave.open('sfx.wav','wb') as f:
    f.setnchannels(1); f.setsampwidth(2); f.setframerate(SR); f.writeframes((out*32767).astype(np.int16).tobytes())
print('ok')
