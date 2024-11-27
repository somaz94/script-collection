package main

import (
	"fmt"
	"log"
	"os/exec"
	"strings"
	"strconv"
)

// convertKiToGi converts memory from Ki to Gi
func convertKiToGi(ki float64) float64 {
	return ki / 1024 / 1024
}

func main() {
	fmt.Println("Checking physical CPU and memory for each node...")

	// Get the list of all nodes
	out, err := exec.Command("kubectl", "get", "nodes", "-o", "jsonpath={.items[*].metadata.name}").Output()
	if err != nil {
		log.Fatalf("Failed to get nodes: %v", err)
	}

	nodes := strings.Fields(string(out))

	// Loop through each node
	for _, node := range nodes {
		fmt.Printf("Node: %s\n", node)

		// Get CPU capacity
		cpuOut, err := exec.Command("kubectl", "get", "node", node, "-o", "jsonpath={.status.capacity.cpu}").Output()
		if err != nil {
			log.Printf("Failed to get CPU for node %s: %v", node, err)
			continue
		}
		fmt.Printf("  CPU: %s cores\n", string(cpuOut))

		// Get memory capacity
		memOut, err := exec.Command("kubectl", "get", "node", node, "-o", "jsonpath={.status.capacity.memory}").Output()
		if err != nil {
			log.Printf("Failed to get memory for node %s: %v", node, err)
			continue
		}

		// Convert memory string (remove 'Ki' suffix and convert to number)
		memStr := strings.TrimSuffix(string(memOut), "Ki")
		memKi, err := strconv.ParseFloat(memStr, 64)
		if err != nil {
			log.Printf("Failed to parse memory value for node %s: %v", node, err)
			continue
		}

		memGi := convertKiToGi(memKi)
		fmt.Printf("  Memory: %.2f Gi\n", memGi)
		fmt.Println("-------------------------------------")
	}
}
