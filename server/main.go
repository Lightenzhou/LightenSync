package main

import (
	"flag"
	"fmt"
	"log"
	"os"

	"github.com/save-backup/server/api"
	"github.com/save-backup/server/config"
)

func main() {
	var (
		configFile = flag.String("config", "config.json", "Path to config file")
		port       = flag.Int("port", 8080, "Server port")
		addDest    = flag.String("add-dest", "", "Add a destination: name:path (e.g. NDS:/data/nds)")
		listDests  = flag.Bool("list-dests", false, "List all destinations")
		removeDest = flag.String("remove-dest", "", "Remove a destination by name")
	)
	flag.Parse()

	cfg, err := config.Load(*configFile)
	if err != nil {
		cfg = config.New()
	}
	cfg.ConfigFile = *configFile

	if *addDest != "" {
		if err := cfg.AddDestination(*addDest); err != nil {
			log.Fatalf("Failed to add destination: %v", err)
		}
		if err := cfg.Save(); err != nil {
			log.Fatalf("Failed to save config: %v", err)
		}
		fmt.Println("Destination added successfully")
		os.Exit(0)
	}

	if *listDests {
		cfg.ListDestinations()
		os.Exit(0)
	}

	if *removeDest != "" {
		if err := cfg.RemoveDestination(*removeDest); err != nil {
			log.Fatalf("Failed to remove destination: %v", err)
		}
		if err := cfg.Save(); err != nil {
			log.Fatalf("Failed to save config: %v", err)
		}
		fmt.Println("Destination removed successfully")
		os.Exit(0)
	}

	cfg.Port = *port
	if err := cfg.Save(); err != nil {
		log.Printf("Warning: failed to save config: %v", err)
	}

	server := api.NewServer(cfg)
	log.Printf("Starting backup server on port %d", *port)
	log.Printf("Destinations configured: %d", len(cfg.Destinations))
	if err := server.Start(); err != nil {
		log.Fatalf("Server failed: %v", err)
	}
}
