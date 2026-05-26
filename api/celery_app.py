import os
from celery import Celery
from dotenv import load_dotenv

# Load environmental variables from root .env
load_dotenv()

redis_url = os.getenv("REDIS_URL", "redis://localhost:6379/0")

celery_app = Celery(
    "cortex_tasks",
    broker=redis_url,
    backend=redis_url,
    include=["api.tasks"]
)

celery_app.conf.update(
    task_serializer="json",
    result_serializer="json",
    accept_content=["json"],
    timezone="UTC",
    enable_utc=True,
    task_track_started=True,
)

from celery.schedules import crontab

celery_app.conf.beat_schedule = {
    "weekly-synthesis": {
        "task": "api.tasks.weekly_synthesis_task",
        "schedule": crontab(hour=23, minute=0, day_of_week=0),  # Sunday at 23:00
    },
    "daily-serendipity": {
        "task": "api.tasks.daily_serendipity_task",
        "schedule": crontab(hour=8, minute=30),  # Daily at 08:30
    },
    "retroactive-backlink": {
        "task": "api.tasks.retroactive_backlink_task",
        "schedule": crontab(hour=2, minute=0, day_of_week=0),  # Sunday at 02:00
    },
}

