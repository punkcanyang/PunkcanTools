use std::process::Command;
use serde::{Deserialize, Serialize};

/// Nmap status info
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NmapStatus {
    pub installed: bool,
    pub version: Option<String>,
    pub path: Option<String>,
}

/// Check if nmap is installed
pub fn check_nmap() -> NmapStatus {
    match Command::new("nmap").arg("--version").output() {
        Ok(output) => {
            let stdout = String::from_utf8_lossy(&output.stdout).to_string();
            let version = stdout
                .lines()
                .find(|line| line.contains("Nmap version"))
                .map(|line| {
                    line.trim()
                        .replace("Nmap version ", "")
                        .split(' ')
                        .next()
                        .unwrap_or("unknown")
                        .to_string()
                });
            
            let path = Command::new("which").arg("nmap").output()
                .ok()
                .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string());
            
            NmapStatus {
                installed: true,
                version,
                path,
            }
        }
        Err(_) => NmapStatus {
            installed: false,
            version: None,
            path: None,
        },
    }
}

/// Install nmap via brew (macOS)
pub fn install_nmap() -> Result<String, String> {
    // Check if brew is available
    let brew_check = Command::new("which").arg("brew").output();
    match brew_check {
        Ok(output) if output.status.success() => {
            // Install via brew
            let install = Command::new("brew")
                .arg("install")
                .arg("nmap")
                .output()
                .map_err(|e| format!("Failed to run brew: {}", e))?;
            
            if install.status.success() {
                Ok("nmap 安裝成功！".to_string())
            } else {
                let stderr = String::from_utf8_lossy(&install.stderr).to_string();
                Err(format!("安裝失敗: {}", stderr))
            }
        }
        _ => {
            Err("未找到 Homebrew。請先安裝 Homebrew: https://brew.sh".to_string())
        }
    }
}

/// OS detection result from nmap
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OsDetectResult {
    pub ip: String,
    pub os_name: Option<String>,
    pub os_accuracy: Option<u32>,
    pub os_family: Option<String>,
    pub os_vendor: Option<String>,
    pub mac_address: Option<String>,
    pub mac_vendor: Option<String>,
    pub method: String,  // "nmap" or "banner" or "ttl"
}

/// Run nmap OS detection on a single IP (requires root/sudo)
pub async fn nmap_os_detect(ip: &str) -> OsDetectResult {
    // Try nmap OS detection
    let output = Command::new("nmap")
        .args(&["-O", "--osscan-guess", "-T4", ip])
        .output();
    
    match output {
        Ok(out) => {
            let stdout = String::from_utf8_lossy(&out.stdout).to_string();
            parse_nmap_os_output(ip, &stdout)
        }
        Err(_) => OsDetectResult {
            ip: ip.to_string(),
            os_name: None,
            os_accuracy: None,
            os_family: None,
            os_vendor: None,
            mac_address: None,
            mac_vendor: None,
            method: "failed".to_string(),
        },
    }
}

/// Run nmap service/version detection (does not require root)
pub async fn nmap_service_detect(ip: &str) -> OsDetectResult {
    let output = Command::new("nmap")
        .args(&["-sV", "-T4", "--version-light", ip])
        .output();
    
    match output {
        Ok(out) => {
            let stdout = String::from_utf8_lossy(&out.stdout).to_string();
            let mut result = OsDetectResult {
                ip: ip.to_string(),
                os_name: None,
                os_accuracy: None,
                os_family: None,
                os_vendor: None,
                mac_address: None,
                mac_vendor: None,
                method: "nmap-sV".to_string(),
            };
            
            // Parse MAC address
            for line in stdout.lines() {
                let line = line.trim();
                if line.starts_with("MAC Address:") {
                    let parts: Vec<&str> = line.splitn(3, ' ').collect();
                    if parts.len() >= 3 {
                        result.mac_address = Some(parts[2].to_string());
                        // Extract vendor from parentheses
                        if let Some(start) = line.find('(') {
                            if let Some(end) = line.find(')') {
                                result.mac_vendor = Some(line[start+1..end].to_string());
                            }
                        }
                    }
                }
                
                // Try to infer OS from service versions
                if line.contains("OpenSSH") {
                    if line.contains("Ubuntu") {
                        result.os_name = Some(format!("Ubuntu ({})", extract_version(line, "OpenSSH")));
                        result.os_family = Some("Linux".to_string());
                        result.os_vendor = Some("Canonical".to_string());
                    } else if line.contains("Debian") {
                        result.os_name = Some(format!("Debian ({})", extract_version(line, "OpenSSH")));
                        result.os_family = Some("Linux".to_string());
                        result.os_vendor = Some("Debian".to_string());
                    }
                }
                if line.contains("Microsoft") || line.contains("Windows") {
                    result.os_family = Some("Windows".to_string());
                    result.os_vendor = Some("Microsoft".to_string());
                }
                if line.contains("Apache") && line.contains("Unix") {
                    result.os_family = Some("Unix/Linux".to_string());
                }
            }
            
            result
        }
        Err(_) => OsDetectResult {
            ip: ip.to_string(),
            os_name: None,
            os_accuracy: None,
            os_family: None,
            os_vendor: None,
            mac_address: None,
            mac_vendor: None,
            method: "failed".to_string(),
        },
    }
}

