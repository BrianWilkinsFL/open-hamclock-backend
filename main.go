package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"math"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"
)

/*
Compatibility notes (from capture):
- HamClock sends HTTP/1.0 GETs, Host header, Connection: close.
- Responses observed include:
  - "HTTP/1.0 200 Ok"
  - "Content-Type: text/plain; charset=ISO-8859-1"
  - Body formats are line oriented and rigid.
  :contentReference[oaicite:2]{index=2}
*/

type Config struct {
	ListenAddr string // e.g. ":80" or "127.0.0.1:8080"
	DataDir    string // where xray/rank2 files are stored

	// Version endpoint
	HamClockVersion string // e.g. "4.22"
	VersionInfo     string // e.g. "No info for version  4.22"

	// Weather endpoint (OpenWeather proxy/normalizer)
	OWMApiKey string // optional; if absent, returns stubbed deterministic data
	OWMBase   string // default https://api.openweathermap.org

	// Optional upstream sources for static-ish datasets
	XraySourceURL   string // if set, periodically refresh xray.txt from this URL
	Rank2SourceURL  string // if set, periodically refresh rank2_coeffs.txt from this URL
	RefreshInterval time.Duration
}

func envOr(key, def string) string {
	if v := strings.TrimSpace(os.Getenv(key)); v != "" {
		return v
	}
	return def
}

func mustDuration(s string, def time.Duration) time.Duration {
	if strings.TrimSpace(s) == "" {
		return def
	}
	d, err := time.ParseDuration(s)
	if err != nil {
		return def
	}
	return d
}

func loadConfig() Config {
	return Config{
		ListenAddr:       envOr("LISTEN_ADDR", ":7777"),
		DataDir:          envOr("DATA_DIR", "./data"),
		HamClockVersion:  envOr("HAMCLOCK_VERSION", "4.22"),
		VersionInfo:      envOr("VERSION_INFO", "No info for version  4.22"),
		OWMApiKey:        strings.TrimSpace(os.Getenv("OWM_API_KEY")),
		OWMBase:          envOr("OWM_BASE", "https://api.openweathermap.org"),
		XraySourceURL:    strings.TrimSpace(os.Getenv("XRAY_SOURCE_URL")),
		Rank2SourceURL:   strings.TrimSpace(os.Getenv("RANK2_SOURCE_URL")),
		RefreshInterval:  mustDuration(os.Getenv("REFRESH_INTERVAL"), 10*time.Minute),
	}
}

type fileCache struct {
	mu    sync.RWMutex
	path  string
	etag  string
	lm    string // Last-Modified
	bytes []byte
}

func newFileCache(path string) *fileCache {
	return &fileCache{path: path}
}

func (c *fileCache) loadFromDisk() error {
	b, err := os.ReadFile(c.path)
	if err != nil {
		return err
	}
	c.mu.Lock()
	c.bytes = b
	c.mu.Unlock()
	return nil
}

func (c *fileCache) get() []byte {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return append([]byte(nil), c.bytes...)
}

func (c *fileCache) set(b []byte, etag, lm string) {
	c.mu.Lock()
	c.bytes = b
	if etag != "" {
		c.etag = etag
	}
	if lm != "" {
		c.lm = lm
	}
	c.mu.Unlock()
}

func (c *fileCache) meta() (etag, lm string) {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.etag, c.lm
}

// Ensure we respond in a conservative, HamClock-friendly way.
func writePlain(w http.ResponseWriter, status int, body []byte) {
	w.Header().Set("Content-Type", "text/plain; charset=ISO-8859-1")
	// HamClock uses Connection: close; we can explicitly close too.
	w.Header().Set("Connection", "close")
	w.WriteHeader(status)
	_, _ = w.Write(body)
}

func writeNotFound(w http.ResponseWriter) {
	writePlain(w, http.StatusNotFound, []byte("404 not found\n"))
}

