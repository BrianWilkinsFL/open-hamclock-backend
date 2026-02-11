# This file was reused (with permission) from https://github.com/ciphernaut/ESPHamClock
# with slight modification to support OHB file paths

import os
import math
import time
import struct
import zlib
import logging
import datetime
# numpy imported locally where needed to avoid import hangs

try:
    from ingestion import ionosonde_service
except ImportError:
    try:
        import ionosonde_service
    except ImportError:
        pass

logger = logging.getLogger(__name__)

MAP_W = 660
MAP_H = 330

# Caches initialized locally
MUF_CACHE = None
REL_CACHE = None
TOA_CACHE = None

# Simple result cache
VOACAP_MAP_CACHE = {}
MAX_CACHE_SIZE = 100

# Global Base Maps (loaded on start)
COUNTRIES_MAP = None
TERRAIN_MAP = None
COUNTRIES_MASK = None

# Precompute grids for vectorization
RX_LAT_RADS_GRID = None
RX_LNG_RADS_GRID = None
SIN_RX_LATS_GRID = None
COS_RX_LATS_GRID = None

def load_base_maps():
    import numpy as np
    global COUNTRIES_MAP, TERRAIN_MAP, COUNTRIES_MASK
    
    if COUNTRIES_MAP is not None: return

    try:
        base_dir = os.path.dirname(os.path.dirname(__file__))
        data_dir = os.path.join(base_dir, "data")
        processed_data = os.path.join(data_dir, "processed_data")
        
        c_path = os.path.join(processed_data, "map-D-660x330-Countries.bmp")
        t_path = os.path.join(processed_data, "map-D-660x330-Terrain.bmp")
        mask_path = os.path.join(data_dir, "countries_mask.bin")
        
        if os.path.exists(c_path):
            with open(c_path, "rb") as f:
                f.seek(122)
                COUNTRIES_MAP = np.frombuffer(f.read(MAP_W*MAP_H*2), dtype='<u2').reshape(MAP_H, MAP_W)
        
        if os.path.exists(t_path):
            with open(t_path, "rb") as f:
                f.seek(122)
                TERRAIN_MAP = np.frombuffer(f.read(MAP_W*MAP_H*2), dtype='<u2').reshape(MAP_H, MAP_W)
                
        if os.path.exists(mask_path):
            with open(mask_path, "rb") as f:
                COUNTRIES_MASK = np.frombuffer(f.read(), dtype=np.uint16).reshape(MAP_H, MAP_W)
        else:
            logger.warning(f"Countries mask not found at {mask_path}")
            
    except Exception as e:
        logger.error(f"Error loading base maps: {e}")

def blend_rgb565_vectorized(fg, bg, alpha):
    import numpy as np
    """Vectorized blend of RGB565 arrays."""
    # Expand FG
    r1 = (fg >> 11) & 0x1F
    g1 = (fg >> 5) & 0x3F
    b1 = fg & 0x1F
    
    # Expand BG
    r2 = (bg >> 11) & 0x1F
    bg_raw_g = (bg >> 5) & 0x3F
    b2 = bg & 0x1F
    
    inv_alpha = 1.0 - alpha
    r = (r1 * alpha + r2 * inv_alpha).astype(np.uint16)
    g = (g1 * alpha + bg_raw_g * inv_alpha).astype(np.uint16)
    b = (b1 * alpha + b2 * inv_alpha).astype(np.uint16)
    
    np.clip(r, 0, 31, out=r)
    np.clip(g, 0, 63, out=g)
    np.clip(b, 0, 31, out=b)
    
    return (r << 11) | (g << 5) | b

