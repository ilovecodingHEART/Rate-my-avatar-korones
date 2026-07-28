"""Render preview images of the GUI by parsing real values out of the scripts,
so the docs cannot drift from the code."""
import os, re, sys
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CLIENT = open(os.path.join(ROOT,'src/StarterGui/MainUI/Client.client.lua')).read()
SERVER = open(os.path.join(ROOT,'src/ServerScriptService/BoothServer.server.lua')).read()
LOADER = open(os.path.join(ROOT,'src/ReplicatedFirst/LoadingScreen.client.lua')).read()
OUT = os.path.join(ROOT,'docs')

T = {}
for k,r,g,b in re.findall(r'(\w+)\s*=\s*Color3\.fromRGB\((\d+),\s*(\d+),\s*(\d+)\)', CLIENT):
    T.setdefault(k,(int(r),int(g),int(b)))
LT = {}
for k,r,g,b in re.findall(r'(\w+)\s*=\s*Color3\.fromRGB\((\d+),\s*(\d+),\s*(\d+)\)', LOADER):
    LT.setdefault(k,(int(r),int(g),int(b)))

ROWS = re.findall(r'\{Name = "(\w+)", Order = (\d+), Height = ([\d.]+), Width = ([\d.]+)\}', CLIENT)
ROWS.sort(key=lambda x:int(x[1]))
PAD = float(re.search(r'ListLayout\.Padding = UDim\.new\(([\d.]+)', CLIENT).group(1))
TOPPAD = float(re.search(r'Padding\.PaddingTop = UDim\.new\(([\d.]+)', CLIENT).group(1))

PASSES=[]
for k,i,t,bl in re.findall(r'(\w+) = \{\s*Id = (\d+),\s*IsGamePass = \w+,\s*Title = "([^"]+)",\s*Blurb = "([^"]+)"', SERVER):
    PASSES.append({'key':k,'id':i,'title':t,'blurb':bl})
ORDER=[x.strip().strip('"') for x in re.search(r'SHOP_ORDER = \{([^}]+)\}', SERVER).group(1).split(',')]
PASSES.sort(key=lambda p: ORDER.index(p['key']))

TOTAL=int(re.search(r'TOTAL_ASSETS = (\d+)', LOADER).group(1))
LTITLE=re.search(r'TITLE = "([^"]+)"', LOADER).group(1)

S=3
def font(px, bold=False):
    for p in ["/usr/share/fonts/truetype/dejavu/DejaVuSans%s.ttf"%("-Bold" if bold else ""),
              "/usr/share/fonts/truetype/liberation/LiberationSans%s.ttf"%("-Bold" if bold else "")]:
        try: return ImageFont.truetype(p, max(px,6))
        except: pass
    return ImageFont.load_default()

def backdrop(W,H):
    img=Image.new('RGB',(W,H),(108,114,128))
    d=ImageDraw.Draw(img)
    for x in range(0,W,34*S): d.line([(x,0),(x,H)],fill=(99,105,119),width=S)
    for y in range(0,H,34*S): d.line([(0,y),(W,y)],fill=(99,105,119),width=S)
    return img,d

def panel(d,img,box,fill,stroke,radius,width=3*S,sheen=False):
    d.rounded_rectangle(box,radius=radius,fill=fill,outline=stroke,width=width)
    if sheen:
        x0,y0,x1,y1=[int(v) for v in box]
        ov=Image.new('RGBA',(x1-x0,y1-y0),(0,0,0,0)); od=ImageDraw.Draw(ov)
        h=y1-y0
        for i in range(h):
            od.line([(0,i),(x1-x0,i)],fill=(255,255,255,int(20*(1-i/h))))
        mask=Image.new('L',ov.size,0)
        ImageDraw.Draw(mask).rounded_rectangle([0,0,ov.size[0]-1,ov.size[1]-1],radius=radius,fill=255)
        img.paste(Image.alpha_composite(img.crop((x0,y0,x1,y1)).convert('RGBA'),ov).convert('RGB'),(x0,y0),mask)

def ctext(d,box,text,f,col):
    x0,y0,x1,y1=box
    tb=d.textbbox((0,0),text,font=f)
    d.text(((x0+x1-tb[2]-tb[0])/2,(y0+y1-tb[3]-tb[1])/2),text,font=f,fill=col)

