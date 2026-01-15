
import requests
import uuid
import time

BASE_URL = "http://localhost:8000"

def get_auth_headers(token):
    return {"Authorization": f"Bearer {token}"}

def register_user(username, password):
    email = f"{username}@test.com"
    resp = requests.post(f"{BASE_URL}/auth/signup", json={
        "email": email,
        "password": password,
        "username": username,
        "full_name": username
    })
    if resp.status_code == 201:
        data = resp.json()
        return data["access_token"], data["user_id"], data["invite_code"]
    # If user exists, login
    resp = requests.post(f"{BASE_URL}/auth/login", json={
        "identifier": email,
        "password": password
    })
    if resp.status_code == 200:
        data = resp.json()
        return data["access_token"], data["user_id"], data["invite_code"]
    print(f"Failed to register/login {username}: {resp.text}")
    return None, None, None

def test_vault_flow():
    print("--- Starting Vault Flow Test ---")
    
    # 1. Register Users
    suffix = str(uuid.uuid4())[:8]
    token1, uid1, invite1 = register_user(f"user_a_{suffix}", "password123")
    token2, uid2, invite2 = register_user(f"user_b_{suffix}", "password123")
    
    if not token1 or not token2:
        print("Failed to authenticate users")
        return

    headers1 = get_auth_headers(token1)
    headers2 = get_auth_headers(token2)

    # 2. Make them friends (needed for Pair Vault)
    # Check if already friends
    resp = requests.get(f"{BASE_URL}/friends/", headers=headers1)
    # FriendListResponse model has 'friends' key
    friends = [f["id"] for f in resp.json()["friends"]]
    if uid2 not in friends:
        print("Sending friend request...")
        # Use invite_code, not user_id
        requests.post(f"{BASE_URL}/friends/request", headers=headers1, json={"invite_code": invite2})
        # Accept
        print("Accepting friend request...")
        # Get request ID
        resp = requests.get(f"{BASE_URL}/friends/requests/pending", headers=headers2)
        # PendingRequestsResponse has 'requests' key
        reqs = resp.json()["requests"]
        print(f"DEBUG: Pending requests for User B: {reqs}")
        print(f"DEBUG: Looking for sender {uid1}")
        
        # In pending requests, user_id is the sender
        req_id = next((r["id"] for r in reqs if r["user_id"] == uid1), None)
        if req_id:
            requests.post(f"{BASE_URL}/friends/requests/{req_id}/accept", headers=headers2)
        else:
            print("Friend request lookup failed/already connected")
    
    # 3. Create Solo Vault 1
    print("Creating Solo Vault 1...")
    resp = requests.post(f"{BASE_URL}/vaults/", headers=headers1, json={
        "name": "Solo 1",
        "type": "solo"
    })
    if resp.status_code == 201:
        v1 = resp.json()
        print(f"Created Solo 1: {v1['id']} Status: {v1.get('status')}")
    else:
        print(f"Failed to create Solo 1: {resp.text}")

    # 4. Create Solo Vault 2 (Test Limit)
    print("Creating Solo Vault 2...")
    resp = requests.post(f"{BASE_URL}/vaults/", headers=headers1, json={
        "name": "Solo 2",
        "type": "solo"
    })
    if resp.status_code == 201:
        v2 = resp.json()
        print(f"Created Solo 2: {v2['id']} (Multiple vaults working)")
    else:
        print(f"Failed to create Solo 2: {resp.text} (Limit/Bug exists)")

    # 5. Create Pair Vault (Invite User B)
    print("Creating Pair Vault...")
    resp = requests.post(f"{BASE_URL}/vaults/", headers=headers1, json={
        "name": "Pair Vault",
        "type": "pair",
        "invitee_id": uid2
    })
    pair_id = None
    if resp.status_code == 201:
        pv = resp.json()
        pair_id = pv["id"]
        print(f"Created Pair Vault: {pair_id} Status: {pv.get('status')}")
        if pv.get('status') != "PENDING":
            print("ERROR: Pair vault should be PENDING")
    else:
        print(f"Failed to create Pair Vault: {resp.text}")

    # 6. User B checks invites and accepts
    print("User B checking invites...")
    resp = requests.get(f"{BASE_URL}/vaults/invites/pending", headers=headers2)
    invites = resp.json()
    invite = next((i for i in invites if i["id"] == pair_id), None)
    
    if invite:
        print("Found invite, accepting...")
        resp = requests.post(f"{BASE_URL}/vaults/{pair_id}/accept", headers=headers2)
        if resp.status_code == 200:
            active_pv = resp.json()
            print(f"Accepted! Status: {active_pv.get('status')}")
            if active_pv.get('status') != "ACTIVE":
                print("ERROR: Vault should be ACTIVE after accept")
        else:
            print(f"Failed to accept: {resp.text}")
    else:
        print("Invite not found for User B")

    # 7. Create Strict Vault and Delete (Test Deletion Bug)
    print("Creating Strict Vault...")
    resp = requests.post(f"{BASE_URL}/vaults/", headers=headers1, json={
        "name": "Strict Vault",
        "type": "solo",
        "mode": "strict"
    })
    if resp.status_code == 201:
        sv = resp.json()
        sv_id = sv["id"]
        print(f"Created Strict Vault: {sv_id}")
        
        print("Deleting Strict Vault...")
        resp = requests.delete(f"{BASE_URL}/vaults/{sv_id}", headers=headers1)
        if resp.status_code == 204:
            print("Strict Vault Deleted Successfully (Bug Fixed!)")
        else:
            print(f"Failed to delete strict vault: {resp.status_code} {resp.text}")
    else:
        print(f"Failed to create start vault: {resp.text}")

if __name__ == "__main__":
    try:
        test_vault_flow()
    except Exception as e:
        import traceback
        traceback.print_exc()
        print(f"Test crashed: {e}")
