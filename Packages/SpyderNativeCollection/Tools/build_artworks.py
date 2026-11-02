#!/usr/bin/env python3
"""Offline raster-to-polygon vectorization. Output: native Canvas geometry + documentation-only PNGs.
Original image inputs are from user-provided reference images and are NOT required at runtime.
Usage: python Tools/build_artworks.py /path/to/reference_directory
Input names: IMG_8802.jpeg IMG_8803.jpeg IMG_8801.jpeg IMG_8774.jpeg IMG_8773.jpeg
"""
import cv2, json, math, random, sys
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw, ImageFont
BASE=Path(__file__).resolve().parent.parent
REF=Path(sys.argv[1]) if len(sys.argv)>1 else Path('/mnt/data')
refs={name:cv2.imread(str(REF/f'{name}.jpeg')) for name in ['IMG_8802','IMG_8803','IMG_8801','IMG_8774','IMG_8773']}
for k,v in refs.items():
 if v is None: raise FileNotFoundError(k)
# Rows and columns exclude the labels/text in the Pinterest comparison graphic.
collage_rois=[(35,36,226,245),(273,35,475,248),(512,40,724,245),
              (30,332,236,544),(270,336,480,544),(505,337,731,542),
              (28,628,241,844),(264,628,487,846),(511,628,726,834)]
def roi(src,rect):
 x0,y0,x1,y1=rect;return src[y0:y1,x0:x1]
entries=[
 ('dual-fang','Dual Fang',roi(refs['IMG_8802'],(145,425,935,1660)),True,'Two-tone vector traced from large red/white reference'),
 ('bone-needle','Bone Needle',roi(refs['IMG_8803'],(177,380,555,1080)),False,'White segmented reference'),
 ('classic-talon','Classic Talon',roi(refs['IMG_8801'],collage_rois[0]),False,'First reference in 3x3 comparison'),
 ('long-strike','Long Strike',roi(refs['IMG_8801'],collage_rois[1]),False,'Second reference in 3x3 comparison'),
 ('armor-core','Armor Core',roi(refs['IMG_8801'],collage_rois[2]),False,'Third reference in 3x3 comparison'),
 ('white-phantom','White Phantom',roi(refs['IMG_8774'],(240,475,495,865)),False,'Large white spider reference'),
 ('crimson-fang','Crimson Fang',roi(refs['IMG_8801'],collage_rois[4]),False,'Fifth reference in 3x3 comparison'),
 ('ghost-venom','Ghost Venom',roi(refs['IMG_8801'],collage_rois[5]),False,'Sixth reference in 3x3 comparison'),
 ('street-web','Street Web',roi(refs['IMG_8801'],collage_rois[6]),False,'Seventh reference in 3x3 comparison'),
 ('orbit-spider','Orbit Spider',roi(refs['IMG_8773'],(127,535,612,1110)),False,'Large red circular reference'),
 ('violet-arc','Violet Arc',roi(refs['IMG_8801'],collage_rois[8]),False,'Ninth reference in 3x3 comparison'),
 ('webverse-ring','Webverse Ring',roi(refs['IMG_8801'],collage_rois[7]),False,'Eighth reference in 3x3 comparison'),
]
def get_masks(image,dual):
 img=cv2.GaussianBlur(image,(3,3),0.52)
 b,g,r=cv2.split(img)
 maxv=np.max(img,axis=2).astype(np.int16)
 minv=np.min(img,axis=2).astype(np.int16)
 bright=maxv>91
 sat=(maxv-minv)>31
 # Near-white for reference first, other logos can be any color including magenta.
 white=(minv>105) & ((maxv-minv)<52)
 active=bright & (white | sat)
 if dual:
  accent=(bright & (r.astype(np.int16) > g.astype(np.int16)*1.25) & (r.astype(np.int16)>b.astype(np.int16)*1.22))
  core=white
  masks=[('accent',accent),('core',core)]
 else:
  masks=[('accent',active)]
 return [(name,(mask.astype(np.uint8)*255)) for name,mask in masks]
def process_masks(image,dual):
 masks=get_masks(image,dual)
 # Drop tiny JPEG artifacts with minimum component area but preserve tapered long legs.
 ret=[]
 for role, mask in masks:
  contours,hierarchy=cv2.findContours(mask,cv2.RETR_TREE,cv2.CHAIN_APPROX_SIMPLE)
  polygons=[]
  for c in contours:
   arc=cv2.arcLength(c,True); area=abs(cv2.contourArea(c))
   if area < 6 or arc<17: continue
   approx=cv2.approxPolyDP(c,max(.55,arc*0.0015),True)[:,0,:]
   if len(approx)<3:continue
   polygons.append(approx)
  ret.append((role,polygons))
 return ret

