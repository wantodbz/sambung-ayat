"""Uji ujung-ke-ujung Murajaah: murottal -> potong di jeda -> whisper.cpp -> koreksi.
Port Python dari lib/services/wav.dart dan lib/services/matcher.dart.
Pemakaian: python3 tool/e2e_test.py <model.bin> <whisper-main> <surat> [folder-qari]"""
import json, math, os, subprocess, sys, time, urllib.request, wave, array
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
Q = json.load(open(os.path.join(ROOT, "assets", "quran.json"), encoding="utf-8"))
def T(s, a): return Q["surahs"][s-1]["verses"][a-1]
def normalize(s):
    out=[]
    for idx,ch in enumerate(s):
        r=ord(ch)
        if r==0x648 and idx+1<len(s) and ord(s[idx+1])==0x670: continue
        if (0x610<=r<=0x61A) or (0x64B<=r<=0x65F) or r==0x670 or (0x6D6<=r<=0x6ED) or r==0x640: continue
        if r in (0x621,0x622,0x623,0x625,0x627,0x671): continue
        if r==0x624: out.append('و'); continue
        if r in (0x626,0x649,0x6CC): out.append('ي'); continue
        if r==0x629: out.append('ه'); continue
        if r==0x6A9: out.append('ك'); continue
        if 0x621<=r<=0x64A: out.append(ch)
    return ''.join(out)
def last_row(a,b):
    n=len(b); prev=list(range(n+1))
    for i in range(1,len(a)+1):
        cur=[i]+[0]*n
        for j in range(1,n+1):
            cur[j]=min(prev[j-1]+(a[i-1]!=b[j-1]), prev[j]+1, cur[j-1]+1)
        prev=cur
    return prev
def sim(a,b):
    m=max(len(a),len(b)); return 1 if m==0 else 1-last_row(a,b)[len(b)]/m