def interpolate_color_value(val, scale):
    if val <= scale[0][0]: c = scale[0][1]
    elif val >= scale[-1][0]: c = scale[-1][1]
    else:
        for i in range(len(scale) - 1):
            v1, c1 = scale[i]
            v2, c2 = scale[i+1]
            if v1 <= val <= v2:
                f = (val - v1) / (v2 - v1)
                r1, g1, b1 = (c1 >> 16) & 0xFF, (c1 >> 8) & 0xFF, c1 & 0xFF
                r2, g2, b2 = (c2 >> 16) & 0xFF, (c2 >> 8) & 0xFF, c2 & 0xFF
                r, g, b = int(r1+(r2-r1)*f), int(g1+(g2-g1)*f), int(b1+(b2-b1)*f)
                return ((r & 0xF8) << 8) | ((g & 0xFC) << 3) | (b >> 3)
    r, g, b = (c >> 16) & 0xFF, (c >> 8) & 0xFF, c & 0xFF
    return ((r & 0xF8) << 8) | ((g & 0xFC) << 3) | (b >> 3)

def precompute_scales():
    import numpy as np
    global RX_LAT_RADS_GRID, RX_LNG_RADS_GRID, SIN_RX_LATS_GRID, COS_RX_LATS_GRID, MUF_CACHE, REL_CACHE, TOA_CACHE
    
    if MUF_CACHE is not None: return

    MUF_CACHE = np.zeros(501, dtype=np.uint16)
    REL_CACHE = np.zeros(1001, dtype=np.uint16)
    TOA_CACHE = np.zeros(401, dtype=np.uint16)
    
    m_scale = [(0, 0), (4, 0x4E138A), (9, 0x001EF5), (15, 0x78FBD6), (20, 0x78FA4D), (27, 0xFEFD54), (30, 0xEC6F2D), (35, 0xE93323)]
    r_scale = [(0, 0x666666), (21, 0xEE6766), (40, 0xEEEE44), (60, 0xEEEE44), (83, 0x44CC44), (100, 0x44CC44)]
    t_scale = [(0, 0x44CC44), (5, 0x44CC44), (15, 0xEEEE44), (25, 0xEE6766), (40, 0x666666)]
    
    for i in range(501): MUF_CACHE[i] = interpolate_color_value(i / 10.0, m_scale)
    for i in range(1001): REL_CACHE[i] = interpolate_color_value(i / 10.0, r_scale)
    for i in range(401): TOA_CACHE[i] = interpolate_color_value(i / 10.0, t_scale)

    # Precompute Lat/Lng Grids
    lat_vals = np.array([90.0 - (y * 180.0 / MAP_H) for y in range(MAP_H)])
    lng_vals = np.array([-180.0 + (x * 360.0 / MAP_W) for x in range(MAP_W)])
    
    rx_lat_rads = np.radians(lat_vals)
    rx_lng_rads = np.radians(lng_vals)
    
    RX_LNG_RADS_GRID, RX_LAT_RADS_GRID = np.meshgrid(rx_lng_rads, rx_lat_rads)
    SIN_RX_LATS_GRID = np.sin(RX_LAT_RADS_GRID)
    COS_RX_LATS_GRID = np.cos(RX_LAT_RADS_GRID)

def create_bmp_565_header(w, h):
    core_size = 14
    dib_size = 108
    hdr_len = core_size + dib_size
    row_bytes = (w * 2)
    pix_bytes = row_bytes * h
    file_bytes = hdr_len + pix_bytes
    header = bytearray(b'BM')
    header += struct.pack('<LHH L', file_bytes, 0, 0, hdr_len)
    header += struct.pack('<LllHHLLllLLLLLLLLLLLLLLLLLLL',
        dib_size, w, -h, 1, 16, 3, pix_bytes, 3780, 3780, 0, 0,
        0xF800, 0x07E0, 0x001F, 0x0000, 1,
        0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0
    )
    return header

def get_ssn():
    try:
        base_data = "/opt/hamclock-backend/htdocs/ham/HamClock"
        ssn_path = os.path.join(base_data, "ssn", "ssn-31.txt")
        if os.path.exists(ssn_path):
            with open(ssn_path, "r") as f:
                lines = [l.strip() for l in f.readlines() if l.strip()]
                if lines:
                    last_line = lines[-1]
                    parts = last_line.split()
                    if len(parts) >= 4:
                        return float(parts[3])
    except: pass
    return 70.0

