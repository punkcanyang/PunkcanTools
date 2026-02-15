mod scanner;

use scanner::{network, ping, ports, nmap, banner};
use serde::{Deserialize, Serialize};
use std::net::Ipv4Addr;
use std::sync::Arc;
use std::path::PathBuf;
use tokio::sync::Mutex;
use tauri::{State, Emitter};
use std::fs;
use std::time::SystemTime;

/// Device information gathered from scanning
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct DeviceInfo {
    pub ip: String,
    pub is_alive: bool,
    pub latency_ms: Option<f64>,
    pub ttl: Option<u8>,
    pub os_guess: String,
    pub os_detail: Option<String>,
    pub os_accuracy: Option<u32>,
    pub os_method: String,
    pub mac: Option<String>,
    pub vendor: String,
    pub open_ports: Vec<ports::PortResult>,
    pub device_type: String,
    pub banners: Vec<banner::BannerResult>,
}

/// Scan progress state
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct ScanProgress {
    pub phase: String,
    pub current: usize,
    pub total: usize,
    pub found_devices: usize,
}

/// Scan profile for saving/loading
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ScanProfile {
    pub id: String,
    pub name: String,
    pub network: String,
    pub created_at: String,
    pub updated_at: String,
    pub devices: Vec<DeviceInfo>,
}

/// Profile summary for listing (without full device data)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProfileSummary {
    pub id: String,
    pub name: String,
    pub network: String,
    pub created_at: String,
    pub updated_at: String,
    pub device_count: usize,
}

/// Shared scan state
pub struct ScanState {
    pub is_scanning: Arc<Mutex<bool>>,
    pub progress: Arc<Mutex<ScanProgress>>,
    pub results: Arc<Mutex<Vec<DeviceInfo>>>,
}

impl Default for ScanState {
    fn default() -> Self {
        Self {
            is_scanning: Arc::new(Mutex::new(false)),
            progress: Arc::new(Mutex::new(ScanProgress::default())),
            results: Arc::new(Mutex::new(Vec::new())),
        }
    }
}

/// Get local network suggestion
#[tauri::command]
fn get_local_network() -> Option<String> {
    network::get_local_network()
}

/// Check nmap status
#[tauri::command]
fn check_nmap_status() -> nmap::NmapStatus {
    nmap::check_nmap()
}

/// Install nmap
#[tauri::command]
async fn install_nmap_cmd() -> Result<String, String> {
    // Run install in blocking context since it calls brew
    tokio::task::spawn_blocking(|| nmap::install_nmap())
        .await
        .map_err(|e| format!("Task error: {}", e))?
}

