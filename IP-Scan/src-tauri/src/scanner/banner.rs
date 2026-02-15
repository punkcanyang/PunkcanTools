use std::net::Ipv4Addr;
use std::time::Duration;
use tokio::io::AsyncReadExt;
use tokio::net::TcpStream;
use tokio::time::timeout;
use serde::{Deserialize, Serialize};

/// Banner grab result
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BannerResult {
    pub port: u16,
    pub banner: String,
    pub service_info: String,
    pub os_hint: Option<String>,
}

/// Grab banner from a specific port
pub async fn grab_banner(ip: Ipv4Addr, port: u16) -> Option<BannerResult> {
    let addr = format!("{}:{}", ip, port);
    
    let stream = match timeout(Duration::from_millis(2000), TcpStream::connect(&addr)).await {
        Ok(Ok(s)) => s,
        _ => return None,
    };
    
    // Some services send banner on connect, others need a probe
    let banner = match port {
        80 | 8080 | 443 | 8443 => grab_http_banner(stream).await,
        _ => grab_raw_banner(stream).await,
    };
    
    banner.map(|b| {
        let os_hint = detect_os_from_banner(&b, port);
        let service_info = detect_service_from_banner(&b, port);
        BannerResult {
            port,
            banner: b,
            service_info,
            os_hint,
        }
    })
}

/// Read raw banner (for SSH, FTP, SMTP, etc.)
async fn grab_raw_banner(mut stream: TcpStream) -> Option<String> {
    let mut buf = vec![0u8; 1024];
    match timeout(Duration::from_millis(2000), stream.read(&mut buf)).await {
        Ok(Ok(n)) if n > 0 => {
            let banner = String::from_utf8_lossy(&buf[..n]).trim().to_string();
            if !banner.is_empty() {
                Some(banner)
            } else {
                None
            }
        }
        _ => None,
    }
}

/// Send HTTP request and read response banner
async fn grab_http_banner(mut stream: TcpStream) -> Option<String> {
    use tokio::io::AsyncWriteExt;
    
    let request = "GET / HTTP/1.1\r\nHost: target\r\nConnection: close\r\n\r\n";
    if stream.write_all(request.as_bytes()).await.is_err() {
        return None;
    }
    
    let mut buf = vec![0u8; 4096];
    match timeout(Duration::from_millis(3000), stream.read(&mut buf)).await {
        Ok(Ok(n)) if n > 0 => {
            let response = String::from_utf8_lossy(&buf[..n]).to_string();
            // Only return headers
            if let Some(header_end) = response.find("\r\n\r\n") {
                Some(response[..header_end].to_string())
            } else {
                Some(response.chars().take(500).collect())
            }
        }
        _ => None,
    }
}

