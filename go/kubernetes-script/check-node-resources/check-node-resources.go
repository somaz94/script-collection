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
	fmt.Println("Checking physical CPU, memory, and disk storage for each node...")

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

		// Convert memory string
		memStr := strings.TrimSuffix(string(memOut), "Ki")
		memKi, err := strconv.ParseFloat(memStr, 64)
		if err != nil {
			log.Printf("Failed to parse memory value for node %s: %v", node, err)
			continue
		}
		memGi := convertKiToGi(memKi)
		fmt.Printf("  Memory: %.2f Gi\n", memGi)

		// Get disk capacity
		diskOut, err := exec.Command("kubectl", "get", "node", node, "-o", "jsonpath={.status.capacity.ephemeral-storage}").Output()
		if err != nil {
			log.Printf("Failed to get disk storage for node %s: %v", node, err)
			continue
		}

		// Convert disk string
		diskStr := strings.TrimSuffix(string(diskOut), "Ki")
		diskKi, err := strconv.ParseFloat(diskStr, 64)
		if err != nil {
			log.Printf("Failed to parse disk value for node %s: %v", node, err)
			continue
		}
		diskGi := convertKiToGi(diskKi)
		fmt.Printf("  Disk: %.2f Gi\n", diskGi)

		fmt.Println("-------------------------------------")
	}
}