/// Start network scan
#[tauri::command]
async fn start_scan(
    app: tauri::AppHandle,
    network_input: String,
    scan_ports: bool,
    scan_banner: bool,
    scan_os: bool,
    skip_ips: Option<Vec<String>>,
    state: State<'_, ScanState>,
) -> Result<(), String> {
    // Check if already scanning
    {
        let mut is_scanning = state.is_scanning.lock().await;
        if *is_scanning {
            return Err("Scan already in progress".to_string());
        }
        *is_scanning = true;
    }

    // Clear previous results
    {
        let mut results = state.results.lock().await;
        results.clear();
    }

    // Check nmap availability (only if OS detection is enabled)
    let nmap_available = if scan_os { nmap::check_nmap().installed } else { false };

    // Parse network input
    let mut ips = network::parse_network(&network_input)?;

    // Filter out skipped IPs if provided
    if let Some(ref skip) = skip_ips {
        ips.retain(|ip| !skip.contains(&ip.to_string()));
    }
    let total_ips = ips.len();

    // Update progress - ping phase
    let _ = app.emit("scan-progress", ScanProgress {
        phase: "Pinging hosts...".to_string(),
        current: 0,
        total: total_ips,
        found_devices: 0,
    });

    // Ping all hosts with progress updates
    let ping_results = {
        use futures::stream::{self, StreamExt};
        
        let mut results: Vec<ping::PingResult> = Vec::new();
        let mut completed = 0usize;

        let mut stream = stream::iter(ips.clone())
            .map(|ip| ping::ping_host(ip))
            .buffer_unordered(80);

        while let Some(result) = stream.next().await {
            completed += 1;

            // Ping 到存活主机，立即发送简化版设备信息
            if result.is_alive {
                let preliminary_device = DeviceInfo {
                    ip: result.ip.clone(),
                    is_alive: true,
                    latency_ms: result.latency_ms,
                    ttl: result.ttl,
                    os_guess: result.ttl
                        .map(|t| ping::guess_os_from_ttl(t).to_string())
                        .unwrap_or_else(|| "Unknown".to_string()),
                    os_method: "ttl".to_string(),
                    vendor: "Unknown".to_string(),
                    device_type: "Unknown".to_string(),
                    ..Default::default()
                };
                let _ = app.emit("device-found", preliminary_device);
            }

            let alive_count = results.iter().filter(|r| r.is_alive).count()
                + if result.is_alive { 1 } else { 0 };
            
            let _ = app.emit("scan-progress", ScanProgress {
                phase: "Pinging hosts...".to_string(),
                current: completed,
                total: total_ips,
                found_devices: alive_count,
            });
            
            results.push(result);
        }
        
        results
    };

    // Filter alive hosts
    let alive_hosts: Vec<_> = ping_results.iter()
        .filter(|r| r.is_alive)
        .collect();

    let alive_count = alive_hosts.len();

    // Build phase name
    let phase_name = if scan_ports && scan_os && nmap_available {
        "Scanning ports & OS (nmap)..."
    } else if scan_ports && scan_banner {
        "Scanning ports & banners..."
    } else if scan_ports {
        "Scanning ports..."
    } else {
        "Processing..."
    };
    let _ = app.emit("scan-progress", ScanProgress {
        phase: phase_name.to_string(),
        current: 0,
        total: alive_count,
        found_devices: alive_count,
    });

    let mut devices: Vec<DeviceInfo> = Vec::new();
    let mut scanned = 0;

    for ping_result in alive_hosts {
        let ip: Ipv4Addr = ping_result.ip.parse().unwrap();
        
        // Scan ports (if enabled)
        let open_ports = if scan_ports {
            ports::scan_common_ports(ip).await
        } else {
            Vec::new()
        };
        
        // Determine device type
        let device_type = ports::identify_device_type(&open_ports);
        
        // Grab banners (if enabled and has open ports)
        let banners = if scan_banner && !open_ports.is_empty() {
            let open_port_nums: Vec<u16> = open_ports.iter().map(|p| p.port).collect();
            banner::grab_banners(ip, &open_port_nums).await
        } else {
            Vec::new()
        };
        
        // OS detection
        let (os_guess, os_detail, os_accuracy, os_method, mac, vendor) = if scan_os {
            if nmap_available {
                let nmap_result = nmap::nmap_service_detect(&ping_result.ip).await;
                
                let has_nmap_os = nmap_result.os_name.is_some();
                let has_banner_os = banners.iter().any(|b| b.os_hint.is_some());
                
                let method = if has_nmap_os {
                    "nmap"
                } else if has_banner_os {
                    "banner"
                } else {
                    "ttl"
                };
                
                let os_name = nmap_result.os_name
                    .or_else(|| banners.iter().filter_map(|b| b.os_hint.clone()).next())
                    .or_else(|| ping_result.ttl.map(|ttl| ping::guess_os_from_ttl(ttl).to_string()))
                    .unwrap_or_else(|| "Unknown".to_string());
                
                (
                    os_name,
                    nmap_result.os_family,
                    nmap_result.os_accuracy,
                    method.to_string(),
                    nmap_result.mac_address,
                    nmap_result.mac_vendor.unwrap_or_else(|| "Unknown".to_string()),
                )
            } else {
                // Banner/TTL only
                let os_from_banner = banners.iter().filter_map(|b| b.os_hint.clone()).next();
                let os_guess = os_from_banner.clone()
                    .or_else(|| ping_result.ttl.map(|ttl| ping::guess_os_from_ttl(ttl).to_string()))
                    .unwrap_or_else(|| "Unknown".to_string());
                let method = if os_from_banner.is_some() { "banner" } else { "ttl" };
                (os_guess, None, None, method.to_string(), None, "Unknown".to_string())
            }
        } else {
            // OS detection disabled - just use TTL
            let os_guess = ping_result.ttl
                .map(|ttl| ping::guess_os_from_ttl(ttl).to_string())
                .unwrap_or_else(|| "Unknown".to_string());
            (os_guess, None, None, "ttl".to_string(), None, "Unknown".to_string())
        };
        
        let device = DeviceInfo {
            ip: ping_result.ip.clone(),
            is_alive: true,
            latency_ms: ping_result.latency_ms,
            ttl: ping_result.ttl,
            os_guess,
            os_detail,
            os_accuracy,
            os_method,
            mac,
            vendor,
            open_ports,
            device_type: device_type.to_string(),
            banners,
        };
        
        devices.push(device.clone());
        
        scanned += 1;
        let _ = app.emit("scan-progress", ScanProgress {
            phase: phase_name.to_string(),
            current: scanned,
            total: alive_count,
            found_devices: alive_count,
        });
        
        let _ = app.emit("device-updated", device);
    }

    // Save results
    {
        let mut results = state.results.lock().await;
        *results = devices;
    }

    // Mark scan as complete
    {
        let mut is_scanning = state.is_scanning.lock().await;
        *is_scanning = false;
    }

    let _ = app.emit("scan-complete", ());

    Ok(())
}

