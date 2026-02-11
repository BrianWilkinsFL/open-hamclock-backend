# This file was reused (with permission) from https://github.com/ciphernaut/ESPHamClock

import requests
import math
import time
import logging
from datetime import datetime, timezone

logger = logging.getLogger(__name__)

# KC2G Ionosonde API
PROPY_API_URL = "https://prop.kc2g.com/api/stations.json"
CACHE_TTL = 600  # 10 minutes
MAX_VALID_DISTANCE_KM = 3000

# In-memory cache
_ionosonde_cache = {
    "data": [],
    "timestamp": 0
}

def fetch_ionosonde_data():
    """
    Fetch real-time ionosonde data from KC2G (GIRO network).
    Returns a list of station dicts with lat, lon, foF2, mufd, etc.
    """
    global _ionosonde_cache
    now = time.time()

    # Return cached data if fresh
    if _ionosonde_cache["data"] and (now - _ionosonde_cache["timestamp"]) < CACHE_TTL:
        return _ionosonde_cache["data"]

    try:
        logger.info(f"Fetching ionosonde data from {PROPY_API_URL}...")
        resp = requests.get(PROPY_API_URL, timeout=10)
        resp.raise_for_status()
        data = resp.json()

        valid_stations = []
        # Filter to recent and valid stations
        # KC2G data format: list of objects with "station" info and measurements
        for s in data:
            if not s.get('fof2') or not s.get('station'):
                continue
            
            # Basic validation of confidence score if available
            cs = s.get('cs', 0)
            if cs <= 0: continue

            # Time check (last 2 hours)
            try:
                s_time_str = s.get('time', '').replace('Z', '+00:00')
                s_dt = datetime.fromisoformat(s_time_str)
                s_ts = s_dt.timestamp()
                # Allow data up to 24 hours "old" or "future" to handle sim time divergence
                if abs(now - s_ts) > 86400: 
                    # logger.debug(f"Discarding station {s.get('station')} due to time diff: {now - s_ts}")
                    continue
            except:
                continue

            # Normalize longitude to -180..180
            lon = float(s['station']['longitude'])
            if lon > 180: lon -= 360

            station_record = {
                'code': s['station']['code'],
                'name': s['station']['name'],
                'lat': float(s['station']['latitude']),
                'lon': lon,
                'foF2': float(s['fof2']),
                'mufd': float(s['mufd']) if s.get('mufd') else None, # MUF(3000)
                'hmF2': float(s['hmf2']) if s.get('hmf2') else None,
                'md': float(s['md']) if s.get('md') else 3.0, # M(3000)F2 factor
                'confidence': cs,
                'time': s_ts
            }
            valid_stations.append(station_record)

        _ionosonde_cache = {
            "data": valid_stations,
            "timestamp": now
        }
        logger.info(f"Fetched {len(valid_stations)} valid ionosonde stations.")
        return valid_stations

    except Exception as e:
        logger.error(f"Error fetching ionosonde data: {e}")
        # Update timestamp to prevent immediate retry on error
        _ionosonde_cache["timestamp"] = now
        return _ionosonde_cache["data"] # Return stale cache if fetch fails

def haversine_distance(lat1, lon1, lat2, lon2):
    """Calculate distance between two points in km."""
    R = 6371.0
    dlat = math.radians(lat2 - lat1)
    dlon = math.radians(lon2 - lon1)
    a = math.sin(dlat / 2)**2 + math.cos(math.radians(lat1)) * math.cos(math.radians(lat2)) * math.sin(dlon / 2)**2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
    return R * c

