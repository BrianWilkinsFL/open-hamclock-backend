# Time Synchronization

Open HamClock Backend (OHB) and all HamClock clients must maintain accurate and synchronized system time.

OHB generates time-series data (aurora, solar wind, DRAP, SSN, etc.) using Unix epoch timestamps. HamClock clients compute data age using:

```age = now_client - epoch_from_backend```

If the client clock is incorrect or significantly out of sync with the backend, HamClock will discard valid data and log errors such as:

AURORA: skipping age -491926 hrs
AURORA: only 0 points

Negative ages indicate the client believes the data is from the future.

# Required Conditions

* Backend system clock must be accurate
* HamClock client clock must be accurate
* Clock skew between backend and clients should be less than a few seconds

Even multi-minute skew can distort plotted slopes
Large skew (hours/days/years) will cause complete data rejection

## Enabling Time Sync (Linux / Raspberry Pi)

Verify status:

```timedatectl```

Enable NTP synchronization:

```sudo timedatectl set-ntp true```
```sudo systemctl restart systemd-timesyncd```

If systemd-timesyncd is not available:

```sudo apt install ntp```
```sudo systemctl enable ntp```
```sudo systemctl start ntp```

Confirm synchronization:

```timedatectl```

You should see:

```System clock synchronized: yes```

## Why This Matters

* OHB uses deterministic epoch flooring
* HamClock assumes evenly spaced historical bins

OHB does not compensate for client clock drift by design

