package service

import "sync"

// hub fans out events of running analyses to SSE subscribers and keeps
// the history so late subscribers get a full replay.
type hub struct {
	mu sync.Mutex
	m  map[string]*topic
}

type topic struct {
	events []Event
	subs   map[int]chan Event
	next   int
}

func newHub() *hub { return &hub{m: map[string]*topic{}} }

func (h *hub) open(id string) {
	h.mu.Lock()
	defer h.mu.Unlock()
	h.m[id] = &topic{subs: map[int]chan Event{}}
}

func (h *hub) publish(id string, e Event) {
	h.mu.Lock()
	defer h.mu.Unlock()
	t, ok := h.m[id]
	if !ok {
		return
	}
	t.events = append(t.events, e)
	for k, ch := range t.subs {
		select {
		case ch <- e:
		default:
			// Slow client: drop it; it reconnects and gets a replay.
			close(ch)
			delete(t.subs, k)
		}
	}
}

// close ends the topic; subscribers' channels are closed and later
// subscribers are served from the store.
func (h *hub) close(id string) {
	h.mu.Lock()
	defer h.mu.Unlock()
	t, ok := h.m[id]
	if !ok {
		return
	}
	for _, ch := range t.subs {
		close(ch)
	}
	delete(h.m, id)
}

func (h *hub) subscribe(id string) ([]Event, <-chan Event, func(), bool) {
	h.mu.Lock()
	defer h.mu.Unlock()
	t, ok := h.m[id]
	if !ok {
		return nil, nil, nil, false
	}
	ch := make(chan Event, 256)
	k := t.next
	t.next++
	t.subs[k] = ch
	past := append([]Event(nil), t.events...)
	cancel := func() {
		h.mu.Lock()
		defer h.mu.Unlock()
		if t, ok := h.m[id]; ok {
			if c, ok := t.subs[k]; ok {
				close(c)
				delete(t.subs, k)
			}
		}
	}
	return past, ch, cancel, true
}
