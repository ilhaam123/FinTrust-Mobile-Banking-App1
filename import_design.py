"""Import the user's local .fig: preserve original geometry, glyphs and links.

Decode canvas.fig first with tool/fig_decoder/decode.cjs. Original vector layers
are exported individually; complete-screen reference renders are never app assets.
"""
import base64, collections, copy, hashlib, html, json, math, struct, subprocess, zipfile
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
ROOT=Path(__file__).resolve().parents[1]
DOC=json.loads((ROOT/'design/document.json').read_text())
def key(g): return f"{g['sessionID']}:{g['localID']}"
NODES={key(n['guid']):n for n in DOC['nodeChanges']}
# Resolve shared paints: exported node paint caches may be stale.
for n in NODES.values():
 for ref,field in [('styleIdForFill','fillPaints'),('styleIdForStroke','strokePaints'),('styleIdForEffect','effects')]:
  g=n.get(ref,{}).get('guid')
  if g and key(g) in NODES and field in NODES[key(g)]:n[field]=copy.deepcopy(NODES[key(g)][field])
CHILDREN=collections.defaultdict(list)
for n in NODES.values():
 if 'parentIndex' in n: CHILDREN[key(n['parentIndex']['guid'])].append(n)
for kids in CHILDREN.values(): kids.sort(key=lambda n:n['parentIndex']['position'])
IMAGES={p.name:p.read_bytes() for p in (ROOT.parent/'Untitled.fig/images').iterdir() if p.is_file()}
OUT=ROOT/'assets/local';OUT.mkdir(parents=True,exist_ok=True)
REF=ROOT/'design/reference';REF.mkdir(parents=True,exist_ok=True)
PATHS={}
def commands(index):
 if str(index) in PATHS:return PATHS[str(index)]
 b=bytes(DOC['blobs'][index]['bytes']); result=[]; i=0
 while i<len(b):
  op=b[i];i+=1; count=[0,2,2,4,6][op]; vals=struct.unpack_from('<'+'f'*count,b,i);i+=4*count
  result.append([op,*[round(v,7) for v in vals]])
 PATHS[str(index)]=result
 return result

def path(index):return ' '.join('ZMLQC'[op]+' '.join(str(x) for x in values) for i,(op,*values) in enumerate(commands(index)) if op != 0 or i != 0)
def rgba(c,opacity=1):
 return '#%02x%02x%02x'%(round(c.get('r',0)*255),round(c.get('g',0)*255),round(c.get('b',0)*255)),c.get('a',1)*opacity

def matrix(t):return [t.get(k,v) for k,v in zip(('m00','m10','m01','m11','m02','m12'),(1,0,0,1,0,0))]
def matrixstr(t):return 'matrix('+','.join(str(v) for v in matrix(t))+')'
def bounds(n):
 a,b,c,d,e,f=matrix(n.get('transform',{}));w=n.get('size',{}).get('x',0);h=n.get('size',{}).get('y',0)
 pts=[(a*x+c*y+e,b*x+d*y+f) for x,y in [(0,0),(w,0),(0,h),(w,h)]]
 xs,ys=zip(*pts);return min(xs),min(ys),max(xs)-min(xs),max(ys)-min(ys)

def resolved_children(n):
 if n['type']!='INSTANCE':return CHILDREN.get(key(n['guid']),[])
 source=NODES.get(key(n.get('symbolData',{}).get('symbolID',n['guid'])))
 if source is None:return []
 overrides={}
 for group in [n.get('symbolData',{}).get('symbolOverrides',[]),n.get('derivedSymbolData',[])]:
  for o in group:
   ids=o.get('guidPath',{}).get('guids',[])
   if ids: overrides.setdefault(key(ids[-1]),{}).update({k:v for k,v in o.items() if k!='guidPath'})
 def clone(base):
  k=key(base['guid']); item=copy.deepcopy(base); item.update(overrides.get(k,{}))
  item['_children']=[clone(x) for x in CHILDREN.get(k,[])]
  return item
 return [clone(c) for c in CHILDREN.get(key(source['guid']),[])]

def visible(n):return n.get('visible',True) and n.get('opacity',1)>0 and n.get('phase')!='REMOVED'

