from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_create_and_list_todo():
    created = client.post("/todos", json={"title": "buy milk"})
    assert created.status_code == 201
    assert created.json()["title"] == "buy milk"

    listed = client.get("/todos")
    assert listed.status_code == 200
    assert any(t["title"] == "buy milk" for t in listed.json())
