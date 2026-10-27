import sys, re, json, urllib.request, struct, io
from concurrent.futures import ThreadPoolExecutor
UA={'User-Agent':'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36'}
def fetch(u, timeout=25):
    try:
        r=urllib.request.Request(u,headers=UA)
        return urllib.request.urlopen(r,timeout=timeout).read(), None
    except Exception as e:
        return None, str(e)
def og(u):
    b,err=fetch(u)
    if b is None: return u, 'ERR '+err, None
    h=b.decode('utf8','ignore')
    m=re.search(r'<meta[^>]+property=["\']og:image["\'][^>]+content=["\']([^"\']+)', h) or \
      re.search(r'<meta[^>]+content=["\']([^"\']+)["\'][^>]+property=["\']og:image["\']', h) or \
      re.search(r'<meta[^>]+name=["\']twitter:image["\'][^>]+content=["\']([^"\']+)', h)
    if not m: return u, 'NO_OG', None
    return u, 'OK', m.group(1)
def dims(img):
    b,err=fetch(img,20)
    if b is None: return 'ERR '+err
    if b[:2]==b'\xff\xd8':
        i=2
        while i < len(b)-9:
            if b[i]!=0xFF: i+=1; continue
            mk=b[i+1]
            if mk in (0xC0,0xC1,0xC2,0xC3):
                h,w=struct.unpack('>HH', b[i+5:i+9]); return f'{w}x{h}'
            ln=struct.unpack('>H', b[i+2:i+4])[0]; i+=2+ln
        return 'jpeg(?dims)'
    if b[:8]==b'\x89PNG\r\n\x1a\n':
        w,h=struct.unpack('>II', b[16:24]); return f'{w}x{h}'
    if b[:4]==b'RIFF' and b[8:12]==b'WEBP':
        if b[12:16]==b'VP8X':
            w=int.from_bytes(b[24:27],'little')+1; h=int.from_bytes(b[27:30],'little')+1; return f'{w}x{h}'
        return 'webp(?dims)'
    return 'unknown'
urls=[l.strip() for l in sys.stdin if l.strip()]
with ThreadPoolExecutor(max_workers=8) as ex:
    res=list(ex.map(og, urls))
for u,st,img in res:
    print(f"\n{st} {u[:110]}")
    if img:
        print(f"   IMG {img}")
        print(f"   SIZE {dims(img)}")
