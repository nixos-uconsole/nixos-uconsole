package config

import (
	"os"

	"github.com/BurntSushi/toml"
)

const DefaultPath = "/etc/uc-power.toml"

type Config struct {
	PowerButton  PowerButtonConfig  `toml:"power-button"`
	DisplayPower DisplayPowerConfig `toml:"display-power"`
}

type PowerButtonConfig struct {
	HoldDurationMs int        `toml:"hold-duration-ms"`
	LongPress      string     `toml:"long-press"`
	ShortPress     ShortPress `toml:"short-press"`
}

type ShortPress struct {
	WhenAwake  string `toml:"when-awake"`
	WhenAsleep string `toml:"when-asleep"`
}

type DisplayPowerConfig struct {
	CPU      CPUConfig      `toml:"cpu"`
	Keyboard KeyboardConfig `toml:"keyboard"`
	Hooks    HooksConfig    `toml:"hooks"`
}

type CPUConfig struct {
	SleepFreqMinKhz int `toml:"sleep-freq-min-khz"`
	SleepFreqMaxKhz int `toml:"sleep-freq-max-khz"`
	AwakeFreqMaxKhz int `toml:"awake-freq-max-khz"`
}

type KeyboardConfig struct {
	SuspendDriver bool `toml:"suspend-driver"`
}

type HooksConfig struct {
	OnSleep []string `toml:"on-sleep"`
	OnWake  []string `toml:"on-wake"`
}

func Default() Config {
	return Config{
		PowerButton: PowerButtonConfig{
			HoldDurationMs: 700,
			LongPress:      "poweroff",
			ShortPress: ShortPress{
				WhenAwake:  "displayOff",
				WhenAsleep: "displayOn",
			},
		},
		DisplayPower: DisplayPowerConfig{
			CPU: CPUConfig{
				SleepFreqMinKhz: 600000,
				SleepFreqMaxKhz: 600000,
				AwakeFreqMaxKhz: 1800000,
			},
			Keyboard: KeyboardConfig{
				SuspendDriver: true,
			},
			Hooks: HooksConfig{
				OnSleep: []string{},
				OnWake:  []string{},
			},
		},
	}
}

func Load(path string) (Config, error) {
	cfg := Default()

	data, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			return cfg, nil
		}
		return cfg, err
	}

	if _, err := toml.Decode(string(data), &cfg); err != nil {
		return cfg, err
	}

	return cfg, nil
}