class Renderer:
 def __init__(self):self.defs=[];self.counter=0
 def uid(self):self.counter+=1;return 'd'+str(self.counter)
 def paint(self,p,n):
  if p.get('visible',True)==False:return 'none',1
  kind=p.get('type'); opacity=p.get('opacity',1)
  if kind=='SOLID':return rgba(p.get('color',{}),opacity)
  if kind=='GRADIENT_LINEAR':
   ident=self.uid();t=p.get('transform',{});a,b,c,d,e,f=matrix(t);det=a*d-b*c
   w=n['size']['x'];h=n['size']['y']
   def inv(x,y):return ((d*(x-e)-c*(y-f))/det*w,(-b*(x-e)+a*(y-f))/det*h)
   x1,y1=inv(0,.5);x2,y2=inv(1,.5)
   stops=''.join(f'<stop offset="{s["position"]}" stop-color="{rgba(s["color"])[0]}" stop-opacity="{rgba(s["color"])[1]}"/>' for s in p['stops'])
   self.defs.append(f'<linearGradient id="{ident}" gradientUnits="userSpaceOnUse" x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}">{stops}</linearGradient>')
   return f'url(#{ident})',opacity
  return 'none',1
 def geometry(self,n,field,paintfield):
  out=[];geom=n.get(field,[]); paints=n.get(paintfield,[])
  for shape in geom:
   for p in paints:
    if not p.get('visible',True):continue
    data=path(shape['commandsBlob']);rule='evenodd' if shape.get('windingRule')=='ODD' else 'nonzero'
    if p['type']=='IMAGE':
     ident=self.uid();self.defs.append(f'<clipPath id="{ident}"><path d="{data}" fill-rule="{rule}"/></clipPath>')
     hsh=bytes(p['image']['hash']).hex();blob=IMAGES[hsh]
     mime='image/png' if blob[:8]==b'\x89PNG\r\n\x1a\n' else 'image/jpeg'
     a,b,c,d,e,f=matrix(p.get('transform',{}));det=a*d-b*c;w=n['size']['x'];h=n['size']['y']
     trans=f'matrix({d/det*w},{-b/det*h},{-c/det*w},{a/det*h},{(c*f-d*e)/det*w},{(b*e-a*f)/det*h})'
     out.append(f'<g clip-path="url(#{ident})"><image width="1" height="1" preserveAspectRatio="none" transform="{trans}" href="data:{mime};base64,{base64.b64encode(blob).decode()}"/></g>')
    else:
     fill,op=self.paint(p,n)
     item=f'<path d="{data}" fill="{fill}" fill-opacity="{op}" fill-rule="{rule}"/>'
     if field=='strokeGeometry' and n.get('strokeAlign') in ('INSIDE','OUTSIDE'):
      ident=self.uid();fills=''.join(f'<path d="{path(g["commandsBlob"])}" fill="white"/>' for g in n.get('fillGeometry',[]))
      if n['strokeAlign']=='INSIDE':
       self.defs.append(f'<clipPath id="{ident}">{fills}</clipPath>'); item=f'<g clip-path="url(#{ident})">{item}</g>'
      else:
       self.defs.append(f'<mask id="{ident}" x="-100%" y="-100%" width="300%" height="300%"><rect x="-10000" y="-10000" width="20000" height="20000" fill="white"/>{fills.replace("white","black")}</mask>');item=f'<g mask="url(#{ident})">{item}</g>'
     out.append(item)
  return ''.join(out)
 def glyphs(self,n):
  out=[]
  for g in textglyphs(n):
   out.append(f'<path d="{path(g["path"])}" fill="{g["color"]}" transform="translate({g["x"]},{g["y"]}) scale({g["size"]}, {-g["size"]})"/>')
  return ''.join(out)
 def node(self,n,transform=True):
  if not visible(n):return ''
  if n['type']=='TEXT':content=self.glyphs(n)
  else:
   content=self.geometry(n,'fillGeometry','fillPaints')+self.geometry(n,'strokeGeometry','strokePaints')
   kids=n.get('_children') if '_children' in n else resolved_children(n)
   mask_id=None
   for c in kids:
    if c.get('isMask') or c.get('mask'):
     mask_id=self.uid(); self.defs.append(f'<mask id="{mask_id}" mask-type="{"luminance" if c.get("maskType")=="LUMINANCE" else "alpha"}">{self.node(c)}</mask>')
    else:
     child=self.node(c)
     content+=f'<g mask="url(#{mask_id})">{child}</g>' if mask_id else child
  effects=[e for e in n.get('effects',[]) if e.get('visible',True)]
  for e in effects:
   if e['type'] not in ('DROP_SHADOW','INNER_SHADOW'):continue
   ident=self.uid();col,alpha=rgba(e['color']);offset=e.get('offset',{});dx=offset.get('x',0);dy=offset.get('y',0);sigma=e.get('radius',0)/2
   shape=''.join(f'<path d="{path(g["commandsBlob"])}" fill="white"/>' for g in n.get('fillGeometry',[]))
   if not shape:continue
   if e['type']=='DROP_SHADOW':
    self.defs.append(f'<filter id="{ident}" x="-100%" y="-100%" width="300%" height="300%"><feGaussianBlur stdDeviation="{sigma}"/><feOffset dx="{dx}" dy="{dy}"/><feFlood flood-color="{col}" flood-opacity="{alpha}"/><feComposite in2="SourceAlpha" operator="in"/></filter>')
    # Blur+offset mask, then remove the object's interior (transparent cards).
    blur=self.uid();mask=self.uid()
    self.defs.append(f'<filter id="{blur}" x="-100%" y="-100%" width="300%" height="300%"><feGaussianBlur stdDeviation="{sigma}"/><feOffset dx="{dx}" dy="{dy}"/></filter>')
    self.defs.append(f'<mask id="{mask}" x="-100%" y="-100%" width="300%" height="300%"><g filter="url(#{blur})">{shape}</g>{shape.replace("white","black")}</mask>')
    shadow=f'<rect x="-1000" y="-1000" width="3000" height="3000" fill="{col}" opacity="{alpha}" mask="url(#{mask})"/>'
    content=shadow+content
   else:
    self.defs.append(f'<filter id="{ident}" x="-100%" y="-100%" width="300%" height="300%"><feOffset in="SourceAlpha" dx="{dx}" dy="{dy}"/><feGaussianBlur stdDeviation="{sigma}" result="shifted"/><feComposite in="SourceAlpha" in2="shifted" operator="out" result="edge"/><feFlood flood-color="{col}" flood-opacity="{alpha}"/><feComposite operator="in" in2="edge"/></filter>')
    content+=f'<g filter="url(#{ident})">{shape}</g>'
  if n['type'] in ('FRAME','SYMBOL') and not n.get('frameMaskDisabled',False):
   ident=self.uid();w=n.get('size',{}).get('x',0);h=n.get('size',{}).get('y',0)
   self.defs.append(f'<clipPath id="{ident}"><rect width="{w}" height="{h}"/></clipPath>');content=f'<g clip-path="url(#{ident})">{content}</g>'
  opacity=n.get('opacity',1)
  return f'<g opacity="{opacity}" transform="{matrixstr(n.get("transform",{})) if transform else ""}">{content}</g>'
 def svg(self,content,box):
  x,y,w,h=box
  return f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="{x} {y} {w} {h}"><defs>{"".join(self.defs)}</defs>{content}</svg>'