def get_current_space_wx():
    """Read current space weather from processed data files"""
    swx = {
        'kp': 3.0,
        'sw_speed': 400.0,
        'bz': 0.0,
        'ssn': 100.0  # fallback
    }
    
    try:
        base_data = "/opt/hamclock-backend/htdocs/ham/HamClock"
        
        # 1. SSN
        ssn_val = get_ssn()
        swx['ssn'] = ssn_val

        # 2. Kp Index
        kp_path = os.path.join(base_data, "geomag", "kindex.txt")
        if os.path.exists(kp_path):
             with open(kp_path, "r") as f:
                lines = [l.strip() for l in f.readlines() if l.strip()]
                if lines:
                    idx = 55 if len(lines) > 55 else -1
                    swx['kp'] = float(lines[idx])

        # 3. Solar Wind Speed
        sw_path = os.path.join(base_data, "solar-wind", "swind-24hr.txt")
        if os.path.exists(sw_path):
            with open(sw_path, "r") as f:
                lines = [l.strip() for l in f.readlines() if l.strip()]
                if lines:
                    parts = lines[-1].split()
                    if len(parts) >= 3:
                        swx['sw_speed'] = float(parts[2])

        # 4. Bz
        bz_path = os.path.join(base_data, "Bz", "Bz.txt")
        if os.path.exists(bz_path):
            with open(bz_path, "r") as f:
                lines = [l.strip() for l in f.readlines() if l.strip() and not l.startswith("#")]
                if lines:
                    parts = lines[-1].split()
                    if len(parts) >= 4:
                        swx['bz'] = float(parts[3])

    except Exception as e:
        logger.error(f"Error reading space weather: {e}")

    return swx

def get_solar_pos(year, month, day, utc):
    days_in_month = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    doy = sum(days_in_month[:month-1]) + day
    dec = 23.44 * math.sin(math.radians(360.0/365.25 * (doy - 81)))
    sub_lng = (12.0 - utc) * 15.0
    return math.radians(dec), math.radians(sub_lng)

# ==================================================================================
# NEW PHYSICS PORT (Plan B)
# ==================================================================================

# Mode advantage in dB (relative to SSB)
MODE_ADVANTAGE_DB = {
    'CW': 16,    # Very efficient
    'FT8': 12, # Weak signal
    'FT4': 10,
    'JT65': 15,
    'WSPR': 25,  # Extremely efficient
    'SSB': 0,    # Baseline
    'AM': -6,    # Inefficient
    'FM': -3,
    'RTTY': 5,
    'PSK31': 14
}

def calculate_signal_margin(mode, power_watts):
    """
    Calculate signal margin in dB based on mode and power.
    Baseline is 100W SSB = 0 dB.
    """
    mode_adv = MODE_ADVANTAGE_DB.get(mode, 0)
    power = max(0.01, float(power_watts))
    power_offset = 10 * math.log10(power / 100.0) # dB relative to 100W
    return mode_adv + power_offset

def calculate_muf(dist_km, mid_lat, mid_lon, hour, sfi, ssn, iono_data):
    """
    Calculate MUF using real ionosonde data if available, or solar model fallback.
    Ported from OpenHamClock/server.js
    """
    muf3000 = None
    
    if iono_data and iono_data.get('mufd'):
         muf3000 = float(iono_data['mufd'])
         
    elif iono_data and iono_data.get('foF2'):
        M = iono_data.get('md', 3.0)
        muf3000 = float(iono_data['foF2']) * M

    if muf3000:
        if dist_km < 3000:
             return muf3000 * math.sqrt(dist_km / 3000.0)
        else:
             return muf3000 * (1 + 0.15 * math.log10(dist_km / 3000.0))

    # Solar Model Fallback
    hour_factor = 1.0 + 0.4 * math.cos((hour - 14) * math.pi / 12.0)
    lat_factor = 1.0 - abs(mid_lat) / 150.0
    foF2_est = 0.9 * math.sqrt(ssn + 15) * hour_factor * lat_factor
    
    M = 3.0
    muf3000 = foF2_est * M
    
    if dist_km < 3000:
        return muf3000 * math.sqrt(dist_km / 3000.0)
    else:
        return muf3000 * (1 + 0.15 * math.log10(dist_km / 3000.0))

