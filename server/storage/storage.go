package storage

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"io"
	"os"
	"path/filepath"
	"time"
)

const MetaFileName = ".backup_meta.json"

type FileMeta struct {
	Hash    string    `json:"hash"`
	ModTime time.Time `json:"mod_time"`
	Size    int64     `json:"size"`
}

type DirMeta struct {
	Files     map[string]FileMeta `json:"files"`
	UpdatedAt time.Time           `json:"updated_at"`
}

func LoadMeta(destPath string) (*DirMeta, error) {
	metaFile := filepath.Join(destPath, MetaFileName)
	data, err := os.ReadFile(metaFile)
	if err != nil {
		if os.IsNotExist(err) {
			return &DirMeta{Files: make(map[string]FileMeta)}, nil
		}
		return nil, err
	}
	meta := &DirMeta{}
	if err := json.Unmarshal(data, meta); err != nil {
		return &DirMeta{Files: make(map[string]FileMeta)}, nil
	}
	return meta, nil
}

func SaveMeta(destPath string, meta *DirMeta) error {
	meta.UpdatedAt = time.Now()
	data, err := json.MarshalIndent(meta, "", "  ")
	if err != nil {
		return err
	}
	metaFile := filepath.Join(destPath, MetaFileName)
	return os.WriteFile(metaFile, data, 0644)
}

func HashFile(path string) (string, error) {
	f, err := os.Open(path)
	if err != nil {
		return "", err
	}
	defer f.Close()

	h := sha256.New()
	if _, err := io.Copy(h, f); err != nil {
		return "", err
	}
	return hex.EncodeToString(h.Sum(nil)), nil
}

func WriteFile(destPath, relPath string, data []byte, modTime time.Time) error {
	fullPath := filepath.Join(destPath, relPath)
	if err := os.MkdirAll(filepath.Dir(fullPath), 0755); err != nil {
		return err
	}
	if err := os.WriteFile(fullPath, data, 0644); err != nil {
		return err
	}
	return os.Chtimes(fullPath, modTime, modTime)
}
