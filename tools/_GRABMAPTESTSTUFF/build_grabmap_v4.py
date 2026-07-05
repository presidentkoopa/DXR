#!/usr/bin/env python3
# GRABMAP v4 - DoomXR feature-showcase ninja course, built from the swarm's validated spec.
# Zones: START/throw, CLIMB (real-tex only), WHIP chasm+stairs, ICEHOOK tower, static PORTAL
# (Line_SetPortal 156 with explicit id=), GRAVITY goal ledge, LEAP islands, SDF gallery+finish,
# FIRING/PARRY spur, RELOAD RANGE (manual-reload gauntlet). Generated geometry, validated
# (closure/dangling/portal/things/gutters).
import struct, sys, json

verts=[]; lines=[]; sides=[]; sectors=[]; things=[]; markers=[]; footprints=[]; pillars=[]
def V(x,y): verts.append((float(x),float(y))); return len(verts)-1
def SEC(fh,ch,ft,ct,light):
    sectors.append(dict(fh=fh,ch=ch,ft=ft,ct=ct,light=light)); return len(sectors)-1
def SD(sec,mid="-",top="-",bot="-"):
    sides.append(dict(sec=sec,mid=mid,top=top,bot=bot)); return len(sides)-1
def LN(v1,v2,front,back=-1,block=False,climb_tex=None,climb_kw=False,special=0,args=(0,0,0,0,0),lid=None):
    lines.append(dict(v1=v1,v2=v2,front=front,back=back,block=block,climb_tex=climb_tex,
                      climb_kw=climb_kw,special=special,args=args,lid=lid))
def THING(x,y,typ,ang=0): things.append(dict(x=x,y=y,ang=ang,typ=typ))
def SDF(shape,x,y,z,color,anim=""): markers.append(dict(shape=shape,x=x,y=y,z=z,color=color,anim=anim))
def signed_area(p):
    a=0.0
    for i in range(len(p)):
        x1,y1=p[i]; x2,y2=p[(i+1)%len(p)]; a+=x1*y2-x2*y1
    return a*0.5
def loop(coords, want_cw):
    if (signed_area(coords)<0)!=want_cw: coords=list(reversed(coords))
    return [V(x,y) for (x,y) in coords]

ROOMCEIL=2560   # tall open-sky room so the aerial gravity coaster has airspace above the course
room=SEC(0,ROOMCEIL,"FLOOR0_1","F_SKY1",200)
planks=[]       # aerial gravity-coaster tiles: dict(pos,normal,tangent,length)

def platform(x0,y0,x1,y1,floorh,ceilh=ROOMCEIL,ctex="F_SKY1",ftex="FLOOR4_8",bot="METAL",light=175,name="plat"):
    ps=SEC(floorh,ceilh,ftex,ctex,light)
    vs=loop([(x0,y0),(x0,y1),(x1,y1),(x1,y0)], want_cw=False)   # CCW: front=room, back=platform
    for k in range(4):
        v1=vs[k]; v2=vs[(k+1)%4]
        top = "STARTAN2" if ceilh<ROOMCEIL else "-"            # upper tex if our ceiling is below room
        LN(v1,v2, SD(room, bot=bot, top=top), back=SD(ps), block=False)
    footprints.append((name,min(x0,x1),min(y0,y1),max(x0,x1),max(y0,y1)))
    return ps

def void_pillar(cx,cy,half,tex,climb=True,name="pillar"):
    quad=[(cx-half,cy-half),(cx-half,cy+half),(cx+half,cy+half),(cx+half,cy-half)]
    vs=loop(quad, want_cw=False)          # hole: CCW, front=room, wall tex in MID
    for k in range(4):
        LN(vs[k],vs[(k+1)%4], SD(room, mid=tex), back=-1, block=True,
           climb_tex=(tex if climb else None))
    pillars.append((cx-half,cy-half,cx+half,cy+half))
    footprints.append((name,cx-half,cy-half,cx+half,cy+half))

