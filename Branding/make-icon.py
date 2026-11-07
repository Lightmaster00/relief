import math
def squircle(x0,y0,size,n=5.0,N=360):
    c=size/2; pts=[]
    for i in range(N):
        t=2*math.pi*i/N; ct,st=math.cos(t),math.sin(t)
        x=abs(ct)**(2/n)*(1 if ct>=0 else -1); y=abs(st)**(2/n)*(1 if st>=0 else -1)
        pts.append((x0+c+c*x,y0+c+c*y))
    return 'M'+' L'.join(f'{a:.2f} {b:.2f}' for a,b in pts)+' Z'
tile=squircle(100,100,824)
# speaker body (side view): rounded box + cone flare, centred ~ (380,512)
spk = 'M262 422 L340 422 L456 326 L456 698 L340 602 L262 602 Z'
def arc(r, w):
    cx,cy=478,512; a=math.radians(46)
    x1,y1=cx+r*math.cos(-a),cy+r*math.sin(-a); x2,y2=cx+r*math.cos(a),cy+r*math.sin(a)
    return f'<path d="M{x1:.1f} {y1:.1f} A{r} {r} 0 0 1 {x2:.1f} {y2:.1f}" fill="none" stroke="#fff" stroke-width="{w}" stroke-linecap="round"/>'
def extr(r,w,i):
    cols=[("#7FF0E6","#22D3C5"),("#C3B2FF","#8E70FF"),("#FFB3D3","#FF5FA2")]
    top,side=cols[i]
    d=arc(r,w)
    a=d.replace('stroke="#fff"','stroke="%s"'%side).replace('<path','<path transform="translate(0 16)"')
    b=d.replace('stroke="#fff"','stroke="url(#w%d)"'%i)
    return a+b
svg=f'''<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
<defs>
  <linearGradient id="tile" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#A184FF"/><stop offset=".55" stop-color="#6A47F0"/><stop offset="1" stop-color="#4A2BC9"/>
  </linearGradient>
  <radialGradient id="glowA" cx="230" cy="880" r="520" gradientUnits="userSpaceOnUse">
    <stop offset="0" stop-color="#22D3C5" stop-opacity=".75"/><stop offset="1" stop-color="#22D3C5" stop-opacity="0"/>
  </radialGradient>
  <radialGradient id="glowB" cx="860" cy="170" r="480" gradientUnits="userSpaceOnUse">
    <stop offset="0" stop-color="#FF5FA2" stop-opacity=".65"/><stop offset="1" stop-color="#FF5FA2" stop-opacity="0"/>
  </radialGradient>
  <linearGradient id="sheen" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#fff" stop-opacity=".22"/><stop offset=".5" stop-color="#fff" stop-opacity="0"/>
  </linearGradient>
  <linearGradient id="glyph" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#FFFFFF"/><stop offset="1" stop-color="#E9E4FF"/>
  </linearGradient>
  <linearGradient id="w0" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#FFFFFF"/><stop offset="1" stop-color="#B9FFF8"/></linearGradient>
  <linearGradient id="w1" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#FFFFFF"/><stop offset="1" stop-color="#E2D9FF"/></linearGradient>
  <linearGradient id="w2" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#FFFFFF"/><stop offset="1" stop-color="#FFD9EA"/></linearGradient>
  <filter id="tileShadow" x="-20%" y="-20%" width="140%" height="140%">
    <feDropShadow dx="0" dy="12" stdDeviation="14" flood-color="#000" flood-opacity=".3"/>
  </filter>
  <filter id="lift" x="-30%" y="-30%" width="160%" height="160%">
    <feDropShadow dx="0" dy="14" stdDeviation="16" flood-color="#1E0D6B" flood-opacity=".45"/>
  </filter>
  <clipPath id="clip"><path d="{tile}"/></clipPath>
</defs>
<path d="{tile}" fill="url(#tile)" filter="url(#tileShadow)"/>
<g clip-path="url(#clip)">
  <rect width="1024" height="1024" fill="url(#glowA)"/>
  <rect width="1024" height="1024" fill="url(#glowB)"/>
  <rect width="1024" height="1024" fill="url(#sheen)"/>
</g>
<path d="{tile}" fill="none" stroke="#fff" stroke-opacity=".18" stroke-width="3"/>
<g filter="url(#lift)">
  <path d="{spk}" fill="#C9BCFF" stroke="#C9BCFF" stroke-width="28" stroke-linejoin="round" transform="translate(0 14)"/>
  <path d="{spk}" fill="url(#glyph)" stroke="url(#glyph)" stroke-width="28" stroke-linejoin="round"/>
  {extr(110,48,0)}
  {extr(198,48,1)}
  {extr(286,48,2)}
</g>
</svg>'''
open('icon.svg','w').write(svg)