/// Detect OS from banner content
fn detect_os_from_banner(banner: &str, port: u16) -> Option<String> {
    let lower = banner.to_lowercase();
    
    // SSH banners
    if port == 22 || lower.starts_with("ssh-") {
        if lower.contains("ubuntu") {
            return Some(infer_ubuntu_version(banner));
        }
        if lower.contains("debian") {
            return Some(format!("Debian Linux ({})", extract_ssh_version(banner)));
        }
        if lower.contains("centos") || lower.contains("el7") || lower.contains("el8") || lower.contains("el9") {
            return Some("CentOS/RHEL Linux".to_string());
        }
        if lower.contains("freebsd") {
            return Some("FreeBSD".to_string());
        }
        // Generic OpenSSH version can hint at OS
        if let Some(ver) = extract_ssh_version(banner).strip_prefix("OpenSSH_") {
            if let Some(major) = ver.split('.').next() {
                if let Ok(v) = major.parse::<u32>() {
                    return Some(format!("Linux/Unix (OpenSSH {})", ver.split_whitespace().next().unwrap_or(ver)));
                }
            }
        }
    }
    
    // HTTP Server headers
    if lower.contains("server:") {
        if lower.contains("microsoft-iis") {
            if lower.contains("iis/10") {
                return Some("Windows Server 2016/2019/2022 or Windows 10/11".to_string());
            }
            if lower.contains("iis/8.5") {
                return Some("Windows Server 2012 R2 or Windows 8.1".to_string());
            }
            if lower.contains("iis/8.0") {
                return Some("Windows Server 2012 or Windows 8".to_string());
            }
            if lower.contains("iis/7.5") {
                return Some("Windows Server 2008 R2 or Windows 7".to_string());
            }
            return Some("Windows Server (IIS)".to_string());
        }
        if lower.contains("apache") {
            if lower.contains("ubuntu") {
                return Some("Ubuntu Linux (Apache)".to_string());
            }
            if lower.contains("debian") {
                return Some("Debian Linux (Apache)".to_string());
            }
            if lower.contains("centos") || lower.contains("red hat") {
                return Some("CentOS/RHEL (Apache)".to_string());
            }
            if lower.contains("unix") {
                return Some("Unix/Linux (Apache)".to_string());
            }
        }
        if lower.contains("nginx") {
            return Some("Linux (Nginx)".to_string());
        }
    }
    
    // FTP banners
    if port == 21 {
        if lower.contains("microsoft ftp") {
            return Some("Windows (Microsoft FTP)".to_string());
        }
        if lower.contains("vsftpd") {
            return Some("Linux (vsftpd)".to_string());
        }
        if lower.contains("proftpd") {
            return Some("Linux (ProFTPD)".to_string());
        }
    }
    
    // RDP
    if port == 3389 {
        return Some("Windows".to_string());
    }
    
    None
}

/// Detect service name from banner
fn detect_service_from_banner(banner: &str, port: u16) -> String {
    let lower = banner.to_lowercase();
    
    if lower.starts_with("ssh-") {
        return extract_ssh_version(banner);
    }
    if lower.contains("220") && (port == 21 || lower.contains("ftp")) {
        return format!("FTP: {}", banner.lines().next().unwrap_or(""));
    }
    if lower.contains("http/") {
        if let Some(server_line) = banner.lines().find(|l| l.to_lowercase().starts_with("server:")) {
            return server_line.trim().to_string();
        }
        return "HTTP Service".to_string();
    }
    if lower.contains("smtp") || lower.contains("220") && port == 25 {
        return format!("SMTP: {}", banner.lines().next().unwrap_or(""));
    }
    
    // Truncate long banners
    banner.chars().take(80).collect()
}

/// Extract SSH version string
fn extract_ssh_version(banner: &str) -> String {
    banner.lines()
        .next()
        .unwrap_or("")
        .trim()
        .to_string()
}

/// Infer Ubuntu version from OpenSSH version
fn infer_ubuntu_version(banner: &str) -> String {
    let lower = banner.to_lowercase();
    
    // OpenSSH version mapping to Ubuntu versions
    if lower.contains("openssh_9.6") {
        "Ubuntu 24.04 LTS".to_string()
    } else if lower.contains("openssh_8.9") {
        "Ubuntu 22.04 LTS".to_string()
    } else if lower.contains("openssh_8.2") || lower.contains("openssh_8.4") {
        "Ubuntu 20.04 LTS".to_string()
    } else if lower.contains("openssh_7.6") {
        "Ubuntu 18.04 LTS".to_string()
    } else if lower.contains("openssh_7.2") {
        "Ubuntu 16.04 LTS".to_string()
    } else {
        format!("Ubuntu Linux ({})", extract_ssh_version(banner))
    }
}

/// Grab banners from multiple ports
pub async fn grab_banners(ip: Ipv4Addr, ports: &[u16]) -> Vec<BannerResult> {
    let mut results = Vec::new();
    
    for &port in ports {
        if let Some(banner) = grab_banner(ip, port).await {
            results.push(banner);
        }
    }
    
    results
}
