#!/usr/bin/env python3
"""Cross-platform invariant checks. Does NOT replace an Xcode build."""
from pathlib import Path
import json, sys
base=Path(__file__).resolve().parent.parent
art=json.loads((base/'Sources/SpyderNativeCollection/Resources/artworks.json').read_text())
assert len(art)==12, len(art)
assert len({a['id'] for a in art})==12
minpoints=0
for a in art:
 assert a['name'] and .2<a['aspect']<2, a['id']
 assert len(a['particles'])==480, a['id']
 assert len(a['layers'])>=1
 assert (base/'Previews'/f"{art.index(a)+1:02d}-{a['id']}.png").is_file()
 for layer in a['layers']:
  assert layer['role'] in ('core','accent')
  assert len(layer['polygons'])>=1
  for poly in layer['polygons']:
   assert len(poly)>=3, (a['id'],'polygon')
   minpoints+=len(poly)
   assert all(len(p)==2 and 0<=p[0]<=1 and 0<=p[1]<=1 for p in poly),a['id']
 for p in a['particles']:
  assert len(p)==3 and all(0<=v<=1 for v in p),a['id']
assert minpoints>=1000
assert (base/'Previews/collection-12.png').stat().st_size>10000
source='\n'.join(p.read_text() for p in (base/'Sources/SpyderNativeCollection').glob('*.swift'))
assert 'Canvas(' in source and 'TimelineView(' in source
assert 'accessibilityReduceMotion' in source
assert 'animationOnChatEntryOnly' in source
assert 'SpyderNativeBackdropView' in source
assert 'SpyderVectorArtworkView' in source
print(f'PASS | {len(art)} styles | {len(art)*480} particle targets | {minpoints} vector vertices | 12 PNG previews')
