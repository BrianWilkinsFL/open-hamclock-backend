# This file was reused (with permission) from https://github.com/ciphernaut/ESPHamClock
# with slight modification to accept query params and convert into Python dict

import os
import time
import datetime
import logging
import sys
try:
    from ingestion import voacap_service
except ImportError:
    import voacap_service

logger = logging.getLogger(__name__)

def get_band_conditions(query):
    """
    Generate band conditions text in HamClock format.
    """
    tx_lat = float(query.get('TXLAT', [0])[0])
    tx_lng = float(query.get('TXLNG', [0])[0])
    rx_lat = float(query.get('RXLAT', [0])[0])
    rx_lng = float(query.get('RXLNG', [0])[0])
    
    # Map Numerical Mode to Names
    # 38 -> SSB, 19 -> FT8 (based on parity analysis)
    raw_mode = query.get('MODE', ['CW'])[0]
    mode_map = {
        '38': 'SSB',
        '22': 'RTTY',
        '49': 'AM',
        '13': 'FT8',
        '19': 'CW',
        '17': 'FT4',
        '3': 'WSPR'
    }
    mode_name = mode_map.get(raw_mode, raw_mode)
    
    # Map Power
    power = query.get('POW', query.get('POWER', ['100']))[0]
    power_str = f"{power}W"
    
    # Map Path (0 -> SP, 1 -> LP)
    raw_path = query.get('PATH', ['0'])[0]
    path_str = "LP" if raw_path == '1' else "SP"
    
    # TOA Header Formatting
    raw_toa = query.get('TOA', ['3'])[0]
    try:
        toa_val = float(raw_toa)
        # Format as integer if possible (3.0 -> 3)
        toa_hdr = str(int(toa_val)) if toa_val == int(toa_val) else f"{toa_val:.1f}"
    except:
        toa_hdr = raw_toa

    current_utc = int(query.get('UTC', [time.gmtime().tm_hour])[0])
    ssn = voacap_service.get_ssn()
    
    bands = [3.5, 5.3, 7.0, 10.1, 14.0, 18.1, 21.0, 24.9, 28.0]
    
    lines = []
    
    # Helper to get reliability for all bands at a specific UTC
    def get_rels_for_utc(utc_val):
        rels = []
        for mhz in bands:
            rel = calculate_point_reliability(
                tx_lat, tx_lng, rx_lat, rx_lng, mhz, float(raw_toa), utc_val, ssn, 
                path=int(raw_path), mode=mode_name, power=power
            )
            rels.append(f"{rel:.2f}")
        return ",".join(rels)

    # Line 1: Current condition
    lines.append(get_rels_for_utc(current_utc))
    
    # Line 2: Parameters - Match exactly: 50W,SSB,TOA>3,LP,S=97
    lines.append(f"{power_str},{mode_name},TOA>{toa_hdr},{path_str},S={int(ssn)}")
    
    # Lines 3-26: Hourly forecast (1 to 23, then 0)
    for h in range(1, 24):
        lines.append(f"{h} {get_rels_for_utc(h)}")
    lines.append(f"0 {get_rels_for_utc(0)}")
    
    return "\n".join(lines) + "\n"

def calculate_point_reliability(tlat, tlng, rlat, rlng, mhz, toa, utc, ssn, path=0, mode="SSB", power=100):
    """
    Use the refined VOACAP-based model for consistency.
    """
    now = datetime.datetime.now()
    year = now.year
    month = now.month
    
    # voacap_service.calculate_point_propagation returns (muf, rel)
    _, rel = voacap_service.calculate_point_propagation(
        tlat, tlng, rlat, rlng, mhz, toa, year, month, float(utc), ssn, 
        path=path, mode=mode, power=power
    )
    return rel

def _argv_to_querydict(argv):
    """
    Convert argv like: ['--TXLAT','45','--TXLNG','-75', ...]
    into: {'TXLAT': ['45'], 'TXLNG': ['-75'], ...}
    """
    if len(argv) % 2 != 0:
        raise ValueError("Expected even number of args: --KEY VALUE ...")

    q = {}
    i = 0
    while i < len(argv):
        k = argv[i]
        if not k.startswith("--"):
            raise ValueError(f"Bad arg {k!r}; expected --KEY")
        key = k[2:]
        val = argv[i + 1]
        # parse_qs-style: list of strings
        q.setdefault(key, []).append(val)
        i += 2

    return q

def cli_main():
    # Build query dict in the exact shape you requested
    query = _argv_to_querydict(sys.argv[1:])

    # Call your existing function
    result = get_band_conditions(query)

    # Output ONLY the payload for CGI consumption
    sys.stdout.write(result)

if __name__ == "__main__":
    try:
        cli_main()
    except Exception as e:
        # Keep stdout clean; error text goes to stdout only because CGI will return it.
        # If you prefer stderr logging, print to stderr and have Perl return a generic message.
        sys.stdout.write(f"Error: {e}\n")
        raise SystemExit(1)