def calculate_luf(dist_km, mid_lat, hour, sfi, k_index):
    """
    Calculate LUF based on solar indices.
    """
    path_factor = math.sqrt(dist_km / 1000.0)
    solar_factor = math.sqrt(float(sfi))
    
    zenith_angle = abs(hour - 12) * 15 # degrees from noon
    zenith_rad = math.radians(zenith_angle)
    diurnal_factor = max(0.1, math.cos(zenith_rad)) ** 0.5
    
    storm_factor = 1.0 + (float(k_index) * 0.1)
    
    base_luf = 2.0 * path_factor * solar_factor * diurnal_factor * storm_factor / 10.0
    
    if hour < 6 or hour > 18:
        base_luf *= 0.3
        
    return max(1.0, base_luf)

def calculate_enhanced_reliability(freq, dist_km, mid_lat, mid_lon, hour, sfi, ssn, k_index, iono_data, current_hour, signal_margin_db=0):
    """
    Core physics logic ported from OpenHamClock/server.js
    """
    hour_iono_data = iono_data
    if iono_data and hour != current_hour:
        current_hour_factor = 1.0 + 0.4 * math.cos((current_hour - 14) * math.pi / 12.0)
        target_hour_factor = 1.0 + 0.4 * math.cos((hour - 14) * math.pi / 12.0)
        scale_factor = target_hour_factor / current_hour_factor
        
        hour_iono_data = iono_data.copy()
        if 'foF2' in hour_iono_data: hour_iono_data['foF2'] *= scale_factor
        if 'mufd' in hour_iono_data and hour_iono_data['mufd'] is not None: hour_iono_data['mufd'] *= scale_factor
    
    muf = calculate_muf(dist_km, mid_lat, mid_lon, hour, sfi, ssn, hour_iono_data)
    luf = calculate_luf(dist_km, mid_lat, hour, sfi, k_index)
    
    effective_muf = muf * (1 + signal_margin_db * 0.012)
    effective_luf = luf * max(0.1, 1 - signal_margin_db * 0.008)
    
    reliability = 0.0
    
    if freq > effective_muf * 1.1:
        reliability = max(0.0, 30.0 - (freq - effective_muf) * 5.0)
    elif freq > effective_muf:
         reliability = 30.0 + (effective_muf * 1.1 - freq) / (effective_muf * 0.1) * 20.0
    elif freq < effective_luf * 0.8:
         reliability = max(0.0, 20.0 - (effective_luf - freq) * 10.0)
    elif freq < effective_luf:
         reliability = 20.0 + (freq - effective_luf * 0.8) / (effective_luf * 0.2) * 30.0
    else:
         owf = effective_muf * 0.85
         r_range = effective_muf - effective_luf
         
         if r_range <= 0:
             reliability = 30.0
         else:
             position = (freq - effective_luf) / r_range
             optimal_position = 0.75
             
             if position < optimal_position:
                 reliability = 50.0 + (position / optimal_position) * 45.0
             else:
                 reliability = 95.0 - ((position - optimal_position) / (1.0 - optimal_position)) * 45.0

    if k_index >= 7: reliability *= 0.1
    elif k_index >= 6: reliability *= 0.2
    elif k_index >= 5: reliability *= 0.4
    elif k_index >= 4: reliability *= 0.6
    elif k_index >= 3: reliability *= 0.8
    
    hops = math.ceil(dist_km / 3500.0)
    if hops > 1:
        reliability *= pow(0.92, hops - 1)
        
    if abs(mid_lat) > 60:
        reliability *= 0.7
        if k_index >= 3: reliability *= 0.7
    
    if freq >= 21 and sfi < 100: reliability *= math.sqrt(sfi / 100.0)
    if freq >= 28 and sfi < 120: reliability *= math.sqrt(sfi / 120.0)
    if freq >= 50 and sfi < 150: reliability *= pow(sfi / 150.0, 1.5)
    
    local_hour = (hour + mid_lon / 15.0 + 24) % 24
    is_night = local_hour < 6 or local_hour > 18
    if freq <= 7 and is_night: reliability *= 1.1
    if freq <= 3.5 and not is_night: reliability *= 0.7
    
    return min(99.0, max(0.0, reliability))

