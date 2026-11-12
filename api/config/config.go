// Package config holds embedded default configuration files.
package config

import _ "embed"

// TemperatureJSON is the default weights file for the temperature score.
//
//go:embed temperature.json
var TemperatureJSON []byte
