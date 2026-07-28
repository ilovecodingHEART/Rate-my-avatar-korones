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
for m in re.finditer(r'(\w+) = \{\s*Id = (\d+),\s*IsGamePass = \w+,\s*Category = "([^"]*)",\s*Title = "([^"]+)",\s*Blurb = "([^"]+)",\s*Icon = "([^"]*)",\s*Price = "([^"]*)"', SERVER):
    k,i,cat,t,bl,icon,price = m.groups()
    PASSES.append({'key':k,'id':i,'cat':cat,'title':t,'blurb':bl,'icon':icon,'price':price})
CATS=[x.strip().strip('"') for x in re.search(r'SHOP_CATEGORIES = \{([^}]+)\}', SERVER).group(1).split(',')]
# Shop order now comes from each pass's Order field, sorted at run time.
ORDERS={}
for m in re.finditer(r'(\w+) = \{\s*Id = \d+,.*?Order = (\d+),', SERVER, re.S):
    ORDERS.setdefault(m.group(1), int(m.group(2)))
PASSES.sort(key=lambda p: ORDERS.get(p['key'], 999))

TOTAL=int(re.search(r'TOTAL_ASSETS = (\d+)', LOADER).group(1))
LTITLE=re.search(r'^local TITLE = "([^"]+)"', LOADER, re.M).group(1)
LSUB=re.search(r'^local SUBTITLE = "([^"]*)"', LOADER, re.M).group(1)
LLOGO=re.search(r'^local LOGO_IMAGE = "([^"]*)"', LOADER, re.M).group(1)
LASPECT=float(re.search(r'^local LOGO_ASPECT = ([\d.]+)', LOADER, re.M).group(1))

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
def shop(path, owned_keys, tab=None):
    tab = tab or CATS[0]
    FW,FH = int(0.56*1180*S), int(0.50*820*S)
    M = 52*S; TOP = 60*S
    W,H = FW+M*2, FH+M+TOP
    img,d = backdrop(W,H)
    FX,FY = M, TOP
    OUT_=T['ShopOutline']

    # title above the window
    ctext(d,(FX,FY-TOP,FX+FW,FY),"Shop!",font(int(TOP*0.72),True),T['Text'])

    panel(d,img,(FX,FY,FX+FW,FY+FH),T['PanelBackground'],OUT_,16*S,4*S,True)

    # sidebar
    sx = FX+0.028*FW; sy = FY+0.05*FH
    sw, sh = 0.235*FW, 0.9*FH
    th = 0.235*sh; gap = 0.035*sh
    for i,c in enumerate(CATS):
        by = sy + i*(th+gap)
        bb=(sx+0.05*sw, by, sx+0.95*sw, by+th)
        if c==tab:
            panel(d,img,bb,T['TabActive'],OUT_,16*S,4*S)
            ctext(d,bb,c,font(int(th*0.30),True),T['Text'])
        else:
            panel(d,img,bb,T['TabIdle'],OUT_,16*S,3*S)
            ctext(d,bb,c,font(int(th*0.30),True),T['MutedText'])

    # grid
    gx = FX+0.285*FW; gy = FY+0.05*FH
    gw, gh = 0.69*FW, 0.9*FH
    cw = 0.47*gw
    cardh = cw/1.30
    padx = 0.04*gw; pady = 0.04*gw
    items=[p for p in PASSES if p['cat']==tab]
    if not items:
        ctext(d,(gx,gy+gh/2-30*S,gx+gw,gy+gh/2+30*S),"Nothing here yet.",
              font(int(26*S)),T['MutedText'])
    for n,p in enumerate(items):
        col = n%2; row = n//2
        x0 = gx + col*(cw+padx)
        y0 = gy + row*(cardh+pady)
        if y0+cardh > gy+gh+cardh*0.5: break
        cb=(x0,y0,x0+cw,y0+cardh)
        panel(d,img,cb,T['CardBackground'],OUT_,16*S,4*S)
        # title
        ctext(d,(x0,y0+0.03*cardh,x0+cw,y0+0.22*cardh),p['title'],
              font(int(cardh*0.125),True),T['Text'])
        # icon box
        ib=(x0+0.06*cw, y0+0.26*cardh, x0+0.40*cw, y0+0.70*cardh)
        panel(d,img,ib,T['InputBackground'],OUT_,8*S,2*S)
        if not p['icon']:
            ctext(d,ib,"icon",font(int(cardh*0.085)),T['Placeholder'])
        # price + blurb
        ltext(d,(x0+0.44*cw,y0+0.28*cardh,x0+0.94*cw,y0+0.48*cardh),
              p['price'],font(int(cardh*0.115),True),T['Text'],padx=0)
        # wrap the blurb to the text column instead of letting it overflow
        fb=font(int(cardh*0.070))
        maxw=0.50*cw
        words=p['blurb'].split(); lines=[]; cur=""
        for w in words:
            t=(cur+" "+w).strip()
            if d.textlength(t,font=fb)<=maxw: cur=t
            else:
                if cur: lines.append(cur)
                cur=w
            if len(lines)==3: break
        if cur and len(lines)<3: lines.append(cur)
        ly=y0+0.47*cardh
        for ln in lines:
            d.text((x0+0.44*cw,ly),ln,font=fb,fill=T['MutedText'])
            ly+=int(cardh*0.085)
        # buy
        bh2=0.22*cardh
        bb2=(x0+0.07*cw, y0+cardh-0.04*cardh-bh2, x0+0.93*cw, y0+cardh-0.04*cardh)
        if p['key'] in owned_keys:
            panel(d,img,bb2,T['OwnedBackground'],OUT_,8*S,3*S)
            ctext(d,bb2,"Owned",font(int(bh2*0.46),True),T['OwnedText'])
        else:
            panel(d,img,bb2,T['BuyBackground'],OUT_,8*S,3*S)
            ctext(d,bb2,"Buy",font(int(bh2*0.46),True),T['BuyText'])

    # close button
    r=0.046*FW
    cx,cy=FX+FW, FY
    d.ellipse((cx-r,cy-r,cx+r,cy+r),fill=T['DangerBackground'],outline=OUT_,width=3*S)
    ctext(d,(cx-r,cy-r,cx+r,cy+r),"X",font(int(r*1.0),True),T['DangerText'])

    img.resize((W//S,H//S),Image.LANCZOS).save(path)
    return path

# ------------------------------------------------------------------ loading
def loading(path, pct=0.62, spin=20):
    import math
    W,H=760*S,428*S
    img=Image.new('RGB',(W,H),LT['Background']); d=ImageDraw.Draw(img)

    # logo box above the title (placeholder while LOGO_IMAGE is empty)
    lh=int(0.185*H); lw=int(lh*LASPECT)
    lx0,ly0=(W-lw)//2, int(0.335*H)
    lb=(lx0,ly0,lx0+lw,ly0+lh)
    if LLOGO:
        d.rounded_rectangle(lb,radius=6*S,fill=(90,90,90))
    else:
        ov=Image.new('RGBA',(lw,lh),(0,0,0,0)); od=ImageDraw.Draw(ov)
        od.rounded_rectangle((0,0,lw-1,lh-1),radius=6*S,
                             fill=LT['Title']+(38,), outline=LT['Subtitle']+(150,), width=2*S)
        img.paste(Image.alpha_composite(img.crop(lb).convert('RGBA'),ov).convert('RGB'),(lx0,ly0))
        ctext(d,lb,"LOGO_IMAGE",font(int(lh*0.20)),LT['Subtitle'])

    # title + subtitle, centred, thin type
    ctext(d,(0,int(0.565*H),W,int(0.635*H)),LTITLE,font(int(0.058*H)),LT['Title'])
    ctext(d,(0,int(0.648*H),W,int(0.688*H)),LSUB,font(int(0.030*H)),LT['Subtitle'])

    # thin progress bar
    bw,bh=0.30*W,max(0.006*H,3*S)
    bx0,by0=(W-bw)/2,0.735*H
    d.rounded_rectangle((bx0,by0,bx0+bw,by0+bh),radius=int(bh/2),fill=LT['BarBackground'])
    eased=1-(1-pct)*(1-pct)
    fw=bw*eased
    if fw>bh:
        d.rounded_rectangle((bx0,by0,bx0+fw,by0+bh),radius=int(bh/2),fill=LT['BarFill'])

    shown=int(eased*TOTAL)
    ctext(d,(0,int(0.775*H),W,int(0.82*H)),
          "Loading assets.. %d / %d"%(shown,TOTAL),font(int(0.026*H)),LT['Counter'])

    # spinning cube, bottom right
    cs=int(0.075*H)
    cx,cy=int(0.90*W),int(0.80*H)
    cube=Image.new('RGBA',(cs*3,cs*3),(0,0,0,0))
    cd=ImageDraw.Draw(cube)
    o=cs
    cd.rounded_rectangle((o,o,o+cs,o+cs),radius=int(cs*0.16),fill=LT['Cube'])
    hs=int(cs*0.34)
    hx=o+(cs-hs)//2
    cd.rounded_rectangle((hx,hx,hx+hs,hx+hs),radius=int(hs*0.12),fill=LT['Background'])
    cube=cube.rotate(-spin,resample=Image.BICUBIC,center=(o+cs/2,o+cs/2))
    img.paste(cube,(cx-int(o+cs/2),cy-int(o+cs/2)),cube)

    img.resize((W//S,H//S),Image.LANCZOS).save(path)
    return path

# -------------------------------------------------------------------- admin
def admin(path):
    FW,FH = int(0.62*1180*S), int(0.60*820*S)
    M_=52*S; TOP=56*S
    W,H = FW+M_*2, FH+M_+TOP
    img,d = backdrop(W,H)
    FX,FY = M_, TOP
    OUT_=T['ShopOutline']

    ctext(d,(FX,FY-TOP,FX+FW,FY),"Admin",font(int(TOP*0.66),True),T['Text'])
    panel(d,img,(FX,FY,FX+FW,FY+FH),T['PanelBackground'],OUT_,16*S,4*S,True)

    # left list
    lx,ly = FX+0.03*FW, FY+0.05*FH
    lw,lh = 0.32*FW, 0.78*FH
    panel(d,img,(lx,ly,lx+lw,ly+lh),T['CardBackground'],OUT_,8*S,3*S)
    names=[(p['title'],True) for p in PASSES]+[("Speed Boost",False)]
    rh=30*S
    for i,(nm,builtin) in enumerate(names):
        ry=ly+8*S+i*(rh+4*S)
        rb=(lx+0.04*lw,ry,lx+0.96*lw,ry+rh)
        panel(d,img,rb,T['TabIdle'],OUT_,8*S,2*S)
        ctext(d,rb,nm,font(int(rh*0.42)),T['Text'])
    nb=(lx,FY+0.85*FH,lx+lw,FY+0.95*FH)
    panel(d,img,nb,T['BuyBackground'],OUT_,8*S,3*S)
    ctext(d,nb,"+ New Gamepass",font(int((nb[3]-nb[1])*0.40),True),T['BuyText'])

    # right editor
    ex,ey = FX+0.37*FW, FY+0.05*FH
    ew,eh = 0.60*FW, 0.90*FH
    rows=[("Key","SPEED_PASS"),("Name","Speed Boost"),("Asset ID","424242"),
          ("Price","Gamepass"),("Icon ID","rbxassetid://12345"),
          ("Blurb","Run faster."),("Category","Passes")]
    fh_=0.115*eh
    for i,(lab,val) in enumerate(rows):
        fy=ey+i*(fh_+6*S)
        ltext(d,(ex,fy,ex+0.26*ew,fy+fh_),lab,font(int(fh_*0.40)),T['MutedText'],padx=0)
        bb=(ex+0.28*ew,fy+0.09*fh_,ex+ew,fy+0.91*fh_)
        panel(d,img,bb,T['InputBackground'],T['InputStroke'],8*S,2*S)
        ltext(d,bb,val,font(int(fh_*0.38)),T['Text'],padx=10*S)
    sy=ey+7*(fh_+6*S)
    ctext(d,(ex,sy,ex+ew,sy+0.08*eh),"Saved.",font(int(0.055*eh)),T['Good'])
    by=sy+0.09*eh
    sb=(ex,by,ex+0.48*ew,by+0.12*eh)
    panel(d,img,sb,T['BuyBackground'],OUT_,8*S,3*S)
    ctext(d,sb,"Save",font(int(0.12*eh*0.44),True),T['BuyText'])
    db=(ex+0.52*ew,by,ex+ew,by+0.12*eh)
    panel(d,img,db,T['DangerBackground'],OUT_,8*S,3*S)
    ctext(d,db,"Delete",font(int(0.12*eh*0.44),True),T['DangerText'])

    r=0.042*FW
    cx,cy=FX+FW,FY
    d.ellipse((cx-r,cy-r,cx+r,cy+r),fill=T['DangerBackground'],outline=OUT_,width=3*S)
    ctext(d,(cx-r,cy-r,cx+r,cy+r),"X",font(int(r*1.0),True),T['DangerText'])

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

def hud(path):
    W,H=760*S,300*S
    img,d=backdrop(W,H)
    bw,bh=0.30*W,0.115*H
    for i,cap in enumerate(["Shop","Open Booth Menu"]):
        by=0.30*H+i*(bh+0.035*H)
        bb=(0.03*W,by,0.03*W+bw,by+bh)
        panel(d,img,bb,T['PanelBackground'],T['ShopOutline'],16*S,4*S,True)
        ctext(d,bb,cap,font(int(bh*0.36),True),T['Text'])
    img.resize((W//S,H//S),Image.LANCZOS).save(path)
    return path

os.makedirs(OUT,exist_ok=True)
made=[
 booth_menu(os.path.join(OUT,'gui-booth-locked.png'), False),
 booth_menu(os.path.join(OUT,'gui-booth-unlocked.png'), True),
 shop(os.path.join(OUT,'gui-shop.png'), set()),
 shop(os.path.join(OUT,'gui-shop-owned.png'), {'UPLOAD','PERMANENT'}),
 shop(os.path.join(OUT,'gui-shop-items-tab.png'), set(), tab=CATS[1] if len(CATS)>1 else CATS[0]),
 hud(os.path.join(OUT,'gui-hud.png')),
 admin(os.path.join(OUT,'gui-admin.png')),
 loading(os.path.join(OUT,'gui-loading.png')),
 loading(os.path.join(OUT,'gui-loading-spin.png'), pct=0.28, spin=58),
 boombox(os.path.join(OUT,'gui-boombox.png')),
]
for m in made: print("wrote", os.path.relpath(m, ROOT))
