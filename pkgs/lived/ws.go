package main

import (
	"bufio"
	"crypto/rand"
	"crypto/sha1"
	"crypto/tls"
	"encoding/base64"
	"encoding/binary"
	"fmt"
	"io"
	"net"
	"net/url"
	"strings"
	"sync"
	"time"
)

const wsGUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

// Minimal RFC 6455 WebSocket client using Go standard library only.
type wsClient struct {
	conn net.Conn
	r    *bufio.Reader
	mu   sync.Mutex
}

func dialWS(rawURL string, secret string) (*wsClient, error) {
	u, err := url.Parse(rawURL)
	if err != nil {
		return nil, err
	}

	host := u.Host
	if !strings.Contains(host, ":") {
		if u.Scheme == "wss" || u.Scheme == "https" {
			host += ":443"
		} else {
			host += ":80"
		}
	}

	var conn net.Conn
	dialer := &net.Dialer{Timeout: 10 * time.Second}
	if u.Scheme == "wss" || u.Scheme == "https" {
		conn, err = tls.DialWithDialer(dialer, "tcp", host, &tls.Config{
			ServerName: u.Hostname(),
		})
	} else {
		conn, err = dialer.Dial("tcp", host)
	}
	if err != nil {
		return nil, err
	}

	var keyBytes [16]byte
	_, _ = rand.Read(keyBytes[:])
	secKey := base64.StdEncoding.EncodeToString(keyBytes[:])

	path := u.RequestURI()
	if path == "" {
		path = "/"
	}

	var req strings.Builder
	fmt.Fprintf(&req, "GET %s HTTP/1.1\r\n", path)
	fmt.Fprintf(&req, "Host: %s\r\n", u.Host)
	req.WriteString("Upgrade: websocket\r\n")
	req.WriteString("Connection: Upgrade\r\n")
	fmt.Fprintf(&req, "Sec-WebSocket-Key: %s\r\n", secKey)
	req.WriteString("Sec-WebSocket-Version: 13\r\n")
	if secret != "" {
		fmt.Fprintf(&req, "Authorization: Bearer %s\r\n", secret)
	}
	req.WriteString("\r\n")

	_ = conn.SetDeadline(time.Now().Add(10 * time.Second))
	if _, err := conn.Write([]byte(req.String())); err != nil {
		conn.Close()
		return nil, err
	}

	br := bufio.NewReader(conn)
	statusLine, err := br.ReadString('\n')
	if err != nil {
		conn.Close()
		return nil, err
	}
	if !strings.Contains(statusLine, "101") {
		conn.Close()
		return nil, fmt.Errorf("websocket handshake failed: %s", strings.TrimSpace(statusLine))
	}

	expectedAccept := computeAcceptKey(secKey)
	gotAccept := ""
	for {
		line, err := br.ReadString('\n')
		if err != nil {
			conn.Close()
			return nil, err
		}
		line = strings.TrimRight(line, "\r\n")
		if line == "" {
			break
		}
		if parts := strings.SplitN(line, ":", 2); len(parts) == 2 {
			if strings.EqualFold(strings.TrimSpace(parts[0]), "Sec-WebSocket-Accept") {
				gotAccept = strings.TrimSpace(parts[1])
			}
		}
	}
	if gotAccept != expectedAccept {
		conn.Close()
		return nil, fmt.Errorf("invalid Sec-WebSocket-Accept")
	}

	_ = conn.SetDeadline(time.Time{})
	return &wsClient{conn: conn, r: br}, nil
}

func computeAcceptKey(key string) string {
	h := sha1.New()
	h.Write([]byte(key))
	h.Write([]byte(wsGUID))
	return base64.StdEncoding.EncodeToString(h.Sum(nil))
}

func (c *wsClient) WriteText(msg []byte) error {
	return c.writeFrame(0x1, msg)
}

func (c *wsClient) writeFrame(opcode byte, payload []byte) error {
	c.mu.Lock()
	defer c.mu.Unlock()

	var frame []byte
	frame = append(frame, 0x80|opcode) // FIN + opcode

	length := len(payload)
	switch {
	case length < 126:
		frame = append(frame, 0x80|byte(length))
	case length <= 65535:
		frame = append(frame, 0x80|126)
		var ext [2]byte
		binary.BigEndian.PutUint16(ext[:], uint16(length))
		frame = append(frame, ext[:]...)
	default:
		frame = append(frame, 0x80|127)
		var ext [8]byte
		binary.BigEndian.PutUint64(ext[:], uint64(length))
		frame = append(frame, ext[:]...)
	}

	var mask [4]byte
	_, _ = rand.Read(mask[:])
	frame = append(frame, mask[:]...)

	masked := make([]byte, length)
	for i := range length {
		masked[i] = payload[i] ^ mask[i%4]
	}
	frame = append(frame, masked...)

	_ = c.conn.SetWriteDeadline(time.Now().Add(10 * time.Second))
	_, err := c.conn.Write(frame)
	return err
}

func (c *wsClient) ReadMessage() ([]byte, error) {
	for {
		var hdr [2]byte
		if _, err := io.ReadFull(c.r, hdr[:]); err != nil {
			return nil, err
		}
		opcode := hdr[0] & 0x0f
		masked := (hdr[1] & 0x80) != 0
		length := uint64(hdr[1] & 0x7f)

		switch length {
		case 126:
			var ext [2]byte
			if _, err := io.ReadFull(c.r, ext[:]); err != nil {
				return nil, err
			}
			length = uint64(binary.BigEndian.Uint16(ext[:]))
		case 127:
			var ext [8]byte
			if _, err := io.ReadFull(c.r, ext[:]); err != nil {
				return nil, err
			}
			length = binary.BigEndian.Uint64(ext[:])
		}

		if length > 1024*1024 {
			return nil, fmt.Errorf("ws frame too large: %d", length)
		}

		var mask [4]byte
		if masked {
			if _, err := io.ReadFull(c.r, mask[:]); err != nil {
				return nil, err
			}
		}

		payload := make([]byte, length)
		if length > 0 {
			if _, err := io.ReadFull(c.r, payload); err != nil {
				return nil, err
			}
		}
		if masked {
			for i := range payload {
				payload[i] ^= mask[i%4]
			}
		}

		switch opcode {
		case 0x1, 0x2: // text or binary
			return payload, nil
		case 0x8: // close
			return nil, io.EOF
		case 0x9: // ping -> reply pong
			_ = c.writeFrame(0xA, payload)
		case 0xA: // pong
			continue
		}
	}
}

func (c *wsClient) Close() {
	_ = c.writeFrame(0x8, nil)
	_ = c.conn.Close()
}