def ltext(d,box,text,f,col,padx=14*S):
    x0,y0,x1,y1=box
    tb=d.textbbox((0,0),text,font=f)
    d.text((x0+padx,(y0+y1-tb[3]-tb[1])/2),text,font=f,fill=col)

# ---------------------------------------------------------------- booth menu
def booth_menu(path, unlocked):
    FW,FH=470*S,286*S; M=46*S
    BOT=132*S
    W,H=FW+M*2,FH+M+BOT
    img,d=backdrop(W,H)
    FX,FY=M,M
    panel(d,img,(FX,FY,FX+FW,FY+FH),T['PanelBackground'],T['PanelStroke'],14*S,3*S,True)
    y=FY+TOPPAD*FH
    CAP={'TextLabel':'Booth Menu','TextBox':'Enter Booth Text here..','ChangeText':'Send',
         'ImageBox':'Enter Image / Decal ID..' if unlocked else 'Requires Gamepass..',
         'ChangeImage':'Set Image' if unlocked else 'Unlock Image Uploads',
         'Status':'Image set. It will stay on this booth.' if unlocked else 'Image uploads need the Gamepass.',
         'UnclaimBooth':'Unclaim Booth'}
    for name,order,h,w in ROWS:
        hh,ww=float(h)*FH,float(w)*FW
        x0=FX+(FW-ww)/2; box=(x0,y,x0+ww,y+hh); txt=CAP[name]
        if name=='TextLabel':
            ctext(d,box,txt,font(int(hh*0.62),True),T['Text'])
        elif name=='Status':
            ctext(d,box,txt,font(int(hh*0.78)),T['Good'] if unlocked else T['Bad'])
        elif 'Box' in name:
            panel(d,img,box,T['InputBackground'],T['InputStroke'],8*S,2*S)
            ltext(d,box,txt,font(int(hh*0.42)),T['Placeholder'])
        elif name=='UnclaimBooth':
            panel(d,img,box,T['DangerBackground'],T['DangerStroke'],8*S,2*S)
            ctext(d,box,txt,font(int(hh*0.52),True),T['DangerText'])
        elif name=='ChangeImage' and not unlocked:
            panel(d,img,box,T['LockedBackground'],T['LockedStroke'],8*S,2*S)
            ctext(d,box,txt,font(int(hh*0.52),True),T['LockedText'])
        else:
            panel(d,img,box,T['ButtonBackground'],T['ButtonStroke'],8*S,2*S)
            ctext(d,box,txt,font(int(hh*0.52),True),T['Text'])
        y+=hh+PAD*FH
    # side buttons
    bw,bh=0.30*FW,0.16*FH*0.62
    for i,cap in enumerate(["Shop","Open Booth Menu"]):
        by=FY+FH+14*S+i*(bh+10*S)
        bb=(FX+8*S,by,FX+8*S+bw,by+bh)
        panel(d,img,bb,T['PanelBackground'],T['PanelStroke'],8*S,2*S,True)
        ctext(d,bb,cap,font(int(bh*0.40),True),T['Text'])
    img.resize((W//S,H//S),Image.LANCZOS).save(path)
    return path

# ---------------------------------------------------------------------- shop
def shop(path, owned_keys):
    FW,FH=int(0.42*1100*S),int(0.46*950*S)
    M=46*S; W,H=FW+M*2,FH+M*2
    img,d=backdrop(W,H)
    FX,FY=M,M
    panel(d,img,(FX,FY,FX+FW,FY+FH),T['PanelBackground'],T['PanelStroke'],14*S,3*S,True)
    y=FY+0.03*FH
    th=0.14*FH
    ctext(d,(FX,y,FX+FW,y+th),"Shop",font(int(th*0.6),True),T['Text'])
    y+=th+0.02*FH
    for p in PASSES:
        rh=0.20*FH; rw=0.94*FW; x0=FX+(FW-rw)/2
        nh=0.36*rh
        ctext(d,(x0,y,x0+rw,y+nh),p['title'],font(int(nh*0.62),True),T['Text'])
        by=y+nh+0.02*rh; bh2=0.26*rh
        ctext(d,(x0,by,x0+rw,by+bh2),p['blurb'],font(int(bh2*0.62)),T['MutedText'])
        cy=by+bh2+0.02*rh; ch=0.34*rh; cw=0.55*rw
        cb=(FX+(FW-cw)/2,cy,FX+(FW+cw)/2,cy+ch)
        if p['key'] in owned_keys:
            panel(d,img,cb,T['OwnedBackground'],T['OwnedStroke'],8*S,2*S)
            ctext(d,cb,"Owned",font(int(ch*0.5),True),T['OwnedText'])
        else:
            panel(d,img,cb,T['ButtonBackground'],T['ButtonStroke'],8*S,2*S)
            ctext(d,cb,"Buy",font(int(ch*0.5),True),T['Text'])
        y+=rh+0.02*FH
    ch=0.11*FH; cw=0.34*FW
    cb=(FX+(FW-cw)/2,FY+FH-0.03*FH-ch,FX+(FW+cw)/2,FY+FH-0.03*FH)
    panel(d,img,cb,T['ButtonBackground'],T['ButtonStroke'],8*S,2*S)
    ctext(d,cb,"Close",font(int(ch*0.46),True),T['Text'])
    img.resize((W//S,H//S),Image.LANCZOS).save(path)
    return path

# ------------------------------------------------------------------ loading
def loading(path, pct=0.62):
    W,H=760*S,428*S
    img=Image.new('RGB',(W,H),LT['PanelBackground']); d=ImageDraw.Draw(img)
    ctext(d,(0,int(0.30*H),W,int(0.42*H)),LTITLE,font(int(0.075*H),True),LT['Text'])
    bw,bh=0.46*W,0.022*H
    bx0,by0=(W-bw)/2,0.52*H-bh/2
    bb=(bx0,by0,bx0+bw,by0+bh)
    d.rounded_rectangle(bb,radius=int(bh/2),fill=LT['BarBackground'],outline=LT['PanelStroke'],width=2*S)
    eased=1-(1-pct)*(1-pct)
    fw=bw*eased
    if fw>bh:
        d.rounded_rectangle((bx0,by0,bx0+fw,by0+bh),radius=int(bh/2),fill=LT['BarFill'])
    shown=int(eased*TOTAL)
    ctext(d,(0,int(0.555*H),W,int(0.605*H)),
          "Loading assets.. %d / %d"%(shown,TOTAL),font(int(0.032*H)),LT['MutedText'])
    img.resize((W//S,H//S),Image.LANCZOS).save(path)
    return path

# ------------------------------------------------------------------ boombox
def boombox(path):
    W,H=760*S,180*S
    img,d=backdrop(W,H)
    pw,ph=0.62*W,0.46*H
    x0,y0=(W-pw)/2,(H-ph)/2
    panel(d,img,(x0,y0,x0+pw,y0+ph),T['PanelBackground'],T['PanelStroke'],14*S,3*S,True)
    bx=(x0+0.04*pw, y0+0.22*ph, x0+0.62*pw, y0+0.78*ph)
    panel(d,img,bx,T['InputBackground'],T['InputStroke'],8*S,2*S)
    ltext(d,bx,"Audio ID..",font(int((bx[3]-bx[1])*0.44)),T['Placeholder'])
    pb=(x0+0.64*pw, y0+0.22*ph, x0+0.80*pw, y0+0.78*ph)
    panel(d,img,pb,T['ButtonBackground'],T['ButtonStroke'],8*S,2*S)
    ctext(d,pb,"Play",font(int((pb[3]-pb[1])*0.42),True),T['Text'])
    sb=(x0+0.82*pw, y0+0.22*ph, x0+0.98*pw, y0+0.78*ph)
    panel(d,img,sb,T['DangerBackground'],T['DangerStroke'],8*S,2*S)
    ctext(d,sb,"Stop",font(int((sb[3]-sb[1])*0.42),True),T['DangerText'])
    img.resize((W//S,H//S),Image.LANCZOS).save(path)
    return path

os.makedirs(OUT,exist_ok=True)
made=[
 booth_menu(os.path.join(OUT,'gui-booth-locked.png'), False),
 booth_menu(os.path.join(OUT,'gui-booth-unlocked.png'), True),
 shop(os.path.join(OUT,'gui-shop.png'), set()),
 shop(os.path.join(OUT,'gui-shop-owned.png'), {'UPLOAD','PERMANENT'}),
 loading(os.path.join(OUT,'gui-loading.png')),
 boombox(os.path.join(OUT,'gui-boombox.png')),
]
for m in made: print("wrote", os.path.relpath(m, ROOT))
