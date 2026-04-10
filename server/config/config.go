package config

import (
	"encoding/json"
	"fmt"
	"os"
	"strings"
)

type Destination struct {
	Name string `json:"name"`
	Path string `json:"path"`
}

type Config struct {
	Port         int           `json:"port"`
	Destinations []Destination `json:"destinations"`
	ConfigFile   string        `json:"-"`
}

func New() *Config {
	return &Config{
		Port:         8080,
		Destinations: []Destination{},
	}
}

func Load(path string) (*Config, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	cfg := &Config{}
	if err := json.Unmarshal(data, cfg); err != nil {
		return nil, err
	}
	cfg.ConfigFile = path
	return cfg, nil
}

func (c *Config) Save() error {
	data, err := json.MarshalIndent(c, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(c.ConfigFile, data, 0644)
}

func (c *Config) AddDestination(spec string) error {
	parts := strings.SplitN(spec, ":", 2)
	if len(parts) != 2 {
		return fmt.Errorf("invalid format, expected name:path")
	}
	name := strings.TrimSpace(parts[0])
	path := strings.TrimSpace(parts[1])
	if name == "" || path == "" {
		return fmt.Errorf("name and path cannot be empty")
	}
	for _, d := range c.Destinations {
		if d.Name == name {
			return fmt.Errorf("destination '%s' already exists", name)
		}
	}
	if err := os.MkdirAll(path, 0755); err != nil {
		return fmt.Errorf("failed to create directory '%s': %v", path, err)
	}
	c.Destinations = append(c.Destinations, Destination{Name: name, Path: path})
	return nil
}

func (c *Config) RemoveDestination(name string) error {
	for i, d := range c.Destinations {
		if d.Name == name {
			c.Destinations = append(c.Destinations[:i], c.Destinations[i+1:]...)
			return nil
		}
	}
	return fmt.Errorf("destination '%s' not found", name)
}

func (c *Config) GetDestination(name string) (*Destination, bool) {
	for _, d := range c.Destinations {
		if d.Name == name {
			return &d, true
		}
	}
	return nil, false
}

func (c *Config) ListDestinations() {
	if len(c.Destinations) == 0 {
		fmt.Println("No destinations configured")
		return
	}
	fmt.Printf("%-20s %s\n", "NAME", "PATH")
	fmt.Println(strings.Repeat("-", 60))
	for _, d := range c.Destinations {
		fmt.Printf("%-20s %s\n", d.Name, d.Path)
	}
}
