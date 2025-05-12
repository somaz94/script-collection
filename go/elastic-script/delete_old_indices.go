package main

import (
	"flag"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"time"
)

// Configuration Constants
// ---------------------
// These constants define the basic configuration for Elasticsearch connection
// and index management parameters
const (
	elasticUser          = "elastic"   // Elasticsearch username
	elasticPassword      = ""          // Elasticsearch password
	elasticHost          = ""          // Elasticsearch host URL
	indexPattern         = "logstash-" // Pattern to match indices for deletion
	minRetentionDays     = 7           // Minimum allowed retention period
	defaultRetentionDays = 30          // Default retention period if not specified
)

// showHelp displays usage information and examples
// This function is called when -h or --help flag is used
func showHelp() {
	fmt.Printf(`Usage: %s [OPTIONS]

Delete Elasticsearch indices older than specified retention period.

Options:
    -h, --help      Show this help message
    -d, --days      Number of days to retain indices (default: %d, minimum: %d)

Examples:
    %s         # Delete indices older than 30 days
    %s -d 60   # Delete indices older than 60 days

Note: Minimum retention period is %d days for safety.
`, filepath.Base(os.Args[0]), defaultRetentionDays, minRetentionDays,
		filepath.Base(os.Args[0]), filepath.Base(os.Args[0]), minRetentionDays)
	os.Exit(0)
}

func main() {
	// Command Line Flag Parsing
	// ------------------------
	// Parse command line arguments for retention days and help flag
	days := flag.Int("d", defaultRetentionDays, "Number of days to retain indices")
	help := flag.Bool("h", false, "Show help message")

	// Set custom help message handler
	flag.Usage = showHelp
	flag.Parse()

	// Show help if requested
	if *help {
		showHelp()
	}

	// Input Validation
	// --------------
	// Ensure retention period meets minimum requirement
	if *days < minRetentionDays {
		fmt.Fprintf(os.Stderr, "Error: Retention period cannot be less than %d days\n", minRetentionDays)
		os.Exit(1)
	}

	// Calculate threshold date for index deletion
	// Format: YYYY.MM.DD
	thresholdDate := time.Now().AddDate(0, 0, -(*days)).Format("2006.01.02")

	// Retrieve and Process Indices
	// --------------------------
	// Get list of all indices from Elasticsearch
	indices, err := getIndices()
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: Failed to retrieve indices: %v\n", err)
		os.Exit(1)
	}

	// Exit if no indices found
	if len(indices) == 0 {
		fmt.Println("No indices found")
		return
	}

	// Process each index
	for _, index := range indices {
		processIndex(index, thresholdDate)
	}
}

// getIndices retrieves all indices from Elasticsearch
// Returns a slice of index names that match the indexPattern
func getIndices() ([]string, error) {
	// Create HTTP client with basic authentication
	client := &http.Client{}
	req, err := http.NewRequest("GET", elasticHost+"/_cat/indices?v", nil)
	if err != nil {
		return nil, err
	}

	// Set basic authentication
	req.SetBasicAuth(elasticUser, elasticPassword)

	// Execute request
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	// Read response body
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}

	// Parse indices from response
	// Filter indices that match the pattern
	var indices []string
	for _, line := range strings.Split(string(body), "\n") {
		fields := strings.Fields(line)
		if len(fields) > 2 && strings.HasPrefix(fields[2], indexPattern) {
			indices = append(indices, fields[2])
		}
	}

	return indices, nil
}

// processIndex handles a single index
// Checks if the index is older than the threshold date and deletes if necessary
func processIndex(index, thresholdDate string) {
	// Extract date from index name using regex
	re := regexp.MustCompile(indexPattern + `(.+)`)
	matches := re.FindStringSubmatch(index)
	if len(matches) != 2 {
		fmt.Printf("Warning: Skipping %s - Invalid format\n", index)
		return
	}

	// Get and validate index date
	indexDate := matches[1]
	if !isValidDate(indexDate) {
		fmt.Printf("Warning: Skipping %s - Invalid date format\n", index)
		return
	}

	// Compare dates and delete if older than threshold
	if indexDate < thresholdDate {
		fmt.Printf("Deleting index: %s (older than %s)\n", index, thresholdDate)
		if err := deleteIndex(index); err != nil {
			fmt.Printf("Error deleting index %s: %v\n", index, err)
		}
	} else {
		fmt.Printf("Skipping index: %s (newer than or equal to %s)\n", index, thresholdDate)
	}
}

// deleteIndex sends a DELETE request to remove an index from Elasticsearch
func deleteIndex(index string) error {
	// Create HTTP client
	client := &http.Client{}
	req, err := http.NewRequest("DELETE", elasticHost+"/"+index, nil)
	if err != nil {
		return err
	}

	// Set basic authentication
	req.SetBasicAuth(elasticUser, elasticPassword)

	// Execute delete request
	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	// Check for error status codes
	if resp.StatusCode >= 400 {
		return fmt.Errorf("received status code %d", resp.StatusCode)
	}
	return nil
}

// isValidDate checks if a string is a valid date in the format YYYY.MM.DD
func isValidDate(date string) bool {
	_, err := time.Parse("2006.01.02", date)
	return err == nil
}
