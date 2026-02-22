# 🛟 OHB — Open HamClock Backend

When the original backend went dark, the clocks didn’t have to.

Open-source, self-hostable backend replacement for HamClock — restoring live propagation data, maps, and feeds.

Drop-in compatible with existing HamClock clients — no firmware changes required.

OHB provides faithful replacements for the data feeds and map assets
that HamClock depends on — built by operators, for operators.

> This project is not affiliated with HamClock or its creator,
> Elwood Downey, WB0OEW.
> We extend our sincere condolences to the Downey family.

## ✨ What OHB Does

- Rebuilds HamClock dynamic text feeds (solar, geomag, DRAP, PSK, RBN, WSPR, Amateur Satellites, DxNews, Contests, etc)
- Generates map overlays (MUF-RT, DRAP, Aurora, Wx-mB, etc.)
- Produces zlib-compressed BMP assets in multiple resolutions
- Designed for Raspberry Pi, cloud, or on-prem deployment
- Fully open source and community maintained

## 🧭 Architecture
```
[ NOAA / KC2G / PSK / SWPC ]
              |
              v
        +-------------+
        |     OHB     |
        |-------------|
        | Python/Perl|
        | GMT/Maps   |
        | Cron Jobs  |
        +-------------+
              |
           HTTP/ZLIB
              |
         +----------+
         | lighttpd |
         +----------+
              |
         +----------+
         | HamClock |
         +----------+
```

## 💬 Join us on Discord
We are building a community-powered backend to keep HamClock running. \
Discord is where we can collaborate, troubleshoot, and exchange ideas — no RF license required 😎 \
https://discord.gg/wb8ATjVn6M

# OHB in Production (Live HamClock Clients)

<img width="798" height="568" alt="image" src="https://github.com/user-attachments/assets/14b24350-c0a5-4b00-a36f-9c34c74fef3d" />
<img width="799" height="568" alt="image" src="https://github.com/user-attachments/assets/f10d67f5-186c-43b6-b9d9-71149fd897f7" />
<img width="795" height="569" alt="image" src="https://github.com/user-attachments/assets/476bb210-fe1d-4caf-9243-5ada8fffc608" />
<img width="797" height="569" alt="image" src="https://github.com/user-attachments/assets/35e843bf-f2c6-4b99-881b-1bf675660b7a" />
<img width="797" height="571" alt="image" src="https://github.com/user-attachments/assets/859d158c-e441-4788-bd67-3aaa48be45e0" />
<img width="797" height="476" alt="image" src="https://github.com/user-attachments/assets/b8644372-0d6c-4c81-9eeb-ee5d763b490d" />

## 🚀 Quick Start 👉 [Quick Start Guide](QUICK_START.md)
## 📦 Installation 👉 [Detailed installation instructions](INSTALL.md)
## 📊 Project Completion Status

OHB targets ~40+ HamClock artifacts (feeds, maps, and endpoints).

As of today:

- All core dynamic maps implemented
- All text feeds replicated
- Amateur satellites with fresh TLEs
- RSS feed works for thousands for clients
- Integration-tested on live HamClock clients
- Remaining work focused on VOACAP + RBN endpoints  

👉 Full artifact tracking and integration status:
[PROJECT_STATUS.md](PROJECT_STATUS.md) 
## 📚 Data Attribution 👉 [Attribution](ATTRIBUTION.md)
## 🤝 Contributing