def portal_booth(bx0,by0,bx1,by1,my_id,target_id,name="portal"):
    # booth (floor 0, real ceiling) + alcove behind, both sub-areas of the room floor, sharing the
    # seam line. All outer edges 2-sided to room (CCW, front=room); the seam is an internal T-junction.
    booth=SEC(0,ROOMCEIL,"FLOOR0_1","CEIL1_1",185)
    alc  =SEC(0,ROOMCEIL,"FLOOR0_1","CEIL1_1",150)
    bl=V(bx0,by0); br=V(bx1,by0); tr=V(bx1,by1); tl=V(bx0,by1)
    ar=V(bx1,by1+56); al=V(bx0,by1+56)
    LN(bl,br, SD(room), back=SD(booth), block=False)   # booth south
    LN(br,tr, SD(room), back=SD(booth), block=False)   # booth east
    LN(tr,ar, SD(room), back=SD(alc),   block=False)   # alcove east
    LN(ar,al, SD(room), back=SD(alc),   block=False)   # alcove north
    LN(al,tl, SD(room), back=SD(alc),   block=False)   # alcove west
    LN(tl,bl, SD(room), back=SD(booth), block=False)   # booth west
    LN(tl,tr, SD(booth), back=SD(alc), block=False,    # SEAM + portal special
       special=156, args=(target_id,0,3,0,0), lid=my_id)
    footprints.append((name,bx0,by0,bx1,by1+56))

# player start
THING(0,-1250,1,90)

# =============== START / throw pit ===============
for (x,y) in [(-480,-980),(-360,-960),(-600,-960),(-480,-1080)]: THING(x,y,2035)   # barrels
for (x,y) in [(-480,-380),(-380,-340),(-580,-340)]: THING(x,y,3004,270)            # zombie cluster
SDF(0,0,-1050,120,"0.10,0.90,1.00","pulse,spin1.5")
SDF(3,0,-1050,175,"1.00,0.85,0.10","pulse,spin1.5,bob8")
SDF(2,-480,-960,170,"1.00,0.48,0.10","pulse,spin6,bob8")

# =============== CLIMB gauntlet (IWAD-real climb tex only + STARTAN2 control) ===============
CLIMB=["SUPPORT2","SUPPORT3","PIPE1","PIPE2","PIPE4","PIPE6","METAL","BROWN96","COMPTALL","TEKWALL"]
tex_row=CLIMB+["STARTAN2"]
spacing=280; startx=-(spacing*(len(tex_row)-1))/2.0; py=-650
for i,tex in enumerate(tex_row):
    void_pillar(startx+i*spacing, py, 48, tex, climb=(tex!="STARTAN2"), name="climbpillar%d"%i)
platform(-1500,-560,1500,-460,192,ftex="FLOOR4_8",bot="METAL",name="climbshelf")
SDF(272,0,-760,180,"0.20,1.00,0.35","pulse,bob6")
SDF(272,1400,-760,180,"1.00,0.15,0.15","")   # red obelisk = STARTAN2 no-climb control

# =============== WHIP chasm ===============
platform(-1500,100,1500,200,192,bot="METAL",name="whipledge")
platform(-260,-120,260,-20,512,bot="METAL",name="whipanchor")
# (west recovery stairs dropped: abutting platforms made coincident verts. A single standalone
#  recovery island instead -- no shared edges with anything, so it can't create dangling lines.)
platform(-1720,-260,-1590,-120,96,bot="METAL",name="whiprecover")
THING(0,-70,3004,270)   # zombie on the 512 anchor = entangle-yank target
SDF(512,0,-300,160,"1.00,0.48,0.10","pulse,bob10")
SDF(512,0,150,232,"0.24,0.47,1.00","pulse,spin1.5")

# =============== ICEHOOK free-climb tower ===============
void_pillar(-1200,540,140,"STARTAN2",climb=False,name="icehooktower")
platform(-1340,760,-1060,900,384,bot="METAL",name="icehookledge")
SDF(272,-1200,300,180,"0.55,0.20,1.00","pulse,bob6")

# =============== PORTAL (static linked, id 900/901) ===============
portal_booth(-680,300,-520,440,900,901,name="portalA")
portal_booth(520,800,680,940,901,900,name="portalB")
SDF(288,-600,370,220,"1.00,1.00,1.00","pulse")     # same white spin-cross at both = "linked"
SDF(288,600,870,220,"1.00,1.00,1.00","pulse")
SDF(0,-600,370,320,"0.10,0.90,1.00","pulse,spin-2")

# =============== GRAVITY goal ledge (VR paint-a-path target; ceiling chamber DROPPED) ===============
platform(1550,300,1736,900,512,bot="METAL",name="gravgoal")
SDF(304,700,300,180,"0.70,0.16,1.00","pulse,spin3,bob6")
SDF(512,1200,600,404,"0.55,0.25,1.00","")