def match_start(exp,heard):
    if not heard or not exp: return (0,0,False)
    row=last_row(exp,heard); L=len(exp); best=-1; bj=0
    for j in range(max(1,L//2),len(heard)+1):
        s=1-row[j]/max(L,j)
        if s>best+1e-9: best=s; bj=j
    if best<0: return (0,0,False)
    tl=min(8,L); tail=exp[L-tl:]; ts=0
    for w in range(tl-2,tl+3):
        if w<=0 or bj-w<0: continue
        ts=max(ts,sim(tail,heard[bj-w:bj]))
    return (best,bj,ts>=0.6)
def prefix_sim(exp,heard):
    if not heard: return 1
    row=last_row(heard,exp); m=len(heard)
    return max(1-row[j]/max(m,j) for j in range(1,len(exp)+1))
BAS=normalize(T(1,1)); TAA=normalize('أعوذ بالله من الشيطان الرجيم')
def leading(heard,exp):
    cut=0
    for p in (TAA,BAS):
        if p is BAS and exp.startswith(BAS): continue
        rest=heard[cut:]
        if len(rest) < int(len(p)*0.85): continue
        r=match_start(p,rest)
        if r[0]>=0.8: cut+=r[1]
    return cut
NAMES={'ا':'الف','ل':'لام','م':'ميم','ص':'صاد','ر':'را','ك':'كاف','ه':'ها','ي':'يا','ع':'عين','ط':'طا','س':'سين','ح':'حا','ق':'قاف','ن':'نون','ٱ':'الف'}
MQ={2,3,7,10,11,12,13,14,15,19,20,26,27,28,29,30,31,32,36,38,40,41,42,43,44,45,46,50,68}
def cands(s,a):
    t=T(s,a); c=[normalize(t)]
    if (a==1 and s in MQ) or (s==42 and a==2):
        w=t.split(' '); sp=''.join(NAMES.get(ch,'') for ch in w[0]); c.append(normalize(sp+' '+' '.join(w[1:])))
    return c
def align_segment(exp, heard, frm, slack, max_span):
    s=heard[frm:frm+slack+max_span]; n=len(s); L=len(exp)
    if n==0 or L==0: return (0.0, frm)
    # biaya: substitusi 2, sisipan (huruf lebih di bacaan) 2, huruf ayat tak tertangkap 1
    prev=[0 if j<=slack else 2*(j-slack) for j in range(n+1)]
    for i in range(1,L+1):
        cur=[i]+[0]*n; ca=exp[i-1]
        for j in range(1,n+1):
            cur[j]=min(prev[j-1]+(0 if ca==s[j-1] else 2), prev[j]+1, cur[j-1]+2)
        prev=cur
    bj=min(range(n+1), key=lambda j:(prev[j], j))
    return (1-prev[bj]/(2*L), frm+bj)

def best_align(sa, heard, pos, slack):
    best=(-1,pos)
    for c in cands(*sa):
        r=align_segment(c, heard, pos, slack, 2*len(c)+40)
        if r[0]>best[0]: best=r
    return best

def review(ayahs, heard, thr=0.75, debug=False):
    pos=leading(heard, cands(*ayahs[0])[0]); slack=25; res=[]
    for i,sa in enumerate(ayahs):
        if pos >= len(heard)-1:
            res.append((sa,'TIDAK TERBACA',0)); continue
        if sa[1]==1: slack=max(slack,25)   # basmalah boleh dibaca di awal surat
        best=best_align(sa, heard, pos, slack)
        if debug and sa in debug: print('DBG', sa, best, pos, slack, heard[pos:pos+60], '| exp', cands(*sa)[0])
        if best[0]>=thr:
            res.append((sa,'BENAR',round(best[0],2))); pos=best[1]; slack=6; continue
        res.append((sa,'SALAH',round(best[0],2)))
        L=len(cands(*sa)[0])
        if i+1<len(ayahs):
            nxt=ayahs[i+1]
            a1=best_align(nxt, heard, pos, slack+L+20)   # ayat i dianggap terlewat
            a2=best_align(nxt, heard, best[1], 6)        # ayat i dianggap terbaca (salah)
            if a1[0]>a2[0]+0.05: slack=slack+L+20
            else: pos=best[1]; slack=6
    return res


def split_on_pauses(pcm, sr=16000):
    frame = sr // 50; n = len(pcm) // frame
    rms = [math.sqrt(sum(x*x for x in pcm[f*frame:(f+1)*frame]) / frame) for f in range(n)]
    floor = sorted(rms)[int(n*0.1)]; speech = max(floor*3, 0.004)
    maxlen, minlen, win = 28*50, 12*50, 7
    def around(f): return sum(rms[max(0,f-win):min(n-1,f+win)+1])
    out = []; start = 0
    while start < n:
        if n - start <= maxlen: end = n
        else:
            end = min(range(start+minlen, start+maxlen+1), key=around)
        if sum(1 for f in range(start, end) if rms[f] > speech) >= 15:
            out.append(pcm[start*frame: len(pcm) if end == n else end*frame])
        start = end
    return out

def main():
    model, wmain, s = sys.argv[1], sys.argv[2], int(sys.argv[3])
    reciter = sys.argv[4] if len(sys.argv) > 4 else "Ayman_Sowaid_64kbps"
    n = len(Q["surahs"][s-1]["verses"])
    files = []
    for a in range(1, n+1):
        fn = f"{s:03d}{a:03d}.mp3"
        if not os.path.exists(fn):
            urllib.request.urlretrieve(f"https://everyayah.com/data/{reciter}/{fn}", fn)
        files.append(fn)
    subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", "concat:" + "|".join(files),
                    "-ar", "16000", "-ac", "1", "-c:a", "pcm_s16le", "full.wav"], check=True)
    w = wave.open("full.wav"); raw = array.array("h", w.readframes(w.getnframes())); w.close()
    pcm = [x/32768.0 for x in raw]
    chunks = split_on_pauses(pcm)
    t0 = time.time(); texts = []
    for i, c in enumerate(chunks):
        cw = wave.open(f"c{i}.wav", "wb"); cw.setnchannels(1); cw.setsampwidth(2); cw.setframerate(16000)
        cw.writeframes(array.array("h", [max(-32768, min(32767, int(x*32768))) for x in c]).tobytes()); cw.close()
        r = subprocess.run([wmain, "-m", model, "-l", "ar", "-nt", "-t", "4", "-f", f"c{i}.wav"],
                           capture_output=True, text=True)
        texts.append(r.stdout.strip())
    dt = time.time() - t0
    heard = normalize(" ".join(texts))
    ayahs = [(s, a) for a in range(1, n+1)]
    res = review(ayahs, heard)
    bad = [(x[0][1], x[1], x[2]) for x in res if x[1] != "BENAR"]
    name = os.path.basename(model)
    dur = len(pcm)/16000
    print(f"::notice title={name} surat {s}::audio {dur:.0f}s, {len(chunks)} potongan, proses {dt:.0f}s, "
          f"benar {n-len(bad)}/{n}, salah: {bad}")
    for i, t in enumerate(texts[:3]):
        print(f"potongan {i}: {t}")

if __name__ == "__main__":
    main()
