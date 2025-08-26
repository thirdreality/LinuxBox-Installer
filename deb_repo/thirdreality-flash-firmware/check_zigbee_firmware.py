#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# Simplified version: only get BL702 MAC, App Version and Stack Version

import serial
import struct
import time
import binascii
import sys

class AccurateBL702Test:
    def __init__(self, verbose=False):
        self.ser = None
        self.tx_seq = 0  # TX sequence number
        self.verbose = verbose
        
    def compute_crc(self, data):
        """Compute CRC-16 (same algorithm as firmware/logs)."""
        def calc_crc16(new_byte, prev_result):
            prev_result = ((prev_result >> 8) | (prev_result << 8)) & 0xFFFF
            prev_result ^= new_byte
            prev_result ^= (prev_result & 0xFF) >> 4
            prev_result ^= ((prev_result << 8) << 4) & 0xFFFF
            prev_result ^= (((prev_result & 0xFF) << 5) | ((prev_result & 0xFF) >> 3) << 8) & 0xFFFF
            return prev_result
        
        crc16 = 0xFFFF
        for byte in data:
            crc16 = calc_crc16(byte, crc16)
        return struct.pack('>H', crc16)  # big-endian bytes
    
    def escape_frame(self, data):
        """Escape frame payload bytes."""
        escaped = bytearray()
        for byte in data:
            if byte in (0x42, 0x4C, 0x07):
                escaped.append(0x07)
                escaped.append(byte ^ 0x10)
            else:
                escaped.append(byte)
        return bytes(escaped)
    
    def unescape_frame(self, data):
        """Unescape frame payload bytes."""
        unescaped = bytearray()
        it = iter(data)
        for byte in it:
            if byte == 0x07:
                unescaped.append(next(it) ^ 0x10)
            else:
                unescaped.append(byte)
        return bytes(unescaped)
    
    def build_frame(self, frame_id, payload=b''):
        """Build a complete frame."""
        # As seen in logs: frmCtrl=0x00, combined seq byte
        seq = (self.tx_seq << 4) | 0  # TX seq in high 4 bits, RX seq = 0
        
        # Frame: frmCtrl + seq + frame_id (little-endian) + payload
        frame_data = struct.pack('<BBH', 0x00, seq, frame_id) + payload
        
        # Compute CRC and append
        crc = self.compute_crc(frame_data)
        frame_with_crc = frame_data + crc
        
        # Escape
        escaped = self.escape_frame(frame_with_crc)
        
        # Add frame delimiters
        final_frame = bytes([0x42]) + escaped + bytes([0x4C])
        
        # Advance sequence number
        self.tx_seq = (self.tx_seq + 1) % 16
        
        return final_frame
    
    def connect(self):
        """Open serial port."""
        try:
            self.ser = serial.Serial('/dev/ttyAML3', 2000000, timeout=3)
            return True
        except Exception as e:
            return False
    
    def disconnect(self):
        """Close serial port."""
        if self.ser and self.ser.is_open:
            self.ser.close()
    
    def send_frame(self, frame):
        """Send a frame."""
        if not self.ser or not self.ser.is_open:
            return False
        self.ser.write(frame)
        self.ser.flush()
        return True
    
    def wait_for_frame(self, expected_frame_ids, timeout=3.0):
        """Wait for a frame with an expected frame_id; ACK and ignore others."""
        buffer = bytearray()
        start_time = time.time()

        def try_extract_one():
            nonlocal buffer
            start_idx = buffer.find(0x42)
            if start_idx == -1:
                buffer.clear()
                return None
            stop_idx = buffer.find(0x4C, start_idx + 1)
            if stop_idx == -1:
                return None

            raw_frame = buffer[start_idx:stop_idx + 1]
            frame_body = buffer[start_idx + 1:stop_idx]
            buffer = buffer[stop_idx + 1:]

            if len(frame_body) == 0:
                return None

            unescaped = self.unescape_frame(frame_body)

            if len(unescaped) < 6:
                return None

            frmCtrl, seq, frame_id = struct.unpack('<BBH', unescaped[:4])

            # ACK any data frame
            self.send_ack(unescaped)

            if frame_id in expected_frame_ids:
                return unescaped
            else:
                return None

        while time.time() - start_time < timeout:
            if self.ser.in_waiting > 0:
                chunk = self.ser.read(self.ser.in_waiting)
                buffer.extend(chunk)

                while True:
                    fr = try_extract_one()
                    if fr is not None:
                        return fr
                    if buffer.find(0x42) == -1:
                        break

            time.sleep(0.01)

        return None
    
    def send_ack(self, received_frame):
        """Send ACK frame."""
        if len(received_frame) < 2:
            return
        
        rx_seq = received_frame[1] & 0x0F  # extract RX sequence
        tx_seq = rx_seq << 4  # ACK's TX sequence
        
        ack_data = struct.pack('<BBH', 0x00, tx_seq, 0x0001)  # ACK frame_id = 0x0001
        crc = self.compute_crc(ack_data)
        ack_frame_with_crc = ack_data + crc
        escaped = self.escape_frame(ack_frame_with_crc)
        final_ack = bytes([0x42]) + escaped + bytes([0x4C])
        
        self.ser.write(final_ack)
        self.ser.flush()
    
    def parse_get_value_response(self, frame_data):
        """Parse GET_VALUE response."""
        if len(frame_data) < 6:
            return None
        
        frmCtrl, seq, frame_id = struct.unpack('<BBH', frame_data[:4])
        payload = frame_data[4:-2]  # strip CRC
        
        if frame_id == 0x0010 and len(payload) >= 2:  # GET_VALUE response
            status = payload[0]
            value_length = payload[1]
            value = payload[2:2+value_length] if len(payload) >= 2+value_length else b''
            
            if status == 0:
                return value
        
        return None
    
    def network_init(self):
        """Network initialization."""
        # Send NETWORK_INIT (0x0034)
        frame = self.build_frame(0x0034)
        if not self.send_frame(frame):
            return False
        
        # Wait for 0x0034 response; ignore 0x0035 callbacks
        response = self.wait_for_frame({0x0034}, timeout=5.0)
        return response is not None
    
    def get_mac_address(self):
        """Read MAC address."""
        # Build GET_VALUE for value_id = 0x20
        payload = struct.pack('<B', 0x20)
        frame = self.build_frame(0x0010, payload)
        
        if not self.send_frame(frame):
            return None
        
        # Wait for 0x0010 response; ignore other frames
        response = self.wait_for_frame({0x0010}, timeout=5.0)
        if response:
            value = self.parse_get_value_response(response)
            
            if value and len(value) == 8:
                # Example: raw 00005ae24c75e14c (LE) -> 4c:e1:75:4c:e2:5a:00:00
                mac_str = ':'.join(f'{b:02x}' for b in reversed(value))
                return mac_str
        
        return None
    
    def get_app_version(self):
        """Read application version."""
        # Build GET_VALUE for value_id = 0x21
        payload = struct.pack('<B', 0x21)
        frame = self.build_frame(0x0010, payload)
        
        if not self.send_frame(frame):
            return None
        
        # Wait for 0x0010 response; ignore other frames
        response = self.wait_for_frame({0x0010}, timeout=5.0)
        if response:
            value = self.parse_get_value_response(response)
            
            if value:
                try:
                    version = value.decode('utf-8').rstrip('\x00')
                    return version
                except:
                    version_hex = binascii.hexlify(value).decode()
                    return version_hex
        
        return None

    def get_stack_version(self):
        """Read stack version (build, major, minor, patch)."""
        payload = struct.pack('<B', 0x01)  # BLZ_VALUE_ID_STACK_VERSION
        frame = self.build_frame(0x0010, payload)
        if not self.send_frame(frame):
            return None
        response = self.wait_for_frame({0x0010}, timeout=5.0)
        if response:
            value = self.parse_get_value_response(response)
            if value and len(value) >= 5:
                build = value[0] | (value[1] << 8)
                major = value[2]
                minor = value[3]
                patch = value[4]
                return f"{major}.{minor}.{patch} (build {build})"
        return None

def main():
    """Main function - only get and display MAC, App Version and Stack Version"""
    try:
        tester = AccurateBL702Test(verbose=False)
        if not tester.connect():
            print("Failed to connect to BL702")
            sys.exit(1)
        
        try:
            # Flush pending RX
            time.sleep(0.1)
            if tester.ser.in_waiting > 0:
                tester.ser.read(tester.ser.in_waiting)
            
            # Network init
            if not tester.network_init():
                print("Network init failed, continue...")
            
            time.sleep(0.5)
            
            # Read MAC
            mac = tester.get_mac_address()
            print(f"MAC: {mac if mac else 'Failed'}")
            
            time.sleep(0.5)
            
            # Read application version
            version = tester.get_app_version()
            print(f"App Version: {version if version else 'Failed'}")
            
            time.sleep(0.5)
            
            # Read stack version
            stack_ver = tester.get_stack_version()
            print(f"Stack Version: {stack_ver if stack_ver else 'Failed'}")
            
        finally:
            tester.disconnect()
            
    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
