import math
def squircle(x0,y0,size,n=5.0,N=360):
    c=size/2; pts=[]
    for i in range(N):
        t=2*math.pi*i/N; ct,st=math.cos(t),math.sin(t)
        x=abs(ct)**(2/n)*(1 if ct>=0 else -1); y=abs(st)**(2/n)*(1 if st>=0 else -1)
        pts.append((x0+c+c*x,y0+c+c*y))
    return 'M'+' L'.join(f'{a:.2f} {b:.2f}' for a,b in pts)+' Z'
tile=squircle(100,100,824)
def ridge_pts(base, peaks, x0=60, x1=964, N=220):
    pts=[]
    for i in range(N+1):
        x=x0+(x1-x0)*i/N
        y=base
        for (cx,h,w) in peaks:
            y-=h*math.exp(-((x-cx)/w)**2)
        pts.append((x,y))
    return pts
def path(pts, bottom=1024):
    return 'M'+' L'.join(f'{x:.1f} {y:.1f}' for x,y in pts)+f' L{pts[-1][0]} {bottom} L{pts[0][0]} {bottom} Z'
def line(pts):
    return 'M'+' L'.join(f'{x:.1f} {y:.1f}' for x,y in pts)
layers=[
  dict(base=560, peaks=[(600,250,70),(700,90,60),(430,70,70),(300,40,60)], fill='url(#l0)', edge='#E6FFFC'),
  dict(base=650, peaks=[(420,250,62),(330,90,55),(540,110,55),(760,60,70)], fill='url(#l1)', edge='#F3EEFF'),
  dict(base=745, peaks=[(590,200,52),(690,95,48),(470,70,55),(250,35,70),(830,30,60)], fill='url(#l2)', edge='#FFFFFF'),
]
body=''
for L in layers:
    p=ridge_pts(L['base'],L['peaks'])
    body+=f'<path d="{path(p)}" fill="#0B0820" opacity=".55" filter="url(#blur)" transform="translate(0 -10)"/>\n'
    body+=f'<path d="{path(p)}" fill="{L["fill"]}"/>\n'
    body+=f'<path d="{line(p)}" fill="none" stroke="{L["edge"]}" stroke-width="5" stroke-opacity=".9" stroke-linejoin="round"/>\n'
svg=f'''<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
<defs>
  <linearGradient id="tile" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#2B2357"/><stop offset="1" stop-color="#120E2A"/>
  </linearGradient>
  <radialGradient id="sky" cx="560" cy="260" r="460" gradientUnits="userSpaceOnUse">
    <stop offset="0" stop-color="#8F72FF" stop-opacity=".6"/><stop offset="1" stop-color="#8F72FF" stop-opacity="0"/>
  </radialGradient>
  <linearGradient id="l0" x1="0" y1="300" x2="0" y2="760" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="#5FE6DA"/><stop offset="1" stop-color="#127E86"/></linearGradient>
  <linearGradient id="l1" x1="0" y1="390" x2="0" y2="860" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="#A88EFF"/><stop offset="1" stop-color="#4A2BC9"/></linearGradient>
  <linearGradient id="l2" x1="0" y1="540" x2="0" y2="930" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="#FF8FBF"/><stop offset="1" stop-color="#B8336E"/></linearGradient>
  <linearGradient id="sheen" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#fff" stop-opacity=".14"/><stop offset=".4" stop-color="#fff" stop-opacity="0"/>
  </linearGradient>
  <filter id="tileShadow" x="-20%" y="-20%" width="140%" height="140%">
    <feDropShadow dx="0" dy="12" stdDeviation="14" flood-color="#000" flood-opacity=".35"/>
  </filter>
  <filter id="blur" x="-10%" y="-20%" width="120%" height="140%"><feGaussianBlur stdDeviation="14"/></filter>
  <clipPath id="clip"><path d="{tile}"/></clipPath>
</defs>
<path d="{tile}" fill="url(#tile)" filter="url(#tileShadow)"/>
<g clip-path="url(#clip)">
  <rect width="1024" height="1024" fill="url(#sky)"/>
  {body}
  <rect width="1024" height="1024" fill="url(#sheen)"/>
</g>
<path d="{tile}" fill="none" stroke="#fff" stroke-opacity=".14" stroke-width="3"/>
</svg>'''
open('icon.svg','w').write(svg)