/// Stop current scan
#[tauri::command]
async fn stop_scan(state: State<'_, ScanState>) -> Result<(), String> {
    let mut is_scanning = state.is_scanning.lock().await;
    *is_scanning = false;
    Ok(())
}

/// Get current scan results
#[tauri::command]
async fn get_scan_results(state: State<'_, ScanState>) -> Result<Vec<DeviceInfo>, String> {
    let results = state.results.lock().await;
    Ok(results.clone())
}

/// Get scan progress
#[tauri::command]
async fn get_scan_progress(state: State<'_, ScanState>) -> Result<ScanProgress, String> {
    let progress = state.progress.lock().await;
    Ok(progress.clone())
}

/// Scan ports for a specific IP
#[tauri::command]
async fn scan_device_ports(ip: String) -> Result<Vec<ports::PortResult>, String> {
    let ip_addr: Ipv4Addr = ip.parse()
        .map_err(|_| "Invalid IP address")?;
    Ok(ports::scan_common_ports(ip_addr).await)
}

/// Open connection tool for a specific port
#[tauri::command]
async fn open_connection(ip: String, port: u16) -> Result<String, String> {
    let url = match port {
        22 => format!("ssh://{}", ip),
        80 | 8080 => format!("http://{}:{}", ip, port),
        443 => "https://".to_string() + &ip,
        8443 => format!("https://{}:{}", ip, port),
        3389 => format!("rdp://full%20address=s:{}:3389", ip),
        5900 => format!("vnc://{}", ip),
        445 | 139 => format!("smb://{}", ip),
        21 => format!("ftp://{}", ip),
        _ => return Err(format!("Port {} 無對應的連線工具", port)),
    };
    std::process::Command::new("open")
        .arg(&url)
        .spawn()
        .map_err(|e| format!("啟動失敗: {}", e))?;
    Ok(format!("已開啟 {}", url))
}

/// Get connection string for a specific port
#[tauri::command]
fn get_connection_string(ip: String, port: u16) -> Result<String, String> {
    match port {
        22 => Ok(format!("ssh root@{}", ip)),
        3306 => Ok(format!("mysql -h {} -u root -p", ip)),
        5432 => Ok(format!("psql -h {} -U postgres", ip)),
        6379 => Ok(format!("redis-cli -h {}", ip)),
        27017 => Ok(format!("mongosh mongodb://{}:27017", ip)),
        1433 => Ok(format!("sqlcmd -S {} -U sa", ip)),
        1521 => Ok(format!("sqlplus user/pass@{}:1521/ORCL", ip)),
        9200 => Ok(format!("curl http://{}:9200", ip)),
        80 | 8080 => Ok(format!("curl http://{}:{}", ip, port)),
        443 | 8443 => Ok(format!("curl https://{}:{}", ip, port)),
        _ => Err(format!("Port {} 無預設連線字串", port)),
    }
}

/// Grab banner from a single port
#[tauri::command]
async fn grab_port_banner(ip: String, port: u16) -> Result<banner::BannerResult, String> {
    let ip_addr: Ipv4Addr = ip.parse().map_err(|_| "Invalid IP")?;
    banner::grab_banner(ip_addr, port).await
        .ok_or_else(|| "無法取得 Banner 資訊".to_string())
}

/// Get profiles directory path
fn get_profiles_dir() -> Result<PathBuf, String> {
    let home = std::env::var("HOME").map_err(|_| "無法取得 HOME 目錄".to_string())?;
    let dir = PathBuf::from(home).join(".ip-scan").join("profiles");
    if !dir.exists() {
        fs::create_dir_all(&dir).map_err(|e| format!("建立目錄失敗: {}", e))?;
    }
    Ok(dir)
}

