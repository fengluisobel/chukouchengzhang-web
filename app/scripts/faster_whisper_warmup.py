#!/usr/bin/env python3
import json
import os
import sys


def main():
    model_name = os.environ.get("CKCZ_STT_MODEL", "small")
    model_path = os.environ.get("CKCZ_STT_MODEL_PATH", "")
    device = os.environ.get("CKCZ_STT_DEVICE", "cpu")
    compute_type = os.environ.get("CKCZ_STT_COMPUTE_TYPE", "int8")

    try:
        from faster_whisper import WhisperModel
        WhisperModel(model_path or model_name, device=device, compute_type=compute_type)
        print(json.dumps({
            "ok": True,
            "provider": "faster-whisper",
            "model": model_name,
            "modelPath": model_path or None,
            "device": device,
            "computeType": compute_type,
            "warmed": True
        }, ensure_ascii=False))
        return 0
    except Exception as exc:
        print(json.dumps({
            "ok": False,
            "provider": "faster-whisper",
            "model": model_name,
            "modelPath": model_path or None,
            "device": device,
            "computeType": compute_type,
            "error": f"{type(exc).__name__}: {exc}"
        }, ensure_ascii=False))
        return 1


if __name__ == "__main__":
    sys.exit(main())
