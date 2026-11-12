// Package llm is a minimal OpenAI-compatible chat client for the LiteLLM
// gateway on SPARK. The model target is configuration, never code.
package llm

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"
)

// ErrUnavailable means the gateway or model could not serve the request.
var ErrUnavailable = errors.New("llm unavailable")

// Client talks to /v1/chat/completions.
type Client struct {
	BaseURL string // e.g. http://SPARK_HOST:8080/v1
	APIKey  string
	Model   string
	HTTP    *http.Client
}

// Usage is token accounting reported by the server.
type Usage struct {
	PromptTokens     int `json:"prompt_tokens"`
	CompletionTokens int `json:"completion_tokens"`
}

// Request is one JSON-mode chat completion.
type Request struct {
	System    string
	User      string
	MaxTokens int
}

type message struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

type payload struct {
	Model              string            `json:"model"`
	Messages           []message         `json:"messages"`
	Temperature        float64           `json:"temperature"`
	MaxTokens          int               `json:"max_tokens,omitempty"`
	ResponseFormat     map[string]string `json:"response_format"`
	ChatTemplateKwargs map[string]bool   `json:"chat_template_kwargs"`
}

type response struct {
	Choices []struct {
		Message struct {
			Content string `json:"content"`
		} `json:"message"`
		FinishReason string `json:"finish_reason"`
	} `json:"choices"`
	Usage Usage `json:"usage"`
}

// ChatJSON sends the request and returns the raw assistant content.
func (c *Client) ChatJSON(ctx context.Context, r Request) (string, Usage, error) {
	body, err := json.Marshal(payload{
		Model:              c.Model,
		Messages:           []message{{"system", r.System}, {"user", r.User}},
		Temperature:        0,
		MaxTokens:          r.MaxTokens,
		ResponseFormat:     map[string]string{"type": "json_object"},
		ChatTemplateKwargs: map[string]bool{"enable_thinking": false},
	})
	if err != nil {
		return "", Usage{}, fmt.Errorf("marshal: %w", err)
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, strings.TrimRight(c.BaseURL, "/")+"/chat/completions", bytes.NewReader(body))
	if err != nil {
		return "", Usage{}, fmt.Errorf("request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	if c.APIKey != "" {
		req.Header.Set("Authorization", "Bearer "+c.APIKey)
	}
	hc := c.HTTP
	if hc == nil {
		hc = &http.Client{Timeout: 5 * time.Minute}
	}
	resp, err := hc.Do(req)
	if err != nil {
		return "", Usage{}, fmt.Errorf("%w: %v", ErrUnavailable, err)
	}
	defer resp.Body.Close()
	raw, err := io.ReadAll(io.LimitReader(resp.Body, 4<<20))
	if err != nil {
		return "", Usage{}, fmt.Errorf("%w: read: %v", ErrUnavailable, err)
	}
	if resp.StatusCode != http.StatusOK {
		msg := string(raw)
		if len(msg) > 300 {
			msg = msg[:300]
		}
		return "", Usage{}, fmt.Errorf("%w: HTTP %d: %s", ErrUnavailable, resp.StatusCode, msg)
	}
	var out response
	if err := json.Unmarshal(raw, &out); err != nil {
		return "", Usage{}, fmt.Errorf("decode response: %w", err)
	}
	if len(out.Choices) == 0 {
		return "", out.Usage, errors.New("empty choices")
	}
	return out.Choices[0].Message.Content, out.Usage, nil
}

// ExtractJSON returns the outermost JSON object in s, tolerating code
// fences or stray text around it.
func ExtractJSON(s string) string {
	start := strings.IndexByte(s, '{')
	end := strings.LastIndexByte(s, '}')
	if start < 0 || end < start {
		return s
	}
	return s[start : end+1]
}
