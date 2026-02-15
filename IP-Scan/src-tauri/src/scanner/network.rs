use ipnetwork::IpNetwork;
use std::net::Ipv4Addr;

/// Parse CIDR notation or IP range and return a list of IP addresses
pub fn parse_network(input: &str) -> Result<Vec<Ipv4Addr>, String> {
    let input = input.trim();

    // Try parsing as CIDR (e.g., 192.168.1.0/24)
    if input.contains('/') {
        return parse_cidr(input);
    }

    // Try parsing as range (e.g., 192.168.1.1-254)
    if input.contains('-') {
        return parse_range(input);
    }

    // Try parsing as single IP
    match input.parse::<Ipv4Addr>() {
        Ok(ip) => Ok(vec![ip]),
        Err(_) => Err(format!("Invalid IP format: {}", input)),
    }
}

/// Parse CIDR notation (e.g., 192.168.1.0/24)
fn parse_cidr(input: &str) -> Result<Vec<Ipv4Addr>, String> {
    let network: IpNetwork = input.parse().map_err(|e| format!("Invalid CIDR: {}", e))?;

    match network {
        IpNetwork::V4(net) => {
            let ips: Vec<Ipv4Addr> = net
                .iter()
                .filter(|ip| {
                    // Skip network and broadcast addresses for /24 and larger
                    let octets = ip.octets();
                    if net.prefix() >= 24 {
                        octets[3] != 0 && octets[3] != 255
                    } else {
                        true
                    }
                })
                .collect();
            Ok(ips)
        }
        IpNetwork::V6(_) => Err("IPv6 not supported yet".to_string()),
    }
}

/// Parse IP range (e.g., 192.168.1.1-254 or 192.168.1.1-192.168.1.254)
fn parse_range(input: &str) -> Result<Vec<Ipv4Addr>, String> {
    let parts: Vec<&str> = input.split('-').collect();
    if parts.len() != 2 {
        return Err("Invalid range format".to_string());
    }

    let start_ip: Ipv4Addr;
    let end_val: u8;

    // Check if it's a full IP range or just last octet
    if parts[1].contains('.') {
        // Full IP range: 192.168.1.1-192.168.1.254
        start_ip = parts[0].parse().map_err(|_| "Invalid start IP")?;
        let end_ip: Ipv4Addr = parts[1].parse().map_err(|_| "Invalid end IP")?;

        let start_octets = start_ip.octets();
        let end_octets = end_ip.octets();

        // Ensure same network prefix
        if start_octets[0..3] != end_octets[0..3] {
            return Err("Start and end IP must be in same /24 network".to_string());
        }

        end_val = end_octets[3];
    } else {
        // Last octet only: 192.168.1.1-254
        start_ip = parts[0].parse().map_err(|_| "Invalid start IP")?;
        end_val = parts[1].parse().map_err(|_| "Invalid end value")?;
    }

    let start_octets = start_ip.octets();
    let start_val = start_octets[3];

    if start_val > end_val {
        return Err("Start must be less than or equal to end".to_string());
    }

    let ips: Vec<Ipv4Addr> = (start_val..=end_val)
        .map(|last| Ipv4Addr::new(start_octets[0], start_octets[1], start_octets[2], last))
        .collect();

    Ok(ips)
}

/// Get local network interface info
pub fn get_local_network() -> Option<String> {
    // Try to detect local network automatically
    let interface = pnet::datalink::interfaces()
        .into_iter()
        .find(|iface| iface.is_up() && !iface.is_loopback() && !iface.ips.is_empty());

    if let Some(iface) = interface {
        for ip in &iface.ips {
            if let ipnetwork::IpNetwork::V4(net) = ip {
                return Some(format!("{}/{}", net.network(), net.prefix()));
            }
        }
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_cidr() {
        let ips = parse_network("192.168.1.0/24").unwrap();
        assert_eq!(ips.len(), 254); // .1 to .254
        assert_eq!(ips[0], Ipv4Addr::new(192, 168, 1, 1));
        assert_eq!(ips[253], Ipv4Addr::new(192, 168, 1, 254));
    }

    #[test]
    fn test_parse_range() {
        let ips = parse_network("192.168.1.1-10").unwrap();
        assert_eq!(ips.len(), 10);
    }
}
