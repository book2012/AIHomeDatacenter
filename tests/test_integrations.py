from core.integrations.status import IntegrationStatus


def test_integration_status_shape():
    status = IntegrationStatus().check()

    assert "integrations" in status
    assert "openai" in status["integrations"]
    assert "notion" in status["integrations"]
    assert "github" in status["integrations"]
