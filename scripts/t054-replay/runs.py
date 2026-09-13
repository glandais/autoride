"""How long does the motion score stay above the threshold, riding vs not?

If the T054 premise held -- "the burst is 5 s, a ride is minutes" -- the two
run-length distributions would separate. They are read off `win`, which covers
both cases at 1 Hz: journeys and the phantom recordings the false starts opened.
"""
import bisect, collections, statistics
CONF=0.7
def ramp(v,lo,i,hi):
    if v<lo or v>hi: return 0.
    return 1. if v>=i else (v-lo)/(i-lo)
def mot(a,g): return .5*ramp(a,2,3,12)+.5*ramp(g,.4,.9,3)

starts,ends={},{}
for l in open('tripev.tsv'):
    p=l.rstrip('\n').split('\t'); t,tid,a=int(p[0]),int(p[1]),p[2]
    if a=='start': starts.setdefault(tid,t)
    elif a in ('stop','discard'): ends[tid]=(t,int(p[4]),int(p[7]))
T0=int(open('evals3.tsv').readline().split('\t')[0])
J,P={},{}
for tid,(te,dist,net) in ends.items():
    tsx=starts.get(tid)
    if tsx is None or tsx<T0: continue
    (J if (net>=100 or dist>=500) else P)[tid]=(tsx,te)
allj=sorted(list(J.items())+list(P.items()), key=lambda kv: kv[1][0]); jt=[v[1][0] for v in allj]
series=collections.defaultdict(list)
for l in open('win.tsv'):
    p=l.split('\t'); t=int(p[0])
    i=bisect.bisect_right(jt,t)-1
    if i>=0:
        tid,(tsx,te)=allj[i]
        if tsx<t<=te: series[tid].append((t,mot(float(p[1]),float(p[2]))))

def runs(ids):
    out=[]; above=0; total=0
    for tid in ids:
        r=0; prev=None
        for t,m in series.get(tid,[]):
            total+=1
            if prev is not None and t-prev>5000:
                if r: out.append(r)
                r=0
            prev=t
            if m>=CONF: r+=1; above+=1
            else:
                if r: out.append(r)
                r=0
        if r: out.append(r)
    return sorted(out), (above/total if total else 0), total

for name, ids in (("deplacements reels", J), ("enregistrements fantomes", P)):
    r, duty, total = runs(ids)
    if not r: continue
    q=lambda p: r[min(len(r)-1,int(len(r)*p))]
    print(f"{name:>26} : {total/3600:5.1f} h, cycle de service {duty*100:5.1f} %  "
          f"| bouffees n={len(r):4d}  med {q(.5):3d}s  p90 {q(.9):3d}s  p99 {q(.99):4d}s  max {r[-1]:4d}s")
    hist=collections.Counter(min(x,60) for x in r)
    print(f"{'':>26}   >=3s {sum(1 for x in r if x>=3):4d}   >=5s {sum(1 for x in r if x>=5):4d}"
          f"   >=10s {sum(1 for x in r if x>=10):4d}   >=20s {sum(1 for x in r if x>=20):4d}"
          f"   >=30s {sum(1 for x in r if x>=30):4d}   >=60s {sum(1 for x in r if x>=60):4d}")
