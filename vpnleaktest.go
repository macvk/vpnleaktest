// VPN connection test client for bash.ws.
// Project: https://github.com/macvk/vpnleaktest
// SPDX-License-Identifier: MIT

package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"
)

const (
	version   = "1.0.0"
	apiDomain = "bash.ws"
)

type vpnRecord struct {
	Type string `json:"type"`
	Text string `json:"text"`
}

type apiClient struct {
	base             string
	http             *http.Client
	networkInterface string
	probeDomain      string
	probeScheme      string
	timeout          time.Duration
}

func clientForInterfaceFamily(value string, timeout time.Duration, family int) (*http.Client, error) {
	if value == "" {
		return &http.Client{Timeout: timeout}, nil
	}

	ip := net.ParseIP(value)

	if ip == nil {
		device, err := net.InterfaceByName(value)

		if err != nil {
			return nil, err
		}

		addresses, err := device.Addrs()

		if err != nil {
			return nil, err
		}

		for _, address := range addresses {
			candidate, _, _ := net.ParseCIDR(address.String())

			if candidate == nil || candidate.IsLoopback() {
				continue
			}

			if (family == 4 && candidate.To4() == nil) || (family == 6 && candidate.To4() != nil) {
				continue
			}

			ip = candidate
			break
		}

		if ip == nil {
			if family == 0 {
				return nil, fmt.Errorf("cannot determine an address for interface %q", value)
			}

			return nil, fmt.Errorf("cannot determine an IPv%d address for interface %q", family, value)
		}
	}

	if (family == 4 && ip.To4() == nil) || (family == 6 && ip.To4() != nil) {
		return nil, fmt.Errorf("address %q is not IPv%d", value, family)
	}

	dialer := &net.Dialer{LocalAddr: &net.TCPAddr{IP: ip}}
	transport := &http.Transport{DialContext: func(ctx context.Context, network, address string) (net.Conn, error) {
		return dialer.DialContext(ctx, network, address)
	}}

	return &http.Client{Transport: transport, Timeout: timeout}, nil
}

func clientForInterface(value string, timeout time.Duration) (*http.Client, error) {
	return clientForInterfaceFamily(value, timeout, 0)
}

func newClient(base, networkInterface string, timeout time.Duration) (*apiClient, error) {
	httpClient, err := clientForInterface(networkInterface, timeout)

	if err != nil {
		return nil, err
	}

	parsed, err := url.Parse(strings.TrimRight(base, "/"))

	if err != nil || parsed.Hostname() == "" {
		return nil, errors.New("invalid API base URL")
	}

	domain, scheme := parsed.Hostname(), parsed.Scheme

	if domain == apiDomain || strings.HasSuffix(domain, "."+apiDomain) {
		domain, scheme = apiDomain, "https"
	}

	return &apiClient{
		base: strings.TrimRight(base, "/"), http: httpClient, networkInterface: networkInterface,
		probeDomain: domain, probeScheme: scheme, timeout: timeout,
	}, nil
}

func (client *apiClient) resolve(value string) string {
	if strings.HasPrefix(value, "http://") || strings.HasPrefix(value, "https://") {
		return value
	}

	return client.base + "/" + strings.TrimLeft(value, "/")
}

func (client *apiClient) request(target string, fields url.Values) ([]byte, error) {
	var body io.Reader
	method := http.MethodGet

	if fields != nil {
		method, body = http.MethodPost, strings.NewReader(fields.Encode())
	}

	request, err := http.NewRequest(method, client.resolve(target), body)

	if err != nil {
		return nil, err
	}

	request.Header.Set("User-Agent", "bash.ws vpnleaktest-go/"+version)

	if fields != nil {
		request.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	}

	response, err := client.http.Do(request)

	if err != nil {
		return nil, err
	}

	defer response.Body.Close()

	data, err := io.ReadAll(response.Body)

	if err != nil {
		return nil, err
	}

	if response.StatusCode < 200 || response.StatusCode >= 300 {
		return nil, fmt.Errorf("%s returned HTTP %d", target, response.StatusCode)
	}

	return data, nil
}

func decodeResponse(data []byte, target string, result interface{}) error {
	if err := json.Unmarshal(data, result); err != nil {
		text := strings.TrimSpace(string(data))

		if len(text) > 160 {
			text = text[:160]
		}

		if text == "" {
			text = "[empty response]"
		}

		return fmt.Errorf("invalid response from %s: %s", target, text)
	}

	return nil
}

func (client *apiClient) testID() (string, error) {
	data, err := client.request("/id", nil)

	if err != nil {
		return "", err
	}

	value := strings.ToLower(strings.TrimSpace(string(data)))

	if len(value) != 16 {
		return "", errors.New("invalid test ID returned by /id")
	}

	for _, char := range value {
		if (char < '0' || char > '9') && (char < 'a' || char > 'z') {
			return "", errors.New("invalid test ID returned by /id")
		}
	}

	return value, nil
}

