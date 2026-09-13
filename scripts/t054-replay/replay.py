"""T054 replay, corrected for the truncation bias on BOTH sides.

The 3-second rule truncates every positive run at 3 seconds: the trip opens and
`start` stops. But the seconds that follow are not lost -- once the trip is
active the stop path emits `win` at 1 Hz, and `win.sd`/`win.gy` are the same
StationaryWindow statistics (1.5 s instead of 1 s; validated at the seam, median
2.97 against the asd 2.92 that fired it, from one second in).

So every run the baseline cut short can be continued into `win` and asked
whether a longer rule would have sustained it. Without that continuation a
longer streak looks free at rest, because the evidence that would have
convicted it was blacked out.
"""
import bisect, collections, statistics

CONF=0.7; ASD=(2.,3.,12.); GAV=(.4,.9,3.)
def ramp(v,lo,i,hi):
    if v<lo or v>hi: return 0.
    return 1. if v>=i else (v-lo)/(i-lo)
def mot(a,g): return .5*ramp(a,*ASD)+.5*ramp(g,*GAV)

class Streak:
    def __init__(s,n): s.need,s.name=n,f"streak {n}s"
    def reset(s): s.run=0
    def step(s,m):
        s.run=s.run+1 if m>=CONF else 0
        return s.run>=s.need
class Duty:
    def __init__(s,w,d): s.w,s.d,s.name=w,d,f"duty {int(d*100)}%/{w}s"
    def reset(s): s.buf=[]
    def step(s,m):
        s.buf.append(m>=CONF)
        if len(s.buf)>s.w: s.buf.pop(0)
        return len(s.buf)==s.w and sum(s.buf)>=s.d*s.w
RULES=[Streak(n) for n in (3,4,5,6,8,10,15,20,30)]+\
      [Duty(w,d) for w,d in ((15,.5),(15,.7),(30,.4),(30,.5),(30,.7),(60,.3),(60,.5),(120,.3))]

starts,ends={},{}
for l in open('tripev.tsv'):
    p=l.rstrip('\n').split('\t'); t,tid,a=int(p[0]),int(p[1]),p[2]
    if a=='start': starts.setdefault(tid,t)
    elif a in ('stop','discard'): ends[tid]=(t,int(p[4]),int(p[7]))
evals=[]
for l in open('evals3.tsv'):
    p=l.rstrip('\n').split('\t')
    evals.append((int(p[0]), mot(float(p[4]),float(p[5])) if int(p[6])>=5 else 0.))
T0=evals[0][0]
journeys=[];phantoms=[]
for tid,(te,dist,net) in sorted(ends.items(),key=lambda kv:kv[1][0]):
    tsx=starts.get(tid)
    if tsx is None or tsx<T0: continue
    (journeys if (net>=100 or dist>=500) else phantoms).append((tid,tsx,te))

win=collections.defaultdict(list)
allj=sorted(journeys+phantoms,key=lambda x:x[1]); jt=[x[1] for x in allj]
for l in open('win.tsv'):
    p=l.split('\t'); t=int(p[0])
    i=bisect.bisect_right(jt,t)-1
    if i>=0:
        tid,tsx,te=allj[i]
        if tsx<=t<=te: win[tid].append((t,mot(float(p[1]),float(p[2]))))
# the trip-start second reads 0 because the stop window is cleared there
for k in win: win[k]=[x for x in win[k] if x[0]>starts[k]]

byid={tid:(tsx,te) for tid,tsx,te in allj}
def continuation(t):
    """The motion score series of the recording the baseline opened at t."""
    for tid,(tsx,te) in byid.items():
        if abs(tsx-t)<=2000: return win.get(tid,[])
    return []

def latency(rule):
    out={}
    for tid,tsx,te in journeys:
        s=win.get(tid,[])
        if len(s)<10: continue
        rule.reset(); prev=None
        for t,m in s:
            if prev is not None and t-prev>5000: rule.reset()
            prev=t
            if rule.step(m): out[tid]=(t-tsx)/1000; break
    return out, sum(1 for tid,_,_ in journeys if len(win.get(tid,[]))>=10)

jw=[(tsx-900_000,te) for _,tsx,te in journeys]
def at_rest(t): return not any(a<=t<=b for a,b in jw)

def rest_fires(rule):
    rule.reset(); n=0; prev=None; black=0; observed=0; carried=0
    for t,m in evals:
        if t<black: prev=t; continue
        if prev is not None:
            d=t-prev
            if d>5000: rule.reset()
            elif at_rest(t): observed+=d
        prev=t
        fired=rule.step(m)
        if not fired:
            # the baseline may have cut this run short here; follow it into the
            # recording it opened rather than pretending the run ended.
            cont=continuation(t)
            if cont:
                ct=None
                for ct2,cm in cont:
                    if rule.step(cm): fired=True; ct=ct2; break
                if fired: carried+=1; t=ct
        if fired:
            if at_rest(t): n+=1
            rule.reset(); black=t+420_000
    return n, observed/3.6e6, carried

print(f"corpus : {len(journeys)} deplacements reels, {len(phantoms)} fantomes, "
      f"{sum(len(v) for v in win.values())/3600:.1f} h de `win` exploitables\n")
print(f"{'regle':>13} | {'departs':>9} {'latence med':>12} {'p90':>7} {'pire':>7} | {'repos':>6} {'/24h':>6} {'(suites)':>9}")
print("-"*84)
for r in RULES:
    lat,cov=latency(r); v=sorted(lat.values())
    n,h,carried=rest_fires(r)
    med=f"{statistics.median(v):.0f}s" if v else "--"
    p90=f"{v[int(len(v)*.9)]:.0f}s" if v else "--"
    wst=f"{max(v):.0f}s" if v else "--"
    print(f"{r.name:>13} | {len(v):>3}/{cov:<5} {med:>12} {p90:>7} {wst:>7} | {n:>6} {n/(h/24):>6.1f} {carried:>9}")
print(f"\ntemps au repos observe : {rest_fires(Streak(3))[1]:.1f} h")
