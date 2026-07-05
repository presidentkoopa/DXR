#!/usr/bin/env python3
# Generates GRABMAP.wad - a DoomXR VR test range (climb pillars + whip platforms + lift).
# UDMF geometry is generated (not hand-typed) so winding/sidedef refs are correct.
import struct, sys

# ---- climbable texture names (KEYWORDS.json climb namespace = the LIVE list) ----
CLIMB_TEX = ["SUPPORT2","SUPPORT3","PIPE1","PIPE2","PIPE4","PIPE6",
             "LADDER","METLADR","CLIMBABLE","METAL","BROWN96","COMPTALL","TEKWALL"]
NONCLIMB_TEX = "STARTAN2"   # control pillar - should NOT climb

verts=[]; lines=[]; sides=[]; sectors=[]; things=[]

def V(x,y):
    verts.append((float(x),float(y))); return len(verts)-1
def SEC(fh,ch,ft,ct,light,tag=0):
    sectors.append(dict(fh=fh,ch=ch,ft=ft,ct=ct,light=light,tag=tag)); return len(sectors)-1
def SD(sec,mid="-",top="-",bot="-"):
    sides.append(dict(sec=sec,mid=mid,top=top,bot=bot)); return len(sides)-1
def LN(v1,v2,front,back=-1,block=False,climb_tex=None,special=0,args=(0,0,0,0,0),playercross=False,repeat=False):
    lines.append(dict(v1=v1,v2=v2,front=front,back=back,block=block,climb_tex=climb_tex,
                      special=special,args=args,pc=playercross,rep=repeat))
def THING(x,y,ang,typ):
    things.append(dict(x=x,y=y,ang=ang,typ=typ))

def signed_area(pts):
    a=0.0
    for i in range(len(pts)):
        x1,y1=pts[i]; x2,y2=pts[(i+1)%len(pts)]; a+=x1*y2-x2*y1
    return a*0.5

def loop(coords, want_cw):
    """coords: list of (x,y). Returns vertex indices oriented CW (want_cw) or CCW."""
    a=signed_area(coords)
    is_cw = a<0
    if is_cw!=want_cw: coords=list(reversed(coords))
    return [V(x,y) for (x,y) in coords]

# ================= geometry =================
# One big room. Floor 0, ceiling 640 (tall for climb + whip swing).
RF, RC = 0, 640
room = SEC(RF, RC, "FLOOR0_1", "CEIL1_1", 190)

# outer wall rectangle: room interior INSIDE -> wind CW, front=room (one-sided).
minx,maxx,miny,maxy = -1152,1152,-768,1408
outer = loop([(minx,miny),(minx,maxy),(maxx,maxy),(maxx,miny)], want_cw=True)
for i in range(4):
    v1=outer[i]; v2=outer[(i+1)%4]
    LN(v1,v2, SD(room, mid="BROWNGRN"), back=-1, block=True)

# player 1 start near south wall, facing north
THING(0,-576,90,1)

# ---- CLIMB PILLARS: one-sided void columns along the back, one per climb texture ----
# void columns => room is OUTSIDE the loop => wind CCW, front=room, wall tex in MID slot.
n=len(CLIMB_TEX)+1                      # +1 control pillar
half=48                                 # 96x96 pillars
spacing=160
startx=-(spacing*(n-1))/2.0
py=1180
tex_list = CLIMB_TEX + [NONCLIMB_TEX]
for i,tex in enumerate(tex_list):
    cx=startx+i*spacing
    quad=[(cx-half,py-half),(cx-half,py+half),(cx+half,py+half),(cx+half,py-half)]
    vs=loop(quad, want_cw=False)        # CCW hole
    for k in range(4):
        v1=vs[k]; v2=vs[(k+1)%4]
        LN(v1,v2, SD(room, mid=tex), back=-1, block=True, climb_tex=tex)

# ---- WHIP PLATFORMS: raised sectors on the right, stair-stepped up ----
# each platform = its own sector, CCW loop, front=room (bottom tex = step face), back=platform.
plat_heights=[128,256,384,512]
px0=520; pw=360; pdepth=300; py0=-200
for i,ph in enumerate(plat_heights):
    x0=px0; x1=px0+pw
    y0=py0+i*(pdepth+40); y1=y0+pdepth
    psec=SEC(ph, RC, "FLOOR4_8", "CEIL1_1", 170)
    quad=[(x0,y0),(x0,y1),(x1,y1),(x1,y0)]
    vs=loop(quad, want_cw=False)        # CCW: front=room, back=platform
    for k in range(4):
        v1=vs[k]; v2=vs[(k+1)%4]
        fs=SD(room, bot="METAL")        # room-facing: shows the step face (whip target)
        bs=SD(psec)
        LN(v1,v2, fs, back=bs, block=False)

