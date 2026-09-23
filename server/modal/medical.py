"""Doctor-R1, MedVAL-4B and Baichuan-M2-32B on a GPU, for CramDown Cloud's Pro medical models.

The same GGUF files the app downloads to a phone, served by llama.cpp's own
OpenAI-compatible server on an NVIDIA L4. Each model is its own web endpoint,
scales to zero when idle (so it costs nothing while nobody uses it) and keeps
its weights on a Volume, so a cold start loads from disk instead of
re-downloading 5 GB.

Deployed by .github/workflows/modal-deploy.yml; the worker reaches the two
endpoints as AI_DOCTOR_URL and AI_MEDVAL_URL with the API key in the
"cramdown-medical" Modal secret.
"""
import os
import subprocess

import modal

app = modal.App("cramdown-medical")

image = (
    modal.Image.from_registry("ghcr.io/ggml-org/llama.cpp:server-cuda", add_python="3.12")
    .entrypoint([])
)
weights = modal.Volume.from_name("cramdown-medical-weights", create_if_missing=True)
secret = modal.Secret.from_name("cramdown-medical")

PORT = 8080
GPU = "L4"
IDLE = 5 * 60  # seconds with no requests before the GPU is let go


def serve(model: str) -> None:
    env = {**os.environ, "LLAMA_CACHE": "/weights"}
    subprocess.Popen(
        [
            "/app/llama-server",
            "--host", "0.0.0.0", "--port", str(PORT),
            "-hf", model,
            "-ngl", "99",        # every layer on the GPU
            "-c", "8192",
            "--jinja",
            "--api-key", os.environ["API_KEY"],
        ],
        env=env,
    )


@app.function(image=image, gpu=GPU, volumes={"/weights": weights}, secrets=[secret],
              scaledown_window=IDLE, timeout=60 * 60)
@modal.concurrent(max_inputs=4)
@modal.web_server(PORT, startup_timeout=15 * 60, label="cramdown-doctor")
def doctor():
    serve("mradermacher/Doctor-R1-GGUF:Q4_K_M")


@app.function(image=image, gpu=GPU, volumes={"/weights": weights}, secrets=[secret],
              scaledown_window=IDLE, timeout=60 * 60)
@modal.concurrent(max_inputs=4)
@modal.web_server(PORT, startup_timeout=15 * 60, label="cramdown-medval")
def medval():
    serve("stanfordmimi/MedVAL-4B-GGUF:Q4_K_M")


# Baichuan-M2-32B, CramDown Cloud's writer and checker: 20 GB at Q4_K_M, so a
# 48 GB L40S rather than the L4 the small models use.
@app.function(image=image, gpu="L40S", volumes={"/weights": weights}, secrets=[secret],
              scaledown_window=IDLE, timeout=60 * 60)
@modal.concurrent(max_inputs=4)
@modal.web_server(PORT, startup_timeout=25 * 60, label="cramdown-baichuan")
def baichuan():
    serve("bartowski/baichuan-inc_Baichuan-M2-32B-GGUF:Q4_K_M")
