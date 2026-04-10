package api

import (
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"path/filepath"
	"time"

	"github.com/save-backup/server/config"
	"github.com/save-backup/server/storage"
)

type Server struct {
	cfg *config.Config
}

func NewServer(cfg *config.Config) *Server {
	return &Server{cfg: cfg}
}

func (s *Server) Start() error {
	mux := http.NewServeMux()
	mux.HandleFunc("/destinations", s.handleDestinations)
	mux.HandleFunc("/meta", s.handleMeta)
	mux.HandleFunc("/upload", s.handleUpload)

	addr := fmt.Sprintf(":%d", s.cfg.Port)
	return http.ListenAndServe(addr, mux)
}

// GET /destinations
func (s *Server) handleDestinations(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	type resp struct {
		Destinations []string `json:"destinations"`
	}
	var names []string
	for _, d := range s.cfg.Destinations {
		names = append(names, d.Name)
	}
	writeJSON(w, resp{Destinations: names})
}

// GET /meta?dest=NDS
func (s *Server) handleMeta(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	destName := r.URL.Query().Get("dest")
	dest, ok := s.cfg.GetDestination(destName)
	if !ok {
		http.Error(w, "destination not found", http.StatusNotFound)
		return
	}
	meta, err := storage.LoadMeta(dest.Path)
	if err != nil {
		http.Error(w, "failed to load meta", http.StatusInternalServerError)
		return
	}
	writeJSON(w, meta)
}

// POST /upload
// Multipart form fields: dest, path, mod_time, hash, size
// File field: file
func (s *Server) handleUpload(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	// Parse multipart: max 512MB
	if err := r.ParseMultipartForm(512 << 20); err != nil {
		http.Error(w, "failed to parse form", http.StatusBadRequest)
		return
	}

	destName := r.FormValue("dest")
	relPath := r.FormValue("path")
	hashVal := r.FormValue("hash")
	modTimeStr := r.FormValue("mod_time")
	sizeStr := r.FormValue("size")

	if destName == "" || relPath == "" || hashVal == "" {
		http.Error(w, "missing required fields", http.StatusBadRequest)
		return
	}

	dest, ok := s.cfg.GetDestination(destName)
	if !ok {
		http.Error(w, "destination not found", http.StatusNotFound)
		return
	}

	// Prevent path traversal
	clean := filepath.Clean(relPath)
	if filepath.IsAbs(clean) || clean[:2] == ".." {
		http.Error(w, "invalid path", http.StatusBadRequest)
		return
	}

	modTime, err := time.Parse(time.RFC3339Nano, modTimeStr)
	if err != nil {
		modTime = time.Now()
	}

	var size int64
	fmt.Sscanf(sizeStr, "%d", &size)

	file, _, err := r.FormFile("file")
	if err != nil {
		http.Error(w, "missing file", http.StatusBadRequest)
		return
	}
	defer file.Close()

	data, err := io.ReadAll(file)
	if err != nil {
		http.Error(w, "failed to read file data", http.StatusInternalServerError)
		return
	}

	if err := storage.WriteFile(dest.Path, relPath, data, modTime); err != nil {
		log.Printf("Error writing file %s: %v", relPath, err)
		http.Error(w, "failed to write file", http.StatusInternalServerError)
		return
	}

	// Update meta
	meta, err := storage.LoadMeta(dest.Path)
	if err != nil {
		meta = &storage.DirMeta{Files: make(map[string]storage.FileMeta)}
	}
	meta.Files[relPath] = storage.FileMeta{
		Hash:    hashVal,
		ModTime: modTime,
		Size:    int64(len(data)),
	}
	if err := storage.SaveMeta(dest.Path, meta); err != nil {
		log.Printf("Warning: failed to save meta: %v", err)
	}

	log.Printf("Uploaded: dest=%s path=%s hash=%s", destName, relPath, hashVal[:8])
	writeJSON(w, map[string]string{"status": "ok", "path": relPath})
}

func writeJSON(w http.ResponseWriter, v any) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(v)
}
