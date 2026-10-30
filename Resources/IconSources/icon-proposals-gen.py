import re, cairosvg, os
ESAI = open('/tmp/esai/docs/assets/icon.svg').read()
FLOWER = re.search(r'<path d="([^"]+)"', ESAI).group(1)   # exact esai 12-petal geometry (18-unit grid)
PETAL = "M 8.68 6.95 L 8.06 1.69 C 8.06 1.17085 8.48085 0.75 9 0.75 C 9.51915 0.75 9.94 1.17085 9.94 1.69 L 9.32 6.95 Q 9 7.55 8.68 6.95 Z"  # esai top petal, inner end rounded
BOLT = "M 9.75 6.2 L 7.35 9.35 L 8.85 9.35 L 8.25 11.8 L 10.65 8.65 L 9.15 8.65 Z"
GRAD = {'A':('#94CD3D','#08A264'), 'B':('#86E0C8','#079A96'), 'C':('#A6D84A','#0A9A78'), 'D':('#7FD9EE','#1478C8')}
NAMES = {'A':'余量花瓣','B':'脉冲花心','C':'流量环','D':'闪电花心'}
WHY = {'A':'沿用 esai 十二瓣，最后三瓣变淡，像一块“剩余量表”，一眼读出还剩多少。',
       'B':'花型完全不变，花心镂空成“信号点+涟漪”，配湖水青渐变，表达代理在线与脉冲。',
       'C':'缩小的 esai 花朵外加一圈 3/4 进度环，花是家族识别，环是剩余流量。',
       'D':'花型不变，花心嵌入一道闪电（Impulse），色相转向青蓝，与 esai 绿成姊妹款。'}
def hole(r): return f'M 9 {9-r} A {r} {r} 0 1 0 9 {9+r} A {r} {r} 0 1 0 9 {9-r} Z'
SHORT={'A':['后三瓣变淡，像剩余量表，','一眼读出还剩多少。'],'B':['花心镂空成信号点+涟漪，','湖水青渐变，代表在线与脉冲。'],
 'C':['esai 花朵 + 3/4 进度环，','花是家族识别，环是剩余流量。'],'D':['花心嵌入闪电（Impulse），','青蓝色相，与 esai 绿成姊妹款。']}
def rot(k): return f'rotate({30*k} 9 9)'
def body(v, fill, dim, uid):
    """Elements in the 18x18 grid. fill = paint; dim = opacity for 'remaining' parts."""
    if v=='A':
        s=''.join(f'<path d="{PETAL}" transform="{rot(k)}" fill="{fill}" opacity="{1 if k<9 else dim}"/>' for k in range(12))
        return s+f'<circle cx="9" cy="9" r="1.25" fill="{fill}"/>'
    if v=='B':
        return (f'<path d="{FLOWER} {hole(2.05)}" fill-rule="evenodd" fill="{fill}"/><circle cx="9" cy="9" r="1.0" fill="{fill}"/>')
    if v=='C':
        import math
        def pt(a,r=7.9): a=math.radians(a-90); return f'{9+r*math.cos(a):.3f} {9+r*math.sin(a):.3f}'
        arc=f'M {pt(0)} A 7.9 7.9 0 1 1 {pt(270)}'
        rest=f'M {pt(270)} A 7.9 7.9 0 0 1 {pt(360-0.01)}'
        return (f'<path d="{rest}" fill="none" stroke="{fill}" stroke-width="1.35" opacity="{dim}"/>'
                f'<path d="{arc}" fill="none" stroke="{fill}" stroke-width="1.35" stroke-linecap="round"/>'
                f'<g transform="translate(9 9) scale(0.64) translate(-9 -9)"><path d="{FLOWER}" fill="{fill}"/></g>')
    if v=='D':
        pd="M 8.6 5.75 L 8.06 1.69 C 8.06 1.17085 8.48085 0.75 9 0.75 C 9.51915 0.75 9.94 1.17085 9.94 1.69 L 9.4 5.75 Q 9 6.3 8.6 5.75 Z"
        return (''.join(f'<path d="{pd}" transform="{rot(k)}" fill="{fill}"/>' for k in range(12))+f'<path d="{BOLT}" fill="{fill}" stroke="{fill}" stroke-width="0.35" stroke-linejoin="round"/>')
def grad(v,uid):
    a,b=GRAD[v]
    return f'<radialGradient id="g{uid}" gradientUnits="userSpaceOnUse" cx="9" cy="9" r="8.4"><stop stop-color="{a}"/><stop offset="1" stop-color="{b}"/></radialGradient>'
def app_icon(v,uid):
    return (f'<defs><linearGradient id="p{uid}" x1="0" y1="0" x2="0" y2="1"><stop stop-color="#FFFFFF"/><stop offset="1" stop-color="#F0F5F1"/></linearGradient>'
            f'{grad(v,uid)}<filter id="s{uid}" x="-20%" y="-20%" width="140%" height="140%"><feDropShadow dx="0" dy="5" stdDeviation="6" flood-opacity="0.12"/></filter></defs>'
            f'<rect x="100" y="100" width="824" height="824" rx="182" fill="url(#p{uid})" stroke="#E2E9E3" stroke-width="1.5" filter="url(#s{uid})"/>'
            f'<g transform="translate(176 176) scale(37.33333333)">{body(v,f"url(#g{uid})",0.22,uid+"a")}</g>')
