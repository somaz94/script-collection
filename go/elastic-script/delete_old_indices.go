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

const (
	elasticUser          = "elastic"
	elasticPassword      = "concrit123!"                     // password
	elasticHost          = "http://elasticsearch.concrit.us" // url
	minRetentionDays     = 7
	defaultRetentionDays = 30
)

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
	// Parse command line flags
	days := flag.Int("d", defaultRetentionDays, "Number of days to retain indices")
	help := flag.Bool("h", false, "Show help message")

	// Custom error handling for flag parsing
	flag.Usage = showHelp
	flag.Parse()

	if *help {
		showHelp()
	}

	// Validate retention days
	if *days < minRetentionDays {
		fmt.Fprintf(os.Stderr, "Error: Retention period cannot be less than %d days\n", minRetentionDays)
		os.Exit(1)
	}

	// Calculate threshold date
	thresholdDate := time.Now().AddDate(0, 0, -(*days)).Format("2006.01.02")

	// Get all indices
	indices, err := getIndices()
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: Failed to retrieve indices: %v\n", err)
		os.Exit(1)
	}

	if len(indices) == 0 {
		fmt.Println("No indices found")
		return
	}

	// Process indices
	for _, index := range indices {
		processIndex(index, thresholdDate)
	}
}

func getIndices() ([]string, error) {
	// Create HTTP client with basic auth
	client := &http.Client{}
	req, err := http.NewRequest("GET", elasticHost+"/_cat/indices?v", nil)
	if err != nil {
		return nil, err
	}

	req.SetBasicAuth(elasticUser, elasticPassword)

	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	// Read and parse response using io.ReadAll instead of ioutil.ReadAll
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}

	var indices []string
	for _, line := range strings.Split(string(body), "\n") {
		fields := strings.Fields(line)
		if len(fields) > 2 && strings.HasPrefix(fields[2], "logstash-") {
			indices = append(indices, fields[2])
		}
	}

	return indices, nil
}

func processIndex(index, thresholdDate string) {
	// Extract date from index name
	re := regexp.MustCompile(`logstash-(.+)`)
	matches := re.FindStringSubmatch(index)
	if len(matches) != 2 {
		fmt.Printf("Warning: Skipping %s - Invalid format\n", index)
		return
	}

	indexDate := matches[1]
	if !isValidDate(indexDate) {
		fmt.Printf("Warning: Skipping %s - Invalid date format\n", index)
		return
	}

	// Compare dates
	if indexDate < thresholdDate {
		fmt.Printf("Deleting index: %s (older than %s)\n", index, thresholdDate)
		if err := deleteIndex(index); err != nil {
			fmt.Printf("Error deleting index %s: %v\n", index, err)
		}
	} else {
		fmt.Printf("Skipping index: %s (newer than or equal to %s)\n", index, thresholdDate)
	}
}

func deleteIndex(index string) error {
	client := &http.Client{}
	req, err := http.NewRequest("DELETE", elasticHost+"/"+index, nil)
	if err != nil {
		return err
	}

	req.SetBasicAuth(elasticUser, elasticPassword)

	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode >= 400 {
		return fmt.Errorf("received status code %d", resp.StatusCode)
	}
	return nil
}

func isValidDate(date string) bool {
	_, err := time.Parse("2006.01.02", date)
	return err == nil
}