# =============== LEAP islands ===============
platform(-500,960,-100,1120,256,bot="METAL",name="leap1")
platform(100,1180,500,1340,384,bot="METAL",name="leap2")
platform(-500,1400,-100,1560,512,bot="METAL",name="leap3")
platform(100,1620,500,1780,640,bot="METAL",name="leap4")
SDF(256,-300,1280,300,"1.00,0.85,0.10","pulse,bob4")

# =============== SDF gallery + FINISH (things/billboards only) ===============
gallery=[0,1,2,3,512,256,272,288,304]
gcol=["0.10,0.90,1.00","0.20,1.00,0.40","1.00,0.48,0.10","1.00,0.85,0.10","0.24,0.47,1.00",
      "1.00,0.85,0.10","0.20,1.00,0.35","1.00,0.15,1.00","0.70,0.16,1.00"]
for i,sh in enumerate(gallery):
    SDF(sh, -1600+i*400, 1810, 160, gcol[i], "pulse,spin3")
SDF(3,0,1840,300,"1.00,0.85,0.10","pulse,spin3,bob6")   # finish beacon

# =============== FIRING / PARRY west spur ===============
platform(-1736,-900,-1560,-720,64,bot="METAL",name="firepedestal")
THING(-1650,-810,3001,0)   # imp
THING(-1650,-790,3004,0)   # zombie (hitscan parry)
SDF(272,-1400,-810,130,"1.00,0.30,0.20","pulse")
SDF(288,-1400,-640,175,"1.00,0.15,1.00","pulse,bob6")

# =============== RELOAD RANGE (manual-reload gauntlet, east/south spur) ===============
# Firing box the player stands in, weapon pedestals behind, ammo caches to force empties,
# and four downrange dummies at increasing distance so a full mag rarely covers the run.
platform(300,-1400,700,-1300,64,bot="METAL",name="reloadbox")
THING(320,-1340,2001,90)   # shotgun
THING(360,-1340,2002,90)   # chaingun
THING(400,-1340,2003,90)   # rocket launcher
THING(440,-1340,2004,90)   # plasma rifle
THING(500,-1360,2008,90)   # shotgun shells
THING(540,-1360,2008,90)   # shotgun shells
THING(580,-1360,2007,90)   # clip
THING(620,-1360,2047,90)   # cell
THING(660,-1360,2010,90)   # rocket ammo
for (x,y) in [(1000,-1340),(1200,-1340),(1400,-1340),(1600,-1340)]: THING(x,y,3004,180)   # zombie dummies at range
THING(1300,-1420,3001,180)   # imp behind the line, punishes a slow reload
SDF(0,500,-1340,120,"1.00,0.85,0.10","pulse,spin2")     # dispensary marker
SDF(3,1600,-1340,180,"1.00,0.15,0.15","pulse,bob6")     # far dummy beacon

# =============== AERIAL GRAVITY COASTER (planks above the arena; reuses baked XR_GravityPathNode) ===============
import math as _m
def _u(v):
    l=_m.sqrt(v[0]*v[0]+v[1]*v[1]+v[2]*v[2]) or 1.0; return (v[0]/l,v[1]/l,v[2]/l)
def _x(a,b): return (a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0])
def _rot(v,k,deg):
    k=_u(k); t=_m.radians(deg); c=_m.cos(t); s=_m.sin(t); kv=_x(k,v); kd=k[0]*v[0]+k[1]*v[1]+k[2]*v[2]
    return (v[0]*c+kv[0]*s+k[0]*kd*(1-c), v[1]*c+kv[1]*s+k[1]*kd*(1-c), v[2]*c+kv[2]*s+k[2]*kd*(1-c))
_SEG=80.0; _TLEN=104.0
_P=[0.0,1250.0,4.0]; _F=(0.0,-1.0,0.0); _U=(0.0,0.0,1.0)   # RAMP BASE on the arena floor (walk on here), heading south
def _run(steps,yaw,pitch,roll):
    global _P,_F,_U
    for _ in range(steps):
        planks.append(dict(pos=tuple(_P),normal=_u(_U),tangent=_u(_F),length=_TLEN))
        _P=[_P[0]+_F[0]*_SEG,_P[1]+_F[1]*_SEG,_P[2]+_F[2]*_SEG]
        R=_u(_x(_F,_U))
        F,U=_F,_U
        if yaw: F=_rot(F,U,yaw)
        if pitch: F=_rot(F,R,pitch); U=_rot(U,R,pitch)
        if roll: U=_rot(U,F,roll)
        _F=_u(F); _U=_u(U)