# ---- LIFT: a moving platform on the left, perpetual raise, tripped at spawn ----
lift_tag=1
lx0=-980; lx1=-620; ly0=-120; ly1=240
lift=SEC(256, RC, "FLOOR4_8", "CEIL1_1", 170, tag=lift_tag)  # starts at 256; perpetual-raise oscillates 0..256
quad=[(lx0,ly0),(lx0,ly1),(lx1,ly1),(lx1,ly0)]
vs=loop(quad, want_cw=False)
for k in range(4):
    v1=vs[k]; v2=vs[(k+1)%4]
    fs=SD(room, bot="SUPPORT3"); bs=SD(lift)
    LN(v1,v2, fs, back=bs, block=False)
# trigger line the player crosses right after spawn -> start perpetual lift (special 60)
t1=V(-160,-500); t2=V(160,-500)
LN(t1,t2, SD(room), back=SD(room), special=60, args=(lift_tag,16,105,0,0), playercross=True, repeat=True)

# ================= emit UDMF TEXTMAP =================
o=[]
o.append('namespace = "zdoom";\n')
for (x,y) in verts:
    o.append("vertex{x=%.3f;y=%.3f;}\n"%(x,y))
for L in lines:
    s=["v1=%d;v2=%d;sidefront=%d;"%(L["v1"],L["v2"],L["front"])]
    if L["back"]>=0: s.append("sideback=%d;twosided=true;"%L["back"])
    if L["block"]: s.append("blocking=true;")
    if L["special"]:
        a=L["args"]
        s.append("special=%d;arg0=%d;arg1=%d;arg2=%d;arg3=%d;arg4=%d;"%(L["special"],a[0],a[1],a[2],a[3],a[4]))
    if L["pc"]: s.append("playercross=true;")
    if L["rep"]: s.append("repeatspecial=true;")
    # climbability is intentionally driven ONLY by the wall texture name (honest per-texture test);
    # no keyword override, so the STARTAN2 control pillar stays non-climbable.
    o.append("linedef{%s}\n"%"".join(s))
for S in sides:
    o.append('sidedef{sector=%d;texturemiddle="%s";texturetop="%s";texturebottom="%s";}\n'
             %(S["sec"],S["mid"],S["top"],S["bot"]))
for S in sectors:
    o.append('sector{heightfloor=%d;heightceiling=%d;texturefloor="%s";textureceiling="%s";lightlevel=%d;%s}\n'
             %(S["fh"],S["ch"],S["ft"],S["ct"],S["light"], ("id=%d;"%S["tag"]) if S["tag"] else ""))
for T in things:
    o.append("thing{x=%.3f;y=%.3f;angle=%d;type=%d;skill1=true;skill2=true;skill3=true;skill4=true;skill5=true;single=true;coop=true;dm=true;}\n"
             %(T["x"],T["y"],T["ang"],T["typ"]))
textmap="".join(o).encode("ascii")

zmapinfo=b'map GRABMAP "VR TEST RANGE"\n{\n    sky1 = "SKY1"\n    music = "D_RUNNIN"\n    cluster = 1\n}\n'

# ================= assemble PWAD =================
def wad(lumps):
    # lumps: list of (name, bytes)
    data=b""; dirent=[]
    off=12
    for name,b in lumps:
        dirent.append((off,len(b),name)); data+=b; off+=len(b)
    dirt=b""
    for (fp,sz,name) in dirent:
        nm=name.encode("ascii")[:8]; nm=nm+b"\x00"*(8-len(nm))
        dirt+=struct.pack("<ii",fp,sz)+nm
    header=b"PWAD"+struct.pack("<ii",len(lumps),12+len(data))
    return header+data+dirt

blob=wad([("ZMAPINFO",zmapinfo),("GRABMAP",b""),("TEXTMAP",textmap),("ENDMAP",b"")])
for out in sys.argv[1:]:
    open(out,"wb").write(blob)
print("verts=%d lines=%d sides=%d sectors=%d things=%d  wadbytes=%d"%(
    len(verts),len(lines),len(sides),len(sectors),len(things),len(blob)))
print("climb pillars (left->right):", ", ".join(tex_list))
