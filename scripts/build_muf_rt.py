#!/usr/bin/env python3
import argparse
import datetime as dt
import json
import math
import os
import struct
import sys
import time
import zlib
from io import BytesIO
from urllib.request import Request, urlopen

import numpy as np
from PIL import Image, ImageDraw, ImageFont

KC2G_URL = "https://prop.kc2g.com/api/stations.json"
EARTH_RADIUS_KM = 6371.0


def http_get(url, timeout=20):
    req = Request(url, headers={"User-Agent": "OHB"})
    with urlopen(req, timeout=timeout) as r:
        return r.read()


def parse_time(ts):
    if isinstance(ts, (int, float)):
        return float(ts)
    try:
        return dt.datetime.fromisoformat(ts.replace("Z", "")).timestamp()
    except Exception:
        return 0.0


def haversine_rad(lon1, lat1, lon2, lat2):
    dlon = (lon2 - lon1 + np.pi) % (2*np.pi) - np.pi
    dlat = lat2 - lat1
    a = np.sin(dlat/2)**2 + np.cos(lat1)*np.cos(lat2)*np.sin(dlon/2)**2
    return 2*np.arcsin(np.sqrt(a))


def lonlat_to_xy(lon, lat, w, h):
    x = int((lon+180)/360*(w-1))
    y = int((90-lat)/180*(h-1))
    return max(0,min(w-1,x)), max(0,min(h-1,y))


def colormap(mhz):
    stops = [
        (5,0,0,180),(10,0,180,255),(15,0,255,0),
        (20,255,255,0),(25,255,165,0),(30,255,60,0),(35,255,0,0)
    ]
    xs = np.array([s[0] for s in stops])
    rs = np.array([s[1] for s in stops])
    gs = np.array([s[2] for s in stops])
    bs = np.array([s[3] for s in stops])
    flat = mhz.ravel()
    r = np.interp(flat,xs,rs)
    g = np.interp(flat,xs,gs)
    b = np.interp(flat,xs,bs)
    return np.stack([r,g,b],axis=1).astype(np.uint8).reshape((*mhz.shape,3))


def solar_mu0(lat, lon, t):
    jd = t/86400.0 + 2440587.5
    n = jd-2451545.0
    L = np.deg2rad((280.46 + 0.9856474*n)%360)
    g = np.deg2rad((357.528 + 0.9856003*n)%360)
    lam = L + np.deg2rad(1.915*np.sin(g)+0.020*np.sin(2*g))
    eps = np.deg2rad(23.439)
    delta = np.arcsin(np.sin(eps)*np.sin(lam))
    gmst = (280.46061837 + 360.98564736629*n)%360
    H = np.deg2rad((lon+gmst+540)%360-180)
    phi = np.deg2rad(lat)
    mu0 = np.sin(phi)*np.sin(delta)+np.cos(phi)*np.cos(delta)*np.cos(H)
    return np.clip(mu0,0,1)


def load_base(p):
    if p.endswith(".bmp.z"):
        return Image.open(BytesIO(zlib.decompress(open(p,"rb").read()))).convert("RGB")
    return Image.open(p).convert("RGB")


def write_bmp(img,out):
    w,h = img.size
    rgb = img.convert("RGB").tobytes()
    rows = bytearray()
    for y in range(h):
        for x in range(w):
            i=(y*w+x)*3
            r,g,b = rgb[i:i+3]
            v=((r>>3)<<11)|((g>>2)<<5)|(b>>3)
            rows+=struct.pack("<H",v)
    hdr = struct.pack("<2sIHHI",b"BM",14+108+len(rows),0,0,122)
    v4 = struct.pack("<IiiHHIIiiIIIIII36sIII",108,w,-h,1,16,3,len(rows),0,0,0,0,
        0xF800,0x07E0,0x001F,0,0x73524742,b"\0"*36,0,0,0)
    bmp = hdr+v4+rows
    open(out+".tmp","wb").write(bmp)
    open(out+".z.tmp","wb").write(zlib.compress(bmp,9))
    os.replace(out+".tmp",out)
    os.replace(out+".z.tmp",out+".z")


def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("--width",type=int,required=True)
    ap.add_argument("--height",type=int,required=True)
    ap.add_argument("--grid-w",type=int,default=720)
    ap.add_argument("--grid-h",type=int,default=360)
    ap.add_argument("--base-day")
    ap.add_argument("--outdir",required=True)
    ap.add_argument("--alpha",type=float,default=0.38)
    ap.add_argument("--k",type=int,default=16)
    ap.add_argument("--p",type=float,default=2.8)
    ap.add_argument("--influence-km",type=float,default=4000)
    ap.add_argument("--use-sza",action="store_true")
    args=ap.parse_args()

    raw=json.loads(http_get(KC2G_URL))
    now=time.time()

    pts=[]
    for r in raw:
        st=r.get("station",{})
        try:
            lon=float(st["longitude"])
            lat=float(st["latitude"])
            muf=float(r["mufd"])
        except:
            continue
        if now-parse_time(r.get("time"))>3600: continue
        conf=float(r.get("confidence",1))
        if conf>1: conf/=100
        pts.append((lon,lat,muf,conf))

    lons=np.array([p[0] for p in pts])
    lats=np.array([p[1] for p in pts])
    vals=np.log(np.clip(np.array([p[2] for p in pts]),5,35))
    confs=np.array([p[3] for p in pts])

    lonsr=np.deg2rad(lons); latsr=np.deg2rad(lats)

    xs=np.linspace(-180,180,args.grid_w)
    ys=np.linspace(90,-90,args.grid_h)
    glon,glat=np.meshgrid(xs,ys)
    glonr=np.deg2rad(glon); glatr=np.deg2rad(glat)

    out=np.zeros((args.grid_h,args.grid_w),np.float32)
    maxrad=args.influence_km/EARTH_RADIUS_KM

    for y in range(0,args.grid_h,32):
        d=haversine_rad(glonr[y:y+32,:,None],glatr[y:y+32,:,None],lonsr,None*lonsr+latsr)
        idx=np.argpartition(d,args.k-1,axis=2)[:,:,:args.k]
        dk=np.take_along_axis(d,idx,axis=2)
        w=1/(dk+1e-6)**args.p
        w*=confs[idx]
        w=np.where(dk<=maxrad,w,0)

        latfac=(np.cos(np.deg2rad(np.abs(glat[y:y+32,:])))**1.5)[...,None]
        w*=latfac

        if args.use_sza:
            mu0=solar_mu0(glat[y:y+32,:],glon[y:y+32,:],now)
            w*=(mu0**0.7)[...,None]

        v=vals[idx]
        out[y:y+32]=np.exp(np.sum(w*v,axis=2)/(np.sum(w,axis=2)+1e-9))

    out=np.clip(out,5,35)
    img=Image.fromarray(out,"F").resize((args.width,args.height),Image.BILINEAR)
    rgb=colormap(np.array(img))
    alpha=int(args.alpha*255)
    overlay=Image.fromarray(np.dstack([rgb,np.full(rgb.shape[:2],alpha,np.uint8)]),"RGBA")

    base=load_base(args.base_day).resize((args.width,args.height))
    comp=Image.alpha_composite(base.convert("RGBA"),overlay).convert("RGB")

    os.makedirs(args.outdir,exist_ok=True)
    write_bmp(comp,f"{args.outdir}/map-D-{args.width}x{args.height}-MUF-RT.bmp")


if __name__=="__main__":
    main()

