#!/usr/bin/env node
/**
 * Generates self-signed TLS certificates for TermAway HTTPS/WSS support.
 * Certificates are stored in ~/.termaway/certs/
 */

import { execFileSync } from 'child_process';
import { existsSync, mkdirSync, chmodSync } from 'fs';
import os from 'os';
import path from 'path';

const TERMAWAY_DIR = path.join(os.homedir(), '.termaway');
const CERTS_DIR = path.join(TERMAWAY_DIR, 'certs');
const KEY_PATH = path.join(CERTS_DIR, 'server.key');
const CERT_PATH = path.join(CERTS_DIR, 'server.crt');

// Create directories if they don't exist
if (!existsSync(TERMAWAY_DIR)) {
  mkdirSync(TERMAWAY_DIR, { recursive: true });
  console.log(`Created ${TERMAWAY_DIR}`);
}

if (!existsSync(CERTS_DIR)) {
  mkdirSync(CERTS_DIR, { recursive: true });
  console.log(`Created ${CERTS_DIR}`);
}

// Check if certificates already exist
if (existsSync(KEY_PATH) && existsSync(CERT_PATH)) {
  console.log('Certificates already exist:');
  console.log(`  Key:  ${KEY_PATH}`);
  console.log(`  Cert: ${CERT_PATH}`);
  console.log('\nTo regenerate, delete these files and run again.');
  process.exit(0);
}

// Get hostname and local IP for certificate
const hostname = os.hostname();
const localIP = getLocalIP();

console.log('Generating self-signed certificates...');
console.log(`  Hostname: ${hostname}`);
console.log(`  Local IP: ${localIP}`);

// Generate self-signed certificate using openssl
const opensslArgs = [
  'req', '-x509', '-newkey', 'rsa:2048', '-nodes',
  '-keyout', KEY_PATH,
  '-out', CERT_PATH,
  '-days', '365',
  '-subj', '/CN=TermAway/O=TermAway/C=US',
  '-addext', `subjectAltName=DNS:localhost,DNS:${hostname},DNS:${hostname}.local,IP:127.0.0.1,IP:${localIP}`
];

try {
  execFileSync('openssl', opensslArgs, { stdio: 'pipe' });

  // Set restrictive permissions on key
  chmodSync(KEY_PATH, 0o600);
  chmodSync(CERT_PATH, 0o644);

  console.log('\nCertificates generated successfully:');
  console.log(`  Key:  ${KEY_PATH}`);
  console.log(`  Cert: ${CERT_PATH}`);
  console.log('\nRestart TermAway server to use HTTPS/WSS.');
  console.log('\nNote: Since this is a self-signed certificate, you\'ll need to');
  console.log('accept the security warning in your browser on first connection.');
} catch (error) {
  console.error('Failed to generate certificates:', error.message);
  console.error('\nMake sure openssl is installed on your system.');
  process.exit(1);
}

function getLocalIP() {
  const interfaces = os.networkInterfaces();
  for (const name of Object.keys(interfaces)) {
    for (const iface of interfaces[name]) {
      if (iface.family === 'IPv4' && !iface.internal) {
        return iface.address;
      }
    }
  }
  return '127.0.0.1';
}
