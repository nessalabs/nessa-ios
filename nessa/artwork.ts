// The reference design's halftone equations, recorded by Exact's Canvas 2D host.
// All dimensions are in points; the host selects the backing scale for its screen.
import type { Ctx2D, Frame } from './app.contract.d.ts';
export const surfaces = { horizon: 1, channelTile: 2, profile: 0, avatar: 2, gridGlyph: 0 };
const tau = Math.PI * 2;
const ink = 'rgba(214,210,206,0.9)';

function dots(c: Ctx2D, w: number, h: number, cell: number, cutoff: number, fraction: number,
  from: number, light: (x: number, y: number) => number) {
  c.beginPath();
  for (let y = Math.floor(from / cell) * cell + cell / 2; y < h + cell / 2; y += cell) {
    for (let x = cell / 2; x < w + cell / 2; x += cell) {
      const d = cell * fraction * Math.sqrt(light(x, y));
      if (d <= cutoff) continue;
      c.moveTo(x + d / 2, y); c.arc(x, y, d / 2, 0, tau);
    }
  }
  c.fill();
}

// The same FNV-1a / SplitMix64 sequence as NessaAvatarPaint. Keeping it here,
// instead of sending an image over the bridge, makes the art deterministic offline.
function blooms(seed: string) {
  const mask = BigInt('18446744073709551615'), one = BigInt(1);
  let state = BigInt('14695981039346656037');
  for (const ch of encodeURIComponent(seed).replace(/%([\dA-F]{2})/gi,
    (_, hex: string) => String.fromCharCode(parseInt(hex, 16)))) {
    state = ((state ^ BigInt(ch.charCodeAt(0))) * BigInt('1099511628211')) & mask;
  }
  function unit() {
    state = (state + BigInt('11400714819323198485')) & mask;
    let z = state;
    z = ((z ^ (z >> BigInt(30))) * BigInt('13787848793156543929')) & mask;
    z = ((z ^ (z >> BigInt(27))) * BigInt('10723151780598845931')) & mask;
    return Number((z ^ (z >> BigInt(31))) >> BigInt(11)) / Number(one << BigInt(53));
  }
  return Array.from({ length: 3 }, () => [unit()*1.2-0.1, unit()*1.2-0.1, unit()*0.4+0.45, unit()*0.45+0.55]);
}

export function draw(surface: string, args: unknown[], c: Ctx2D, f: Frame): boolean {
  const w = f.width, h = f.height;
  if (!w || !h) return false;
  c.reset();
  if (surface === 'horizon') {
    const animate = args[0] === true, age = Math.max(0, f.time - f.mounted);
    c.fillStyle = '#000'; c.fillRect(0, 0, w, h);
    const rise = animate ? 1 - Math.pow(1 - Math.min(1, age / 1100), 3) : 1;
    c.save(); c.translate(0, 120 * (1 - rise)); c.globalAlpha = rise;
    const light = (x: number, y: number) => {
      const a = Math.max(0, Math.min(1, 1 - (h-y)/(h*0.56)));
      return Math.pow(a*a*(3-2*a), 1.6) * (1-0.25*Math.pow((x-w/2)/(w/2), 2));
    };
    const g = c.createLinearGradient(0,h*0.44,0,h);
    for (let i=0; i<=12; i++) g.addColorStop(i/12, 'rgba(214,210,206,'+(0.2*light(w/2,h*(0.44+0.56*i/12)))+')');
    c.fillStyle = g; c.fillRect(0,h*0.44,w,h*0.56);
    const t = animate ? (f.time / 1000) % (40*Math.PI) : 0;
    c.fillStyle = 'rgba(214,210,206,0.51)';
    dots(c,w,h,5,1.1,0.9,h*0.44,(x,y) => Math.min(1,light(x,y)*(t ? 1+0.24*Math.sin(x/60+t*0.5)*Math.cos(y/42-t*0.35) : 1)));
    c.restore();
    return animate;
  }
  if (surface === 'gridGlyph') {
    c.scale(w/24,h/24); c.lineWidth = 1.4*24/22; c.strokeStyle = '#fafafa'; c.beginPath();
    for (const x of [3.5,13.5]) for (const y of [3.5,13.5]) c.roundRect(x,y,7,7,2);
    c.stroke(); return false;
  }
  const tile = surface === 'channelTile';
  c.save(); c.beginPath();
  if (tile) c.roundRect(0,0,w,h,9); else c.ellipse(w/2,h/2,w/2,h/2,0,0,tau);
  c.clip(); c.fillStyle = '#000'; c.fillRect(0,0,w,h); c.fillStyle = ink;
  if (tile) {
    const sources = [[0.5,1.25],[-0.15,-0.15],[1.25,0.5],[0.5,-0.25]];
    const [sx,sy] = sources[((Number(args[1])%4)+4)%4];
    dots(c,w,h,3,0.7,0.95,0,(x,y) => 0.1+0.9*Math.max(0,1-Math.hypot(x-sx*w,y-sy*h)/(w*1.15)));
    const initial = (String(args[0]).match(/[\p{L}\p{N}]/u)?.[0] ?? '·').toUpperCase();
    c.font = '19px Georgia'; c.textAlign = 'center'; c.textBaseline = 'middle';
    c.shadowColor = 'rgba(0,0,0,0.9)'; c.shadowBlur = 3; c.fillStyle = '#fafafa'; c.fillText(initial,w/2,h/2); c.shadowBlur = 0;
  } else if (surface === 'profile') {
    dots(c,w,h,2,0.6,0.95,0,(x,y) => {
      const below = 0.7 + 0.3*(1-Math.max(0,Math.min(1,1.15-y/h)));
      const person = Math.hypot(x-w/2,y-h*0.4)<w*0.18 || ((x/w-0.5)/0.36)**2+((y/h-1.02)/0.36)**2<1;
      return person ? 0.7+0.3*below : 0.18*below;
    });
  } else if (surface === 'avatar') {
    const lamps = blooms(String(args[0])), cell = Math.max(1.6,w/18);
    dots(c,w,h,cell,cell*0.25,0.95,0,(x,y) => 0.1+0.9*Math.min(1,lamps.reduce((sum,[a,b,r,s]) =>
      sum+s*Math.max(0,1-Math.hypot(x/w-a,y/h-b)/r)**2,0)));
  }
  c.beginPath(); c.lineWidth = 1;
  c.strokeStyle = surface === 'avatar' && args[1] ? '#8ba7ea' : 'rgba(255,255,255,0.1)';
  if (tile) c.roundRect(0,0,w,h,9); else c.ellipse(w/2,h/2,w/2,h/2,0,0,tau);
  c.stroke(); c.restore(); return false;
}
