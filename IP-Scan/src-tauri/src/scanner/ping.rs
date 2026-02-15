use std::net::{Ipv4Addr, SocketAddr};
use std::time::Duration;
use serde::{Deserialize, Serialize};
use tokio::time::timeout;

/// Result of pinging a single host
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PingResult {
    pub ip: String,
    pub is_alive: bool,
    pub latency_ms: Option<f64>,
    pub ttl: Option<u8>,
}

/// Quick probe ports — if any responds (connect or refused), host is alive
const PROBE_PORTS: &[u16] = &[80, 443, 22, 445, 139, 8080, 53, 3389];

/// Fast host discovery using TCP connect probe
/// Much faster than spawning system ping processes
pub async fn ping_host(ip: Ipv4Addr) -> PingResult {
    let ip_str = ip.to_string();
    let start = std::time::Instant::now();
    
    // Try TCP connect to common ports (100ms timeout each, all concurrent)
    let mut futs = Vec::new();
    for &port in PROBE_PORTS {
        let addr = SocketAddr::from((ip, port));
        futs.push(tcp_probe(addr));
    }
    
    let results = futures::future::join_all(futs).await;
    let tcp_alive = results.iter().any(|r| *r);
    
    if tcp_alive {
        let latency = start.elapsed().as_secs_f64() * 1000.0;
        // Get TTL via quick system ping (background, short timeout)
        let ttl = get_ttl_fast(ip).await;
        return PingResult {
            ip: ip_str,
            is_alive: true,
            latency_ms: Some(latency),
            ttl,
        };
    }
    
    // Fallback: system ping for hosts that don't have open TCP ports
    // (e.g. routers that only respond to ICMP)
    let ping_result = system_ping(ip).await;
    if ping_result.is_alive {
        return ping_result;
    }
    
    PingResult {
        ip: ip_str,
        is_alive: false,
        latency_ms: None,
        ttl: None,
    }
}

/// TCP connect probe — returns true if host is alive
/// A connection success OR "connection refused" both mean the host is up
async fn tcp_probe(addr: SocketAddr) -> bool {
    match timeout(
        Duration::from_millis(150),
        tokio::net::TcpStream::connect(addr),
    ).await {
        Ok(Ok(_)) => true,        // Port open = host alive
        Ok(Err(e)) => {
            // Connection refused = host is alive, just port closed
            let err_str = e.to_string();
            err_str.contains("refused") || err_str.contains("reset")
        }
        Err(_) => false,           // Timeout = probably no host
    }
}

/// Get TTL value via a quick system ping (non-blocking)
async fn get_ttl_fast(ip: Ipv4Addr) -> Option<u8> {
    let ip_str = ip.to_string();
    
    let output = timeout(
        Duration::from_millis(800),
        tokio::process::Command::new("ping")
            .args(&["-c", "1", "-W", "500", &ip_str])
            .output()
    ).await;
    
    match output {
        Ok(Ok(output)) if output.status.success() => {
            let stdout = String::from_utf8_lossy(&output.stdout).to_lowercase();
            stdout
                .split("ttl=")
                .nth(1)
                .and_then(|s| s.split_whitespace().next())
                .and_then(|s| s.parse::<u8>().ok())
        }
        _ => None,
    }
}

/// System ping fallback for ICMP-only hosts
async fn system_ping(ip: Ipv4Addr) -> PingResult {
    let ip_str = ip.to_string();
    
    let output = timeout(
        Duration::from_millis(1200),
        tokio::process::Command::new("ping")
            .args(&["-c", "1", "-W", "800", &ip_str])
            .output()
    ).await;
    
    match output {
        Ok(Ok(output)) if output.status.success() => {
            let stdout = String::from_utf8_lossy(&output.stdout);
            
            let latency_ms = stdout
                .split("time=")
                .nth(1)
                .and_then(|s| s.split_whitespace().next())
                .and_then(|s| s.parse::<f64>().ok());
            
            let ttl = stdout.to_lowercase()
                .split("ttl=")
                .nth(1)
                .and_then(|s| s.split_whitespace().next())
                .and_then(|s| s.parse::<u8>().ok());
            
            PingResult {
                ip: ip_str,
                is_alive: true,
                latency_ms,
                ttl,
            }
        }
        _ => PingResult {
            ip: ip_str,
            is_alive: false,
            latency_ms: None,
            ttl: None,
        },
    }
}

/// Estimate OS based on TTL value
pub fn guess_os_from_ttl(ttl: u8) -> &'static str {
    match ttl {
        1..=64 => "Linux/macOS/iOS",
        65..=128 => "Windows",
        129..=255 => "Network Device (Router/Switch)",
        _ => "Unknown",
    }
}
