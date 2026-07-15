"""Regression coverage for the legacy vault lifecycle using the test app."""


def test_vault_flow(client, test_user, second_user, friends):
    solo_one = client.post(
        "/vaults/",
        headers=test_user["headers"],
        json={"name": "Solo 1", "type": "solo"},
    )
    solo_two = client.post(
        "/vaults/",
        headers=test_user["headers"],
        json={"name": "Solo 2", "type": "solo"},
    )
    assert solo_one.status_code == 201
    assert solo_two.status_code == 201
    assert solo_one.json()["id"] != solo_two.json()["id"]

    pair = client.post(
        "/vaults/",
        headers=test_user["headers"],
        json={
            "name": "Pair Vault",
            "type": "pair",
            "invitee_id": second_user["user_id"],
        },
    )
    assert pair.status_code == 201
    assert pair.json()["status"] == "PENDING"
    pair_id = pair.json()["id"]

    pending = client.get("/vaults/invites/pending", headers=second_user["headers"])
    assert pair_id in [item["id"] for item in pending.json()]
    accepted = client.post(f"/vaults/{pair_id}/accept", headers=second_user["headers"])
    assert accepted.status_code == 200
    assert accepted.json()["status"] == "ACTIVE"

    strict = client.post(
        "/vaults/",
        headers=test_user["headers"],
        json={"name": "Strict Solo", "type": "solo", "mode": "strict"},
    )
    assert strict.status_code == 201
    deleted = client.delete(f"/vaults/{strict.json()['id']}", headers=test_user["headers"])
    assert deleted.status_code == 204
