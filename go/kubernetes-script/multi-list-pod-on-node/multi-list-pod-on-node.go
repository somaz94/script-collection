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

// selectNode prompts the user to select nodes and returns the names of selected nodes
func selectNode(clientset *kubernetes.Clientset) ([]string, error) {
	// Get node list excluding master nodes
	nodes, err := clientset.CoreV1().Nodes().List(context.TODO(), metav1.ListOptions{
		LabelSelector: "!node-role.kubernetes.io/master",
	})
	if err != nil {
		return nil, fmt.Errorf("failed to get node list: %v", err)
	}

	fmt.Println("Available nodes (excluding master nodes):")
	for _, node := range nodes.Items {
		fmt.Println(node.Name)
	}

	fmt.Println("\nEnter node names separated by commas (e.g., node1,node2) or 'all' to select all non-master nodes.")
	fmt.Print("Selection: ")

	reader := bufio.NewReader(os.Stdin)
	input, err := reader.ReadString('\n')
	if err != nil {
		return nil, fmt.Errorf("failed to read input: %v", err)
	}

	input = strings.TrimSpace(input)
	if input == "" {
		return nil, fmt.Errorf("no input provided")
	}

	var selectedNodes []string
	if input == "all" {
		for _, node := range nodes.Items {
			selectedNodes = append(selectedNodes, node.Name)
		}
	} else {
		selectedNodes = strings.Split(input, ",")
	}

	fmt.Printf("Selected nodes: %v\n", selectedNodes)
	return selectedNodes, nil
}

// listPodsOnNode displays pod information for the selected nodes
func listPodsOnNode(clientset *kubernetes.Clientset, nodes []string) error {
	for _, node := range nodes {
		fmt.Printf("\nPods running on node %s:\n", node)

		pods, err := clientset.CoreV1().Pods("").List(context.TODO(), metav1.ListOptions{
			FieldSelector: "spec.nodeName=" + node,
		})
		if err != nil {
			return fmt.Errorf("failed to get pod list: %v", err)
		}

		fmt.Printf("%-16s %-48s %-12s %-24s\n", "NAMESPACE", "NAME", "STATUS", "CREATED")
		for _, pod := range pods.Items {
			fmt.Printf("%-16s %-48s %-12s %-24s\n",
				pod.Namespace,
				pod.Name,
				string(pod.Status.Phase),
				pod.CreationTimestamp.Format("2006-01-02 15:04:05"),
			)
		}
	}
	return nil
}

func main() {
	// Load kubeconfig settings
	kubeconfig := os.Getenv("KUBECONFIG")
	if kubeconfig == "" {
		kubeconfig = os.Getenv("HOME") + "/.kube/config"
	}

	config, err := clientcmd.BuildConfigFromFlags("", kubeconfig)
	if err != nil {
		fmt.Printf("failed to load kubeconfig: %v\n", err)
		os.Exit(1)
	}

	// Create kubernetes client
	clientset, err := kubernetes.NewForConfig(config)
	if err != nil {
		fmt.Printf("failed to create Kubernetes client: %v\n", err)
		os.Exit(1)
	}

	// Select nodes
	selectedNodes, err := selectNode(clientset)
	if err != nil {
		fmt.Printf("failed to select nodes: %v\n", err)
		os.Exit(1)
	}

	// Display pod list for selected nodes
	if err := listPodsOnNode(clientset, selectedNodes); err != nil {
		fmt.Printf("failed to display pod list: %v\n", err)
		os.Exit(1)
	}
}
