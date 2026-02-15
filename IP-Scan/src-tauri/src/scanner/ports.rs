use std::net::{Ipv4Addr, SocketAddr};
use std::time::Duration;
use serde::{Deserialize, Serialize};
use tokio::time::timeout;

/// Common ports to scan
pub const COMMON_PORTS: &[(u16, &str)] = &[
    (21, "FTP"),
    (22, "SSH"),
    (23, "Telnet"),
    (25, "SMTP"),
    (53, "DNS"),
    (80, "HTTP"),
    (110, "POP3"),
    (139, "NetBIOS"),
    (143, "IMAP"),
    (443, "HTTPS"),
    (445, "SMB"),
    (993, "IMAPS"),
    (995, "POP3S"),
    (1433, "MSSQL"),
    (1521, "Oracle"),
    (3306, "MySQL"),
    (3389, "RDP"),
    (5432, "PostgreSQL"),
    (5900, "VNC"),
    (6379, "Redis"),
    (8080, "HTTP-Alt"),
    (8443, "HTTPS-Alt"),
    (9200, "Elasticsearch"),
    (27017, "MongoDB"),
];

/// Result of a port scan
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PortResult {
    pub port: u16,
    pub is_open: bool,
    pub service: String,
}

/// Scan a single port on a host
pub async fn scan_port(ip: Ipv4Addr, port: u16) -> PortResult {
    let addr = SocketAddr::from((ip, port));
    
    let is_open = match timeout(
        Duration::from_millis(300),
        tokio::net::TcpStream::connect(addr)
    ).await {
        Ok(Ok(_)) => true,
        _ => false,
    };
    
    let service = COMMON_PORTS
        .iter()
        .find(|(p, _)| *p == port)
        .map(|(_, s)| s.to_string())
        .unwrap_or_else(|| "Unknown".to_string());
    
    PortResult {
        port,
        is_open,
        service,
    }
}

/// Scan common ports on a host
pub async fn scan_common_ports(ip: Ipv4Addr) -> Vec<PortResult> {
    use futures::stream::{self, StreamExt};
    
    let ports: Vec<u16> = COMMON_PORTS.iter().map(|(p, _)| *p).collect();
    
    let results: Vec<PortResult> = stream::iter(ports)
        .map(|port| scan_port(ip, port))
        .buffer_unordered(24)
        .filter(|r| futures::future::ready(r.is_open))
        .collect()
        .await;
    
    results
}

/// Identify device type based on open ports
pub fn identify_device_type(open_ports: &[PortResult]) -> &'static str {
    let port_nums: Vec<u16> = open_ports.iter().map(|p| p.port).collect();
    
    // Check for server types
    if port_nums.contains(&80) || port_nums.contains(&443) || port_nums.contains(&8080) {
        if port_nums.contains(&3306) || port_nums.contains(&5432) || port_nums.contains(&27017) {
            return "Web Server + Database";
        }
        return "Web Server";
    }
    
    if port_nums.contains(&22) && port_nums.len() == 1 {
        return "SSH Server";
    }
    
    if port_nums.contains(&3389) {
        return "Windows Desktop/Server";
    }
    
    if port_nums.contains(&139) || port_nums.contains(&445) {
        return "File Server (SMB)";
    }
    
    if port_nums.contains(&23) {
        return "Network Device";
    }
    
    if port_nums.is_empty() {
        return "Unknown";
    }
    
    "Server"
}