func (client *apiClient) detectAddress(family, testID string) string {
	familyNumber := 4

	if family == "ipv6" {
		familyNumber = 6
	}

	httpClient, err := clientForInterfaceFamily(client.networkInterface, client.timeout, familyNumber)

	if err != nil {
		return ""
	}

	addressClient := *client
	addressClient.http = httpClient
	target := fmt.Sprintf("%s://%s.%s/myip/test/%s", client.probeScheme, family, client.probeDomain, testID)
	data, err := addressClient.request(target, nil)

	if err != nil {
		return ""
	}

	value := strings.TrimSpace(string(data))
	address := net.ParseIP(value)

	if address == nil || (familyNumber == 4 && address.To4() == nil) || (familyNumber == 6 && address.To4() != nil) {
		return ""
	}

	return value
}

func (client *apiClient) sendDNSProbes(testID string, probes, parallel int) {
	var wait sync.WaitGroup
	semaphore := make(chan struct{}, parallel)

	for index := 1; index <= probes; index++ {
		wait.Add(1)
		semaphore <- struct{}{}

		go func(number int) {
			defer wait.Done()
			defer func() { <-semaphore }()

			target := fmt.Sprintf("%s://%d.%s.%s/", client.probeScheme, number, testID, client.probeDomain)
			ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
			defer cancel()

			request, _ := http.NewRequestWithContext(ctx, http.MethodGet, target, nil)
			response, err := client.http.Do(request)

			if err == nil {
				response.Body.Close()
			}
		}(index)
	}

	wait.Wait()
}

func readTestResult(client *apiClient, target, name string, fields url.Values) error {
	data, err := client.request(target, fields)

	if err != nil {
		return err
	}

	data = bytes.TrimSpace(data)

	if len(data) == 0 {
		return fmt.Errorf("empty response from %s", target)
	}

	var records []vpnRecord

	if err := decodeResponse(data, target, &records); err != nil {
		return err
	}

	for _, record := range records {
		if record.Type == "error" {
			if record.Text == "" {
				return fmt.Errorf("%s test failed", name)
			}

			return errors.New(record.Text)
		}
	}

	return nil
}

func runTest(client *apiClient, testID, route, suffix string, fields url.Values) error {
	target := fmt.Sprintf("%s/test/%s%s?json", route, testID, suffix)
	return readTestResult(client, target, route, fields)
}

func startTest(client *apiClient, testID, route, suffix string) error {
	target := fmt.Sprintf("%s/test/%s%s", route, testID, suffix)
	data, err := client.request(target, url.Values{})

	if err != nil {
		return err
	}

	var response struct {
		Error string `json:"error"`
		Done  int    `json:"done"`
	}

	if err := decodeResponse(data, target, &response); err != nil {
		return err
	}

	if response.Error != "" {
		return errors.New(response.Error)
	}

	if response.Done != 1 {
		return errors.New("test did not complete")
	}

	return nil
}

func runDNSTest(client *apiClient, testID string, probes, parallel int) error {
	client.sendDNSProbes(testID, probes, parallel)
	time.Sleep(1500 * time.Millisecond)

	target := fmt.Sprintf("/dnsleak/test/%s?json=2", testID)
	return readTestResult(client, target, "DNS", nil)
}

func completeTest(client *apiClient, testID string, textOutput bool) ([]vpnRecord, string, error) {
	format := "json"

	if textOutput {
		format = "txt"
	}

	target := fmt.Sprintf("/vpn-leak-test/test/%s?%s", testID, format)
	data, err := client.request(target, nil)

	if err != nil {
		return nil, "", err
	}

	if textOutput {
		return nil, string(data), nil
	}

	data = bytes.TrimSpace(data)

	if len(data) == 0 {
		return nil, "", errors.New("empty VPN connection response")
	}

	var records []vpnRecord

	if err := decodeResponse(data, target, &records); err != nil {
		return nil, "", err
	}

	for _, record := range records {
		if record.Type == "error" {
			return nil, "", errors.New(record.Text)
		}
	}

	return records, "", nil
}

func fail(err error) {
	fmt.Fprintln(os.Stderr, "VPN connection check failed:", err)
	os.Exit(1)
}

type watchOption struct {
	enabled  bool
	interval int
}

func (option *watchOption) String() string {
	return strconv.Itoa(option.interval)
}

func (option *watchOption) Set(value string) error {
	option.enabled = true

	if value == "true" {
		option.interval = 0
		return nil
	}

	interval, err := strconv.Atoi(value)

	if err != nil || interval < 0 {
		return errors.New("expected zero or a positive number of seconds")
	}

	option.interval = interval
	return nil
}

func (option *watchOption) IsBoolFlag() bool {
	return true
}

func normalizeWatchArguments(arguments []string) []string {
	result := make([]string, 0, len(arguments))

	for index := 0; index < len(arguments); index++ {
		argument := arguments[index]

		if argument != "-w" && argument != "--watch" {
			result = append(result, argument)
			continue
		}

		if index+1 < len(arguments) && !strings.HasPrefix(arguments[index+1], "-") {
			argument += "=" + arguments[index+1]
			index++
		}

		result = append(result, argument)
	}

	return result
}

