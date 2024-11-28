package main

import (
	"bufio"
	"context"
	"fmt"
	"os"
	"strings"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/tools/clientcmd"
)

func main() {
	// Load Kubernetes configuration
	kubeconfig := os.Getenv("KUBECONFIG")
	if kubeconfig == "" {
		homeDir, err := os.UserHomeDir()
		if err != nil {
			fmt.Printf("Error getting user home directory: %v\n", err)
			return
		}
		kubeconfig = fmt.Sprintf("%s/.kube/config", homeDir)
	}
	config, err := clientcmd.BuildConfigFromFlags("", kubeconfig)
	if err != nil {
		fmt.Printf("Error loading kubeconfig: %v\n", err)
		return
	}

	// Create Kubernetes client
	clientset, err := kubernetes.NewForConfig(config)
	if err != nil {
		fmt.Printf("Error creating Kubernetes client: %v\n", err)
		return
	}

	// Fetch all namespaces
	fmt.Println("Fetching namespaces...")
	namespaces, err := clientset.CoreV1().Namespaces().List(context.TODO(), metav1.ListOptions{})
	if err != nil {
		fmt.Printf("Error fetching namespaces: %v\n", err)
		return
	}

	// List namespaces
	fmt.Println("Available namespaces:")
	var namespaceNames []string
	for _, ns := range namespaces.Items {
		fmt.Println(ns.Name)
		namespaceNames = append(namespaceNames, ns.Name)
	}

	// Prompt user for namespace
	fmt.Print("\nEnter a namespace to inspect or type 'all' to inspect all namespaces: ")
	scanner := bufio.NewScanner(os.Stdin)
	if !scanner.Scan() {
		fmt.Println("Error reading input:", scanner.Err())
		return
	}
	inputNamespace := strings.TrimSpace(scanner.Text())

	if inputNamespace == "" {
		fmt.Println("Error: Namespace cannot be empty")
		return
	}

	// Check if user wants to inspect all namespaces
	if inputNamespace == "all" {
		for _, namespace := range namespaceNames {
			printPodUsage(clientset, namespace)
		}
	} else {
		// Validate the namespace
		if contains(namespaceNames, inputNamespace) {
			printPodUsage(clientset, inputNamespace)
		} else {
			fmt.Printf("Error: Namespace '%s' does not exist.\n", inputNamespace)
		}
	}
}

// Helper function to print resource usage for all pods in a namespace
func printPodUsage(clientset *kubernetes.Clientset, namespace string) {
	fmt.Printf("\n=== Resource usage in namespace: %s ===\n", namespace)

	pods, err := clientset.CoreV1().Pods(namespace).List(context.TODO(), metav1.ListOptions{})
	if err != nil {
		fmt.Printf("Error fetching pods in namespace '%s': %v\n", namespace, err)
		return
	}

	if len(pods.Items) == 0 {
		fmt.Printf("No pods found in namespace '%s'\n", namespace)
		return
	}

	for _, pod := range pods.Items {
		fmt.Printf("\nPod: %s\n", pod.Name)
		fmt.Printf("Status: %s\n", pod.Status.Phase)

		for _, container := range pod.Spec.Containers {
			cpuRequests := container.Resources.Requests.Cpu().String()
			memRequests := container.Resources.Requests.Memory().String()
			cpuLimits := container.Resources.Limits.Cpu().String()
			memLimits := container.Resources.Limits.Memory().String()

			fmt.Printf("  Container: %s\n", container.Name)
			if cpuRequests == "0" && memRequests == "0" {
				fmt.Println("    No resource requests specified")
			} else {
				fmt.Printf("    CPU Requests: %s, CPU Limits: %s\n", cpuRequests, cpuLimits)
				fmt.Printf("    Memory Requests: %s, Memory Limits: %s\n", memRequests, memLimits)
			}
		}
	}
	fmt.Println()
}

// Helper function to check if a slice contains a specific string
func contains(slice []string, item string) bool {
	for _, v := range slice {
		if v == item {
			return true
		}
	}
	return false
}