/// Parse nmap -O output
fn parse_nmap_os_output(ip: &str, output: &str) -> OsDetectResult {
    let mut result = OsDetectResult {
        ip: ip.to_string(),
        os_name: None,
        os_accuracy: None,
        os_family: None,
        os_vendor: None,
        mac_address: None,
        mac_vendor: None,
        method: "nmap".to_string(),
    };
    
    for line in output.lines() {
        let line = line.trim();
        
        // Parse OS detection results
        // "Running: Microsoft Windows 10"
        if line.starts_with("Running:") {
            result.os_name = Some(line.replace("Running: ", "").trim().to_string());
        }
        
        // "Aggressive OS guesses: Linux 5.4 (97%), ..."
        if line.starts_with("Aggressive OS guesses:") && result.os_name.is_none() {
            let guesses = line.replace("Aggressive OS guesses: ", "");
            if let Some(first_guess) = guesses.split(',').next() {
                // Extract name and accuracy: "Linux 5.4 (97%)"
                if let Some(paren_start) = first_guess.rfind('(') {
                    let name = first_guess[..paren_start].trim().to_string();
                    let accuracy_str = &first_guess[paren_start+1..first_guess.len()-1];
                    let accuracy = accuracy_str.replace('%', "").trim().parse::<u32>().ok();
                    result.os_name = Some(name);
                    result.os_accuracy = accuracy;
                } else {
                    result.os_name = Some(first_guess.trim().to_string());
                }
            }
        }
        
        // "OS details: Microsoft Windows 10 1903 - 2004"
        if line.starts_with("OS details:") {
            result.os_name = Some(line.replace("OS details: ", "").trim().to_string());
        }
        
        // "Device type: general purpose"
        if line.starts_with("OS CPE:") {
            let cpe = line.replace("OS CPE: ", "");
            // cpe:/o:microsoft:windows_10 => vendor=microsoft, family=Windows
            for part in cpe.split(' ') {
                let segments: Vec<&str> = part.split(':').collect();
                if segments.len() >= 4 {
                    result.os_vendor = Some(capitalize(segments[3]));
                    if segments.len() >= 5 {
                        result.os_family = Some(capitalize(segments[4].replace('_', " ").as_str()));
                    }
                }
            }
        }
        
        // "MAC Address: AA:BB:CC:DD:EE:FF (Vendor Name)"
        if line.starts_with("MAC Address:") {
            let content = line.replace("MAC Address: ", "");
            let parts: Vec<&str> = content.splitn(2, ' ').collect();
            if !parts.is_empty() {
                result.mac_address = Some(parts[0].to_string());
            }
            if parts.len() > 1 {
                let vendor = parts[1].trim_start_matches('(').trim_end_matches(')');
                result.mac_vendor = Some(vendor.to_string());
            }
        }
    }
    
    result
}

/// Extract version info from a line
fn extract_version(line: &str, product: &str) -> String {
    if let Some(pos) = line.find(product) {
        let after = &line[pos..];
        after.split_whitespace()
            .take(2)
            .collect::<Vec<&str>>()
            .join(" ")
    } else {
        product.to_string()
    }
}

/// Capitalize first letter
fn capitalize(s: &str) -> String {
    let mut c = s.chars();
    match c.next() {
        None => String::new(),
        Some(f) => f.to_uppercase().collect::<String>() + c.as_str(),
    }
}
