import os
import uuid
import httpx
import uvicorn
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

app = FastAPI(title="Blog Post Orchestrator")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

RESEARCHER_URL = os.getenv("RESEARCHER_URL", "http://localhost:8001")
OUTLINER_URL   = os.getenv("OUTLINER_URL",   "http://localhost:8002")
WRITER_URL     = os.getenv("WRITER_URL",     "http://localhost:8003")
EDITOR_URL     = os.getenv("EDITOR_URL",     "http://localhost:8004")

AGENT_TIMEOUT = 180.0  # seconds per agent call


class GenerateRequest(BaseModel):
    topic: str
    tone: str = "professional"


def extract_text(events: list) -> str:
    """Pull the last model text response out of an ADK event list."""
    for event in reversed(events):
        content = event.get("content") or {}
        if content.get("role") == "model":
            for part in content.get("parts", []):
                text = part.get("text", "").strip()
                if text:
                    return text
    return ""


async def call_agent(base_url: str, app_name: str, message: str) -> str:
    """Create a session on an ADK agent service, run it, and return the text response."""
    user_id   = "orchestrator"
    session_id = str(uuid.uuid4())

    async with httpx.AsyncClient(timeout=AGENT_TIMEOUT) as client:
        # 1. Create session
        session_resp = await client.post(
            f"{base_url}/apps/{app_name}/users/{user_id}/sessions",
            json={"session_id": session_id},
        )
        session_resp.raise_for_status()

        # 2. Run agent (non-streaming)
        run_resp = await client.post(
            f"{base_url}/run",
            json={
                "app_name":    app_name,
                "user_id":     user_id,
                "session_id":  session_id,
                "new_message": {
                    "role":  "user",
                    "parts": [{"text": message}],
                },
            },
            timeout=AGENT_TIMEOUT,
        )
        run_resp.raise_for_status()

    events = run_resp.json()
    text = extract_text(events)
    if not text:
        raise ValueError(f"{app_name} returned no text. Raw events: {events[:2]}")
    return text


@app.get("/health")
def health():
    return {"status": "ok", "service": "orchestrator"}


@app.post("/generate")
async def generate(req: GenerateRequest):
    topic = req.topic.strip()
    tone  = req.tone

    if not topic:
        raise HTTPException(status_code=400, detail="topic is required")

    try:
        # Stage 1 — Research
        research = await call_agent(
            RESEARCHER_URL, "researcher",
            f"Research this blog post topic thoroughly:\n\nTopic: {topic}\nDesired tone: {tone}",
        )

        # Stage 2 — Outline
        outline = await call_agent(
            OUTLINER_URL, "outliner",
            f"Topic: {topic}\nTone: {tone}\n\n--- Research ---\n{research}\n\nCreate a detailed blog post outline.",
        )

        # Stage 3 — Write
        draft = await call_agent(
            WRITER_URL, "writer",
            f"Topic: {topic}\nTone: {tone}\n\n--- Research ---\n{research}\n\n--- Outline ---\n{outline}\n\nWrite the full blog post now.",
        )

        # Stage 4 — Edit
        final_post = await call_agent(
            EDITOR_URL, "editor",
            f"Polish this blog post draft:\n\n{draft}",
        )

        return {
            "blog_post": final_post,
            "stages": {
                "research": research,
                "outline":  outline,
                "draft":    draft,
            },
        }

    except httpx.TimeoutException as e:
        raise HTTPException(status_code=504, detail=f"Agent timed out: {e}")
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=502, detail=f"Agent HTTP error: {e}")
    except ValueError as e:
        raise HTTPException(status_code=502, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=int(os.environ.get("PORT", 8080)))