def textglyphs(n):
 styles={x['styleID']:x for x in n.get('textData',{}).get('styleOverrideTable',[])};charstyles=n.get('textData',{}).get('characterStyleIDs',[]);out=[]
 for g in n.get('derivedTextData',{}).get('glyphs',[]):
  sid=charstyles[g['firstCharacter']] if g.get('firstCharacter',0)<len(charstyles) else 0
  style=styles.get(sid,{})
  paints=style.get('fillPaints',n.get('fillPaints',[]));p=next((p for p in paints if p.get('visible',True)),{})
  color,opacity=rgba(p.get('color',{}),p.get('opacity',1))
  commands(g['commandsBlob'])
  out.append({'path':g['commandsBlob'],'x':g['position']['x'],'y':g['position']['y'],'size':g.get('fontSize',n.get('fontSize',16)),'color':color,'opacity':opacity})
 return out

# Export authored sections as separate assets, with nested semantic hit targets.
frames=[n for n in CHILDREN['196:22'] if n['type']=='FRAME' and n.get('size')=={'x':412,'y':917}]
scenes={};jobs={};manifest=[]
def mul(a,b):
 A,B,C,D,E,F=a;g,h,i,j,k,l=b
 return [A*g+C*h,B*g+D*h,A*i+C*j,B*i+D*j,A*k+C*l+E,B*k+D*l+F]
def rect(n,m):
 w=n.get('size',{}).get('x',0);h=n.get('size',{}).get('y',0);a,b,c,d,e,f=m
 pts=[(a*x+c*y+e,b*x+d*y+f) for x,y in [(0,0),(w,0),(0,h),(w,h)]]
 xs,ys=zip(*pts);return [min(xs),min(ys),max(xs)-min(xs),max(ys)-min(ys)]
def alltext(n):
 return ' '.join([n.get('textData',{}).get('characters','')]+[alltext(c) for c in resolved_children(n) if visible(c)]).strip()