def calculate_snr(reliability):
    if reliability >= 80: return '+20dB'
    if reliability >= 60: return '+10dB'
    if reliability >= 40: return '0dB'
    if reliability >= 20: return '-10dB'
    return '-20dB'

def calculate_point_propagation(tx_lat, tx_lng, rx_lat, rx_lng, mhz, toa, year, month, utc, ssn, path=0, mode="SSB", power=100):
    swx = get_current_space_wx()
    sfi = 70.0
    k = swx.get('kp', 3.0)
    
    dist_km = ionosonde_service.haversine_distance(tx_lat, tx_lng, rx_lat, rx_lng)
    
    mid_lat = (tx_lat + rx_lat) / 2.0
    mid_lon = (tx_lng + rx_lng) / 2.0
    if abs(tx_lng - rx_lng) > 180:
        mid_lon = (tx_lng + rx_lng + 360) / 2.0
        if mid_lon > 180: mid_lon -= 360
        
    iono_data = ionosonde_service.interpolate_fof2(mid_lat, mid_lon)
    
    current_hour = datetime.datetime.now(datetime.timezone.utc).hour
    
    margin = calculate_signal_margin(mode, power)
    
    rel = calculate_enhanced_reliability(
        mhz, dist_km, mid_lat, mid_lon, utc, 
        sfi=150, 
        ssn=ssn, 
        k_index=k, 
        iono_data=iono_data, 
        current_hour=current_hour,
        signal_margin_db=margin
    )
    
    muf = calculate_muf(dist_km, mid_lat, mid_lon, utc, 150, ssn, iono_data)
    
    return muf, rel / 100.0