/// Generate ISO 8601 timestamp
fn now_iso8601() -> String {
    let dur = SystemTime::now()
        .duration_since(SystemTime::UNIX_EPOCH)
        .unwrap_or_default();
    let secs = dur.as_secs();
    // Simple ISO 8601 format
    let days = secs / 86400;
    let rem = secs % 86400;
    let h = rem / 3600;
    let m = (rem % 3600) / 60;
    let s = rem % 60;
     // Calculate date from days since epoch
    let (year, month, day) = days_to_date(days);
    format!("{:04}-{:02}-{:02}T{:02}:{:02}:{:02}Z", year, month, day, h, m, s)
}

fn days_to_date(days: u64) -> (u64, u64, u64) {
    let mut y = 1970;
    let mut remaining = days;
    loop {
        let days_in_year = if is_leap(y) { 366 } else { 365 };
        if remaining < days_in_year { break; }
        remaining -= days_in_year;
        y += 1;
    }
    let months: [u64; 12] = if is_leap(y) {
        [31,29,31,30,31,30,31,31,30,31,30,31]
    } else {
        [31,28,31,30,31,30,31,31,30,31,30,31]
    };
    let mut m = 0;
    for days_in_month in months.iter() {
        if remaining < *days_in_month { break; }
        remaining -= days_in_month;
        m += 1;
    }
    (y, m + 1, remaining + 1)
}

fn is_leap(y: u64) -> bool {
    (y % 4 == 0 && y % 100 != 0) || (y % 400 == 0)
}

/// Save scan profile
#[tauri::command]
fn save_profile(name: String, network: String, devices: Vec<DeviceInfo>) -> Result<ProfileSummary, String> {
    let dir = get_profiles_dir()?;
    let id = format!("{:x}", rand::random::<u64>());
    let now = now_iso8601();
    let profile = ScanProfile {
        id: id.clone(),
        name: name.clone(),
        network: network.clone(),
        created_at: now.clone(),
        updated_at: now.clone(),
        devices: devices.clone(),
    };
    let path = dir.join(format!("{}.json", id));
    let json = serde_json::to_string_pretty(&profile)
        .map_err(|e| format!("序列化失敗: {}", e))?;
    fs::write(&path, json).map_err(|e| format!("寫入失敗: {}", e))?;
    Ok(ProfileSummary {
        id,
        name,
        network,
        created_at: profile.created_at,
        updated_at: profile.updated_at,
        device_count: profile.devices.len(),
    })
}

/// List all profiles
#[tauri::command]
fn list_profiles() -> Result<Vec<ProfileSummary>, String> {
    let dir = get_profiles_dir()?;
    let mut profiles = Vec::new();
    let entries = fs::read_dir(&dir).map_err(|e| format!("讀取目錄失敗: {}", e))?;
    for entry in entries {
        let entry = entry.map_err(|e| format!("讀取項目失敗: {}", e))?;
        let path = entry.path();
        if path.extension().and_then(|e| e.to_str()) == Some("json") {
            if let Ok(content) = fs::read_to_string(&path) {
                if let Ok(profile) = serde_json::from_str::<ScanProfile>(&content) {
                    profiles.push(ProfileSummary {
                        id: profile.id,
                        name: profile.name,
                        network: profile.network,
                        created_at: profile.created_at,
                        updated_at: profile.updated_at,
                        device_count: profile.devices.len(),
                    });
                }
            }
        }
    }
    profiles.sort_by(|a, b| b.updated_at.cmp(&a.updated_at));
    Ok(profiles)
}

/// Load a specific profile
#[tauri::command]
fn load_profile(id: String) -> Result<ScanProfile, String> {
    let dir = get_profiles_dir()?;
    let path = dir.join(format!("{}.json", id));
    let content = fs::read_to_string(&path)
        .map_err(|e| format!("讀取失敗: {}", e))?;
    serde_json::from_str(&content)
        .map_err(|e| format!("解析失敗: {}", e))
}

/// Delete a profile
#[tauri::command]
fn delete_profile(id: String) -> Result<(), String> {
    let dir = get_profiles_dir()?;
    let path = dir.join(format!("{}.json", id));
    fs::remove_file(&path).map_err(|e| format!("刪除失敗: {}", e))
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .manage(ScanState::default())
        .invoke_handler(tauri::generate_handler![
            get_local_network,
            check_nmap_status,
            install_nmap_cmd,
            start_scan,
            stop_scan,
            get_scan_results,
            get_scan_progress,
            scan_device_ports,
            open_connection,
            get_connection_string,
            grab_port_banner,
            save_profile,
            list_profiles,
            load_profile,
            delete_profile,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
