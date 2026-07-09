from core.scheduler.scheduler import Scheduler


def test_scheduler_add_job():
    scheduler = Scheduler()

    job = scheduler.add_job(
        name="status-check",
        worker="ubuntu-main",
        command="status",
    )

    assert job.name == "status-check"
    assert len(scheduler.list_jobs()) == 1


def test_scheduler_run_job():
    scheduler = Scheduler()

    scheduler.add_job(
        name="status-check",
        worker="ubuntu-main",
        command="status",
    )

    task = scheduler.run_job("status-check")

    assert task.status in ["FINISHED", "FAILED"]

    if task.status == "FINISHED":
        assert task.result["ok"] is True
