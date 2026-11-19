// Package config holds embedded default configuration files.
package config

import _ "embed"

// TemperatureJSON is the default weights file for the temperature score.
//
//go:embed temperature.json
var TemperatureJSON []byte

// ClaimsJSON is the default configuration of claim checking (limits,
// source weights, verdict thresholds).
//
//go:embed claims.json
var ClaimsJSON []byte
