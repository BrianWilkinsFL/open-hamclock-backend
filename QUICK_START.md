## 🚀 Quick Start

### Install natively on your OS
Clone and run the installer:

```bash
git clone https://github.com/BrianWilkinsFL/open-hamclock-backend.git
cd open-hamclock-backend
sudo bash install_ohb.sh --size <desired size list>
```
Verify Core Feeds:

```
curl http://localhost/ham/HamClock/solarflux/solarflux-history.txt | tail
curl http://localhost/ham/HamClock/geomag/kindex.txt | tail
```

Verify Maps Exist:
```
sudo ls /opt/hamclock-backend/htdocs/ham/HamClock/maps | head
```

If you see data and maps, OHB is running.

### Install in a container with Docker
Download the manager utility that masks all the Docker details. Visit ```https://github.com/BrianWilkinsFL/open-hamclock-backend/releases``` and download the asset ```Manage Docker installs```.

Make it executable:
```
chmod +x manage-ohb-docker.sh
```

Run it. Substitute the version you want. This installs v0.16:
```
.\manage-ohb-docker.sh install -t 0.16
```

### Full instructions
Full installation details:
👉 [Detailed Installation Instructions](INSTALL.md)