def calculate_grid_propagation_vectorized(tx_lat_rad, tx_lng_rad, m_mhz, toa_param, s_dec_rad, s_lng_rad, muf_base, path=0, space_wx=None, signal_margin_db=0.0):
    import numpy as np
    load_base_maps()
    precompute_scales()
    
    if space_wx is None: space_wx = {}
    kp = space_wx.get('kp', 3.0)
    bz = space_wx.get('bz', 0.0)
    sw_speed = space_wx.get('sw_speed', 400.0)

    # ... (rest of function until loop) ...

    margin_factor_muf = 1.0 + signal_margin_db * 0.012
    margin_factor_abs = 1.0 + signal_margin_db * 0.008

    cos_tx_lat = math.cos(tx_lat_rad)
    sin_tx_lat = math.sin(tx_lat_rad)
    cos_s_dec = math.cos(s_dec_rad)
    sin_s_dec = math.sin(s_dec_rad)
    pole_lat = math.radians(80.5)
    pole_lng = math.radians(-72.5)

    rlat_rad = RX_LAT_RADS_GRID
    rlng_rad = RX_LNG_RADS_GRID
    srl = SIN_RX_LATS_GRID
    crl = COS_RX_LATS_GRID

    d_lon = rlng_rad - tx_lng_rad
    cos_d_lon = np.cos(d_lon)
    
    y_dist = np.sin(d_lon) * crl
    x_dist = cos_tx_lat * srl - sin_tx_lat * crl * cos_d_lon
    az_rad = np.arctan2(y_dist, x_dist)
    
    cos_c = sin_tx_lat * srl + cos_tx_lat * crl * cos_d_lon
    cos_c = np.clip(cos_c, -1.0, 1.0)
    dist_km = np.arccos(cos_c) * 6371.0
    
    if path == 1: 
        dist_km = 40075.0 - dist_km
        az_rad = (az_rad + np.pi)
        az_rad = (az_rad + np.pi) % (2 * np.pi) - np.pi

    s_az_tx = math.atan2(math.sin(s_lng_rad - tx_lng_rad) * cos_s_dec,
                       cos_tx_lat * sin_s_dec - sin_tx_lat * cos_s_dec * math.cos(s_lng_rad - tx_lng_rad))
    
    rel_az = np.abs(az_rad - s_az_tx)
    rel_az = (rel_az + np.pi) % (2 * np.pi) - np.pi
    
    gray_tangent_f = 1.0 + 0.45 * np.power(np.cos(np.abs(rel_az) - np.pi/2), 4.0)
    mag_az_f = 1.0 + 0.4 * np.power(np.cos(az_rad), 2.0)
    combo_f = (gray_tangent_f + mag_az_f) / 2.0
    
    v_tx = np.array([cos_tx_lat * math.cos(tx_lng_rad), cos_tx_lat * math.sin(tx_lng_rad), sin_tx_lat])
    
    v_rx_0 = crl * np.cos(rlng_rad)
    v_rx_1 = crl * np.sin(rlng_rad)
    v_rx_2 = srl

    sum_muf = np.zeros_like(dist_km)
    sum_rel = np.zeros_like(dist_km)
    sample_weights = [0.25, 0.5, 0.25]
    
    v_diff_0 = v_rx_0 - v_tx[0]
    v_diff_1 = v_rx_1 - v_tx[1]
    v_diff_2 = v_rx_2 - v_tx[2]
    
    f_trans = 1.0 / (1.0 + pow(m_mhz / 35.0, 2.0))
    dist_km_norm = dist_km / 1000.0

    kp_muf_factor = max(0.5, 1.0 - max(0, kp - 3.0) * 0.05)
    
    for i, frac in enumerate([0.25, 0.5, 0.75]):
        effective_frac = frac
        vm_0 = v_tx[0] + v_diff_0 * effective_frac
        vm_1 = v_tx[1] + v_diff_1 * effective_frac
        vm_2 = v_tx[2] + v_diff_2 * effective_frac
        
        if path == 1:
             vm_0 = -vm_0
             vm_1 = -vm_1
             vm_2 = -vm_2

        mag = np.sqrt(vm_0*vm_0 + vm_1*vm_1 + vm_2*vm_2)
        mag[mag < 0.001] = 1.0 
        
        vn_0 = vm_0 / mag
        vn_1 = vm_1 / mag
        vn_2 = vm_2 / mag
        
        slat = np.arcsin(np.clip(vn_2, -1.0, 1.0))
        slng = np.arctan2(vn_1, vn_0)
        
        sslat = np.sin(slat)
        cslat = np.cos(slat)
        
        cos_z_s = sslat * sin_s_dec + cslat * cos_s_dec * np.cos(slng - s_lng_rad)
        
        s_ang = np.arccos(np.clip(cos_z_s, -1.0, 1.0))
        s_proj = np.arcsin(np.clip((6371.0 / 6721.0) * np.sin(s_ang), -1.0, 1.0))
        cos_z_p = np.cos(s_proj)
        
        zenith_layer = np.power(np.maximum(0, cos_z_p + 0.1), 0.75)
        azimuth_layer = np.power(np.cos(rel_az), 2.0)
        
        s_mag = sslat * math.sin(pole_lat) + cslat * math.cos(pole_lat) * np.cos(slng - pole_lng)
        m_lat_r = np.arcsin(np.clip(s_mag, -1.0, 1.0))
        m_lat_d = np.degrees(m_lat_r)
        
        is_polar = ((s_dec_rad < -0.1) & (slat < -0.8)) | ((s_dec_rad > 0.1) & (slat > 0.8))

        reflection_factor = (0.4 + 0.6 * zenith_layer) * (0.8 + 0.2 * azimuth_layer)
        
        mask_night = cos_z_s <= -0.1
        if np.any(mask_night):
             floor = np.where(is_polar, 0.4 * np.cos(slat - s_dec_rad), 0.25)
             rf_night = floor + (reflection_factor - floor) * np.exp((cos_z_s + 0.1) * 8.0)
             reflection_factor = np.where(mask_night, rf_night, reflection_factor)
        
        ref_f = 1.0 + dist_km_norm * (1.0 - cos_z_p) * 0.045 * combo_f * f_trans * (1.1 - 0.1 * azimuth_layer)
        
        pca_loss = np.exp(-1.2 * np.power(np.sin(m_lat_r), 4.0) * (20.0 / m_mhz)**1.5)
        m_bend = 0.85 + 0.65 * (np.cos(m_lat_r)**2.5) + 1.1 * (np.exp(-((m_lat_d - 15.5)/6.5)**2) + np.exp(-((m_lat_d + 15.5)/6.5)**2))
        
        p_muf = muf_base * reflection_factor * m_bend * kp_muf_factor
        p_muf *= margin_factor_muf # Apply signal margin to MUF
        sum_muf += p_muf * sample_weights[i]
        
        terminator_h = 1.0 / (1.0 + np.exp(-35.0 * (cos_z_s + 0.04)))
        
        safe_p_muf = np.maximum(0.5, p_muf)
        h_len = 3100.0 * (1.0 / (1.0 + toa_param/35.0)) * (0.55 + 0.45 * (m_mhz/safe_p_muf)) * ref_f
        
        res_total = 0.45 + 3.4 * (np.power(np.cos(math.pi * (dist_km / h_len)), 6.0) + 0.55 * np.power(np.cos(math.pi * (dist_km / (h_len * 1.35))), 4.0))
        
        ele_angle = np.arctan(1800.0 / np.maximum(20.0, h_len))
        
        reflection_eff = np.power(np.cos(math.pi/2.0 - ele_angle), 0.3)
        abs_p = np.exp(-5.0 * terminator_h * zenith_layer * (10.0 / m_mhz)**2.2)
        abs_p *= margin_factor_abs # Apply signal margin to Absorption (Survival)

        path_loss_factor = 1.0 / (1.0 + 0.000065 * dist_km * (1.0 / np.maximum(0.2, combo_f)))
        
        snr_margin = (p_muf / m_mhz) * res_total * abs_p * reflection_eff * path_loss_factor * pca_loss
        
        if bz < -1.0:
            bz_penalty = 1.0 # Simplified for map
            snr_margin *= bz_penalty
        
        exponent = -25.0 * (snr_margin - 0.70)
        exponent = np.clip(exponent, -50, 50) 
        p_rel = 1.0 / (1.0 + np.exp(exponent))
        sum_rel += p_rel * sample_weights[i]

    return sum_muf, sum_rel, dist_km