# --- WALK-UP RAMP (all gravity tiles): arena floor -> coaster height ---
_run(3, 0.0, 0.0, 0.0)     # flat base you step onto from the floor (z~4)
_run(4, 0.0, 12.0, 0.0)    # curve upward
_run(6, 0.0, 0.0, 0.0)     # straight ~48deg climb
_run(4, 0.0,-12.0, 0.0)    # level off at the top (into coaster height)
# --- COASTER (flows straight out of the ramp top) ---
_run(4, 0.0, 0.0, 0.0)     # lead-in
_run(9, 11.0,0.0, 8.0)     # banked sweep
_run(6, 0.0, 7.0, 0.0)     # climb
_run(18,0.0, 20.0,0.0)     # FULL vertical LOOP
_run(12,9.0, 0.0, 10.0)    # corkscrew
_run(6, 0.0,-7.0, 0.0)     # level out
_run(6, 0.0, 0.0, 0.0)     # run-out
SDF(3, 0,1250,120,"0.1,1.0,0.4","pulse,spin4,bob8")   # green START beacon at the ramp base (ground)
SDF(0, 0,1250,220,"1.0,0.9,0.1","pulse,spin-3")        # gold ring: "ride starts here"

# =============== outer wall (built last; room already sector 0) ===============
minx,maxx,miny,maxy=-1800,1800,-1500,1850
outer=loop([(minx,miny),(minx,maxy),(maxx,maxy),(maxx,miny)], want_cw=True)
for i in range(4):
    LN(outer[i],outer[(i+1)%4], SD(room, mid="BROWNGRN"), back=-1, block=True)

# =================== VALIDATION ===================
def validate():
    from collections import Counter, defaultdict
    err=[]; warn=[]
    V_=len(verts)
    # global vertex degree (dangling)
    deg=Counter()
    for L in lines: deg[L["v1"]]+=1; deg[L["v2"]]+=1
    dangling=[v for v in range(V_) if deg[v]<2]
    if dangling: err.append("DANGLING vertices (deg<2): %s"%dangling[:8])
    # per-sector closure
    secedge=defaultdict(lambda:defaultdict(int))
    for L in lines:
        s=[sides[L["front"]]["sec"]]
        if L["back"]>=0: s.append(sides[L["back"]]["sec"])
        for sec,c in Counter(s).items():
            if c%2: secedge[sec][L["v1"]]+=1; secedge[sec][L["v2"]]+=1
    for sec,d in secedge.items():
        if [v for v,c in d.items() if c%2]: err.append("sector %d NOT closed"%sec)
    # duplicate distinct verts at same coords (un-merged shared corner)
    seen={}
    for i,(x,y) in enumerate(verts):
        k=(round(x,2),round(y,2))
        if k in seen: warn.append("dup vert coords %s idx %d & %d"%(k,seen[k],i))
        else: seen[k]=i
    # portal linkage
    ids=Counter(L["lid"] for L in lines if L["lid"] is not None)
    if ids.get(900)!=1 or ids.get(901)!=1: err.append("portal ids bad: %s"%dict(ids))
    for L in lines:
        if L["lid"]==900 and L["args"][0]!=901: err.append("seam900 arg0!=901")
        if L["lid"]==901 and L["args"][0]!=900: err.append("seam901 arg0!=900")
        if L["lid"] in (900,901) and L["block"]: err.append("portal seam is blocking")
    # things not inside a void pillar
    for T in things:
        for (x0,y0,x1,y1) in pillars:
            if x0<T["x"]<x1 and y0<T["y"]<y1: err.append("THING type %d inside pillar"%T["typ"])
    # gutter check (footprints with overlapping y-band need x-gap>=64; all >=64 from perimeter)
    for i in range(len(footprints)):
        n1,ax0,ay0,ax1,ay1=footprints[i]
        if ax0<minx+64 or ax1>maxx-64 or ay0<miny+64 or ay1>maxy-64:
            warn.append("%s within 64u of perimeter"%n1)
        for j in range(i+1,len(footprints)):
            n2,bx0,by0,bx1,by1=footprints[j]
            yov=not(ay1<=by0 or by1<=ay0); xov=not(ax1<=bx0 or bx1<=ax0)
            if xov and yov: err.append("OVERLAP %s & %s"%(n1,n2))
    zmax=0
    for pk in planks:
        px,py,pz=pk["pos"]; zmax=max(zmax,pz)
        if pz>=ROOMCEIL-48 or pz<0: err.append("plank z out of room: %.0f"%pz)
        if px<minx+16 or px>maxx-16 or py<miny+16 or py>maxy-16: warn.append("plank XY over perimeter (%.0f,%.0f)"%(px,py))
    if planks: print("coaster: %d planks, z range %.0f..%.0f (ceil %d)"%(len(planks),min(p["pos"][2] for p in planks),zmax,ROOMCEIL))
    return err,warn

