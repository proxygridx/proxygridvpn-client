// Copyright 2026 ProxyGrid
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

package main

import (
	"os/exec"
	"strconv"
	"strings"
)

// restoreTunDNS sets the TAP adapter's DNS servers back to the given static addresses.
//
// tun.OpenTunDevice switches the adapter's address and DNS to DHCP with netsh. Without
// administrator rights both commands fail and the installer's static settings stay in place.
// With administrator rights the DNS switch can succeed while the address switch does not, which
// leaves the adapter with DHCP turned off and no DNS server. Windows then sends every query to
// the physical adapter's resolver, where the DNS-leak block drops it, so names stop resolving
// although the tunnel works. Setting the servers statically again keeps queries on the adapter.
// Without administrator rights this fails, harmlessly, like the netsh calls above.
func restoreTunDNS(tunName string, dns []string) {
	for i, server := range dns {
		server = strings.TrimSpace(server)
		if server == "" {
			continue
		}
		var cmd *exec.Cmd
		if i == 0 {
			cmd = exec.Command("netsh", "interface", "ipv4", "set", "dnsservers", "name="+tunName,
				"source=static", "address="+server, "register=none", "validate=no")
		} else {
			cmd = exec.Command("netsh", "interface", "ipv4", "add", "dnsservers", "name="+tunName,
				"address="+server, "index="+strconv.Itoa(i+1), "validate=no")
		}
		if out, err := cmd.CombinedOutput(); err != nil {
			logger.Debug("could not set the TAP adapter's DNS server", "server", server, "err", err,
				"output", strings.TrimSpace(string(out)))
			return
		}
	}
	logger.Debug("set the TAP adapter's DNS servers", "servers", dns)
}
