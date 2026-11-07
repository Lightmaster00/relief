import math
def squircle(x0,y0,size,n=5.0,N=360):
    c=size/2; pts=[]
    for i in range(N):
        t=2*math.pi*i/N; ct,st=math.cos(t),math.sin(t)
        x=abs(ct)**(2/n)*(1 if ct>=0 else -1); y=abs(st)**(2/n)*(1 if st>=0 else -1)
        pts.append((x0+c+c*x,y0+c+c*y))
    return 'M'+' L'.join(f'{a:.2f} {b:.2f}' for a,b in pts)+' Z'
T=squircle(100,100,824)
def wave(amp, cycles=2.2, phase=0.0, x0=196, x1=828, cy=512):
    pts=[]
    for i in range(241):
        t=i/240; x=x0+(x1-x0)*t
        env=math.sin(math.pi*t)**1.2
        y=cy-env*amp*math.sin(2*math.pi*(cycles*t+phase))
        pts.append(f'{x:.1f} {y:.1f}')
    return 'M'+' L'.join(pts)
main=wave(215)
ghost=wave(150, cycles=2.2, phase=0.12, cy=530)
svg=f'''<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024"><defs>
<linearGradient id="bg" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#FF6FAE"/><stop offset=".5" stop-color="#B04BE8"/><stop offset="1" stop-color="#5B33F0"/></linearGradient>
<radialGradient id="hl" cx="290" cy="170" r="660" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="#fff" stop-opacity=".28"/><stop offset="1" stop-color="#fff" stop-opacity="0"/></radialGradient>
<radialGradient id="glow" cx="512" cy="512" r="380" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="#fff" stop-opacity=".18"/><stop offset="1" stop-color="#fff" stop-opacity="0"/></radialGradient>
<linearGradient id="w" x1="0" y1="250" x2="0" y2="780" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="#FFFFFF"/><stop offset="1" stop-color="#F1E6FF"/></linearGradient>
<linearGradient id="side" x1="196" y1="0" x2="828" y2="0" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="#FF9CC8"/><stop offset=".5" stop-color="#B98CFF"/><stop offset="1" stop-color="#7C63FF"/></linearGradient>
<filter id="ts" x="-20%" y="-20%" width="140%" height="140%"><feDropShadow dx="0" dy="12" stdDeviation="14" flood-color="#000" flood-opacity=".3"/></filter>
<filter id="lift" x="-30%" y="-40%" width="160%" height="180%"><feDropShadow dx="0" dy="22" stdDeviation="20" flood-color="#2A0A6B" flood-opacity=".45"/></filter>
<clipPath id="clip"><path d="{T}"/></clipPath></defs>
<path d="{T}" fill="url(#bg)" filter="url(#ts)"/>
<g clip-path="url(#clip)">
  <rect width="1024" height="1024" fill="url(#hl)"/>
  <rect width="1024" height="1024" fill="url(#glow)"/>
  <path d="{ghost}" fill="none" stroke="#fff" stroke-opacity=".28" stroke-width="40" stroke-linecap="round" stroke-linejoin="round"/>
  <g filter="url(#lift)">
    <path d="{main}" fill="none" stroke="url(#side)" stroke-width="76" stroke-linecap="round" stroke-linejoin="round" transform="translate(0 18)"/>
    <path d="{main}" fill="none" stroke="url(#w)" stroke-width="76" stroke-linecap="round" stroke-linejoin="round"/>
  </g>
</g>
<path d="{T}" fill="none" stroke="#fff" stroke-opacity=".2" stroke-width="3"/></svg>'''
open('icon.svg','w').write(svg)
# Menu bar: main wave + lighter offset copy (relief), 18 pt
def mbwave(amp, dy=0):
    pts=[]
    for i in range(121):
        t=i/120; x=1.8+14.4*t
        env=math.sin(math.pi*t)**1.2
        y=9+dy-env*amp*math.sin(2*math.pi*2.2*t)
        pts.append(f'{x:.2f} {y:.2f}')
    return 'M'+' L'.join(pts)
mb=f'''<svg xmlns="http://www.w3.org/2000/svg" width="72" height="72" viewBox="0 0 18 18">
<path d="{mbwave(5.6,1.9)}" fill="none" stroke="#000" stroke-opacity=".45" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/>
<path d="{mbwave(5.6)}" fill="none" stroke="#000" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"/>
</svg>'''
open('menubar-icon.svg','w').write(mb)