err,warn=validate()
print("counts: V=%d L=%d S=%d SEC=%d T=%d SDF=%d"%(len(verts),len(lines),len(sides),len(sectors),len(things),len(markers)))
print("ERRORS:", err if err else "NONE")
print("WARN(%d):"%len(warn), warn[:12])

# =================== EMIT ===================
def emit():
    o=['namespace = "zdoom";\n']
    for (x,y) in verts: o.append("vertex{x=%.3f;y=%.3f;}\n"%(x,y))
    for L in lines:
        s=["v1=%d;v2=%d;sidefront=%d;"%(L["v1"],L["v2"],L["front"])]
        if L["back"]>=0: s.append("sideback=%d;twosided=true;"%L["back"])
        if L["block"]: s.append("blocking=true;")
        if L["lid"] is not None: s.append("id=%d;"%L["lid"])
        if L["special"]:
            a=L["args"]; s.append("special=%d;arg0=%d;arg1=%d;arg2=%d;arg3=%d;arg4=%d;"%(L["special"],a[0],a[1],a[2],a[3],a[4]))
        if L["climb_kw"]: s.append('keywords="climb:CLIMBABLE";')
        o.append("linedef{%s}\n"%"".join(s))
    for S in sides:
        o.append('sidedef{sector=%d;texturemiddle="%s";texturetop="%s";texturebottom="%s";}\n'%(S["sec"],S["mid"],S["top"],S["bot"]))
    for S in sectors:
        o.append('sector{heightfloor=%d;heightceiling=%d;texturefloor="%s";textureceiling="%s";lightlevel=%d;}\n'%(S["fh"],S["ch"],S["ft"],S["ct"],S["light"]))
    for T in things:
        o.append("thing{x=%.3f;y=%.3f;angle=%d;type=%d;skill1=true;skill2=true;skill3=true;skill4=true;skill5=true;single=true;coop=true;dm=true;}\n"%(T["x"],T["y"],T["ang"],T["typ"]))
    def _pa(v):
        v=_u(v)
        return int(round(_m.degrees(_m.acos(max(-1.0,min(1.0,v[2])))))), int(round(_m.degrees(_m.atan2(v[1],v[0]))%360.0))
    for i,pk in enumerate(planks):
        npol,nazi=_pa(pk["normal"]); tpol,tazi=_pa(pk["tangent"])
        o.append(("thing{x=%.3f;y=%.3f;height=%.3f;angle=%d;type=30500;arg0=%d;arg1=%d;arg2=%d;arg3=%d;arg4=%d;"
                  "skill1=true;skill2=true;skill3=true;skill4=true;skill5=true;single=true;coop=true;dm=true;}\n")
                 %(pk["pos"][0],pk["pos"][1],pk["pos"][2],i,npol,nazi,tpol,tazi,int(pk["length"])))
    return "".join(o).encode("ascii")
def wad(lumps):
    data=b""; d=[]; off=12
    for n,b in lumps: d.append((off,len(b),n)); data+=b; off+=len(b)
    dirt=b""
    for fp,sz,n in d:
        nm=n.encode()[:8]; nm+=b"\x00"*(8-len(nm)); dirt+=struct.pack("<ii",fp,sz)+nm
    return b"PWAD"+struct.pack("<ii",len(lumps),12+len(data))+data+dirt

if not err:
    zmap=(b'DoomEdNums { 30500 = XR_GravPlank }\n'
          b'map GRABMAP "VR SHOWCASE NINJA COURSE"\n{\n    sky1="SKY1"\n    music="D_RUNNIN"\n    cluster=1\n}\n')
    # v4 adds a RELOAD RANGE spur alongside the v3 ninja course zones.
    blob=wad([("ZMAPINFO",zmap),("GRABMAP",b""),("TEXTMAP",emit()),("ENDMAP",b"")])
    for out in sys.argv[1:]:
        if out.endswith(".wad"): open(out,"wb").write(blob)
        elif out.endswith(".json"): json.dump(markers,open(out,"w"))
    print("wrote wad (%d bytes) + %d markers"%(len(blob),len(markers)))
else:
    print("NOT WRITING — fix errors first")
