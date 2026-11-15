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

// Command ss-test-server is a minimal Shadowsocks (AEAD) server for CI tests of the Windows VPN
// session. It is not shipped in any package. It forwards TCP and UDP to the requested targets and
// prints a running count of connections, so a test can confirm that traffic used the tunnel.
package main

import (
	"bytes"
	"encoding/binary"
	"flag"
	"fmt"
	"io"
	"log"
	"net"
	"net/netip"
	"strconv"
	"sync"
	"sync/atomic"
	"time"

	"golang.getoutline.org/sdk/transport/shadowsocks"
)

var (
	tcpConns atomic.Int64
	udpPkts  atomic.Int64
	dnsPkts  atomic.Int64
)

func main() {
	listen := flag.String("listen", "127.0.0.1:8488", "address to listen on (TCP and UDP)")
	cipher := flag.String("cipher", "chacha20-ietf-poly1305", "AEAD cipher")
	secret := flag.String("secret", "", "shared secret (required)")
	flag.Parse()
	if *secret == "" {
		log.Fatal("-secret is required")
	}
	key, err := shadowsocks.NewEncryptionKey(*cipher, *secret)
	if err != nil {
		log.Fatal(err)
	}
	tl, err := net.Listen("tcp", *listen)
	if err != nil {
		log.Fatal(err)
	}
	ul, err := net.ListenPacket("udp", *listen)
	if err != nil {
		log.Fatal(err)
	}
	log.Printf("listening on %s", tl.Addr())
	go serveUDP(ul, key)
	go func() {
		for range time.Tick(2 * time.Second) {
			fmt.Printf("STATS tcp=%d udp=%d dns=%d\n", tcpConns.Load(), udpPkts.Load(), dnsPkts.Load())
		}
	}()
	for {
		c, err := tl.Accept()
		if err != nil {
			log.Fatal(err)
		}
		go handleTCP(c, key)
	}
}

// readAddr parses a SOCKS5 address (ATYP, address, port) and returns "host:port".
func readAddr(r io.Reader) (string, error) {
	var atyp [1]byte
	if _, err := io.ReadFull(r, atyp[:]); err != nil {
		return "", err
	}
	var host string
	switch atyp[0] {
	case 1:
		var b [4]byte
		if _, err := io.ReadFull(r, b[:]); err != nil {
			return "", err
		}
		host = netip.AddrFrom4(b).String()
	case 3:
		var n [1]byte
		if _, err := io.ReadFull(r, n[:]); err != nil {
			return "", err
		}
		b := make([]byte, n[0])
		if _, err := io.ReadFull(r, b); err != nil {
			return "", err
		}
		host = string(b)
	case 4:
		var b [16]byte
		if _, err := io.ReadFull(r, b[:]); err != nil {
			return "", err
		}
		host = netip.AddrFrom16(b).Unmap().String()
	default:
		return "", fmt.Errorf("unsupported ATYP %d", atyp[0])
	}
	var port [2]byte
	if _, err := io.ReadFull(r, port[:]); err != nil {
		return "", err
	}
	return net.JoinHostPort(host, strconv.Itoa(int(binary.BigEndian.Uint16(port[:])))), nil
}

func socksAddr(a netip.AddrPort) []byte {
	var out []byte
	if a.Addr().Is4() {
		ip := a.Addr().As4()
		out = append([]byte{1}, ip[:]...)
	} else {
		ip := a.Addr().As16()
		out = append([]byte{4}, ip[:]...)
	}
	return binary.BigEndian.AppendUint16(out, a.Port())
}

func handleTCP(c net.Conn, key *shadowsocks.EncryptionKey) {
	defer c.Close()
	r := shadowsocks.NewReader(c, key)
	dst, err := readAddr(r)
	if err != nil {
		return
	}
	tc, err := net.DialTimeout("tcp", dst, 10*time.Second)
	if err != nil {
		return
	}
	defer tc.Close()
	tcpConns.Add(1)
	go func() { io.Copy(tc, r); tc.(*net.TCPConn).CloseWrite() }()
	io.Copy(shadowsocks.NewWriter(c, key), tc)
}

func serveUDP(pc net.PacketConn, key *shadowsocks.EncryptionKey) {
	var mu sync.Mutex
	assocs := map[string]*net.UDPConn{}
	buf := make([]byte, 65535)
	for {
		n, client, err := pc.ReadFrom(buf)
		if err != nil {
			return
		}
		plain, err := shadowsocks.Unpack(nil, buf[:n], key)
		if err != nil {
			continue
		}
		rd := bytes.NewReader(plain)
		dst, err := readAddr(rd)
		if err != nil {
			continue
		}
		target, err := net.ResolveUDPAddr("udp", dst)
		if err != nil {
			continue
		}
		udpPkts.Add(1)
		payload := plain[len(plain)-rd.Len():]
		if target.Port == 53 {
			// The client's DNS-leak protection blocks UDP port 53 outside the tunnel on this same
			// machine, so forward DNS queries upstream over TCP instead.
			dnsPkts.Add(1)
			go answerDNSOverTCP(pc, client, key, target, append([]byte(nil), payload...))
			continue
		}
		mu.Lock()
		conn, ok := assocs[client.String()]
		if !ok {
			conn, err = net.ListenUDP("udp", nil)
			if err != nil {
				mu.Unlock()
				continue
			}
			assocs[client.String()] = conn
			go func(client net.Addr, conn *net.UDPConn) {
				defer func() {
					mu.Lock()
					delete(assocs, client.String())
					mu.Unlock()
					conn.Close()
				}()
				rbuf := make([]byte, 65535)
				out := make([]byte, 65535+128)
				for {
					conn.SetReadDeadline(time.Now().Add(30 * time.Second))
					rn, from, err := conn.ReadFromUDPAddrPort(rbuf)
					if err != nil {
						return
					}
					src := netip.AddrPortFrom(from.Addr().Unmap(), from.Port())
					pkt, err := shadowsocks.Pack(out, append(socksAddr(src), rbuf[:rn]...), key)
					if err == nil {
						pc.WriteTo(pkt, client)
					}
				}
			}(client, conn)
		}
		mu.Unlock()
		conn.WriteToUDP(payload, target)
	}
}

func answerDNSOverTCP(pc net.PacketConn, client net.Addr, key *shadowsocks.EncryptionKey, server *net.UDPAddr, query []byte) {
	c, err := net.DialTimeout("tcp", net.JoinHostPort(server.IP.String(), "53"), 5*time.Second)
	if err != nil {
		return
	}
	defer c.Close()
	c.SetDeadline(time.Now().Add(5 * time.Second))
	if _, err := c.Write(binary.BigEndian.AppendUint16(nil, uint16(len(query)))); err != nil {
		return
	}
	if _, err := c.Write(query); err != nil {
		return
	}
	var n [2]byte
	if _, err := io.ReadFull(c, n[:]); err != nil {
		return
	}
	resp := make([]byte, binary.BigEndian.Uint16(n[:]))
	if _, err := io.ReadFull(c, resp); err != nil {
		return
	}
	src, _ := netip.AddrFromSlice(server.IP)
	out := make([]byte, len(resp)+128)
	pkt, err := shadowsocks.Pack(out, append(socksAddr(netip.AddrPortFrom(src.Unmap(), 53)), resp...), key)
	if err == nil {
		pc.WriteTo(pkt, client)
	}
}
