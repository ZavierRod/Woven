"""
mDNS/Bonjour service advertisement for automatic backend discovery.
"""
import socket
import logging
from typing import Optional

logger = logging.getLogger(__name__)

try:
    from zeroconf import ServiceInfo, Zeroconf, IPVersion
    ZEROCONF_AVAILABLE = True
except ImportError:
    ZEROCONF_AVAILABLE = False
    logger.warning("zeroconf not available. Install with: pip install zeroconf")


def get_local_ip() -> Optional[str]:
    """Get the local IP address of this machine."""
    try:
        # Connect to a remote address to determine local IP
        # This doesn't actually send data
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.settimeout(0)
        try:
            # Try to connect to a non-routable address
            s.connect(('10.254.254.254', 1))
            ip = s.getsockname()[0]
        except Exception:
            ip = '127.0.0.1'
        finally:
            s.close()
        return ip
    except Exception:
        return None


class MDNSService:
    """Handles mDNS service advertisement."""
    
    def __init__(self, port: int = 8001):
        self.port = port
        self.zeroconf: Optional[Zeroconf] = None
        self.service_info: Optional[ServiceInfo] = None
        self._is_advertising = False
    
    def start(self) -> bool:
        """Start advertising the service via mDNS."""
        if not ZEROCONF_AVAILABLE:
            logger.warning("zeroconf not available, skipping mDNS advertisement")
            return False
        
        try:
            local_ip = get_local_ip()
            if not local_ip or local_ip == '127.0.0.1':
                logger.warning("Could not determine local IP address, skipping mDNS")
                return False
            
            # Create service info
            service_type = "_woven-api._tcp.local."
            service_name = "Woven API._woven-api._tcp.local."
            
            self.service_info = ServiceInfo(
                service_type,
                service_name,
                addresses=[socket.inet_aton(local_ip)],
                port=self.port,
                properties={"version": "1.0"},
                server=f"{socket.gethostname()}.local.",
            )
            
            self.zeroconf = Zeroconf(ip_version=IPVersion.V4Only)
            self.zeroconf.register_service(self.service_info)
            self._is_advertising = True
            
            logger.info(f"mDNS service advertised: {service_name} at {local_ip}:{self.port}")
            return True
            
        except Exception as e:
            logger.error(f"Failed to start mDNS service: {e}")
            return False
    
    def stop(self):
        """Stop advertising the service."""
        if self.zeroconf and self.service_info and self._is_advertising:
            try:
                self.zeroconf.unregister_service(self.service_info)
                self.zeroconf.close()
                self._is_advertising = False
                logger.info("mDNS service stopped")
            except Exception as e:
                logger.error(f"Error stopping mDNS service: {e}")
    
    def __enter__(self):
        self.start()
        return self
    
    def __exit__(self, exc_type, exc_val, exc_tb):
        self.stop()


# Global instance
mdns_service = MDNSService()

