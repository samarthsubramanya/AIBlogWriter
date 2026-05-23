import os
import httpx
import uvicorn
from fastapi import FastAPI, Request, HTTPException
from fastapi.responses import HTMLResponse
from fastapi.templating import Jinja2Templates
from pydantic import BaseModel

app = FastAPI(title="Blog Post Writer UI")
templates = Jinja2Templates(directory=os.path.join(os.path.dirname(__file__), "templates"))

ORCHESTRATOR_URL = os.getenv("ORCHESTRATOR_URL", "http://localhost:8005")


class GenerateRequest(BaseModel):
    topic: str
    tone: str = "professional"


@app.get("/", response_class=HTMLResponse)
async def index(request: Request):
    return templates.TemplateResponse(request, "index.html")


@app.post("/generate")
async def generate(req: GenerateRequest):
    async with httpx.AsyncClient(timeout=300.0) as client:
        try:
            resp = await client.post(
                f"{ORCHESTRATOR_URL}/generate",
                json={"topic": req.topic, "tone": req.tone},
                timeout=300.0,
            )
            resp.raise_for_status()
            return resp.json()
        except httpx.TimeoutException:
            raise HTTPException(status_code=504, detail="Generation timed out (>5 min). Try a simpler topic.")
        except httpx.HTTPStatusError as e:
            raise HTTPException(status_code=502, detail=f"Orchestrator error: {e.response.text}")


@app.get("/health")
def health():
    return {"status": "ok", "service": "frontend"}


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=int(os.environ.get("PORT", 8080)))