def render_paths(layers,bb_size,points=None,size=(500,560),color=(235,45,88)):
 W,H=size; img=Image.new('RGB',size,(6,7,11));dr=ImageDraw.Draw(img)
 w,h=bb_size
 scale=min(W*.73/w,H*.70/h)
 left=(W-w*scale)/2;top=(H-h*scale)/2
 # PIL polygon cannot do even-odd holes easily. Use input exact mask for preview separately.
 for role, polygons in layers:
  fill=(244,247,253) if role=='core' else color
  for poly in polygons:
   xy=[(round(left+float(x)*scale),round(top+float(y)*scale)) for x,y in poly]
   dr.polygon(xy,fill=fill)
 return img

out=[]
for j,(sid,name,img,dual,desc) in enumerate(entries):
 layers=process_masks(img,dual)
 xvalues=[];yvalues=[]
 for role, polys in layers:
  for p in polys:
   xvalues.extend(p[:,0]);yvalues.extend(p[:,1])
 if not xvalues:raise Exception(f'No vector data: {sid}')
 x0,x1=int(min(xvalues)),int(max(xvalues)); y0,y1=int(min(yvalues)),int(max(yvalues))
 w=max(1,x1-x0);h=max(1,y1-y0)
 norm=[]
 for role,polygons in layers:
  pp=[]
  for poly in polygons:
   verts=[[round(float(x-x0)/w,4),round(float(y-y0)/h,4)] for x,y in poly]
   if len(verts)>=3: pp.append(verts)
  norm.append({'role':role,'polygons':pp})
 # Particle targets from the observed bright mask, not from a rendered bitmap at runtime.
 mask=np.zeros(img.shape[:2],dtype=np.uint8)
 for _,m in get_masks(img,dual):mask=cv2.bitwise_or(mask,m)
 mask=mask[y0:y1+1,x0:x1+1]
 ys,xs=np.where(mask>0)
 rng=random.Random(9137+j*29)
 n=480
 particles=[]
 if len(xs):
  for i in range(n):
   k=rng.randrange(len(xs))
   particles.append([round(float(xs[k])/w,4),round(float(ys[k])/h,4),round(rng.random(),4)])
 item={'id':sid,'name':name,'description':desc,'aspect':round(w/h,5),'layers':norm,'particles':particles}
 out.append(item)
 # Preview rendered from the vector dataset via OpenCV fill with parity on contours.
 # Replay native polygon layers as masks with even-odd (XOR) fill on same pixel area.
 preview=np.zeros((h+1,w+1,3),np.uint8); preview[:]=(8,9,13)
 accent=(42,75,255) if j!=10 else (220,40,190) # BGR
 for li in norm:
  layer_mask=np.zeros((h+1,w+1),np.uint8)
  for pp in li['polygons']:
   poly=np.array([[int(round(x*w)),int(round(y*h))] for x,y in pp],dtype=np.int32)
   this=np.zeros_like(layer_mask)
   cv2.fillPoly(this,[poly],255)
   cv2.bitwise_xor(layer_mask,this,dst=layer_mask)
  preview[layer_mask>0]= (240,245,252) if li['role']=='core' else accent
 ww,hh=560,610
 scale=min((ww*.68)/w,(hh*.70)/h)
 resized=cv2.resize(preview,(max(1,round(w*scale)),max(1,round(h*scale))),interpolation=cv2.INTER_AREA)
 canvas=np.full((hh,ww,3),(13,10,8),np.uint8)
 top=(hh-resized.shape[0])//2 - 15; left=(ww-resized.shape[1])//2
 canvas[top:top+resized.shape[0],left:left+resized.shape[1]]=resized
 cv2.putText(canvas,name.upper(),(25,hh-40),cv2.FONT_HERSHEY_SIMPLEX,.72,(236,232,229),1,cv2.LINE_AA)
 cv2.putText(canvas,f'{j+1:02d} / 12',(25,46),cv2.FONT_HERSHEY_SIMPLEX,.70,(153,144,139),1,cv2.LINE_AA)
 cv2.imwrite(str(BASE/'Previews'/f'{j+1:02d}-{sid}.png'),canvas)
 print(sid,'polys',sum(len(a['polygons']) for a in norm),'pts',sum(sum(len(p) for p in a['polygons']) for a in norm),'aspect',round(w/h,2))
# Native paths in JSON, no runtime image fetching or PNG dependency.
path=BASE/'Sources'/'SpyderNativeCollection'/'Resources'/'artworks.json'
path.write_text(json.dumps(out,separators=(',',':'),ensure_ascii=False))
print('written',path,round(path.stat().st_size/1024),'KB')
# 4x3 contact sheet, docs only
thumbs=[]
for i,info in enumerate(out):
 im=Image.open(BASE/'Previews'/f"{i+1:02d}-{info['id']}.png").convert('RGB')
 thumbs.append(im)
full=Image.new('RGB',(560*4,610*3),(4,5,8))
for i,t in enumerate(thumbs): full.paste(t,((i%4)*560,(i//4)*610))
full.save(BASE/'Previews'/'collection-12.png',optimize=True)