def interpolate_fof2(lat, lon, stations=None):
    """
    Interpolate foF2 and other params at a given lat/lon using Inverse Distance Weighting (IDW).
    Returns dict with foF2, mufd, etc., or None if no coverage.
    """
    if stations is None:
        stations = fetch_ionosonde_data()
    
    if not stations:
        return None

    # Calculate distances
    stations_with_dist = []
    for s in stations:
        dist = haversine_distance(lat, lon, s['lat'], s['lon'])
        stations_with_dist.append({**s, 'dist': dist})

    # Sort by distance
    stations_with_dist.sort(key=lambda x: x['dist'])

    # Check nearest station
    nearest = stations_with_dist[0]
    if nearest['dist'] > MAX_VALID_DISTANCE_KM:
        return {
            'method': 'no-coverage',
            'nearestStation': nearest['name'],
            'nearestDistance': nearest['dist'],
            'reason': 'Too far from any ionosonde'
        }

    # IDW with nearest 5 stations
    neighbors = [s for s in stations_with_dist if s['dist'] <= MAX_VALID_DISTANCE_KM][:5]
    
    # Check for exact match (very close)
    if neighbors[0]['dist'] < 50:
        s = neighbors[0]
        return {
            'method': 'direct',
            'foF2': s['foF2'],
            'mufd': s['mufd'],
            'hmF2': s['hmF2'],
            'md': s['md'],
            'nearestStation': s['name'],
            'nearestDistance': s['dist']
        }

    # IDW Calculation
    sum_weights = 0.0
    sum_foF2 = 0.0
    sum_mufd = 0.0
    sum_hmF2 = 0.0
    sum_md = 0.0
    
    count_mufd = 0
    count_hmF2 = 0
    count_md = 0

    for s in neighbors:
        # Weight = (Confidence / 100) / Distance^2
        # Use simple 1/d^2 if confidence missing, but we filtered for CS > 0
        weight = (s['confidence'] / 100.0) / (max(1.0, s['dist']) ** 2)
        
        sum_weights += weight
        sum_foF2 += s['foF2'] * weight
        
        if s['mufd']:
            sum_mufd += s['mufd'] * weight
            count_mufd += 1
        
        if s['hmF2']:
            sum_hmF2 += s['hmF2'] * weight
            count_hmF2 += 1
            
        if s['md']:
            sum_md += s['md'] * weight
            count_md += 1

    if sum_weights == 0:
        return None

    result = {
        'method': 'interpolated',
        'stationsUsed': len(neighbors),
        'nearestStation': nearest['name'],
        'nearestDistance': nearest['dist'],
        'foF2': sum_foF2 / sum_weights,
        'mufd': (sum_mufd / sum_weights) * (len(neighbors) / count_mufd) if count_mufd > 0 and count_mufd == len(neighbors) else None, # Only simple avg if all have it? No.
        # Correct weighting for partials is tricky in single loop. 
        # For simplicity in this port: only interpolate values present.
        # Actually... let's keep it simple. If 3/5 have MUFd, the sum is weighted partial. 
        # We need sum_weights per parameter to be perfectly accurate.
        # But foF2 is the critical one and it's guaranteed.
        # For MUFd/hmF2 let's just take the nearest if not all have it, or simple logic.
        # OpenHamClock does: if (s.mufd) sumMufd += ...
        # But it reuses sumWeights which assumes all stations contribute.
        # Let's trust foF2 is the main goal.
    }
    
    # Re-calculate specific weights for optional params if strictness needed?
    # OpenHamClock JS implementation actually does reuse sumWeights even if missing! 
    # That might be a bug in source, but we are porting it.
    # Wait, looking at source: "if (s.mufd) sumMufd += s.mufd * weight;"
    # If a station is missing MUFd, it adds 0 to sum, but adds full weight to divisor.
    # This dilutes the result. We should probably FIX this for the Python port.
    
    # Better implementation for valid port + fix:
    def weighted_avg(key):
        w_sum = 0
        v_sum = 0
        for s in neighbors:
            if s.get(key):
                w = (s['confidence']/100.0) / (max(1.0, s['dist'])**2)
                v_sum += s[key] * w
                w_sum += w
        return v_sum / w_sum if w_sum > 0 else None

    result['foF2'] = weighted_avg('foF2')
    result['mufd'] = weighted_avg('mufd')
    result['hmF2'] = weighted_avg('hmF2')
    result['md'] = weighted_avg('md') or 3.0

    return result

if __name__ == "__main__":
    # Test
    logging.basicConfig(level=logging.INFO)
    data = fetch_ionosonde_data()
    if data:
        # Interpolate for London
        interp = interpolate_fof2(51.5074, -0.1278, data)
        print(f"London: {interp}")
        # Interpolate for New York
        interp = interpolate_fof2(40.7128, -74.0060, data)
        print(f"NYC: {interp}")