func main() {
	cfg := loadConfig()

	if err := os.MkdirAll(cfg.DataDir, 0o755); err != nil {
		log.Fatalf("mkdir DATA_DIR: %v", err)
	}

	// Prepare caches for static-ish endpoints
	rank2Path := filepath.Join(cfg.DataDir, "rank2_coeffs.txt")
	xrayPath := filepath.Join(cfg.DataDir, "xray.txt")

	rank2 := newFileCache(rank2Path)
	xray := newFileCache(xrayPath)

	// Load seed files if they exist
	_ = rank2.loadFromDisk()
	_ = xray.loadFromDisk()

	// Optional refreshers
	client := &http.Client{Timeout: 20 * time.Second}
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	if cfg.Rank2SourceURL != "" {
		go refresher(ctx, client, cfg.Rank2SourceURL, rank2, cfg.RefreshInterval)
	}
	if cfg.XraySourceURL != "" {
		go refresher(ctx, client, cfg.XraySourceURL, xray, cfg.RefreshInterval)
	}

	mux := http.NewServeMux()

	// 1) /ham/HamClock/version.pl
	mux.HandleFunc("/ham/HamClock/version.pl", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			writePlain(w, http.StatusMethodNotAllowed, []byte("method not allowed\n"))
			return
		}
		// Observed response is version + message, newline separated.
		// :contentReference[oaicite:3]{index=3}
		var buf bytes.Buffer
		buf.WriteString(cfg.HamClockVersion)
		buf.WriteString("\n")
		buf.WriteString(cfg.VersionInfo)
		buf.WriteString("\n\n")
		writePlain(w, http.StatusOK, buf.Bytes())
	})

	// 2) /ham/HamClock/wx.pl
	mux.HandleFunc("/ham/HamClock/wx.pl", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			writePlain(w, http.StatusMethodNotAllowed, []byte("method not allowed\n"))
			return
		}
		q := r.URL.Query()
		latS := q.Get("lat")
		lngS := q.Get("lng")
		lat, _ := strconv.ParseFloat(latS, 64)
		lng, _ := strconv.ParseFloat(lngS, 64)

		wx, err := getWeather(r.Context(), client, cfg, lat, lng)
		if err != nil {
			// Fail “soft”: return a deterministic minimal payload rather than 500.
			// HamClock prefers data presence over correctness.
			wx = WeatherKV{
				"city":             "Unknown",
				"temperature_c":    "0.00",
				"pressure_hPa":     "0",
				"pressure_chg":     "-999",
				"humidity_percent": "0",
				"wind_speed_mps":   "0.00",
				"wind_dir_name":    "N",
				"clouds":           "unknown",
				"conditions":       "Unknown",
				"attribution":      "openweathermap.org",
				"timezone":         "0",
			}
		}

		// Observed: key=value lines, no JSON.
		// :contentReference[oaicite:4]{index=4}
		writePlain(w, http.StatusOK, []byte(wx.Render()))
	})

	// 3) /ham/HamClock/xray/xray.txt
	mux.HandleFunc("/ham/HamClock/xray/xray.txt", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			writePlain(w, http.StatusMethodNotAllowed, []byte("method not allowed\n"))
			return
		}
		b := xray.get()
		if len(b) == 0 {
			// Make missing obvious; HamClock will show gaps.
			writePlain(w, http.StatusOK, []byte("\n"))
			return
		}
		writePlain(w, http.StatusOK, b)
	})

	// 4) /ham/HamClock/NOAASpaceWX/rank2_coeffs.txt
	mux.HandleFunc("/ham/HamClock/NOAASpaceWX/rank2_coeffs.txt", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			writePlain(w, http.StatusMethodNotAllowed, []byte("method not allowed\n"))
			return
		}
		b := rank2.get()
		if len(b) == 0 {
			writePlain(w, http.StatusOK, []byte("# missing rank2_coeffs.txt\n"))
			return
		}
		writePlain(w, http.StatusOK, b)
	})

	// Everything else: 404 (for now)
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		writeNotFound(w)
	})

	srv := &http.Server{
		Addr:              cfg.ListenAddr,
		Handler:           logRequests(mux),
		ReadHeaderTimeout: 10 * time.Second,
	}

	log.Printf("hamclock-backend listening on %s", cfg.ListenAddr)
	log.Printf("data dir: %s", cfg.DataDir)
	log.Printf("OWM key present: %v", cfg.OWMApiKey != "")

	if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
		log.Fatalf("server: %v", err)
	}
}

func logRequests(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		ra := r.RemoteAddr
		// If behind reverse proxy, you'll want X-Forwarded-For, etc.
		log.Printf("%s %s %s", ra, r.Method, r.URL.String())
		next.ServeHTTP(w, r)
	})
}

func refresher(ctx context.Context, client *http.Client, url string, cache *fileCache, every time.Duration) {
	t := time.NewTicker(every)
	defer t.Stop()

	// First fetch immediately
	_ = fetchIntoCache(ctx, client, url, cache)

	for {
		select {
		case <-ctx.Done():
			return
		case <-t.C:
			_ = fetchIntoCache(ctx, client, url, cache)
		}
	}
}

func fetchIntoCache(ctx context.Context, client *http.Client, url string, cache *fileCache) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return err
	}

	etag, lm := cache.meta()
	if etag != "" {
		req.Header.Set("If-None-Match", etag)
	}
	if lm != "" {
		req.Header.Set("If-Modified-Since", lm)
	}

	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode == http.StatusNotModified {
		return nil
	}
	if resp.StatusCode < 200 || resp.StatusCode > 299 {
		return fmt.Errorf("upstream %s: %s", url, resp.Status)
	}

	b, err := io.ReadAll(io.LimitReader(resp.Body, 20<<20))
	if err != nil {
		return err
	}

	cache.set(b, resp.Header.Get("ETag"), resp.Header.Get("Last-Modified"))
	_ = os.WriteFile(cache.path, b, 0o644)
	return nil
}

