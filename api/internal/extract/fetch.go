package extract

import (
	"context"
	"errors"
	"fmt"
	"io"
	"mime"
	"net"
	"net/http"
	"net/netip"
	"net/url"
	"strings"
	"syscall"
	"time"
)

// ErrFetch marks errors caused by the remote page (not by us).
var ErrFetch = errors.New("fetch failed")

// Fetcher downloads article pages for user-submitted URLs. It refuses
// private and loopback addresses so the API cannot be used to probe the
// LAN it runs in.
type Fetcher struct {
	UserAgent    string
	MaxBytes     int64
	Timeout      time.Duration
	AllowPrivate bool // tests only
	client       *http.Client
}

// NewFetcher returns a Fetcher with sane limits.
func NewFetcher(userAgent string) *Fetcher {
	return &Fetcher{UserAgent: userAgent, MaxBytes: 5 << 20, Timeout: 15 * time.Second}
}

func (f *Fetcher) httpClient() *http.Client {
	if f.client != nil {
		return f.client
	}
	dialer := &net.Dialer{Timeout: 5 * time.Second, Control: f.checkAddr}
	tr := &http.Transport{
		DialContext:           dialer.DialContext,
		TLSHandshakeTimeout:   5 * time.Second,
		ResponseHeaderTimeout: 10 * time.Second,
		MaxIdleConns:          20,
		IdleConnTimeout:       60 * time.Second,
	}
	f.client = &http.Client{
		Transport: tr,
		Timeout:   f.Timeout,
		CheckRedirect: func(req *http.Request, via []*http.Request) error {
			if len(via) >= 5 {
				return errors.New("too many redirects")
			}
			return CheckURL(req.URL)
		},
	}
	return f.client
}

func (f *Fetcher) checkAddr(_, address string, _ syscall.RawConn) error {
	if f.AllowPrivate {
		return nil
	}
	host, _, err := net.SplitHostPort(address)
	if err != nil {
		return err
	}
	ip, err := netip.ParseAddr(host)
	if err != nil {
		return err
	}
	ip = ip.Unmap()
	if ip.IsLoopback() || ip.IsPrivate() || ip.IsLinkLocalUnicast() || ip.IsLinkLocalMulticast() ||
		ip.IsUnspecified() || ip.IsMulticast() || isCGNAT(ip) {
		return fmt.Errorf("address %s not allowed", ip)
	}
	return nil
}

func isCGNAT(ip netip.Addr) bool {
	return netip.MustParsePrefix("100.64.0.0/10").Contains(ip)
}

// CheckURL accepts only absolute http(s) URLs without credentials.
func CheckURL(u *url.URL) error {
	if u.Scheme != "http" && u.Scheme != "https" {
		return errors.New("only http and https URLs are supported")
	}
	if u.Host == "" || u.User != nil {
		return errors.New("invalid URL")
	}
	return nil
}

// Page is a downloaded HTML page.
type Page struct {
	URL         *url.URL // final URL after redirects
	HTML        []byte
	ContentType string
}

// Fetch downloads an HTML page.
func (f *Fetcher) Fetch(ctx context.Context, raw string) (Page, error) {
	u, err := url.Parse(raw)
	if err != nil {
		return Page{}, fmt.Errorf("%w: %v", ErrFetch, err)
	}
	if err := CheckURL(u); err != nil {
		return Page{}, fmt.Errorf("%w: %v", ErrFetch, err)
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, u.String(), nil)
	if err != nil {
		return Page{}, fmt.Errorf("%w: %v", ErrFetch, err)
	}
	req.Header.Set("User-Agent", f.UserAgent)
	req.Header.Set("Accept", "text/html,application/xhtml+xml;q=0.9,*/*;q=0.5")
	req.Header.Set("Accept-Language", "cs,sk;q=0.9,en;q=0.8,*;q=0.5")
	resp, err := f.httpClient().Do(req)
	if err != nil {
		return Page{}, fmt.Errorf("%w: %v", ErrFetch, err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return Page{}, fmt.Errorf("%w: HTTP %d", ErrFetch, resp.StatusCode)
	}
	if ct := resp.Header.Get("Content-Type"); ct != "" {
		mt, _, _ := mime.ParseMediaType(ct)
		if mt != "text/html" && mt != "application/xhtml+xml" && !strings.HasPrefix(mt, "text/") {
			return Page{}, fmt.Errorf("%w: unsupported content type %s", ErrFetch, mt)
		}
	}
	body, err := io.ReadAll(io.LimitReader(resp.Body, f.MaxBytes+1))
	if err != nil {
		return Page{}, fmt.Errorf("%w: %v", ErrFetch, err)
	}
	if int64(len(body)) > f.MaxBytes {
		return Page{}, fmt.Errorf("%w: page larger than %d bytes", ErrFetch, f.MaxBytes)
	}
	return Page{URL: resp.Request.URL, HTML: body, ContentType: resp.Header.Get("Content-Type")}, nil
}