def generate_voacap_response(query, map_type="REL"):
    try:
        import numpy as np
        t_start = time.time()
        
        target_w = int(query.get('WIDTH', [660])[0])
        target_h = int(query.get('HEIGHT', [330])[0])
        
        tx_lat_d = float(query.get('TXLAT', [0])[0])
        tx_lng_d = float(query.get('TXLNG', [0])[0])
        m_mhz = float(query.get('MHZ', [14.0])[0])
        toa_param = float(query.get('TOA', [3.0])[0])
        year = int(query.get('YEAR', [time.gmtime().tm_year])[0])
        month = int(query.get('MONTH', [time.gmtime().tm_mon])[0])
        utc = float(query.get('UTC', [time.gmtime().tm_hour])[0])
        path = int(query.get('PATH', [0])[0])
        
        is_muf = (m_mhz == 0) or (map_type == "MUF")
        is_toa = (map_type == "TOA")
        
        swx = get_current_space_wx()
        # logger.info(f"VOACAP SpcWx: {swx}")
        
        ssn = swx['ssn']
        
        tx_lat_rad = math.radians(tx_lat_d)
        tx_lng_rad = math.radians(tx_lng_d)
        
        s_dec_rad, s_lng_rad = get_solar_pos(year, month, 15, utc)
        muf_base = 5.0 + 0.1 * ssn

        # Map HamClock Mode ID to Name
        raw_mode = query.get('MODE', ['38'])[0] # Default 38 (SSB)
        mode_id_map = {
            '38': 'SSB', '22': 'RTTY', '49': 'AM',
            '13': 'FT8', '19': 'CW', '17': 'FT4',
            '3': 'WSPR'
        }
        mode_name = mode_id_map.get(raw_mode, 'SSB')
        
        watts = float(query.get('WATTS', [100.0])[0])
        signal_margin = calculate_signal_margin(mode_name, watts)
        
        results = []
        header = create_bmp_565_header(target_w, target_h)
        
        grid_muf, grid_rel, grid_dist_km = calculate_grid_propagation_vectorized(
            tx_lat_rad, tx_lng_rad, m_mhz, toa_param, 
            s_dec_rad, s_lng_rad, muf_base, path=path, space_wx=swx,
            signal_margin_db=signal_margin
        )
        
        val_grid = grid_muf if is_muf else grid_rel
        val_padded = np.pad(val_grid, ((1,1),(0,0)), mode='edge')
        val_c = val_grid
        val_l = np.roll(val_grid, 1, axis=1) 
        val_r = np.roll(val_grid, -1, axis=1)
        val_t = val_padded[:-2, :]
        val_b = val_padded[2:, :]
        smooth_val = (val_c * 4.0 + val_l + val_r + val_t + val_b) / 8.0
        
        
        y_idx, x_idx = np.indices((MAP_H, MAP_W))
        grain = (((x_idx * 13) ^ (y_idx * 17)) & 7) / 100.0 - 0.035
        
        if is_muf:
             val_g = np.clip(smooth_val + grain * 5.0, 0.0, 50.0)
             indices = (val_g * 10).astype(int)
             indices = np.clip(indices, 0, 500)
             c565_grid = MUF_CACHE[indices]
             p_str = np.clip(val_g / 35.0, 0.0, 1.0)
        else:
             val_g = np.clip(smooth_val + grain, 0.0, 1.0)
             g_duct = 0.0
             rel_v = np.round(val_g * 10.0 * (1.0 + g_duct)) * 10.0
             if is_toa:
                 indices = np.clip((2.0 + (grid_dist_km/1000.0)*8.0) * 10, 0, 400).astype(int)
                 c565_toa = TOA_CACHE[indices]
                 c565_void = TOA_CACHE[400]
                 c565_grid = np.where(rel_v > 20.0, c565_toa, c565_void)
             else:
                 indices = np.clip(rel_v * 10, 0, 1000).astype(int)
                 c565_grid = REL_CACHE[indices]
             p_str = val_g

        final_grid = c565_grid
        
        bg_map = COUNTRIES_MAP if COUNTRIES_MAP is not None else TERRAIN_MAP
        if bg_map is not None:
            alpha = 0.4 + 0.4 * p_str
            final_grid = blend_rgb565_vectorized(final_grid, bg_map, alpha)
        
        if COUNTRIES_MASK is not None:
            final_grid[COUNTRIES_MASK > 0] = 0x0000

        if target_w != MAP_W or target_h != MAP_H:
             row_ind = (np.arange(target_h) * MAP_H // target_h).astype(int)
             col_ind = (np.arange(target_w) * MAP_W // target_w).astype(int)
             final_grid = final_grid[row_ind[:, None], col_ind]

        pixel_data = final_grid.astype('<u2').tobytes()
        img_data = zlib.compress(header + pixel_data)
        results.append(img_data)
        results.append(img_data) # Client expects Day and Night maps
            
        return results

    except Exception as e:
        logger.error(f"Error in VOACAP service: {e}", exc_info=True)
        return None

def calculate_dedx_for_bands(de_lat, de_lng, dx_lat, dx_lng, ssn):
    """
    Calculate reliability for standard HamClock bands using new logic.
    Supports Mode/Power if user provided, otherwise defaults.
    """
    band_map = {
        "80m": 3.5, "40m": 7.0, "30m": 10.1, "20m": 14.0,
        "17m": 18.1, "15m": 21.0, "12m": 24.9, "10m": 28.0
    }
    
    t = time.gmtime()
    year, month, utc = t.tm_year, t.tm_mon, t.tm_hour + t.tm_min/60.0
    
    results = {}
    for band, mhz in band_map.items():
        try:
            muf, rel = calculate_point_propagation(
                de_lat, de_lng, dx_lat, dx_lng, mhz, 
                3.0, year, month, utc, float(ssn)
            )
            results[band] = int(rel * 100)
        except Exception as e:
            logger.error(f"Error calculating point prop for {band}: {e}")
            results[band] = 0
            
    return results