func main() {
	flags := flag.NewFlagSet(os.Args[0], flag.ContinueOnError)
	flags.SetOutput(os.Stderr)

	var networkInterface, apiBase string
	var probes, parallel, timeoutSeconds int
	var shortOutput, jsonOutput, showVersion, showHelp bool
	var watch watchOption

	flags.StringVar(&networkInterface, "i", "", "use a specific network interface")
	flags.StringVar(&networkInterface, "interface", "", "use a specific network interface")
	flags.IntVar(&probes, "p", 30, "number of DNS probes")
	flags.IntVar(&probes, "probes", 30, "number of DNS probes")
	flags.IntVar(&parallel, "j", 30, "maximum simultaneous DNS probes")
	flags.IntVar(&parallel, "parallel", 30, "maximum simultaneous DNS probes")
	flags.IntVar(&timeoutSeconds, "t", 90, "maximum time for each test")
	flags.IntVar(&timeoutSeconds, "timeout", 90, "maximum time for each test")
	flags.BoolVar(&shortOutput, "s", false, "print a one-line result")
	flags.BoolVar(&shortOutput, "short", false, "print a one-line result")
	flags.Var(&watch, "w", "repeat continuously in short mode (optional seconds, default: 0)")
	flags.Var(&watch, "watch", "repeat continuously in short mode (optional seconds, default: 0)")
	flags.BoolVar(&jsonOutput, "json", false, "print structured JSON")
	flags.BoolVar(&showVersion, "version", false, "show version")
	flags.BoolVar(&showHelp, "help", false, "show help")
	flags.StringVar(&apiBase, "api-base", "https://"+apiDomain, "API base URL")

	flags.Usage = func() {
		fmt.Fprintf(flags.Output(), "Usage: %s [OPTIONS]\n\n", filepath.Base(os.Args[0]))
		flags.PrintDefaults()
	}

	if err := flags.Parse(normalizeWatchArguments(os.Args[1:])); err != nil {
		if errors.Is(err, flag.ErrHelp) {
			return
		}

		os.Exit(2)
	}

	if showHelp {
		flags.Usage()
		return
	}

	if showVersion {
		fmt.Println(version)
		return
	}

	if flags.NArg() != 0 || probes < 1 || probes > 100 || parallel < 1 || parallel > 100 || timeoutSeconds < 10 || timeoutSeconds > 300 {
		flags.Usage()
		os.Exit(2)
	}

	if watch.enabled {
		shortOutput = true
		jsonOutput = false
	}

	for {
		started := time.Now()
		timeout := time.Duration(timeoutSeconds) * time.Second
		client, err := newClient(apiBase, networkInterface, timeout)

		if err != nil {
			fail(err)
		}

		testID, err := client.testID()

		if err != nil {
			fail(err)
		}

		addresses := map[string]string{}
		var addressWait sync.WaitGroup
		var addressLock sync.Mutex

		for _, family := range []string{"ipv4", "ipv6"} {
			addressWait.Add(1)

			go func(name string) {
				defer addressWait.Done()

				value := client.detectAddress(name, testID)

				addressLock.Lock()
				addresses[name] = value
				addressLock.Unlock()
			}(family)
		}

		addressWait.Wait()

		err = runDNSTest(client, testID, probes, parallel)

		if err != nil {
			fail(err)
		}

		err = startTest(client, testID, "/open-port-check", "")

		if err == nil {
			err = runTest(client, testID, "/open-port-check", "", nil)
		}

		if err != nil {
			fail(err)
		}

		for _, family := range []string{"ipv4", "ipv6"} {
			if addresses[family] == "" {
				continue
			}

			if err := startTest(client, testID, "/ip-blacklist-check", "/"+family); err != nil {
				fail(err)
			}

			if err := runTest(client, testID, "/ip-blacklist-check", "/"+family, nil); err != nil {
				fail(err)
			}
		}

		records, textResult, err := completeTest(client, testID, !jsonOutput && !shortOutput)

		if err != nil {
			fail(err)
		}

		if !jsonOutput && !shortOutput {
			fmt.Print(textResult)
			return
		}

		conclusion := ""

		for _, record := range records {
			if record.Type == "conclusion" {
				conclusion = record.Text
			}
		}

		if conclusion == "" {
			fail(errors.New("invalid conclusion returned by VPN connection check"))
		}

		if jsonOutput {
			encoder := json.NewEncoder(os.Stdout)
			encoder.SetIndent("", "  ")

			if err := encoder.Encode(records); err != nil {
				fail(err)
			}

			return
		}

		if shortOutput {
			fmt.Printf("%s %.2fs %s\n", time.Now().Format(time.RFC3339), time.Since(started).Seconds(), conclusion)
		}

		if !watch.enabled {
			return
		}

		if watch.interval > 0 {
			time.Sleep(time.Duration(watch.interval) * time.Second)
		}
	}
}