def walk(n,m,links,texts,timers):
 if not visible(n):return
 m=mul(m,matrix(n.get('transform',{})));box=rect(n,m)
 if n['type']=='TEXT':texts.append(dict(id=key(n['guid']),text=n.get('textData',{}).get('characters',''),box=box))
 for r in n.get('prototypeInteractions',[]):
  if r.get('isDeleted'):continue
  for a in r.get('actions',[]):
   target=key(a['transitionNodeID']) if 'transitionNodeID'in a else None
   item=dict(id=key(n['guid']),label=alltext(n) or n.get('name',''),box=box,target=target,navigation=a.get('navigationType',''),event=r['event'])
   if r['event']['interactionType']=='AFTER_TIMEOUT':timers.append(item)
   elif r['event']['interactionType'] in ('ON_CLICK','ON_PRESS','DRAG'):links.append(item)
 for c in resolved_children(n):walk(c,m,links,texts,timers)
def visual_bounds(n,m=None):
 if m is None:m=[1,0,0,1,0,0]
 m=mul(m,matrix(n.get('transform',{})));box=rect(n,m)
 if n['type'] not in ('FRAME','SYMBOL') or n.get('frameMaskDisabled',False):
  for c in resolved_children(n):
   if not visible(c):continue
   b=visual_bounds(c,m);x=min(box[0],b[0]);y=min(box[1],b[1])
   box=[x,y,max(box[0]+box[2],b[0]+b[2])-x,max(box[1]+box[3],b[1]+b[3])-y]
 pad=max([e.get('radius',0)+max(abs(e.get('offset',{}).get('x',0)),abs(e.get('offset',{}).get('y',0))) for e in n.get('effects',[]) if e.get('visible',True)]+[0])
 return [box[0]-pad,box[1]-pad,box[2]+2*pad,box[3]+2*pad]

def asset(n,box,own=False):
 r=Renderer()
 body=r.geometry(n,'fillGeometry','fillPaints')+r.geometry(n,'strokeGeometry','strokePaints') if own else r.node(n)
 svg=r.svg(body,box);digest=hashlib.sha256(svg.encode()).hexdigest()[:20]
 p=OUT/(digest+'.svg');p.write_text(svg);png=p.with_suffix('.png');jobs[digest]=(p,png)
 return str(png.relative_to(ROOT))
for f in frames:
 fid=key(f['guid']);layers=[];links=[];texts=[];timers=[]
 layers.append(dict(asset=asset(f,(0,0,412,917),True),box=[0,0,412,917]))
 for n in CHILDREN[fid]:
  if not visible(n):continue
  x,y,w,h=visual_bounds(n)
  if w<=0 or h<=0:continue
  # Clip exported sections to the root viewport without changing source pixels.
  pad=1
  x0=max(0,x-pad);y0=max(0,y-pad);x1=min(412,x+w+pad);y1=min(917,y+h+pad)
  if x1<=x0 or y1<=y0:continue
  box=[x0,y0,x1-x0,y1-y0]
  layers.append(dict(asset=asset(n,box),box=box,id=key(n['guid'])))
  walk(n,[1,0,0,1,0,0],links,texts,timers)
 for reaction in f.get('prototypeInteractions',[]):
  if not reaction.get('isDeleted') and reaction['event']['interactionType']=='AFTER_TIMEOUT':
   for action in reaction.get('actions',[]):
    if 'transitionNodeID'in action:timers.append(dict(target=key(action['transitionNodeID']),event=reaction['event']))
 scenes[fid]=dict(name=f['name'],layers=layers,links=links,texts=texts,timers=timers)
 if fid in ['280:18','269:1090','269:1631','317:281']:
  r=Renderer();body=r.node(f,False);p=REF/(fid.replace(':','_')+'.svg');p.write_text(r.svg(body,(0,0,412,917)));jobs[fid]=(p,p.with_suffix('.png'))
(ROOT/'assets/design.json').write_text(json.dumps(scenes,separators=(',',':')))
(ROOT/'design/manifest.json').write_text(json.dumps({k:{'name':v['name'],'layers':v['layers'],'links':v['links']} for k,v in scenes.items()},indent=2))
def raster(job):
 p,png=job
 subprocess.run(['rsvg-convert','--zoom=2','--output',str(png),str(p)],check=True,stderr=subprocess.PIPE)
with ThreadPoolExecutor(max_workers=4) as pool:list(pool.map(raster,jobs.values()))
print(f'Imported {len(scenes)} screens, {len(jobs)} section assets, {sum(len(s["links"]) for s in scenes.values())} links')

# Keep bundle declarations aligned with regenerated section hashes.
pubspec=ROOT/'pubspec.yaml'
content=pubspec.read_text().split('  assets:')[0]
files=sorted({l['asset'] for scene in scenes.values() for l in scene['layers']})
pubspec.write_text(content+'  assets:\n    - assets/design.json\n'+''.join('    - '+p+'\n' for p in files))
