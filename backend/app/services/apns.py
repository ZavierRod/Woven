import os
import time
import jwt
import httpx
import json
from typing import Dict, Any, Optional

class APNsService:
    """Send push notifications via Apple Push Notification service."""
    
    def __init__(self):
        self.team_id = os.getenv("APNS_TEAM_ID")
        self.key_id = os.getenv("APNS_KEY_ID")
        self.key_path = os.getenv("APNS_KEY_PATH")
        self.bundle_id = os.getenv("APNS_BUNDLE_ID")
        self._token = None
        self._token_generated_at = 0
        
    def _get_jwt_token(self) -> str:
        """Generate or return valid JWT for APNs authentication."""
        now = time.time()
        # Refresh token if it's older than 50 minutes (valid for 1 hour)
        if self._token and (now - self._token_generated_at) < 3000:
            return self._token
            
        if not self.key_path or not os.path.exists(self.key_path):
            print(f"⚠️ APNs key not found at {self.key_path}")
            return None
            
        with open(self.key_path, 'r') as f:
            secret = f.read()
            
        algorithm = 'ES256'
        headers = {
            'alg': algorithm,
            'kid': self.key_id,
        }
        payload = {
            'iss': self.team_id,
            'iat': int(now)
        }
        
        token = jwt.encode(payload, secret, algorithm=algorithm, headers=headers)
        self._token = token
        self._token_generated_at = now
        return token

    async def send_notification(
        self,
        device_token: str,
        title: str,
        body: str,
        data: Dict[str, Any] = None,
        environment: str = "sandbox"
    ) -> bool:
        """Send notification via HTTP/2 to APNs."""
        jwt_token = self._get_jwt_token()
        if not jwt_token:
            return False
            
        # Determine endpoint
        if environment == "production":
            endpoint = "https://api.push.apple.com"
        else:
            endpoint = "https://api.development.push.apple.com"
            
        url = f"{endpoint}/3/device/{device_token}"
        
        headers = {
            "authorization": f"bearer {jwt_token}",
            "apns-topic": self.bundle_id,
            "apns-push-type": "alert",
            "apns-priority": "10",
        }
        
        payload = {
            "aps": {
                "alert": {
                    "title": title,
                    "body": body,
                },
                "sound": "default",
                "badge": 1
            }
        }
        
        if data:
            payload.update(data)
            
        async with httpx.AsyncClient(http2=True) as client:
            try:
                response = await client.post(
                    url,
                    headers=headers,
                    content=json.dumps(payload),
                    timeout=10.0
                )
                
                if response.status_code == 200:
                    print(f"✅ Push sent to {device_token[:8]}...")
                    return True
                else:
                    print(f"❌ Push failed: {response.status_code} - {response.text}")
                    if response.status_code == 410:
                        # Token expired, should remove from DB (handled by caller ideally)
                        pass
                    return False
            except Exception as e:
                print(f"❌ Push error: {e}")
                return False

apns_service = APNsService()
