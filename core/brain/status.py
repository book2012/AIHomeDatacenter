from datetime import datetime
from typing import Any, Dict

from core.integrations.status import IntegrationStatus


class BrainStatus:
    def __init__(self, name: str = "AIControlCenter"):
        self.name = name
        self.integrations = IntegrationStatus()

    def status(self) -> Dict[str, Any]:
        return {
            "name": self.name,
            "role": "brain",
            "state": "ONLINE",
            "standalone": True,
            "timestamp": datetime.utcnow().isoformat(),
            "capabilities": [
                "task_registry",
                "session_manager",
                "scheduler",
                "agent_framework",
                "monitoring",
                "dashboard_api",
                "backup_registry",
                "storage_registry",
                "ai_api",
                "notion",
                "github",
            ],
            "integrations": self.integrations.check(),
        }
