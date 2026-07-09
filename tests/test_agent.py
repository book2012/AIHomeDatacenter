from core.agent.status_agent import StatusAgent


def test_status_agent_run():
    agent = StatusAgent(worker="ubuntu-main")

    task = agent.run()

    assert task.worker == "ubuntu-main"
    assert task.command == "status"
    assert task.status in ["FINISHED", "FAILED"]

    if task.status == "FINISHED":
        assert task.result["ok"] is True
