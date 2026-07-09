from core.brain.status import BrainStatus


def test_brain_status_online():
    brain = BrainStatus()

    status = brain.status()

    assert status["name"] == "AIControlCenter"
    assert status["role"] == "brain"
    assert status["state"] == "ONLINE"
    assert status["standalone"] is True
