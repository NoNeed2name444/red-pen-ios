# One llama.cpp server for one medical model, as a Hugging Face Space.
#
# The Space's MODEL variable says which GGUF to serve (repo:quant), and its
# API_KEY secret is the only key it answers to - the CramDown worker holds the
# same key and is the only thing that calls it. Deployed by
# .github/workflows/spaces-deploy.yml; free CPU hardware to start, and a
# faster GPU is a hardware switch in the Space's settings, nothing else.
FROM ghcr.io/ggml-org/llama.cpp:server
ENV HOME=/tmp LLAMA_CACHE=/tmp/llama-cache
EXPOSE 7860
ENTRYPOINT ["/bin/sh", "-c", "exec /app/llama-server --host 0.0.0.0 --port 7860 -hf \"$MODEL\" -c 8192 --jinja --api-key \"$API_KEY\""]