/* ---------------- Weather ---------------- */

type WeatherKV map[string]string

func (kv WeatherKV) Render() string {
	// Keep stable ordering for safety (client parsers are often simplistic).
	// Observed keys from capture. :contentReference[oaicite:5]{index=5}
	keys := []string{
		"city",
		"temperature_c",
		"pressure_hPa",
		"pressure_chg",
		"humidity_percent",
		"wind_speed_mps",
		"wind_dir_name",
		"clouds",
		"conditions",
		"attribution",
		"timezone",
	}
	var b strings.Builder
	for _, k := range keys {
		if v, ok := kv[k]; ok {
			b.WriteString(k)
			b.WriteString("=")
			b.WriteString(v)
			b.WriteString("\n")
		}
	}
	b.WriteString("\n")
	return b.String()
}

type owmResp struct {
	Name  string `json:"name"`
	Dt    int64  `json:"dt"`
	Zone  int    `json:"timezone"`
	Main  struct {
		Temp     float64 `json:"temp"`
		Pressure int     `json:"pressure"`
		Humidity int     `json:"humidity"`
	} `json:"main"`
	Wind struct {
		Speed float64 `json:"speed"`
		Deg   float64 `json:"deg"`
	} `json:"wind"`
	Weather []struct {
		Main        string `json:"main"`
		Description string `json:"description"`
	} `json:"weather"`
	Clouds struct {
		All int `json:"all"`
	} `json:"clouds"`
}

func getWeather(ctx context.Context, client *http.Client, cfg Config, lat, lng float64) (WeatherKV, error) {
	// If no key, return stub (still includes openweathermap attribution to match observed format).
	if cfg.OWMApiKey == "" {
		return WeatherKV{
			"city":             "Franklin",
			"temperature_c":    "0.01",
			"pressure_hPa":     "1026",
			"pressure_chg":     "-999",
			"humidity_percent": "60",
			"wind_speed_mps":   "2.76",
			"wind_dir_name":    "SE",
			"clouds":           "overcast clouds",
			"conditions":       "Clouds",
			"attribution":      "openweathermap.org",
			"timezone":         "-21600",
		}, nil
	}

	// OpenWeather current weather: /data/2.5/weather?lat=...&lon=...&appid=...&units=metric
	u := fmt.Sprintf("%s/data/2.5/weather?lat=%.6f&lon=%.6f&appid=%s&units=metric",
		strings.TrimRight(cfg.OWMBase, "/"),
		lat, lng, cfg.OWMApiKey,
	)

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, u, nil)
	if err != nil {
		return nil, err
	}
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode > 299 {
		return nil, fmt.Errorf("openweather: %s", resp.Status)
	}

	var o owmResp
	if err := json.NewDecoder(resp.Body).Decode(&o); err != nil {
		return nil, err
	}

	cond := "Unknown"
	clouds := "unknown"
	if len(o.Weather) > 0 {
		cond = o.Weather[0].Main
		// HamClock example has "overcast clouds"; that's closer to description than "Main".
		if o.Weather[0].Description != "" {
			clouds = o.Weather[0].Description
		}
	}

	kv := WeatherKV{
		"city":             nonEmpty(o.Name, "Unknown"),
		"temperature_c":    fmt.Sprintf("%.2f", o.Main.Temp),
		"pressure_hPa":     fmt.Sprintf("%d", o.Main.Pressure),
		"pressure_chg":     "-999", // not provided by OWM; backend likely computed trend elsewhere
		"humidity_percent": fmt.Sprintf("%d", o.Main.Humidity),
		"wind_speed_mps":   fmt.Sprintf("%.2f", o.Wind.Speed),
		"wind_dir_name":    degToDir(o.Wind.Deg),
		"clouds":           clouds,
		"conditions":       cond,
		"attribution":      "openweathermap.org",
		"timezone":         fmt.Sprintf("%d", o.Zone),
	}

	return kv, nil
}

func nonEmpty(v, def string) string {
	if strings.TrimSpace(v) == "" {
		return def
	}
	return v
}

func degToDir(deg float64) string {
	// 16-point compass
	d := math.Mod(deg, 360.0)
	if d < 0 {
		d += 360
	}
	dirs := []string{"N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE", "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"}
	idx := int(math.Round(d/22.5)) % 16
	return dirs[idx]
}

/* ---------------- Optional: bind safety ---------------- */

// If you need to bind :80 in Linux, you’ll typically run as root or give CAP_NET_BIND_SERVICE.
// Not used directly here, but included for completeness.
func canBindPrivilegedPort(addr string) error {
	_, portStr, err := net.SplitHostPort(addr)
	if err != nil {
		return err
	}
	port, _ := strconv.Atoi(portStr)
	if port < 1024 {
		// We won't enforce; caller decides. This is just a helper stub.
		return nil
	}
	return nil
}

