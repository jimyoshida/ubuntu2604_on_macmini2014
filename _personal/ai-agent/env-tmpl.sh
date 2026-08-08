#!/bin/bash

# vertex-ai-proxy.yml reads GOOGLE_CLOUD_LOCATION. It and GOOGLE_CLOUD_PROJECT are
# also defined in cloud-cli/env-tmpl.sh, so set them in one place only.
# GOOGLE_GENAI_USE_VERTEXAI has no remaining consumer since gemini-cli.yml was removed.
export GOOGLE_GENAI_USE_VERTEXAI=
export GOOGLE_CLOUD_PROJECT=
export GOOGLE_CLOUD_LOCATION=