def svg(w,h,inner): return f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">{inner}</svg>'
def menubar(v,x,y,w,dark,uid,label='128.4 GB',color=None):
    bg='#2B2B2E' if dark else '#ECECEE'; fg='#FFFFFF' if dark else '#000000'
    s=2  # @2x so it reads like a real Retina menu bar (24pt bar, 18pt icon, 13pt text)
    out=f'<rect x="{x}" y="{y}" width="{w}" height="{24*s}" fill="{bg}" rx="10"/>'
    ix=x+w-210
    out+=f'<g transform="translate({ix} {y+3*s}) scale({s})">{body(v,fg,0.32,uid)}</g>'
    out+=f'<text x="{ix+22*s}" y="{y+16.6*s}" font-family="Noto Sans CJK SC" font-weight="500" font-size="{13*s}" fill="{color or fg}">{label}</text>'
    # neighbouring system items for context
    out+=f'<text x="{x+24}" y="{y+16.6*s}" font-family="Noto Sans CJK SC" font-size="{13*s}" fill="{fg}" opacity="0.85">  访达   文件   编辑</text>'
    return out
TXT='font-family="Noto Sans CJK SC"'
def sheet(v):
    W,H=1600,1040; o=f'<rect width="{W}" height="{H}" fill="#F5F6F3"/>'
    o+=f'<text x="64" y="84" {TXT} font-size="26" fill="#7A817C">ESAI Impulse</text>'
    o+=f'<text x="64" y="140" {TXT} font-weight="700" font-size="46" fill="#1D211E">方案 {v} · {NAMES[v]}</text>'
    o+=f'<text x="64" y="188" {TXT} font-size="24" fill="#4E5550">{WHY[v]}</text>'
    for i,(bg,lab,lc) in enumerate([('#FFFFFF','应用图标 · 浅色背景','#4E5550'),('#1C1D1F','应用图标 · 深色背景','#C9CCCA')]):
        x=64+i*400
        o+=f'<rect x="{x}" y="230" width="372" height="420" rx="24" fill="{bg}" stroke="#DDE2DE"/>'
        o+=f'<text x="{x+24}" y="270" {TXT} font-size="20" fill="{lc}">{lab}</text>'
        o+=f'<g transform="translate({x+46} 300) scale(0.273)">{app_icon(v,f"{v}{i}")}</g>'
    # big template preview
    o+=f'<rect x="864" y="230" width="672" height="420" rx="24" fill="#FFFFFF" stroke="#DDE2DE"/>'
    o+=f'<text x="888" y="270" {TXT} font-size="20" fill="#4E5550">状态栏模板图标 · 单色自适应（放大预览 · 实际 18 pt）</text>'
    o+=f'<g transform="translate(910 310) scale(16)">{body(v,"#000",0.32,v+"t1")}</g>'
    o+=f'<rect x="1214" y="300" width="300" height="308" rx="18" fill="#1C1D1F"/>'
    o+=f'<g transform="translate(1227 316) scale(15.2)">{body(v,"#fff",0.32,v+"t2")}</g>'
    o+=f'<text x="64" y="712" {TXT} font-size="20" fill="#4E5550">菜单栏预览 · 实际大小（@2x）</text>'
    o+=menubar(v,64,732,1472,False,v+"m1")
    o+=menubar(v,64,800,1472,True,v+"m2")
    o+=f'<text x="64" y="900" {TXT} font-size="20" fill="#4E5550">低流量 / 用尽时只有数字变色，图标保持单色</text>'
    o+=menubar(v,64,920,720,False,v+"m3",'86.2 GB','#C66A08')
    o+=menubar(v,816,920,720,True,v+"m4",'0 GB','#FF453A')
    return svg(W,H,o)
os.makedirs('svg',exist_ok=True); os.makedirs('png',exist_ok=True)
for v in 'ABCD':
    open(f'svg/app-icon-{v}.svg','w').write(svg(1024,1024,app_icon(v,v)))
    open(f'svg/status-template-{v}.svg','w').write(svg(18,18,body(v,"#000",0.32,v)))
    s=sheet(v); open(f'svg/sheet-{v}.svg','w').write(s)
    cairosvg.svg2png(bytestring=s.encode(),write_to=f'png/sheet-{v}.png')
# overview
W,H=1600,820; o=f'<rect width="{W}" height="{H}" fill="#F5F6F3"/>'
o+=f'<text x="64" y="90" {TXT} font-weight="700" font-size="44" fill="#1D211E">ESAI Impulse · 图标方案总览</text>'
o+=f'<text x="64" y="136" {TXT} font-size="22" fill="#4E5550">全部基于 esai 原版十二瓣花朵几何（docs/assets/icon.svg），请选择一个方案</text>'
for i,v in enumerate('ABCD'):
    x=64+i*372
    o+=f'<rect x="{x}" y="176" width="348" height="600" rx="24" fill="#FFFFFF" stroke="#DDE2DE"/>'
    o+=f'<text x="{x+24}" y="222" {TXT} font-weight="700" font-size="28" fill="#1D211E">方案 {v} · {NAMES[v]}</text>'
    o+=f'<g transform="translate({x+34} 240) scale(0.273)">{app_icon(v,"o"+v)}</g>'
    for j,dark in enumerate([False,True]):
        bg='#2B2B2E' if dark else '#ECECEE'; fg='#fff' if dark else '#000'; y=540+j*64
        o+=f'<rect x="{x+24}" y="{y}" width="300" height="48" rx="10" fill="{bg}"/>'
        o+=f'<g transform="translate({x+70} {y+6}) scale(2)">{body(v,fg,0.32,f"o{v}{j}")}</g>'
        o+=f'<text x="{x+114}" y="{y+33}" {TXT} font-weight="500" font-size="26" fill="{fg}">128.4 GB</text>'
    o+=''.join(f'<text x="{x+24}" y="{704+26*n}" {TXT} font-size="17" fill="#4E5550">{l}</text>' for n,l in enumerate(SHORT[v]))
s=svg(W,H,o); open('svg/overview.svg','w').write(s); cairosvg.svg2png(bytestring=s.encode(),write_to='png/overview.png')
print('done')
